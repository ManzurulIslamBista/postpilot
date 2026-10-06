import 'dart:typed_data';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../history/domain/services/history_run_budget.dart';
import '../../../scripting/domain/entities/script_run_result.dart';
import '../../../scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../entities/api_request_entity.dart';
import '../entities/api_response_entity.dart';
import '../repositories/request_repository.dart';
import '../usecases/send_request_usecase.dart';
import 'collection_run_options.dart';
import 'collection_run_plan.dart';
import 'run_selection.dart';

final class CollectionRunResult {
  final RequestSummaryEntity request;
  final ApiResponseEntity? response;
  final ScriptRunResult? scripts;
  final String? error;

  /// The 1-based pass over the collection this request ran in.
  final int iteration;

  const CollectionRunResult({required this.request, this.response, this.scripts, this.error, this.iteration = 1});

  bool get isSuccess => response != null && response!.isSuccess;

  /// A request with assertions passes on those alone (a test may legitimately
  /// expect a 404); one without falls back to HTTP 2xx. Either way a failed
  /// extraction fails it: the variables later requests chain on weren't saved.
  bool get passed {
    final scripts = this.scripts;
    if (scripts == null) return isSuccess;
    return (scripts.assertions.isNotEmpty || isSuccess) && !scripts.hasFailures;
  }

  int get assertionCount => scripts?.assertions.length ?? 0;
  int get passedAssertionCount => scripts?.passedCount ?? 0;

  /// The response body was cut off at the size limit, so the tests and
  /// extractors ran on only the first part of it.
  bool get truncated => response?.truncated ?? false;

  /// What went wrong in the tests and variable saves, one line each (a test
  /// inherited from a folder or the collection says where it comes from); when
  /// the body they ran on was cut short, a last line says so.
  List<String> get failures {
    String from(String? origin) => origin == null ? '' : ' (from $origin)';
    final lines = [
      ...?scripts?.assertions.where((a) => !a.passed).map((a) => '${a.name}${from(a.origin)}'),
      ...?scripts?.extracted.where((e) => !e.ok).map((e) => 'variable ${e.key}: ${e.error}${from(e.origin)}'),
    ];
    if (lines.isNotEmpty && truncated) lines.add(truncatedBodyHint);
    return lines;
  }

  static const truncatedBodyHint = 'The response was cut off at the size limit (see Settings), so tests ran on part of it.';
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// Runs every request in a collection sequentially — Postman's "Collection
/// Runner" — streaming one [CollectionRunResult] per request as it finishes
/// so the UI can show live progress rather than waiting for the whole batch.
/// Each request's scripts run before the next is sent, so extracted
/// variables chain forward through the run.
///
/// The order is the collection's canonical one (see `CollectionOrder`): the order the sidebar shows, folders
/// and their content in place, the same on every pass. A [RunSelection] narrows the run to one folder or to
/// chosen requests without changing that order. A request deleted, or moved to another collection, while the
/// run is going is skipped when its turn comes; moving it elsewhere in the same collection does not change
/// where it runs, the order is fixed when the run starts.
///
/// [CollectionRunOptions] repeats the pass, paces it, and feeds each pass a
/// data row. Its columns are real variables, the top scope of both the send
/// and the scripts that follow it (see `BuildVariableResolverUseCase`), so a
/// column beats a variable of the same name and reaches everything that
/// resolves `{{name}}`: the request, its inherited auth, assertions and
/// extractors, and environment values that reference it.
final class CollectionRunnerService {
  final RequestRepository _requestRepository;
  final SendRequestUseCase _sendRequestUseCase;
  final RunRequestScriptsUseCase _runRequestScriptsUseCase;

  /// Replaceable so tests can run "delays" instantly and inspect them.
  final Future<void> Function(Duration) _delay;

  /// Where the folders come from. Without it the repository's own order stands, as listed.
  final CollectionRepository? _collections;

  const CollectionRunnerService(
    this._requestRepository,
    this._sendRequestUseCase,
    this._runRequestScriptsUseCase, [
    this._delay = _sleep,
  ]) : _collections = null;

  /// The app's runner: [_collections] supplies the folders, so the run follows the collection's canonical order.
  const CollectionRunnerService.withFolders(
    this._requestRepository,
    this._sendRequestUseCase,
    this._runRequestScriptsUseCase,
    CollectionRepository this._collections, [
    this._delay = _sleep,
  ]);

