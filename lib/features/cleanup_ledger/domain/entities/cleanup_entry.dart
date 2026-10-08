// Pure Dart (no Flutter): the ledger of the app and the cleanup of the command line share these.
import '../../../request_builder/domain/entities/api_request_entity.dart';
import 'cleanup_settings.dart';

/// Where a created record stands.
enum CleanupState {
  /// Created and not deleted (yet).
  pending('Not deleted'),
  deleted('Deleted'),

  /// The delete was tried and did not work; [CleanupEntry.reason] says why. It can be tried again.
  failed('Failed'),

  /// Nothing can be deleted: no id was found in the response, or the undo is not set up.
  skipped('Not cleaned up');

  final String label;
  const CleanupState(this.label);
}

/// How one entry is undone. Never [CleanupUndo.auto]: that is decided when the entry is made.
final class CleanupPlan {
  final CleanupUndo kind;

  /// What it will do, for a list: `Odoo unlink res.partner [12, 13]`, `DELETE {{baseUrl}}/partners/12`.
  final String summary;

  /// The request that undoes it, for [CleanupUndo.odooUnlink] and [CleanupUndo.restDelete]: built from the request that
  /// created the record (same server, same headers and authentication) and never saved anywhere. Null for
  /// [CleanupUndo.request], whose request is looked up when it is sent.
  final ApiRequestEntity? request;

  /// The collection the creating request is in; [undoRequest] is looked up there.
  final int collectionId;

  /// The name or `Folder/Name` of the request to send, for [CleanupUndo.request].
  final String undoRequest;

  const CleanupPlan({
    required this.kind,
    required this.summary,
    required this.collectionId,
    this.request,
    this.undoRequest = '',
  });
}

/// What one successful create left on the server, and how to take it away again. Kept in memory for the session only.
final class CleanupEntry {
  /// Counts up from 1 in the order the records were created, so a bigger id was created later.
  final int id;
  final String requestName;

  /// The environment that was active when it was created. A delete is only sent under the same one.
  final String? environment;
  final DateTime createdAt;

  /// What the response named: numbers (`int`) or text ids (`String`).
  final List<Object> ids;
  final CleanupPlan plan;

  /// The variables the undo request is sent with: the run's data row, `created.id`, `created.ids`, `created.count` and
  /// the fields of the create's response as `created.<field>`.
  final Map<String, String> variables;

  final CleanupState state;
  final String? reason;
  final DateTime? settledAt;

  const CleanupEntry({
    required this.id,
    required this.requestName,
    required this.environment,
    required this.createdAt,
    required this.ids,
    required this.plan,
    required this.variables,
    this.state = CleanupState.pending,
    this.reason,
    this.settledAt,
  });

  /// Records this entry stands for: a bulk create makes several.
  int get recordCount => ids.length;

  /// Whether a delete can be (re)tried.
  bool get canDelete => state == CleanupState.pending || state == CleanupState.failed;

  /// `#12, #13`.
  String get idsText => ids.map((id) => '#$id').join(', ');

  CleanupEntry settled(CleanupState next, {String? reason, DateTime? at}) => CleanupEntry(
        id: id,
        requestName: requestName,
        environment: environment,
        createdAt: createdAt,
        ids: ids,
        plan: plan,
        variables: variables,
        state: next,
        reason: reason,
        settledAt: at ?? DateTime.now(),
      );
}
