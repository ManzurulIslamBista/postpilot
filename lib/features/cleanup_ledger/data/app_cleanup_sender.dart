import 'dart:convert';
import '../../auth_renewal/domain/services/relogin_policy.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/entities/api_response_entity.dart';
import '../domain/entities/cleanup_entry.dart';
import '../domain/entities/cleanup_settings.dart';
import '../domain/services/cleanup_executor.dart';
import '../domain/services/delete_response_check.dart';

/// Sends the request that undoes an entry through the app's normal send path (`RequestFlowService`), so the variables
/// of the active environment, the authentication, the unresolved-variable check, History and the console all apply to a
/// cleanup as they do to any request. The production lock is asked by the caller, once, through the executor's gate,
/// because it needs a dialog.
final class AppCleanupSender implements CleanupSender {
  final Future<String?> Function() _environmentName;
  final Future<List<ReloginCandidate<RequestSummaryEntity>>> Function(int collectionId) _candidates;
  final Future<ApiRequestEntity?> Function(int requestId) _findRequest;
  final Future<ApiResponseEntity> Function(ApiRequestEntity request, Map<String, String> variables) _send;

  const AppCleanupSender({
    required this._environmentName,
    required this._candidates,
    required this._findRequest,
    required this._send,
  });

  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) async {
    // The records live on the server the environment pointed at when they were created. Under another environment the
    // same URL would reach another server, where deleting "id 42" deletes somebody else's record.
    String? active;
    try {
      active = await _environmentName();
    } catch (_) {
      active = null;
    }
    if (active != entry.environment) {
      return CleanupPrepared.failed(
        entry,
        'Created under ${_named(entry.environment)}, but ${_named(active)} is active now. '
        'Switch back to it to delete this record.',
      );
    }
    final planned = entry.plan.request;
    if (entry.plan.kind != CleanupUndo.request) {
      return planned == null
          ? CleanupPrepared.failed(entry, 'There is no request to undo this with.')
          : CleanupPrepared.ready(entry, planned);
    }

    final wanted = entry.plan.undoRequest;
    final lookup = ReloginPolicy.find(wanted, await _candidates(entry.plan.collectionId));
    switch (lookup) {
      case ReloginNotFound():
        return CleanupPrepared.failed(entry, 'No request of this collection is called "$wanted" any more.');
      case ReloginAmbiguous(:final count):
        return CleanupPrepared.failed(entry, '"$wanted" names $count requests. Rename one of them.');
      case ReloginFound(:final candidate):
        final full = await _findRequest(candidate.value.id);
        return full == null
            ? CleanupPrepared.failed(entry, 'The request "$wanted" no longer exists.')
            : CleanupPrepared.ready(entry, full);
    }
  }

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) async {
    final entry = prepared.entry;
    final response = await _send(prepared.request!, entry.variables);
    final problem = DeleteResponseCheck.failureOf(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      body: utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    return problem == null ? CleanupResult(entry, CleanupState.deleted) : CleanupResult(entry, CleanupState.failed, problem);
  }

  static String _named(String? environment) => environment == null ? 'no environment' : 'environment "$environment"';
}
