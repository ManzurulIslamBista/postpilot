// The refactoring tools over the real repositories and a real (in-memory SQLite) database: the changes must land in
// every table the screens read, as one operation, and undo must put the database back exactly as it was.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/level_units.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_plan.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_receipt.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/unit_field.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_scope.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/variable_units.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_applier.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_writer.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_renamer.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_report.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_finder.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_reader.dart';

import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'refactor_fixtures.dart' show row;

void main() {
  late AppDatabase db;
  late DriftRepos r;
  late WorkspaceReader reader;
  late RefactorApplier applier;

  RepositoryRefactorWriter realWriter() => RepositoryRefactorWriter(
    r.requestRepository,
    r.scriptsRepository,
    r.exampleRepository,
    r.collectionRepository,
    r.collectionAuthRepository,
    r.collectionVariableRepository,
    r.defaultsRepository,
    r.environmentRepository,
    r.globalVariableRepository,
    r.documentationRepository,
    r.tagRepository,
  );
  late int shop;
  late int orders;
  late int list;
  late int untouched;
  late int dev;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    r = DriftRepos(db);
    reader = WorkspaceReader(
      r.loader,
      r.environmentRepository,
      r.globalVariableRepository,
      r.scriptsRepository,
      r.exampleRepository,
      r.documentationRepository,
      r.tagRepository,
    );
    // As the app wires it: every apply and undo is one database transaction.
    applier = RefactorApplier(reader, realWriter(), atomically: db.transaction);

    shop = await r.collectionRepository.createCollection('Acme Shop');
    await r.collectionAuthRepository.setAuthJson(shop, const RequestAuth(type: AuthType.bearer, bearerToken: '{{acmeToken}}').toJsonString());
    await r.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: shop, key: 'acmeHost', value: 'https://acme.test', enabled: true),
    );
    await r.documentationRepository.setMarkdown(EntityKind.collection, shop, 'Docs for acme');
    await r.tagRepository.setTags(EntityKind.collection, shop, ['acme', 'core']);
    await r.defaultsRepository.saveCollection(
      shop,
      LevelDefaults(headers: [row('X-Acme', 'acme-default')], assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]),
    );
    orders = await r.collectionRepository.createFolder(collectionId: shop, name: 'Acme Orders');
    await r.defaultsRepository.saveFolder(
      orders,
      LevelDefaults(
        headers: [row('X-Folder', 'acme')],
        variables: [
          DefaultVariable(key: 'acmeFolder', value: 'acme folder'),
          DefaultVariable(key: 'acmeSecret', value: 'acme-s3cret', isSecret: true),
          DefaultVariable(key: 'neverUsed', value: 'x'),
        ],
        auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-Acme', apiKeyValue: '{{acmeToken}}'),
        extractors: [ExtractorEntity(path: r'$.id', variableKey: 'acmeOrder')],
      ),
    );
    await r.documentationRepository.setMarkdown(EntityKind.folder, orders, 'Orders of acme');
    await r.tagRepository.setTags(EntityKind.folder, orders, ['acme-orders']);

    list = await addRequest(
      r,
      shop,
      'List acme orders',
      folderId: orders,
      url: '{{acmeHost}}/orders',
      query: [row('owner', 'acme')],
      headers: [row('X-Acme', 'acme')],
      body: const RequestBody(type: BodyType.raw, rawText: '{"owner":"acme"}'),
      auth: const RequestAuth(type: AuthType.basic, basicUsername: 'acme-user', basicPassword: 'acme-pw'),
    );
    await r.scriptsRepository.save(
      RequestScriptsEntity(
        requestId: list,
        assertionsJson: ScriptsJsonCodec.encodeAssertions([AssertionEntity(type: AssertionType.bodyContains, expected: 'acme')]),
        extractorsJson: ScriptsJsonCodec.encodeExtractors([ExtractorEntity(path: r'$.token', variableKey: 'acmeToken')]),
      ),
    );
    await r.documentationRepository.setMarkdown(EntityKind.request, list, 'Lists the acme orders');
    await r.tagRepository.setTags(EntityKind.request, list, ['acme', 'read']);
    await r.exampleRepository.add(
      ResponseExampleEntity(
        id: 0,
        requestId: list,
        name: 'acme ok',
        statusCode: 200,
        headers: const {'x-acme': 'acme', 'content-type': 'application/json'},
        body: '{"acme":true}',
        savedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await r.exampleRepository.add(
      ResponseExampleEntity(id: 0, requestId: list, name: 'second', statusCode: 404, headers: const {}, body: '{"n":1}', savedAt: DateTime.utc(2026, 1, 1)),
    );
    untouched = await addRequest(r, shop, 'Untouched', url: 'https://other.test');

    dev = await r.environmentRepository.create('Dev');
    await r.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: dev, key: 'acmeToken', value: 'tok-acme', isSecret: false, enabled: true),
    );
    await r.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: dev, key: 'apiKey', value: 'sk-acme', isSecret: true, enabled: true),
    );
    await r.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: dev, key: 'legacy', value: 'old', isSecret: false, enabled: true),
    );
    await r.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'acmeGlobal', value: 'acme global', isSecret: false, enabled: true),
    );
    await r.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'unusedGlobal', value: 'g', isSecret: false, enabled: true),
    );
  });

  tearDown(() => db.close());

  /// Every text of the workspace as one sorted list, without ids: what two databases must share to hold the same.
  Future<List<String>> dump() async {
    final snapshot = await reader.read();
    return [
      for (final unit in snapshot.units) ...[
        for (final field in unit.fields()) '${unit.kind.name} | ${unit.trail.join(' / ')} | ${field.path} = ${field.value}',
        // The switches that are not text: whether a variable is secret or switched off.
        if (unit is VariableRowUnit) '${unit.kind.name} | ${unit.trail.join(' / ')} | ${unit.name} flags = secret:${unit.isSecret} enabled:${unit.enabled}',
        if (unit is FolderUnit)
          for (final v in unit.defaults.variables) 'folder | ${unit.trail.join(' / ')} | ${v.key} flags = secret:${v.isSecret} enabled:${v.enabled}',
      ],
    ]..sort();
  }

  Future<String> backup() async => normalizedBackup((await r.backupService.export()).text).toString();

  group('find and replace', () {
    test('lands in every table the screens read, and undo puts every table back', () async {
      final before = await dump();
      final backupBefore = await backup();
      final snapshot = await reader.read();
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'zeta');

      final receipt = await applier.apply(plan, editIds: plan.editIds);

      // Names.
      expect((await r.collectionRepository.watchCollections().first).map((c) => c.name), ['zeta Shop']);
      expect((await r.collectionRepository.watchFolders(shop).first).single.name, 'zeta Orders');
      // The request itself.
      final request = (await r.requestRepository.findById(list))!;
      expect(request.name, 'List zeta orders');
      expect(request.url, '{{zetaHost}}/orders');
      expect(request.queryParams.single.value, 'zeta');
      expect(request.headers.single.key, 'X-zeta');
      expect(request.headers.single.value, 'zeta');
      expect(request.body.rawText, '{"owner":"zeta"}');
      expect(request.auth.basicUsername, 'zeta-user');
      // A secret is left alone unless asked for.
      expect(request.auth.basicPassword, 'acme-pw');
      // Tests, notes, tags, examples.
      final scripts = (await r.scriptsRepository.get(list))!;
      expect(ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson).single.expected, 'zeta');
      expect(ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson).single.variableKey, 'zetaToken');
      expect(await r.documentationRepository.markdownOf(EntityKind.request, list), 'Lists the zeta orders');
      expect((await r.tagRepository.tagsByLocalId(EntityKind.request))[list], ['read', 'zeta']);
      final examples = await r.exampleRepository.watchByRequest(list).first;
      expect([for (final e in examples) e.name], ['zeta ok', 'second']);
      expect(examples.first.body, '{"zeta":true}');
      expect(examples.first.headers, {'x-acme': 'zeta', 'content-type': 'application/json'});
      expect(examples.last.body, '{"n":1}');
      // The collection and the folder.
      expect(RequestAuth.fromJsonString(await r.collectionAuthRepository.getAuthJson(shop))!.bearerToken, '{{zetaToken}}');
      expect((await r.collectionVariableRepository.watchByCollection(shop).first).single.key, 'zetaHost');
      expect((await r.collectionVariableRepository.watchByCollection(shop).first).single.value, 'https://zeta.test');
      expect(await r.documentationRepository.markdownOf(EntityKind.collection, shop), 'Docs for zeta');
      final collectionDefaults = await r.defaultsRepository.getCollection(shop);
      expect(collectionDefaults.headers.single.key, 'X-zeta');
      expect(collectionDefaults.headers.single.value, 'zeta-default');
      final folderDefaults = await r.defaultsRepository.getFolder(orders);
      expect(folderDefaults.headers.single.value, 'zeta');
      expect([for (final v in folderDefaults.variables) v.key], ['zetaFolder', 'zetaSecret', 'neverUsed']);
      expect(folderDefaults.variables[0].value, 'zeta folder');
      expect(folderDefaults.variables[1].value, 'acme-s3cret', reason: 'a secret value');
      expect(folderDefaults.variables[1].isSecret, isTrue);
      expect(folderDefaults.auth!.apiKeyName, 'X-zeta');
      expect(folderDefaults.auth!.apiKeyValue, '{{zetaToken}}');
      expect(folderDefaults.extractors.single.variableKey, 'zetaOrder');
      // Environments and globals.
      final envVars = await r.environmentRepository.watchVariables(dev).first;
      expect([for (final v in envVars) '${v.key}=${v.value}'], ['zetaToken=tok-zeta', 'apiKey=sk-acme', 'legacy=old']);
      expect([for (final g in await r.globalVariableRepository.watchAll().first) '${g.key}=${g.value}'], ['zetaGlobal=zeta global', 'unusedGlobal=g']);
      // What did not match is as it was.
      final other = (await r.requestRepository.findById(untouched))!;
      expect([other.name, other.url], ['Untouched', 'https://other.test']);

      expect(receipt.editsApplied, plan.editCount);
      expect(await dump(), isNot(before));

      final outcome = await applier.undo(receipt);

      expect(outcome.skipped, isEmpty);
      expect(await dump(), before);
      expect(await backup(), backupBefore);
    });

    test('with "include secret values" the secrets change too, and undo still restores them', () async {
      final before = await dump();
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta', includeSecret: true);

      final receipt = await applier.apply(plan, editIds: plan.editIds);

      expect((await r.requestRepository.findById(list))!.auth.basicPassword, 'zeta-pw');
      expect((await r.defaultsRepository.getFolder(orders)).variables[1].value, 'zeta-s3cret');
      expect((await r.environmentRepository.watchVariables(dev).first)[1].value, 'sk-zeta');

      await applier.undo(receipt);
      expect(await dump(), before);
      expect((await r.environmentRepository.watchVariables(dev).first)[1].isSecret, isTrue);
    });

    test('only the occurrences that were ticked are replaced', () async {
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta', scopes: {RefactorScope.urls, RefactorScope.headers});
      // Of the headers, only the value; the key stays.
      final urlEdit = plan.changes.firstWhere((c) => c.path == 'url').edits.single.id;

      await applier.apply(plan, editIds: {urlEdit});

      final request = (await r.requestRepository.findById(list))!;
      expect(request.url, '{{zetaHost}}/orders');
      expect(request.headers.single.key, 'X-Acme');
      expect(request.headers.single.value, 'acme');
    });

    test('the same repositories the screens listen to tell their listeners', () async {
      final seen = <String>[];
      final sub = r.requestRepository.watchById(list).listen((request) => seen.add(request!.name));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta', scopes: {RefactorScope.names});

      await applier.apply(plan, editIds: plan.editIds);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(seen.first, 'List acme orders');
      expect(seen.last, 'List zeta orders');
    });

    test('a text edited after the preview is not overwritten', () async {
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta', scopes: {RefactorScope.urls});
      final request = (await r.requestRepository.findById(list))!;
      await r.requestRepository.saveRequest(request.copyWith(url: '{{acmeHost}}/orders?by=hand'));

      final receipt = await applier.apply(plan, editIds: plan.editIds);

      expect(receipt.stale, 1);
      expect(receipt.isEmpty, isTrue);
      expect((await r.requestRepository.findById(list))!.url, '{{acmeHost}}/orders?by=hand');
    });

    test('undo does not overwrite what was edited after the replace', () async {
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta');
      final receipt = await applier.apply(plan, editIds: plan.editIds);
      await r.documentationRepository.setMarkdown(EntityKind.request, list, 'Rewritten by hand');

      final outcome = await applier.undo(receipt);

      expect(outcome.skipped.single, contains('List zeta orders'));
      expect(await r.documentationRepository.markdownOf(EntityKind.request, list), 'Rewritten by hand');
      // The rest was put back.
      expect((await r.collectionRepository.watchCollections().first).single.name, 'Acme Shop');
    });
  });

  group('when a write fails', () {
    Future<void> failsAndKeepsNothing(RefactorApplier failing) async {
      final before = await dump();
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta');

      await expectLater(
        failing.apply(plan, editIds: plan.editIds),
        throwsA(isA<RefactorException>().having((e) => e.message, 'message', contains('none were kept'))),
      );

      expect(await dump(), before);
    }

    test('in a transaction the database rolls every change back', () async {
      await failsAndKeepsNothing(RefactorApplier(reader, _FailingWriter(realWriter(), onCall: 3), atomically: db.transaction));
    });

    test('without one the writes already made are written back by hand', () async {
      await failsAndKeepsNothing(RefactorApplier(reader, _FailingWriter(realWriter(), onCall: 3)));
    });

    test('the table listeners hear of the whole change once it is committed', () async {
      final names = <String>[];
      final sub = r.collectionRepository.watchFolders(shop).listen((folders) => names.add(folders.single.name));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final plan = WorkspaceFinder.plan(await reader.read(), const FindOptions(query: 'acme'), 'zeta');

      await applier.apply(plan, editIds: plan.editIds);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Never a half-way state: the folder is seen as it was, then as it became.
      expect(names.first, 'Acme Orders');
      expect(names.last, 'zeta Orders');
      expect(names.toSet().difference({'Acme Orders', 'zeta Orders'}), isEmpty);
    });
  });

  group('rename a variable everywhere', () {
    test('changes the definitions and every reference, and undo restores them', () async {
      final before = await dump();
      final backupBefore = await backup();
      final plan = VariableRenamer.plan(await reader.read(), 'acmeToken', 'apiToken');
      expect(plan.conflicts, isEmpty);

      final receipt = await applier.apply(plan, editIds: plan.editIds);

      // Definitions: the environment variable, the request's extractor.
      expect([for (final v in await r.environmentRepository.watchVariables(dev).first) v.key], ['apiToken', 'apiKey', 'legacy']);
      final scripts = (await r.scriptsRepository.get(list))!;
      expect(ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson).single.variableKey, 'apiToken');
      // References: the collection's auth, the folder's auth.
      expect(RequestAuth.fromJsonString(await r.collectionAuthRepository.getAuthJson(shop))!.bearerToken, '{{apiToken}}');
      expect((await r.defaultsRepository.getFolder(orders)).auth!.apiKeyValue, '{{apiToken}}');
      // Everything else, the names and values that merely contain "acme", is as it was.
      expect((await r.requestRepository.findById(list))!.name, 'List acme orders');
      expect((await r.environmentRepository.watchVariables(dev).first).first.value, 'tok-acme');

      await applier.undo(receipt);
      expect(await dump(), before);
      expect(await backup(), backupBefore);
    });

    test('a merge deletes the old definition, keeps the existing value and can be undone', () async {
      await r.environmentRepository.upsertVariable(
        EnvironmentVariableEntity(id: 0, environmentId: dev, key: 'apiToken', value: 'existing-token', isSecret: false, enabled: true),
      );
      final before = await dump();
      final plan = VariableRenamer.plan(await reader.read(), 'acmeToken', 'apiToken');
      expect(plan.needsConfirmation, isTrue);
      expect(plan.conflicts.single.collides, isTrue);

      final receipt = await applier.apply(plan, editIds: plan.editIds, mergeConfirmed: true);

      final vars = await r.environmentRepository.watchVariables(dev).first;
      expect([for (final v in vars) '${v.key}=${v.value}'], ['apiKey=sk-acme', 'legacy=old', 'apiToken=existing-token']);
      expect(RequestAuth.fromJsonString(await r.collectionAuthRepository.getAuthJson(shop))!.bearerToken, '{{apiToken}}');
      expect(receipt.deleted, hasLength(1));

      await applier.undo(receipt);
      expect(await dump(), before);
    });
  });

  group('unused variables', () {
    test('are deleted from the tables they live in, and undo adds them back', () async {
      final before = await dump();
      final report = VariableReport.build(await reader.read());
      final names = [for (final u in report.unused) u.name];
      expect(names, containsAll(['legacy', 'unusedGlobal', 'neverUsed']));
      final plan = RefactorPlan(title: 'Delete unused variables', deletions: [for (final u in report.unused) ...u.definitions]);

      final receipt = await applier.apply(plan, editIds: {});

      expect((await r.environmentRepository.watchVariables(dev).first).map((v) => v.key), isNot(contains('legacy')));
      expect((await r.globalVariableRepository.watchAll().first).map((g) => g.key), isNot(contains('unusedGlobal')));
      expect((await r.defaultsRepository.getFolder(orders)).variables.map((v) => v.key), isNot(contains('neverUsed')));
      expect(receipt.deletionsApplied, plan.deletions.length);

      final outcome = await applier.undo(receipt);

      expect(outcome.skipped, isEmpty);
      expect(await dump(), before);
    });
  });

  group('a workspace with everything in it', () {
    test('a find and replace over the shop fixture, then undo, leaves the backup byte for byte as it was', () async {
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      final repos = DriftRepos(db2);
      await seedShop(repos);
      final shopReader = WorkspaceReader(
        repos.loader,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.scriptsRepository,
        repos.exampleRepository,
        repos.documentationRepository,
        repos.tagRepository,
      );
      final shopApplier = RefactorApplier(
        shopReader,
        RepositoryRefactorWriter(
          repos.requestRepository,
          repos.scriptsRepository,
          repos.exampleRepository,
          repos.collectionRepository,
          repos.collectionAuthRepository,
          repos.collectionVariableRepository,
          repos.defaultsRepository,
          repos.environmentRepository,
          repos.globalVariableRepository,
          repos.documentationRepository,
          repos.tagRepository,
        ),
      );
      final backupBefore = normalizedBackup((await repos.backupService.export()).text).toString();

      final plan = WorkspaceFinder.plan(await shopReader.read(), const FindOptions(query: 'order'), 'purchase', includeSecret: true);
      expect(plan.editCount, greaterThan(5));
      final receipt = await shopApplier.apply(plan, editIds: plan.editIds);
      expect(normalizedBackup((await repos.backupService.export()).text).toString(), isNot(backupBefore));
      expect(receipt.unitCount, greaterThan(3));

      await shopApplier.undo(receipt);

      expect(normalizedBackup((await repos.backupService.export()).text).toString(), backupBefore);
    });
  });
}

/// A writer that fails on one of its calls and does what the real one does on every other.
final class _FailingWriter implements RefactorWriter {
  final RefactorWriter _real;
  final int onCall;
  int _calls = 0;
  _FailingWriter(this._real, {required this.onCall});

  @override
  Future<Map<int, int>> write(RefactorUnit current, RefactorUnit target, Set<String> groups) {
    if (++_calls == onCall) throw StateError('disk full');
    return _real.write(current, target, groups);
  }

  @override
  Future<void> delete(RefactorUnit unit) => _real.delete(unit);

  @override
  Future<void> recreate(RefactorUnit unit) => _real.recreate(unit);
}
