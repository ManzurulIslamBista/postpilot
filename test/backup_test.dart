import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_backup_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/restore_backup_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'support/in_memory_import_export_fakes.dart';
import 'support/shop_seed.dart';

String _backupOf(Map<String, dynamic> overrides) => jsonEncode({
      'format': BackupCodec.formatId,
      'version': BackupCodec.currentVersion,
      'collections': const [],
      'environments': const [],
      'globals': const [],
      ...overrides,
    });

void main() {
  group('backup file', () {
    late InMemoryDb source;
    late Map<String, dynamic> doc;

    setUp(() async {
      source = InMemoryDb();
      await seedShop(source);
      doc = jsonDecode((await ExportBackupUseCase(source.backupService)(const NoParams())).text) as Map<String, dynamic>;
    });

    test('is versioned and marked as holding secrets', () {
      expect(doc['format'], 'postpilot-backup');
      expect(doc['version'], BackupCodec.currentVersion);
      expect(BackupCodec.currentVersion, 2);
      expect(doc['sensitive'], isTrue);
      expect(doc['notice'], contains('secrets'));
      expect(DateTime.tryParse(doc['exportedAt'] as String), isNotNull);
    });

    test('carries collections, environments and global variables, secret values included', () {
      final collections = (doc['collections'] as List).cast<Map<String, dynamic>>();

      expect(collections.map((c) => c['name']), ['Shop', 'Empty']);
      final environments = (doc['environments'] as List).cast<Map<String, dynamic>>();
      expect(environments.map((e) => e['name']), ['Dev', 'Prod']);
      final dev = (environments.first['variables'] as List).cast<Map<String, dynamic>>();
      expect(dev.singleWhere((v) => v['key'] == 'password'), containsPair('value', 'p4ss'));
      expect(dev.singleWhere((v) => v['key'] == 'password'), containsPair('secret', true));
      expect(dev.singleWhere((v) => v['key'] == 'off'), containsPair('enabled', false));
      final globals = (doc['globals'] as List).cast<Map<String, dynamic>>();
      expect(globals.map((g) => g['key']), ['apiVersion', 'masterKey']);
      expect(globals.last, containsPair('value', 'k3y'));
    });

    test('a collection holds its folders, variables, auth, requests, tests and saved examples', () {
      final shop = (doc['collections'] as List).first as Map<String, dynamic>;

      expect((shop['folders'] as List).map((f) => (f as Map)['name']), ['Orders', 'Archive', 'Users']);
      expect((shop['variables'] as List).map((v) => (v as Map)['enabled']), [true, false]);
      expect((shop['auth'] as Map)['type'], 'bearer');
      final requests = (shop['requests'] as List).cast<Map<String, dynamic>>();
      expect(requests.map((r) => r['name']), ['List orders', 'Create order', 'Old order', 'Ping', 'Login', 'Plain']);
      final oldOrder = requests.singleWhere((r) => r['name'] == 'Old order');
      expect((oldOrder['scripts'] as Map)['assertions'], jsonDecode(shopAssertions));
      expect((oldOrder['examples'] as List), hasLength(2));
      final create = requests.singleWhere((r) => r['name'] == 'Create order');
      expect((create['auth'] as Map)['oauth2ClientSecret'], 'client-secret');
      expect((create['auth'] as Map)['oauth2RefreshToken'], 'refresh-token');
    });

    test('a request without tests or examples has neither key', () {
      final requests = ((doc['collections'] as List).first as Map)['requests'] as List;
      final plain = requests.cast<Map<String, dynamic>>().singleWhere((r) => r['name'] == 'Plain');

      expect(plain, isNot(contains('scripts')));
      expect(plain, isNot(contains('examples')));
    });

    test('an empty collection has no auth key', () {
      expect(((doc['collections'] as List).last as Map), isNot(contains('auth')));
    });

    test('requests carry their settings, and collections, folders and requests their descriptions and tags', () {
      final shop = (doc['collections'] as List).first as Map<String, dynamic>;
      final folders = {for (final f in (shop['folders'] as List).cast<Map<String, dynamic>>()) f['name']: f};
      final list = (shop['requests'] as List).cast<Map<String, dynamic>>().singleWhere((r) => r['name'] == 'List orders');

      expect(list['settings'], {'followRedirects': false, 'verifySsl': false, 'timeoutSeconds': 5});
      expect(list, containsPair('description', 'Lists **every** order.'));
      expect(list, containsPair('tags', ['orders', 'read']));
      expect(shop, containsPair('description', '# Shop API'));
      expect(shop, containsPair('tags', ['internal']));
      expect(folders['Archive'], containsPair('description', 'Old orders, read-only.'));
      expect(folders['Orders'], containsPair('tags', ['orders', 'v2']));
      expect(folders['Users'], isNot(anyOf(contains('description'), contains('tags'))));
      final plain = (shop['requests'] as List).cast<Map<String, dynamic>>().singleWhere((r) => r['name'] == 'Plain');
      expect(plain, isNot(anyOf(contains('settings'), contains('description'), contains('tags'))));
    });
  });

  group('restore', () {
    late InMemoryDb source;
    late String backup;

    setUp(() async {
      source = InMemoryDb();
      await seedShop(source);
      backup = (await source.backupService.export()).text;
    });

    test('into an empty database reproduces everything, with fresh ids', () async {
      final target = InMemoryDb()..nextId();
      final summary = await RestoreBackupUseCase(target.backupService)(backup);

      expect(normalizedBackup((await target.backupService.export()).text), normalizedBackup(backup));
      expect(summary.format, ImportFormat.backup);
      expect(summary.collectionIds, hasLength(2));
      expect(summary.folders, 3);
      expect(summary.requests, 6);
      expect(summary.environments, 2);
      expect(summary.globalVariables, 2);
      expect(summary.skipped, 0);
      expect(summary.description, 'Restored 2 collections: 3 folders, 6 requests, 2 environments, 2 global variables');
    });

    test('remaps folder ids: requests end up in the right nested folder', () async {
      final target = InMemoryDb();
      await target.collectionRepository.createFolder(collectionId: await target.collectionRepository.createCollection('Other'), name: 'Noise');

      await target.backupService.restore(backup);

      final shop = target.collections.singleWhere((c) => c.name == 'Shop');
      final folders = {for (final f in target.folders.where((f) => f.collectionId == shop.id)) f.name: f};
      expect(folders['Archive']!.parentFolderId, folders['Orders']!.id);
      final oldOrder = target.requestsOf(shop.id).singleWhere((r) => r.name == 'Old order');
      expect(oldOrder.folderId, folders['Archive']!.id);
      expect(target.requestsOf(shop.id).singleWhere((r) => r.name == 'Ping').folderId, isNull);
      expect(target.scripts[oldOrder.id]!.extractorsJson, shopExtractors);
      expect(target.examples.where((e) => e.requestId == oldOrder.id).map((e) => e.name), unorderedEquals(['200 OK', 'Gone']));
    });

    test('per-request settings, descriptions and tags are re-keyed to the new local ids', () async {
      final target = InMemoryDb();
      await target.collectionRepository.createCollection('Noise');

      await target.backupService.restore(backup);

      final shop = target.collections.singleWhere((c) => c.name == 'Shop');
      final folders = {for (final f in target.folders.where((f) => f.collectionId == shop.id)) f.name: f};
      final list = target.requestsOf(shop.id).singleWhere((r) => r.name == 'List orders');
      expect(target.requestSettings[list.id]!.verifySsl, isFalse);
      expect((target.requestSettings[list.id]!.timeoutSeconds, target.requestSettings[list.id]!.followRedirects), (5, false));
      expect(target.descriptions[InMemoryDb.noteKey(EntityKind.request, list.id)], 'Lists **every** order.');
      expect(target.tags[InMemoryDb.noteKey(EntityKind.request, list.id)], ['orders', 'read']);
      expect(target.descriptions[InMemoryDb.noteKey(EntityKind.collection, shop.id)], '# Shop API');
      expect(target.tags[InMemoryDb.noteKey(EntityKind.collection, shop.id)], ['internal']);
      expect(target.descriptions[InMemoryDb.noteKey(EntityKind.folder, folders['Archive']!.id)], 'Old orders, read-only.');
      expect(target.tags[InMemoryDb.noteKey(EntityKind.folder, folders['Orders']!.id)], ['orders', 'v2']);
      // Nothing else gained anything: only the seeded rows exist.
      expect(target.requestSettings, hasLength(1));
      expect(target.descriptions, hasLength(3));
      expect(target.tags, hasLength(3));
    });

    test('secret values and tokens come back exactly', () async {
      final target = InMemoryDb();

      await target.backupService.restore(backup);

      final create = target.requests.singleWhere((r) => r.name == 'Create order');
      expect(create.auth.oauth2ClientSecret, 'client-secret');
      expect(create.auth.oauth2AccessToken, 'access-token');
      expect(create.auth.oauth2RefreshToken, 'refresh-token');
      expect(create.auth.oauth2TokenExpiry, DateTime.utc(2030));
      expect(target.environmentVariables.singleWhere((v) => v.key == 'password').isSecret, isTrue);
      expect(target.globals.singleWhere((g) => g.key == 'masterKey').value, 'k3y');
      expect(target.globals.singleWhere((g) => g.key == 'masterKey').enabled, isFalse);
      final shop = target.collections.singleWhere((c) => c.name == 'Shop');
      expect(RequestAuth.fromJsonString(target.collectionAuth[shop.id])!.bearerToken, '{{token}}');
    });

    test('never overwrites: existing data stays as it was, new copies get a suffix', () async {
      final target = InMemoryDb();
      final existing = await target.collectionRepository.createCollection('Shop');
      await addRequest(target, existing, 'Mine', url: 'https://mine.test');
      final devId = await target.environmentRepository.create('Dev');
      target.environments[0] = EnvironmentEntity(id: devId, name: 'Dev', isActive: true);
      await target.environmentRepository
          .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: devId, key: 'host', value: 'mine', isSecret: false, enabled: true));
      await target.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'apiVersion', value: '99', isSecret: false, enabled: true));

      final summary = await target.backupService.restore(backup);

      expect(target.collections.map((c) => c.name), ['Shop', 'Shop (restored)', 'Empty']);
      expect(target.requestsOf(existing).single.url, 'https://mine.test');
      expect(target.environments.map((e) => e.name), ['Dev', 'Dev (restored)', 'Prod']);
      expect(target.environments.first.isActive, isTrue);
      expect(target.environments.skip(1).every((e) => !e.isActive), isTrue);
      expect(target.environmentVariables.where((v) => v.environmentId == devId).single.value, 'mine');
      expect(target.globals.singleWhere((g) => g.key == 'apiVersion').value, '99');
      expect(target.globals.map((g) => g.key), ['apiVersion', 'masterKey']);
      expect(summary.globalVariables, 1);
      expect(summary.skipped, 1);
    });

    test('restoring the same backup twice never collides', () async {
      final target = InMemoryDb();

      await target.backupService.restore(backup);
      await target.backupService.restore(backup);
      await target.backupService.restore(backup);

      expect(target.collections.map((c) => c.name),
          ['Shop', 'Empty', 'Shop (restored)', 'Empty (restored)', 'Shop (restored 2)', 'Empty (restored 2)']);
      expect(target.globals, hasLength(2));
    });

    test('a single restored collection is named in the summary', () async {
      final target = InMemoryDb();
      final one = _backupOf({
        'collections': [
          {'name': 'Solo', 'requests': [{'name': 'R', 'url': 'https://a.test'}]},
        ],
      });

      final summary = await target.backupService.restore(one);

      expect(summary.description, 'Restored "Solo": 1 request');
    });

    test('a failure midway leaves no trace of the restore and keeps existing data', () async {
      final target = InMemoryDb();
      final existing = await target.collectionRepository.createCollection('Existing');
      await target.environmentRepository.create('Existing env');
      await target.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'keep', value: '1', isSecret: false, enabled: true));
      target.failSaveRequestOnCall = 4;

      await expectLater(target.backupService.restore(backup), throwsA(isA<StateError>()));

      expect(target.collections.map((c) => c.id), [existing]);
      expect(target.requests, isEmpty);
      expect(target.folders, isEmpty);
      expect(target.environments.map((e) => e.name), ['Existing env']);
      expect(target.globals.map((g) => g.key), ['keep']);
    });

    test('a failure while creating environments also removes the restored collections', () async {
      final target = InMemoryDb();
      target.failCreateEnvironmentOnCall = 2;

      await expectLater(target.backupService.restore(backup), throwsA(isA<StateError>()));

      expect(target.collections, isEmpty);
      expect(target.environments, isEmpty);
      expect(target.environmentVariables, isEmpty);
    });

    test('a failure while adding globals removes what was added, not what was there', () async {
      final target = InMemoryDb();
      await target.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'keep', value: '1', isSecret: false, enabled: true));
      target.failUpsertGlobalOnCall = 3;

      await expectLater(target.backupService.restore(backup), throwsA(isA<StateError>()));

      expect(target.globals.map((g) => g.key), ['keep']);
      expect(target.collections, isEmpty);
      expect(target.environments, isEmpty);
    });

    test('folders whose parent is missing or that form a cycle land at the top level', () async {
      final target = InMemoryDb();
      final odd = _backupOf({
        'collections': [
          {
            'name': 'Odd',
            'folders': [
              {'id': 1, 'parentId': 99, 'name': 'Orphan'},
              {'id': 2, 'parentId': 3, 'name': 'A'},
              {'id': 3, 'parentId': 2, 'name': 'B'},
              {'id': 4, 'parentId': 1, 'name': 'Child'},
            ],
            'requests': [
              {'name': 'In child', 'folderId': 4},
              {'name': 'Nowhere', 'folderId': 42},
            ],
          },
        ],
      });

      await target.backupService.restore(odd);

      final byName = {for (final f in target.folders) f.name: f};
      expect(byName.keys, unorderedEquals(['Orphan', 'A', 'B', 'Child']));
      expect(byName['Orphan']!.parentFolderId, isNull);
      expect(byName['Child']!.parentFolderId, byName['Orphan']!.id);
      expect(byName['A']!.parentFolderId, isNull);
      expect(byName['B']!.parentFolderId, isNull);
      expect(target.requests.singleWhere((r) => r.name == 'In child').folderId, byName['Child']!.id);
      expect(target.requests.singleWhere((r) => r.name == 'Nowhere').folderId, isNull);
    });

    test('a backup with nothing in it is refused', () async {
      await expectLater(InMemoryDb().backupService.restore(_backupOf({})), throwsA(isA<ImportException>()));
    });
  });

  group('rejected files', () {
    Future<void> expectRejected(String text, Matcher message) async {
      final target = InMemoryDb();
      await expectLater(target.backupService.restore(text), throwsA(isA<ImportException>().having((e) => e.message, 'message', message)));
      expect(target.collections, isEmpty);
    }

    test('not JSON', () => expectRejected('hello', contains('not valid JSON')));

    test('JSON that is not a backup', () => expectRejected('{"hello":"world"}', contains('format')));

    test('no version', () => expectRejected('{"format":"postpilot-backup"}', contains('version')));

    test('a version from a newer app', () => expectRejected(_backupOf({'version': BackupCodec.currentVersion + 1}), contains('newer')));

    test('a field of the wrong type', () => expectRejected(_backupOf({'collections': [{'name': 'X', 'auth': {'bearerToken': 5}}]}), contains('damaged')));
  });

  group('codec', () {
    test('tolerates missing optional fields', () {
      final snapshot = BackupCodec.decode(_backupOf({
        'collections': [
          {
            'name': 'Sparse',
            'requests': [
              {'name': 'R'},
            ],
          },
        ],
        'globals': [
          {'key': 'a'},
        ],
      }));

      final request = snapshot.collections.single.requests.single.request;
      expect(request.method, HttpMethod.get);
      expect(request.url, '');
      expect(request.body.type, BodyType.none);
      expect(request.auth.type, AuthType.inherit);
      expect(snapshot.collections.single.auth, isNull);
      expect(snapshot.globals.single.enabled, isTrue);
      expect(snapshot.globals.single.isSecret, isFalse);
    });

    test('a version 1 backup (no settings, descriptions or tags) still restores', () async {
      final target = InMemoryDb();
      final v1 = jsonEncode({
        'format': BackupCodec.formatId,
        'version': 1,
        'collections': [
          {
            'name': 'Old',
            'folders': [
              {'id': 1, 'parentId': null, 'name': 'F'},
            ],
            'requests': [
              {'name': 'R', 'folderId': 1, 'url': 'https://a.test'},
            ],
          },
        ],
      });

      final summary = await target.backupService.restore(v1);

      expect((summary.folders, summary.requests), (1, 1));
      expect(target.requestSettings, isEmpty);
      expect(target.descriptions, isEmpty);
      expect(target.tags, isEmpty);
    });

    test('unreadable settings, and blank or non-text tags, are dropped instead of failing the restore', () {
      final snapshot = BackupCodec.decode(_backupOf({
        'collections': [
          {
            'name': 'C',
            'description': 5,
            'tags': ['ok', '', 3, '  '],
            'requests': [
              {
                'name': 'R',
                'settings': {'verifySsl': 'nope', 'timeoutSeconds': -1},
                'tags': 'not-a-list',
              },
            ],
          },
        ],
      }));

      final collection = snapshot.collections.single;
      expect(collection.notes.description, '');
      expect(collection.notes.tags, ['ok']);
      expect(collection.requests.single.settings, isNull);
      expect(collection.requests.single.notes.isEmpty, isTrue);
    });

    test('drops variables without a key', () {
      final snapshot = BackupCodec.decode(_backupOf({
        'collections': [
          {
            'name': 'C',
            'variables': [
              {'key': '', 'value': 'x'},
              {'key': 'ok', 'value': 'y'},
            ],
          },
        ],
        'environments': [
          {
            'name': 'E',
            'variables': [
              {'value': 'no key'},
            ],
          },
        ],
      }));

      expect(snapshot.collections.single.variables.map((v) => v.key), ['ok']);
      expect(snapshot.environments.single.variables, isEmpty);
    });

    test('the export use case reports the counts of what it wrote', () async {
      final db = InMemoryDb();
      await seedShop(db);

      final export = await ExportBackupUseCase(db.backupService)(const NoParams());

      expect(
        (export.collections, export.folders, export.requests, export.environments, export.globalVariables),
        (2, 3, 6, 2, 2),
      );
    });

    test('an empty database still exports a valid, restorable-as-empty file', () async {
      final export = await InMemoryDb().backupService.export();

      expect(BackupCodec.decode(export.text).collections, isEmpty);
      expect(export.requests, 0);
    });
  });
}
