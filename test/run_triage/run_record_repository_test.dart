// Run records on a real (in-memory SQLite) database: stored masked, newest first, pruned to 50 per collection,
// removed with their collection, and importable from a command-line record file.
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/run_triage/data/run_record_repository_impl.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/repositories/run_record_repository.dart';
import 'package:postpilot/features/run_triage/domain/services/cli_run_importer.dart';
import 'package:postpilot/features/run_triage/domain/services/run_record_codec.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';
import 'run_fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late RunRecordRepositoryImpl records;
  late int shop;
  late int other;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    records = RunRecordRepositoryImpl(db.runRecordsDao);
    shop = await repos.collectionRepository.createCollection('Shop');
    other = await repos.collectionRepository.createCollection('Other');
  });
  tearDown(() => db.close());

  group('storing', () {
    test('a record comes back as it was stored, with its columns filled', () async {
      final doc = run([entry('A', ms: 30), failedWith('B', 500)], environment: 'Staging', source: 'app', trigger: 'monitor', durationMs: 4321);
      final id = await records.save(shop, doc);
      final stored = (await records.byId(id))!;
      expect((stored.id, stored.collectionId), (id, shop));
      expect(stored.doc.environment, 'Staging');
      expect(stored.doc.trigger, 'monitor');
      expect((stored.doc.passed, stored.doc.failed, stored.doc.skipped, stored.doc.durationMs), (1, 1, 0, 4321));
      expect(stored.doc.results.map((r) => (r.name, r.status, r.passed)), [('A', 200, true), ('B', 500, false)]);
      expect(stored.doc.collection, 'Shop');
    });

    test('the table columns hold the masked, capped text', () async {
      await records.save(
        shop,
        run([
          entry('Get', url: 'https://u:pw123456@api.shop.test/a?api_key=SECRETVALUE99', status: null, passed: false, error: 'rejected https://api.shop.test/a?access_token=SECRETVALUE99'),
        ]),
      );
      final row = (await db.runRecordsDao.recentForCollection(shop)).single;
      for (final text in [row.resultsJson, row.summaryJson, row.environmentName, row.source]) {
        expect(text, isNot(contains('SECRETVALUE99')));
        expect(text, isNot(contains('pw123456')));
      }
    });

    test('newest first, by start time and then by id', () async {
      final a = await records.save(shop, run([entry('A')], at: DateTime.utc(2026, 10, 1, 9)));
      final b = await records.save(shop, run([entry('A')], at: DateTime.utc(2026, 10, 3, 9)));
      final c = await records.save(shop, run([entry('A')], at: DateTime.utc(2026, 10, 2, 9)));
      final sameSecondFirst = await records.save(shop, run([entry('A')], at: DateTime.utc(2026, 10, 3, 9)));
      expect((await records.recent(shop)).map((r) => r.id), [sameSecondFirst, b, c, a]);
      expect((await records.recent(shop, limit: 2)).map((r) => r.id), [sameSecondFirst, b]);
    });

    test('a collection\'s history is its own', () async {
      await records.save(shop, run([entry('A')]));
      await records.save(other, run([entry('B')], collection: 'Other'));
      expect(await records.recent(shop), hasLength(1));
      expect((await records.recent(other)).single.doc.results.single.name, 'B');
    });

    test('keeps the newest 50 of a collection and prunes the rest, leaving other collections alone', () async {
      await records.save(other, run([entry('X')], at: DateTime.utc(2026)));
      final ids = <int>[];
      for (var i = 0; i < 55; i++) {
        ids.add(await records.save(shop, run([entry('R$i')], at: DateTime.utc(2026, 10, 1).add(Duration(minutes: i)))));
      }
      final kept = await records.recent(shop, limit: 100);
      expect(kept, hasLength(RunRecordRepository.keepPerCollection));
      expect(kept.first.id, ids.last);
      expect(kept.last.id, ids[5], reason: 'the five oldest were pruned');
      expect(await records.byId(ids.first), isNull);
      expect(await records.recent(other), hasLength(1));
    });

    test('watch emits again whenever a record is added or the history is cleared', () async {
      final seen = <int>[];
      final sub = records.watch(shop).listen((list) => seen.add(list.length));
      await pumpEventQueue();
      await records.save(shop, run([entry('A')]));
      await pumpEventQueue();
      await records.save(shop, run([entry('A')]));
      await pumpEventQueue();
      await records.clear(shop);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [0, 1, 2, 0]);
    });

    test('clear forgets one collection only', () async {
      await records.save(shop, run([entry('A')]));
      await records.save(other, run([entry('B')]));
      await records.clear(shop);
      expect(await records.recent(shop), isEmpty);
      expect(await records.recent(other), hasLength(1));
    });

    test('deleting the collection deletes its records', () async {
      await records.save(shop, run([entry('A')]));
      await repos.collectionRepository.deleteCollection(shop);
      expect(await db.runRecordsDao.recentForCollection(shop), isEmpty);
    });

    test('a damaged row reads as an empty run instead of breaking the list', () async {
      await db.runRecordsDao.insertRecord(
        RunRecordsCompanion.insert(collectionId: shop, passed: const Value(3), summaryJson: const Value('{broken'), resultsJson: const Value('nope')),
      );
      final list = await records.recent(shop);
      expect(list.single.doc.results, isEmpty);
      expect(list.single.doc.passed, 3);
    });
  });

  group('importing a command-line run', () {
    late int loginId;
    late int ordersId;
    late int folderId;

    setUp(() async {
      folderId = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
      loginId = await addRequest(repos, shop, 'Login', method: HttpMethod.post);
      ordersId = await addRequest(repos, shop, 'List', folderId: folderId);
      // Two requests with one name in one folder: a match would be a guess, so neither is matched.
      await addRequest(repos, shop, 'Twin');
      await addRequest(repos, shop, 'Twin');
    });

    Future<List<RequestSummaryEntity>> requests() => repos.requestRepository.watchByCollection(shop).first;
    Future<List<FolderEntity>> folders() => repos.collectionRepository.watchFolders(shop).first;

    String file({String collection = 'Shop', String env = 'Staging', int failed = 1, DateTime? at}) => jsonEncode(
          RunRecordDoc(
            source: 'cli',
            trigger: 'cli',
            collection: collection,
            environment: env,
            startedAt: at ?? DateTime.utc(2026, 10, 6, 10, 42, 7),
            passed: 3,
            failed: failed,
            results: [
              entry('Login', method: 'POST'),
              failedWith('List', 500, folder: 'Orders'),
              entry('Twin'),
              entry('Gone'),
            ],
          ).toJson(),
        );

    test('matches results with the collection\'s requests by folder, method and name, so a failure can be re-run', () async {
      final result = await CliRunImporter.import(text: file(), collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      expect(result.matched, 2);
      final stored = (await records.byId(result.id!))!;
      expect(stored.doc.source, 'cli');
      expect(stored.doc.results.map((r) => (r.name, r.requestId)), [('Login', loginId), ('List', ordersId), ('Twin', null), ('Gone', null)]);
    });

    test('the same file imported twice is one run', () async {
      final first = await CliRunImporter.import(text: file(), collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      final again = await CliRunImporter.import(text: file(), collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      expect(again.id, isNull);
      expect(again.duplicateOf, first.id);
      expect(await records.recent(shop), hasLength(1));
      // Another run at another time is another record.
      final later = await CliRunImporter.import(text: file(at: DateTime.utc(2026, 10, 7)), collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      expect(later.id, isNotNull);
      expect(await records.recent(shop), hasLength(2));
    });

    test('says when the record was made for another collection name', () async {
      final result = await CliRunImporter.import(text: file(collection: 'Shop (old)'), collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      expect(result.differsFrom('Shop'), isTrue);
      expect(result.differsFrom('Shop (old)'), isFalse);
    });

    test('a file that is not a run record changes nothing and says why', () async {
      await expectLater(
        CliRunImporter.import(text: '{"x":1}', collectionId: shop, requests: await requests(), folders: await folders(), records: records),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not a PostPilot run record'))),
      );
      expect(await records.recent(shop), isEmpty);
    });

    test('an imported record is masked like every other', () async {
      final text = jsonEncode(
        RunRecordDoc(
          collection: 'Shop',
          startedAt: DateTime.utc(2026),
          passed: 0,
          failed: 1,
          results: [entry('Login', url: 'https://u:pw123456@api.shop.test/a?token=SECRETVALUE99', status: null, passed: false, error: 'GET https://api.shop.test/a?api_key=SECRETVALUE99 failed')],
        ).toJson(),
      );
      final result = await CliRunImporter.import(text: text, collectionId: shop, requests: await requests(), folders: await folders(), records: records);
      final row = (await db.runRecordsDao.findById(result.id!))!;
      expect(row.resultsJson, isNot(contains('SECRETVALUE99')));
      expect(row.resultsJson, isNot(contains('pw123456')));
    });
  });

  test('the codec keeps the 50-per-collection rule in one place', () {
    expect(RunRecordCodec.keepPerCollection, RunRecordRepository.keepPerCollection);
  });
}
