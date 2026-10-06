// A push of workspace.json must notice a change to what collections and folders pass down.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/workplace/domain/services/workspace_diff.dart';

String _workspace({
  String tenant = 'acme',
  String region = 'eu',
  bool swapFolderIds = false,
  bool extraFolderDefaults = false,
}) {
  final ids = swapFolderIds ? (a: 7, b: 3) : (a: 1, b: 2);
  return BackupCodec.encode(
    BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      collections: [
        BackupCollection(
          name: 'Shop',
          folders: [
            FolderEntity(id: ids.a, collectionId: 0, parentFolderId: null, name: 'Orders'),
            FolderEntity(id: ids.b, collectionId: 0, parentFolderId: ids.a, name: 'Archive'),
          ],
          defaults: LevelDefaults(headers: [KeyValueItem(key: 'X-Tenant', value: tenant)]),
          folderDefaults: {
            ids.a: LevelDefaults(variables: [DefaultVariable(key: 'region', value: region)]),
            if (extraFolderDefaults) ids.b: const LevelDefaults(auth: RequestAuth(type: AuthType.none)),
          },
        ),
      ],
    ),
  );
}

void main() {
  test('the same defaults give no change, whatever ids the folders have in the file', () {
    expect(WorkspaceDiff.compare(_workspace(), _workspace()).isEmpty, isTrue);
    expect(WorkspaceDiff.compare(_workspace(), _workspace(swapFolderIds: true)).isEmpty, isTrue);
  });

  test('a changed default header of the collection is a change to that collection', () {
    final changes = WorkspaceDiff.compare(_workspace(), _workspace(tenant: 'globex'));

    expect(changes.changes.map((c) => (c.kind, c.scope, c.label)), [(WorkspaceChangeKind.changed, 'Collection', 'Shop (defaults)')]);
    expect(changes.commitMessage(), startsWith('Change 1 collection'));
  });

  test('a changed folder variable, or a folder that gained a default, is one too', () {
    expect(WorkspaceDiff.compare(_workspace(), _workspace(region: 'us')).changes.single.label, 'Shop (defaults)');
    expect(WorkspaceDiff.compare(_workspace(), _workspace(extraFolderDefaults: true)).changes.single.label, 'Shop (defaults)');
  });

  test('a workspace file written before defaults existed compares as having none', () {
    final before = BackupCodec.encode(BackupSnapshot(exportedAt: DateTime.utc(2026), collections: [const BackupCollection(name: 'Shop')]));
    final after = BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      collections: [BackupCollection(name: 'Shop', defaults: LevelDefaults(headers: [KeyValueItem(key: 'X-A', value: '1')]))],
    ));

    expect(WorkspaceDiff.compare(before, before).isEmpty, isTrue);
    expect(WorkspaceDiff.compare(before, after).changes.single.label, 'Shop (defaults)');
  });
}
