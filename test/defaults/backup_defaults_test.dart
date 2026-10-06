// A workspace file carries what collections and folders pass down; older files still read.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/import_export/domain/services/backup_service.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';

import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

Future<void> _seedDefaults(DriftRepos repos) async {
  final shop = (await repos.collectionRepository.watchCollections().first).firstWhere((c) => c.name == 'Shop').id;
  final folders = {for (final f in await repos.collectionRepository.watchFolders(shop).first) f.name: f.id};
  await repos.defaultsRepository.saveCollection(
    shop,
    LevelDefaults(
      headers: [_h('X-Tenant', 'acme'), _h('Accept-Language', 'en', enabled: false)],
      assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      extractors: [ExtractorEntity(path: r'$.token', variableKey: 'sessionToken')],
    ),
  );
  await repos.defaultsRepository.saveFolder(
    folders['Orders']!,
    LevelDefaults(
      headers: [_h('X-Api-Version', '2')],
      variables: [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true)],
      auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'orders-token'),
    ),
  );
  await repos.defaultsRepository.saveFolder(
    folders['Archive']!,
    const LevelDefaults(auth: RequestAuth(type: AuthType.none)),
  );
}

void main() {
  late AppDatabase db;
  late DriftRepos repos;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    await seedShop(repos);
  });
  tearDown(() => db.close());

  Future<BackupSnapshot> snapshot() => repos.backupService.snapshot();

  group('the file', () {
    test('a file that carries defaults is version 4, one without stays version 2 so older apps still read it', () async {
      expect(jsonDecode(BackupCodec.encode(await snapshot()))['version'], BackupCodec.currentVersion);

      await _seedDefaults(repos);

      final text = BackupCodec.encode(await snapshot());
      expect(jsonDecode(text)['version'], BackupCodec.defaultsVersion);
      expect(BackupCodec.defaultsVersion, greaterThan(BackupCodec.gitVersion));
    });

    test('the collection and each folder hold their defaults under headers, tests, variables and auth', () async {
      await _seedDefaults(repos);

      final shop = (jsonDecode(BackupCodec.encode(await snapshot()))['collections'] as List).firstWhere((c) => c['name'] == 'Shop');

      expect((shop['headers'] as List).map((h) => '${h['key']}=${h['value']}/${h['enabled']}'), ['X-Tenant=acme/true', 'Accept-Language=en/false']);
      expect((shop['tests']['assertions'] as List).single['type'], 'statusIn2xx');
      expect((shop['tests']['extractors'] as List).single['key'], 'sessionToken');
      final orders = (shop['folders'] as List).firstWhere((f) => f['name'] == 'Orders');
      expect((orders['variables'] as List).map((v) => v['key']), ['region', 'apiKey']);
      expect((orders['variables'] as List)[1]['secret'], true);
      expect(orders['auth']['type'], 'bearer');
      final archive = (shop['folders'] as List).firstWhere((f) => f['name'] == 'Archive');
      expect(archive['auth']['type'], 'none', reason: 'No Auth on a folder is written, it is a setting');
      final users = (shop['folders'] as List).firstWhere((f) => f['name'] == 'Users');
      expect(users.keys, isNot(containsAll(['headers', 'variables', 'auth', 'tests'])), reason: 'nothing set, nothing written');
    });

    test('a file with a version newer than this app reads is refused', () {
      final text = jsonEncode({'format': 'postpilot-backup', 'version': BackupCodec.maxVersion + 1, 'collections': []});
      expect(() => BackupCodec.decode(text), throwsA(anything));
    });

    test('versions 1, 2 and 3 still read, with no defaults', () {
      for (final version in [1, 2, 3]) {
        final snapshot = BackupCodec.decode(jsonEncode({
          'format': 'postpilot-backup',
          'version': version,
          'collections': [
            {
              'name': 'Old',
              'folders': [
                {'id': 1, 'parentId': null, 'name': 'F'},
              ],
              'requests': [],
            },
          ],
        }));
        final old = snapshot.collections.single;
        expect(old.name, 'Old', reason: 'version $version');
        expect(old.hasDefaults, isFalse, reason: 'version $version');
        expect(old.defaults.isEmpty, isTrue);
        expect(old.folderDefaults, isEmpty);
      }
    });

    test('a defaults section that is damaged reads as empty, never as a failure of the whole file', () {
      final snapshot = BackupCodec.decode(jsonEncode({
        'format': 'postpilot-backup',
        'version': 4,
        'collections': [
          {
            'name': 'C',
            'headers': 'not a list',
            'tests': [1, 2],
            'folders': [
              {'id': 1, 'parentId': null, 'name': 'F', 'headers': [7], 'variables': {'a': 1}, 'auth': 'x', 'tests': 'y'},
            ],
          },
        ],
      }));
      expect(snapshot.collections.single.hasDefaults, isFalse);
    });

    test('a collection\'s own variables and auth are not read as defaults', () {
      final snapshot = BackupCodec.decode(jsonEncode({
        'format': 'postpilot-backup',
        'version': 4,
        'collections': [
          {
            'name': 'C',
            'auth': {'type': 'bearer', 'bearerToken': 't'},
            'variables': [
              {'key': 'a', 'value': '1'},
            ],
            'folders': [],
          },
        ],
      }));
      final c = snapshot.collections.single;
      expect(c.hasDefaults, isFalse);
      expect(c.variables.single.key, 'a');
      expect(c.auth?.bearerToken, 't');
    });
  });

  group('a round trip', () {
    test('restores the defaults of the collection and of every folder, by folder', () async {
      await _seedDefaults(repos);
      final text = BackupCodec.encode(await snapshot());

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = DriftRepos(other);
      await target.backupService.restore(text);

      final shop = (await target.collectionRepository.watchCollections().first).firstWhere((c) => c.name == 'Shop');
      final tree = await target.defaultsRepository.loadTree(shop.id);
      final byName = {for (final f in tree.folders) f.name: tree.folderDefaults[f.id]};

      expect([for (final h in tree.collection.headers) (h.key, h.value, h.enabled)], [('X-Tenant', 'acme', true), ('Accept-Language', 'en', false)]);
      expect(tree.collection.assertions.single.type, AssertionType.statusIn2xx);
      expect(tree.collection.extractors.single.variableKey, 'sessionToken');
      expect(byName['Orders']!.headers.single.key, 'X-Api-Version');
      expect(byName['Orders']!.variables, [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true)]);
      expect(byName['Orders']!.auth?.bearerToken, 'orders-token');
      expect(byName['Archive']!.auth?.type, AuthType.none);
      expect(byName['Users'], isNull);
      expect(tree.collection.auth?.type, AuthType.bearer, reason: 'the collection\'s own auth still travels in its own key');
    });

    test('restoring into the same database adds a copy that has its own defaults, and leaves the original alone', () async {
      await _seedDefaults(repos);
      final text = BackupCodec.encode(await snapshot());

      await repos.backupService.restore(text);

      final collections = await repos.collectionRepository.watchCollections().first;
      expect(collections.map((c) => c.name), containsAll(['Shop', 'Shop (restored)']));
      final original = await repos.defaultsRepository.loadTree(collections.firstWhere((c) => c.name == 'Shop').id);
      final copy = await repos.defaultsRepository.loadTree(collections.firstWhere((c) => c.name == 'Shop (restored)').id);
      expect(copy.collection.headers.length, original.collection.headers.length);
      expect(copy.folderDefaults.length, original.folderDefaults.length);
      expect(copy.folders.map((f) => f.id).toSet().intersection(original.folders.map((f) => f.id).toSet()), isEmpty);
    });

    test('a collection that never had defaults restores without any', () async {
      final text = BackupCodec.encode(await snapshot());

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = DriftRepos(other);
      await target.backupService.restore(text);

      expect((await other.customSelect('SELECT COUNT(*) AS n FROM folder_defaults').getSingle()).read<int>('n'), 0);
      expect((await other.customSelect('SELECT COUNT(*) AS n FROM collection_defaults').getSingle()).read<int>('n'), 0);
    });

    test('a service with no defaults repository leaves them out of a restore without failing', () async {
      await _seedDefaults(repos);
      final text = BackupCodec.encode(await snapshot());
      final withoutDefaults = BackupService(
        repos.loader,
        repos.collectionRepository,
        repos.requestRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
        repos.scriptsRepository,
        repos.exampleRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.requestSettingsRepository,
        repos.documentationRepository,
        repos.tagRepository,
      );

      await withoutDefaults.restore(text);

      final restoredId = (await repos.collectionRepository.watchCollections().first).firstWhere((c) => c.name == 'Shop (restored)').id;
      final restored = await repos.defaultsRepository.loadTree(restoredId);
      expect(restored.collection.headers, isEmpty);
      expect(restored.collection.hasTests, isFalse);
      expect(restored.folderDefaults, isEmpty);
      expect(restored.folders, isNotEmpty);
    });

    test('an in-memory bundle carries them as well', () async {
      await _seedDefaults(repos);
      final text = BackupCodec.encode(await snapshot());
      final memory = InMemoryDb();

      await memory.backupService.restore(text);

      expect(memory.collectionDefaults.values.single.headers.map((h) => h.key), ['X-Tenant', 'Accept-Language']);
      expect(memory.folderDefaults, hasLength(2));
    });
  });
}
