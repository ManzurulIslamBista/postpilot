// Every importer writes the order of the file it reads (document order, or the file's own sort keys), and a backup
// brings back exactly the arrangement it was made from. Checked on a real (in-memory SQLite) database.
import 'dart:convert';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_insomnia_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_openapi_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';

void main() {
  late AppDatabase db;
  late DriftRepos repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
  });

  tearDown(() => db.close());

  /// The collection as the sidebar draws it: indented names, folders in brackets.
  Future<List<String>> tree(int c) async {
    final folders = await (db.select(db.folders)..where((t) => t.collectionId.equals(c))).get();
    final requests = await (db.select(db.requests)..where((t) => t.collectionId.equals(c))).get();
    final canonical = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    );
    return [
      for (final e in canonical.entries)
        '${'  ' * e.depth}${e.isFolder ? '[${folders[e.index].name}]' : requests[e.index].name}',
    ];
  }

  /// name -> stored index of the children of one parent.
  Future<Map<String, int>> level(int c, {int? parent}) async {
    final folders = await (db.select(db.folders)
          ..where((t) => t.collectionId.equals(c) & (parent == null ? t.parentFolderId.isNull() : t.parentFolderId.equals(parent))))
        .get();
    final requests = await (db.select(db.requests)
          ..where((t) => t.collectionId.equals(c) & (parent == null ? t.folderId.isNull() : t.folderId.equals(parent))))
        .get();
    return {for (final f in folders) f.name: f.orderIndex, for (final r in requests) r.name: r.orderIndex};
  }

  test('a Postman collection keeps its order, a request before a folder before a request included', () async {
    const postman = '''
{"info":{"name":"Seq","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[
 {"name":"First","request":{"method":"GET","url":"https://api.test/first"}},
 {"name":"Mid","item":[
    {"name":"Inner A","request":{"method":"GET","url":"https://api.test/a"}},
    {"name":"Deep","item":[{"name":"Deepest","request":{"method":"GET","url":"https://api.test/deepest"}}]},
    {"name":"Inner B","request":{"method":"GET","url":"https://api.test/b"}}]},
 {"name":"Last","request":{"method":"GET","url":"https://api.test/last"}}]}
''';
    final c = await ImportPostmanCollectionUseCase(
      repos.collectionRepository,
      repos.requestRepository,
      repos.collectionVariableRepository,
      repos.collectionAuthRepository,
      repos.scriptsRepository,
    )(postman);

    expect(await tree(c), ['First', '[Mid]', '  Inner A', '  [Deep]', '    Deepest', '  Inner B', 'Last']);
    expect(await level(c), {'First': 0, 'Mid': 1, 'Last': 2});
    final mid = (await (db.select(db.folders)..where((t) => t.name.equals('Mid'))).getSingle()).id;
    expect(await level(c, parent: mid), {'Inner A': 0, 'Deep': 1, 'Inner B': 2});
  });

  test('an Insomnia export is ordered by its sort keys, folders and requests on one scale', () async {
    const insomnia = r'''
{"_type":"export","__export_format":4,"resources":[
 {"_id":"wrk_1","_type":"workspace","parentId":null,"name":"Shop"},
 {"_id":"req_c","_type":"request","parentId":"wrk_1","name":"Third","method":"GET","url":"https://api.test/3","metaSortKey":-1},
 {"_id":"fld_a","_type":"request_group","parentId":"wrk_1","name":"Group","metaSortKey":-3},
 {"_id":"req_b","_type":"request","parentId":"wrk_1","name":"Second","method":"GET","url":"https://api.test/2","metaSortKey":-2},
 {"_id":"req_y","_type":"request","parentId":"fld_a","name":"In group B","method":"GET","url":"https://api.test/y","metaSortKey":-1},
 {"_id":"req_x","_type":"request","parentId":"fld_a","name":"In group A","method":"GET","url":"https://api.test/x","metaSortKey":-5}
]}
''';

    final summary = await ImportInsomniaUseCase(repos.writer, repos.collectionRepository, repos.environmentRepository)(insomnia);

    final c = summary.collectionIds.single;
    expect(await tree(c), ['[Group]', '  In group A', '  In group B', 'Second', 'Third']);
    expect(await level(c), {'Group': 0, 'Second': 1, 'Third': 2});
  });

  test('a HAR recording keeps the order of the calls', () async {
    final har = jsonEncode({
      'log': {
        'version': '1.2',
        'entries': [
          for (final path in ['/one', '/two', '/three', '/four'])
            {
              'request': {'method': 'GET', 'url': 'https://shop.example.com/api$path', 'headers': <Object>[]},
              'response': {'status': 200, 'headers': <Object>[], 'content': {'mimeType': 'application/json'}},
            },
        ],
      },
    });

    final summary = await ImportHarUseCase(repos.writer)(har);

    expect(await tree(summary.collectionIds.single), ['GET /api/one', 'GET /api/two', 'GET /api/three', 'GET /api/four']);
  });

  test('an OpenAPI document gets its tag folders first and the untagged requests after, each in document order', () async {
    const openApi = '''
{"openapi":"3.0.0","info":{"title":"Zoo","version":"1"},"paths":{
 "/health":{"get":{"summary":"Health"}},
 "/pets":{"get":{"tags":["pets"],"summary":"List pets"},"post":{"tags":["pets"],"summary":"Add pet"}},
 "/users":{"get":{"tags":["users"],"summary":"List users"}},
 "/ping":{"get":{"summary":"Ping"}}}}
''';

    final c = await ImportOpenApiUseCase(
      repos.collectionRepository,
      repos.requestRepository,
      repos.collectionVariableRepository,
      repos.environmentRepository,
    )(openApi);

    final lines = await tree(c);
    final topLevel = lines.where((l) => !l.startsWith(' ')).toList();
    // [pets], [users], then the two requests without a tag, Health before Ping as in the document
    expect(topLevel.take(2), ['[pets]', '[users]'], reason: 'tag folders first, in document order');
    final rest = topLevel.skip(2).map((l) => l.toLowerCase()).toList();
    expect(rest, hasLength(2));
    expect(rest.first, contains('health'));
    expect(rest.last, contains('ping'));
    expect(lines.where((l) => l.startsWith('  ')).length, 3, reason: 'the three tagged requests sit inside their folders');
  });

  test('cURL commands pasted into an existing collection go after what is already there', () async {
    final c = await repos.collectionRepository.createCollection('Mine');
    final f = await repos.collectionRepository.createFolder(collectionId: c, name: 'Inbox');
    await repos.requestRepository.createRequest(collectionId: c, name: 'Existing');
    await repos.requestRepository.createRequest(collectionId: c, folderId: f, name: 'Old in inbox');

    await ImportCurlScriptUseCase(repos.writer)(
      ImportCurlScriptParams(script: '# One\ncurl https://a.test/1\n# Two\ncurl https://a.test/2', collectionId: c, folderId: f),
    );
    await ImportCurlScriptUseCase(repos.writer)(
      ImportCurlScriptParams(script: '# Three\ncurl https://a.test/3', collectionId: c),
    );

    expect(await tree(c), ['[Inbox]', '  Old in inbox', '  One', '  Two', 'Existing', 'Three']);
  });

  group('backup files', () {
    Future<int> restoreInto(DriftRepos target, String text) async {
      final summary = await target.backupService.restore(text);
      return summary.collectionIds.single;
    }

    test('a file that says where each folder and request sits is restored exactly that way', () async {
      final text = jsonEncode({
        'format': 'postpilot-backup',
        'version': 2,
        'collections': [
          {
            'name': 'Arranged',
            'folders': [
              {'id': 1, 'parentId': null, 'name': 'F', 'order': 1},
              {'id': 2, 'parentId': 1, 'name': 'Sub', 'order': 0},
            ],
            'requests': [
              {'name': 'Last', 'folderId': null, 'order': 2},
              {'name': 'In sub', 'folderId': 2, 'order': 0},
              {'name': 'First', 'folderId': null, 'order': 0},
              {'name': 'In F after sub', 'folderId': 1, 'order': 1},
            ],
          },
        ],
      });

      final c = await restoreInto(repos, text);

      expect(await tree(c), ['First', '[F]', '  [Sub]', '    In sub', '  In F after sub', 'Last']);
      expect(await level(c), {'First': 0, 'F': 1, 'Last': 2}, reason: 'positions are stored as the file gives them');
    });

    test('a file written before order existed lists folders first, then requests, each in file order', () async {
      final text = jsonEncode({
        'format': 'postpilot-backup',
        'version': 2,
        'collections': [
          {
            'name': 'Old',
            'folders': [
              {'id': 7, 'parentId': null, 'name': 'Z folder'},
              {'id': 3, 'parentId': null, 'name': 'A folder'},
            ],
            'requests': [
              {'name': 'req 1', 'folderId': null},
              {'name': 'in Z', 'folderId': 7},
              {'name': 'req 2', 'folderId': null},
            ],
          },
        ],
      });

      final c = await restoreInto(repos, text);

      expect(await tree(c), ['[Z folder]', '  in Z', '[A folder]', 'req 1', 'req 2']);
    });

    test('a file with order on only some entries falls back to file order for that level, so nothing is lost', () async {
      final text = jsonEncode({
        'format': 'postpilot-backup',
        'version': 2,
        'collections': [
          {
            'name': 'Half',
            'folders': <Object>[],
            'requests': [
              {'name': 'a', 'folderId': null, 'order': 5},
              {'name': 'b', 'folderId': null},
              {'name': 'c', 'folderId': null, 'order': 1},
            ],
          },
        ],
      });

      final c = await restoreInto(repos, text);

      expect(await tree(c), ['a', 'b', 'c']);
    });

    test('exporting what was arranged and restoring it elsewhere gives the same arrangement, in a second database', () async {
      final source = await repos.collectionRepository.createCollection('Source');
      final folder = await repos.collectionRepository.createFolder(collectionId: source, name: 'F');
      await repos.requestRepository.createRequest(collectionId: source, name: 'tail');
      await repos.requestRepository.createRequest(collectionId: source, folderId: folder, name: 'inside');
      final request = (await repos.requestRepository.watchByCollection(source).first).firstWhere((r) => r.name == 'tail');
      // the user drags "tail" in front of the folder
      await db.collectionsDao.moveRequest(request.id, collectionId: source, before: OrderRef.folder(folder));
      expect(await tree(source), ['tail', '[F]', '  inside']);

      final text = (await repos.backupService.export()).text;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = DriftRepos(other);
      final restored = await restoreInto(target, text);

      final folders = await (other.select(other.folders)..where((t) => t.collectionId.equals(restored))).get();
      final requests = await (other.select(other.requests)..where((t) => t.collectionId.equals(restored))).get();
      final canonical = CollectionOrder.of(
        folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
        requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
      );
      expect([for (final e in canonical.entries) e.isFolder ? folders[e.index].name : requests[e.index].name], ['tail', 'F', 'inside']);
    });
  });

  test('the in-memory fakes used elsewhere still import and list in creation order (no order stored)', () async {
    final memory = InMemoryDb();
    final c = await memory.collectionRepository.createCollection('Mem');
    final f = await memory.collectionRepository.createFolder(collectionId: c, name: 'F');
    await memory.requestRepository.createRequest(collectionId: c, name: 'r');
    await memory.requestRepository.createRequest(collectionId: c, folderId: f, name: 'in F');

    final loaded = await memory.loader.load(c);

    expect(loaded.requests.map((r) => r.name), ['in F', 'r'], reason: 'a folder before the requests beside it, as before');
  });
}
