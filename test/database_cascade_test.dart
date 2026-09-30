import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> addRequest(int collectionId, {int? folderId, String name = 'request'}) => db.requestsDao.createRequest(
        RequestsCompanion.insert(collectionId: collectionId, folderId: Value(folderId), name: name),
      );

  Future<void> addTestsAndExample(int requestId) async {
    await db.requestScriptsDao.upsert(RequestScriptsCompanion.insert(requestId: Value(requestId)));
    await db.responseExamplesDao.add(ResponseExamplesCompanion.insert(requestId: requestId, name: 'ok', statusCode: 200));
  }

  test('deleting a folder removes its requests and sub-folders at any depth, and nothing else', () async {
    final collectionId = await db.collectionsDao.createCollection('c');
    final folderId = await db.collectionsDao.createFolder(collectionId: collectionId, name: 'f');
    final subFolderId =
        await db.collectionsDao.createFolder(collectionId: collectionId, parentFolderId: folderId, name: 'sub');
    final siblingFolderId = await db.collectionsDao.createFolder(collectionId: collectionId, name: 'sibling');
    await addRequest(collectionId, folderId: folderId);
    await addRequest(collectionId, folderId: subFolderId);
    final siblingRequestId = await addRequest(collectionId, folderId: siblingFolderId);
    final rootRequestId = await addRequest(collectionId);

    await db.collectionsDao.deleteFolder(folderId);

    expect((await db.select(db.folders).get()).map((f) => f.id), [siblingFolderId]);
    expect((await db.select(db.requests).get()).map((r) => r.id), unorderedEquals([siblingRequestId, rootRequestId]));
  });

  test('deleting a collection removes everything that belongs to it', () async {
    final collectionId = await db.collectionsDao.createCollection('c');
    final folderId = await db.collectionsDao.createFolder(collectionId: collectionId, name: 'f');
    final requestId = await addRequest(collectionId, folderId: folderId);
    await addTestsAndExample(requestId);
    await db.collectionVariablesDao.addVariable(CollectionVariablesCompanion.insert(collectionId: collectionId, key: 'k'));
    await db.collectionAuthDao.upsert(collectionId, '{}');
    final otherCollectionId = await db.collectionsDao.createCollection('other');
    final otherRequestId = await addRequest(otherCollectionId);

    await db.collectionsDao.deleteCollection(collectionId);

    expect((await db.select(db.collections).get()).map((c) => c.id), [otherCollectionId]);
    expect(await db.select(db.folders).get(), isEmpty);
    expect((await db.select(db.requests).get()).map((r) => r.id), [otherRequestId]);
    expect(await db.select(db.requestScripts).get(), isEmpty);
    expect(await db.select(db.responseExamples).get(), isEmpty);
    expect(await db.select(db.collectionVariables).get(), isEmpty);
    expect(await db.select(db.collectionAuth).get(), isEmpty);
  });

  test('deleting a request removes its tests and response examples', () async {
    final collectionId = await db.collectionsDao.createCollection('c');
    final requestId = await addRequest(collectionId);
    await addTestsAndExample(requestId);

    await db.requestsDao.deleteRequest(requestId);

    expect(await db.select(db.requestScripts).get(), isEmpty);
    expect(await db.select(db.responseExamples).get(), isEmpty);
  });

  test('deleting an environment removes its variables', () async {
    final environmentId = await db.environmentsDao.create('staging');
    await db.environmentsDao.addVariable(EnvironmentVariablesCompanion.insert(environmentId: environmentId, key: 'k'));

    await db.environmentsDao.deleteEnvironment(environmentId);

    expect(await db.select(db.environmentVariables).get(), isEmpty);
  });

  test('duplicating a request carries its tests and response examples along', () async {
    final collectionId = await db.collectionsDao.createCollection('c');
    final requestId = await addRequest(collectionId);
    await addTestsAndExample(requestId);

    final copyId = await db.collectionsDao.duplicateRequest(requestId);

    expect(copyId, isNot(requestId));
    expect((await db.select(db.requestScripts).get()).map((s) => s.requestId), unorderedEquals([requestId, copyId]));
    expect((await db.select(db.responseExamples).get()).map((e) => e.requestId), unorderedEquals([requestId, copyId]));
  });

  test('duplicating a collection carries every request\'s tests and response examples along', () async {
    final collectionId = await db.collectionsDao.createCollection('c');
    final folderId = await db.collectionsDao.createFolder(collectionId: collectionId, name: 'f');
    await addTestsAndExample(await addRequest(collectionId));
    await addTestsAndExample(await addRequest(collectionId, folderId: folderId));

    await db.collectionsDao.duplicateCollection(collectionId);

    expect(await db.select(db.requests).get(), hasLength(4));
    expect(await db.select(db.requestScripts).get(), hasLength(4));
    expect(await db.select(db.responseExamples).get(), hasLength(4));
  });

  group('duplicating carries the description, tags and settings along', () {
    const requestSettings = '{"verifySsl":false,"timeoutSeconds":5}';

    Future<void> annotate(String kind, int id, String name) async {
      await db.entityDocsDao.setMarkdown(kind, id, 'About $name');
      await db.entityTagsDao.setTags(kind, id, ['$name-tag', 'Shared']);
    }

    Future<void> expectAnnotated(String kind, int id, String name) async {
      expect(await db.entityDocsDao.markdownOf(kind, id), 'About $name', reason: '$kind $name description');
      expect(await db.entityTagsDao.tagsOf(kind, id), ['$name-tag', 'Shared'], reason: '$kind $name tags');
    }

    Future<int> folderNamed(int collectionId, String name) async =>
        (await (db.select(db.folders)..where((t) => t.collectionId.equals(collectionId) & t.name.equals(name))).getSingle()).id;

    Future<int> requestNamed(int collectionId, String name) async => (await (db.select(db.requests)
              ..where((t) => t.collectionId.equals(collectionId) & t.name.equals(name)))
            .getSingle())
        .id;

    /// C > [r1, F > [r2, G > [r3]]], everything annotated, r1 and r3 with settings.
    Future<({int c, int f, int g, int r1, int r2, int r3})> seedTree() async {
      final c = await db.collectionsDao.createCollection('C');
      final f = await db.collectionsDao.createFolder(collectionId: c, name: 'F');
      final g = await db.collectionsDao.createFolder(collectionId: c, parentFolderId: f, name: 'G');
      final r1 = await addRequest(c, name: 'r1');
      final r2 = await addRequest(c, folderId: f, name: 'r2');
      final r3 = await addRequest(c, folderId: g, name: 'r3');
      await annotate('collection', c, 'C');
      await annotate('folder', f, 'F');
      await annotate('folder', g, 'G');
      await annotate('request', r1, 'r1');
      await annotate('request', r2, 'r2');
      await annotate('request', r3, 'r3');
      await db.requestSettingsDao.put(r1, requestSettings);
      await db.requestSettingsDao.put(r3, requestSettings);
      return (c: c, f: f, g: g, r1: r1, r2: r2, r3: r3);
    }

    test('a request keeps its description, tags and settings, and the copy is independent', () async {
      final tree = await seedTree();

      final copyId = await db.collectionsDao.duplicateRequest(tree.r1);

      await expectAnnotated('request', copyId, 'r1');
      expect(await db.requestSettingsDao.get(copyId), requestSettings);
      await db.entityTagsDao.setTags('request', copyId, ['only-the-copy']);
      await db.requestSettingsDao.remove(copyId);
      await expectAnnotated('request', tree.r1, 'r1');
      expect(await db.requestSettingsDao.get(tree.r1), requestSettings);
    });

    test('a folder carries its own notes and those of everything inside it, at any depth', () async {
      final tree = await seedTree();

      final copyId = await db.collectionsDao.duplicateFolder(tree.f);

      await expectAnnotated('folder', copyId, 'F');
      final copiedG = (await (db.select(db.folders)..where((t) => t.parentFolderId.equals(copyId))).getSingle()).id;
      await expectAnnotated('folder', copiedG, 'G');
      final copiedR2 = (await (db.select(db.requests)..where((t) => t.folderId.equals(copyId))).getSingle()).id;
      final copiedR3 = (await (db.select(db.requests)..where((t) => t.folderId.equals(copiedG))).getSingle()).id;
      await expectAnnotated('request', copiedR2, 'r2');
      await expectAnnotated('request', copiedR3, 'r3');
      expect(await db.requestSettingsDao.get(copiedR2), isNull);
      expect(await db.requestSettingsDao.get(copiedR3), requestSettings);
    });

    test('a collection carries its own notes and those of every folder and request in it', () async {
      final tree = await seedTree();

      final copyId = await db.collectionsDao.duplicateCollection(tree.c);

      await expectAnnotated('collection', copyId, 'C');
      await expectAnnotated('folder', await folderNamed(copyId, 'F'), 'F');
      await expectAnnotated('folder', await folderNamed(copyId, 'G'), 'G');
      for (final name in ['r1', 'r2', 'r3']) {
        await expectAnnotated('request', await requestNamed(copyId, name), name);
      }
      expect(await db.requestSettingsDao.get(await requestNamed(copyId, 'r1')), requestSettings);
      expect(await db.requestSettingsDao.get(await requestNamed(copyId, 'r2')), isNull);
      expect(await db.requestSettingsDao.get(await requestNamed(copyId, 'r3')), requestSettings);
    });

    test('the originals are left exactly as they were', () async {
      final tree = await seedTree();

      await db.collectionsDao.duplicateCollection(tree.c);

      await expectAnnotated('collection', tree.c, 'C');
      await expectAnnotated('folder', tree.f, 'F');
      await expectAnnotated('request', tree.r3, 'r3');
      expect(await db.requestSettingsDao.get(tree.r1), requestSettings);
      expect(await db.select(db.requestSettingEntries).get(), hasLength(4));
    });

    test('an entity without notes or settings gets no empty rows for its copy', () async {
      final collectionId = await db.collectionsDao.createCollection('bare');
      final folderId = await db.collectionsDao.createFolder(collectionId: collectionId, name: 'f');
      await addRequest(collectionId, folderId: folderId);

      await db.collectionsDao.duplicateCollection(collectionId);
      await db.collectionsDao.duplicateFolder(folderId);

      expect(await db.select(db.entityDocs).get(), isEmpty);
      expect(await db.select(db.entityTags).get(), isEmpty);
      expect(await db.select(db.requestSettingEntries).get(), isEmpty);
    });
  });
}
