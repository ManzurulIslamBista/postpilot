import 'dart:typed_data';
import '../../../../core/network/api_http_response.dart';
import '../../../scripting/domain/entities/script_run_result.dart';
import '../../../scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../entities/api_request_entity.dart';
import '../entities/api_response_entity.dart';
import '../repositories/request_repository.dart';
import '../usecases/send_request_usecase.dart';
import 'collection_run_options.dart';

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

  /// What went wrong in the tests and variable saves, one line each.
  List<String> get failures => [
        ...?scripts?.assertions.where((a) => !a.passed).map((a) => a.name),
        ...?scripts?.extracted.where((e) => !e.ok).map((e) => 'variable ${e.key}: ${e.error}'),
      ];
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// Runs every request in a collection sequentially — Postman's "Collection
/// Runner" — streaming one [CollectionRunResult] per request as it finishes
/// so the UI can show live progress rather than waiting for the whole batch.
/// Each request's scripts run before the next is sent, so extracted
/// variables chain forward through the run.
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

  const CollectionRunnerService(
    this._requestRepository,
    this._sendRequestUseCase,
    this._runRequestScriptsUseCase, [
    this._delay = _sleep,
  ]);

  /// The requests [run] will send, in the order it sends them.
  Future<List<RequestSummaryEntity>> requestsIn(int collectionId) =>
      _requestRepository.watchByCollection(collectionId).first;

  /// Cancelling [cancelToken] aborts the request in flight (it produces no
  /// result) or the wait between requests, then ends the stream.
  Stream<CollectionRunResult> run(
    int collectionId, {
    CollectionRunOptions options = const CollectionRunOptions(),
    ApiCancelToken? cancelToken,
  }) async* {
    final summaries = await requestsIn(collectionId);
    var sentAny = false;
    for (var iteration = 1; iteration <= options.iterationCount; iteration++) {
      final data = options.dataFor(iteration);
      for (final summary in summaries) {
        if (cancelToken?.isCancelled ?? false) return;
        final full = await _requestRepository.findById(summary.id);
        if (full == null) continue;
        if (sentAny && options.delay > Duration.zero && !await _pause(options.delay, cancelToken)) return;
        sentAny = true;

        final result = await _sendOne(summary, full, iteration, data, cancelToken);
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
  ) async {
    try {
      final response = await _sendRequestUseCase(full, cancelToken: cancelToken, dataVariables: data);
      final scripts = await _runRequestScriptsUseCase(
        RunRequestScriptsParams(
          requestId: full.id,
          collectionId: full.collectionId,
          response: response,
          dataVariables: data,
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
      return CollectionRunResult(request: summary, error: e.toString(), iteration: iteration);
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
      );
}
