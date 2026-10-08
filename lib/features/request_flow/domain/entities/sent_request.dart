import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../settings/domain/entities/request_settings.dart';

/// A request that was sent and got an answer, as the flow service reports it to whoever watches sends (the cleanup
/// ledger records what a create left on the server).
final class SentRequest {
  /// The request as it was sent, with the `{{variables}}` unresolved.
  final ApiRequestEntity request;

  /// The answer: the last try, or the pages merged.
  final ApiResponseEntity response;

  /// The request's own settings, which say what to do with the answer.
  final RequestSettings settings;

  /// The data row of a collection run (empty for a send by hand).
  final Map<String, String> dataVariables;

  /// The active environment's name; null for "No Environment".
  final String? environment;

  const SentRequest({
    required this.request,
    required this.response,
    required this.settings,
    required this.dataVariables,
    required this.environment,
  });
}

/// Told about every send that got an answer. It must not throw into the send: whatever it does is its own business.
typedef SendObserver = Future<void> Function(SentRequest sent);