  /// The collection's folders and requests with the order a run takes through them.
  Future<CollectionRunPlan> planFor(int collectionId) async {
    final requests = await _requestRepository.watchByCollection(collectionId).first;
    final collections = _collections;
    if (collections == null) return CollectionRunPlan.asListed(requests);
    return CollectionRunPlan.canonical(folders: await collections.watchFolders(collectionId).first, requests: requests);
  }

  /// The requests [run] will send for [selection], in the order it sends them.
  Future<List<RequestSummaryEntity>> requestsIn(int collectionId, {RunSelection selection = RunSelection.all}) async =>
      (await planFor(collectionId)).select(selection);

  /// The same requests in full, so a caller can judge what a run would do
  /// (the production lock asks about intent and destination) before it starts.
  Future<List<ApiRequestEntity>> fullRequestsIn(int collectionId, {RunSelection selection = RunSelection.all}) async {
    final full = <ApiRequestEntity>[];
    for (final summary in await requestsIn(collectionId, selection: selection)) {
      final request = await _requestRepository.findById(summary.id);
      if (request != null) full.add(request);
    }
    return full;
  }

  /// Cancelling [cancelToken] aborts the request in flight (it produces no
  /// result) or the wait between requests, then ends the stream.
  Stream<CollectionRunResult> run(
    int collectionId, {
    CollectionRunOptions options = const CollectionRunOptions(),
    ApiCancelToken? cancelToken,
    RunSelection selection = RunSelection.all,
  }) async* {
    final summaries = await requestsIn(collectionId, selection: selection);
    var sentAny = false;
    // However long the run, only a sample of it reaches History (see HistoryRunBudget).
    final historyBudget = HistoryRunBudget();
    for (var iteration = 1; iteration <= options.iterationCount; iteration++) {
      final data = options.dataFor(iteration);
      for (final summary in summaries) {
        if (cancelToken?.isCancelled ?? false) return;
        final full = await _requestRepository.findById(summary.id);
        if (full == null || full.collectionId != collectionId) continue;
        if (sentAny && options.delay > Duration.zero && !await _pause(options.delay, cancelToken)) return;
        sentAny = true;

        final result = await _sendOne(summary, full, iteration, data, cancelToken, historyBudget);
        if (result == null) return;
        yield result;
        if (options.stopOnFailure && !result.passed) return;
      }
    }
  }

  /// False when [cancelToken] fired during the wait.
  Future<bool> _pause(Duration duration, ApiCancelToken? cancelToken) async {
    if (cancelToken == null) {
      await _delay(duration);
      return true;
    }
    await Future.any([_delay(duration), cancelToken.whenCancelled]);
    return !cancelToken.isCancelled;
  }

  /// `null` when the user stopped the run: whatever failed then is just the
  /// abort, not a result worth reporting.
  Future<CollectionRunResult?> _sendOne(
    RequestSummaryEntity summary,
    ApiRequestEntity full,
    int iteration,
    Map<String, String> data,
    ApiCancelToken? cancelToken,
    HistoryRunBudget historyBudget,
  ) async {
    try {
      final response = await _sendRequestUseCase(
        full,
        cancelToken: cancelToken,
        dataVariables: data,
        historyRun: historyBudget,
      );
      final scripts = await _runRequestScriptsUseCase(
        RunRequestScriptsParams(
          requestId: full.id,
          collectionId: full.collectionId,
          response: response,
          dataVariables: data,
          folderId: full.folderId,
        ),
      );
      return CollectionRunResult(
        request: summary,
        response: _withoutBody(response),
        scripts: scripts,
        iteration: iteration,
      );
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) return null;
      // The message can quote the resolved URL, and the result is shown and exported. A network
      // failure is told by its one-line summary where the client wrote one.
      final text = e is NetworkException ? e.summary ?? e.message : e.toString();
      return CollectionRunResult(request: summary, error: SecretMasker.maskMessage(text), iteration: iteration);
    }
  }

  /// A run keeps every result in memory (up to 1000 passes), and nothing here
  /// reads a body back once the scripts have run.
  ApiResponseEntity _withoutBody(ApiResponseEntity response) => ApiResponseEntity(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        headers: response.headers,
        bodyBytes: Uint8List(0),
        duration: response.duration,
        truncated: response.truncated,
        setCookies: response.setCookies,
      );
}
