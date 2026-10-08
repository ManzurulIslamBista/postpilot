import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../history/domain/services/history_run_budget.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/usecases/send_request_usecase.dart';
import '../../../settings/domain/entities/request_settings.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../entities/flow_report.dart';
import '../entities/sent_request.dart';
import '../services/flow_environment.dart';
import '../services/flow_executor.dart';
import '../services/run_if_evaluator.dart';

/// The app's way to send a request that has flow settings: the request editor and the collection runner both go
/// through it. It reads the request's settings, and either sends once, exactly as [SendRequestUseCase] does, or
/// hands the send to the [FlowExecutor] (retry, poll until, fetch all pages). Run if and Always run are answered
/// here too, for the runner.
final class RequestFlowService {
  final RequestSettingsRepository _settings;
  final SendRequestUseCase _send;
  final FlowEnvironment _environment;
  final FlowExecutor _executor;

  /// Told about every try after the first (`attempt 2/3 after 1.2 s`, `page 3`): the console shows them.
  final FlowNote? _observer;

  /// Told about every send that got an answer, with the request's settings: the cleanup ledger records what it created.
  final SendObserver? _onSent;

  RequestFlowService(
    this._settings,
    this._send,
    this._environment, {
    FlowExecutor? executor,
    FlowNote? onNote,
    this._onSent,
  })  : _executor = executor ?? FlowExecutor(),
        _observer = onNote;

  /// The settings of [requestId]; none when they cannot be read.
  Future<RequestSettings> settingsOf(int requestId) async {
    try {
      return await _settings.get(requestId);
    } catch (_) {
      return RequestSettings.none;
    }
  }

  /// The settings of [requestId] as they change, for the Send button's label.
  Stream<RequestSettings> watch(int requestId) => _settings.watch(requestId);

  /// Sends [request] the way its flow settings say. A request with none is sent once and a failure is thrown just
  /// as [SendRequestUseCase] throws it; with settings the failure of the last try comes back in
  /// [FlowOutcome.error] (so the report of the earlier tries is not lost) and only a cancelled or unbuildable
  /// request throws. [dataVariables] and [historyRun] are a collection run's, handed on to every try.
  Future<FlowOutcome> send(
    ApiRequestEntity request, {
    ApiCancelToken? cancelToken,
    Map<String, String> dataVariables = const {},
    HistoryRunBudget? historyRun,
    FlowNote? onNote,
    RequestSettings? settings,
  }) async {
    final stored = settings ?? await settingsOf(request.id);
    final outcome = await _sendWith(
      request,
      cancelToken: cancelToken,
      dataVariables: dataVariables,
      historyRun: historyRun,
      onNote: onNote,
      settings: stored,
    );
    await _announce(request, outcome, stored, dataVariables);
    return outcome;
  }

  /// Tells the [SendObserver] about an answer. It never fails the send: a record that cannot be kept is not a reason to
  /// lose a response that was received.
  Future<void> _announce(ApiRequestEntity request, FlowOutcome outcome, RequestSettings stored, Map<String, String> dataVariables) async {
    final observer = _onSent;
    final response = outcome.response;
    if (observer == null || response == null || outcome.error != null) return;
    try {
      String? environment;
      try {
        environment = await _environment.environmentName();
      } catch (_) {
        environment = null;
      }
      await observer(
        SentRequest(request: request, response: response, settings: stored, dataVariables: dataVariables, environment: environment),
      );
    } catch (_) {
      // The observer's own trouble.
    }
  }

  Future<FlowOutcome> _sendWith(
    ApiRequestEntity request, {
    ApiCancelToken? cancelToken,
    Map<String, String> dataVariables = const {},
    HistoryRunBudget? historyRun,
    FlowNote? onNote,
    RequestSettings? settings,
  }) async {
    final stored = settings ?? await settingsOf(request.id);
    if (!FlowExecutor.changesSending(stored.flow, stored.pagination)) {
      return FlowOutcome(
        response: await _send(request, cancelToken: cancelToken, dataVariables: dataVariables, historyRun: historyRun),
      );
    }
    // Every try would otherwise be a History entry: a poll of fifty is a handful of them.
    final budget = historyRun ?? HistoryRunBudget(limit: 12, okLimit: 4);
    return _executor.execute(
      request: request,
      flow: stored.flow,
      pagination: stored.pagination,
      send: (page) async {
        try {
          return FlowResponded(
            await _send(page, cancelToken: cancelToken, dataVariables: dataVariables, historyRun: budget),
          );
        } on NetworkException catch (error) {
          if (error.kind == NetworkErrorKind.cancelled) rethrow;
          return FlowFailed(error, SecretMasker.maskMessage(error.summary ?? error.message));
        }
      },
      context: FlowContext(
        resolver: () => _environment.resolver(
          collectionId: request.collectionId,
          folderId: request.folderId,
          dataVariables: dataVariables,
        ),
        onNote: (message) {
          _observer?.call(message);
          onNote?.call(message);
        },
        cancelToken: cancelToken,
      ),
    );
  }

  /// Whether [request] (with [settings]) is sent now in a run: its Run if conditions, looking at the variables as
  /// they are and the request that ran just before it in [pass].
  Future<RunIfDecision> decideRunIf(
    ApiRequestEntity request,
    RequestSettings settings,
    FlowRunPass pass, {
    Map<String, String> dataVariables = const {},
  }) async {
    final policy = settings.flow.runIf;
    if (!policy.isActive) return const RunIfDecision.run();
    return RunIfEvaluator.evaluate(
      policy,
      RunIfContext(
        resolver: await _environment.resolver(
          collectionId: request.collectionId,
          folderId: request.folderId,
          dataVariables: dataVariables,
        ),
        environmentName: await _environment.environmentName(),
        previous: pass.previous,
      ),
    );
  }

  /// The active environment, for [RunIfEvaluator.surelySkippedIn].
  Future<String?> environmentName() => _environment.environmentName();
}
