import 'dart:convert';
import '../../../import_export/domain/services/backup_codec.dart';
import 'workplace_entity.dart';

final class WorkplaceContent {
  final WorkplaceEntity workplace;
  final BackupSnapshot snapshot;

  const WorkplaceContent({required this.workplace, required this.snapshot});

  factory WorkplaceContent.empty(WorkplaceEntity workplace) => WorkplaceContent(
    workplace: workplace,
    snapshot: BackupSnapshot(
      exportedAt: DateTime.now(),
      collections: const [],
      environments: const [],
      globals: const [],
    ),
  );

  String toJsonString() {
    // The Git link of each linked collection travels with the workspace.
    final snapshotJson = jsonDecode(BackupCodec.encode(snapshot, includeGit: true)) as Map<String, dynamic>;
    final wpJson = workplace.toJson();
    // Security: Never serialize git token to workspace.json (prevents GitHub secret scanning rejection and credential leaks)
    wpJson['gitToken'] = null;
    // Per-device sync bookkeeping: it changes on every push, so keeping it in the shared file would make
    // every sync look like a change (and carry one machine's state to another).
    wpJson['lastSyncedAt'] = null;
    wpJson['lastSyncedSha'] = null;
    // The same for the environment that is active here: what is selected is each device's own choice.
    wpJson['activeEnvironment'] = null;
    snapshotJson['workplace'] = wpJson;
    return const JsonEncoder.withIndent('  ').convert(snapshotJson);
  }

  factory WorkplaceContent.fromJsonString(String jsonStr, {required WorkplaceEntity fallbackWorkplace}) {
    final Map<String, dynamic> map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final wpMap = map['workplace'] as Map<String, dynamic>?;
    var workplace = wpMap != null ? WorkplaceEntity.fromJson(wpMap) : fallbackWorkplace;
    // Preserve local credentials from fallbackWorkplace
    if (workplace.gitToken == null && fallbackWorkplace.gitToken != null) {
      workplace = workplace.copyWith(gitToken: fallbackWorkplace.gitToken);
    }
    final snapshot = BackupCodec.decode(jsonStr);
    return WorkplaceContent(workplace: workplace, snapshot: snapshot);
  }
}
