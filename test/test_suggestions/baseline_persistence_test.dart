import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/test_suggestions/data/request_baseline_repository_impl.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_file.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/export_baselines_usecase.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';
import 'response_fixtures.dart';

void main() {
  late AppDatabase database;
  late DriftRepos repos;
  late RequestBaselineRepositoryImpl baselines;
  late int collection;
  late int request;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    baselines = RequestBaselineRepositoryImpl(database.requestBaselinesDao);
    collection = await repos.collectionRepository.createCollection('Shop');
    request = await addRequest(repos, collection, 'List');
  });

  tearDown(() => database.close());

  group('the baselines of this device', () {
    test('are stored and read back whole, one per request, the newest replacing the old', () async {
      expect(await baselines.get(request), isNull);
      final first = BaselineRecorder.record(response({'a': 1}));
      await baselines.save(request, first, note: 'v1');
      final stored = (await baselines.get(request))!;
      expect(stored.requestId, request);
      expect(stored.note, 'v1');
      expect(stored.snapshot.fields.keys, ['', 'a']);
      expect(DateTime.now().difference(stored.recordedAt).inMinutes, lessThan(1));

      await baselines.save(request, BaselineRecorder.record(response({'a': 1, 'b': 2})));
      expect((await baselines.get(request))!.snapshot.fields.keys, ['', 'a', 'b']);
      expect(await baselines.all(), hasLength(1));
    });

    test('are watched: recording and removing both show up', () async {
      final seen = <bool>[];
      final subscription = baselines.watch(request).listen((s) => seen.add(s != null));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await baselines.save(request, BaselineRecorder.record(response({'a': 1})));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await baselines.delete(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      expect(seen, [false, true, false]);
    });

    test('go with their request when it is deleted', () async {
      await baselines.save(request, BaselineRecorder.record(response({'a': 1})));
      await repos.requestRepository.deleteRequest(request);
      expect(await baselines.all(), isEmpty);
    });

    test('a row that cannot be read is no baseline instead of an error', () async {
      await database.requestBaselinesDao.upsert(RequestBaselinesCompanion(requestId: Value(request), snapshotJson: const Value('not json {')));
      expect(await baselines.get(request), isNull);
      expect(await baselines.all(), isEmpty);
    });
  });

  group('exporting for the command line', () {
    test('names every baseline by collection, folder path, request name and method', () async {
      final orders = await repos.collectionRepository.createFolder(collectionId: collection, name: 'Orders');
      final archive = await repos.collectionRepository.createFolder(collectionId: collection, parentFolderId: orders, name: 'Archive');
      final nested = await addRequest(repos, collection, 'Old orders', folderId: archive, method: HttpMethod.post);
      final other = await repos.collectionRepository.createCollection('Other');
      final elsewhere = await addRequest(repos, other, 'Ping');
      await addRequest(repos, collection, 'No baseline');
      for (final id in [request, nested, elsewhere]) {
        await baselines.save(id, BaselineRecorder.record(response({'id': id})));
      }

      final loader = CollectionLoader(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      final file = await ExportBaselinesUseCase(baselines, loader)();
      expect(file.entries.map((e) => '${e.collection}|${e.folder}|${e.name}|${e.method}').toSet(), {
        'Shop||List|GET',
        'Shop|Orders/Archive|Old orders|POST',
        'Other||Ping|GET',
      });

      // What the command line reads finds each one by those names.
      final back = BaselineFile.parse(file.encode());
      expect(back.find(collection: 'Shop', folder: 'Orders/Archive', name: 'Old orders', method: 'POST'), isNotNull);
      expect(back.find(collection: 'Shop', folder: '', name: 'No baseline', method: 'GET'), isNull);
    });

    test('with nothing recorded there is nothing to export', () async {
      final loader = CollectionLoader(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      expect((await ExportBaselinesUseCase(baselines, loader)()).entries, isEmpty);
    });
  });

  group('the baseline key of the request settings', () {
    test('is stored under "baseline", and only when it is on', () {
      expect(const RequestSettings(baseline: BaselineSettings(enforce: true)).toJson(), {
        'baseline': {'enforce': true},
      });
      expect(const RequestSettings(baseline: BaselineSettings()).toJson(), isEmpty);
      expect(const RequestSettings(baseline: BaselineSettings(enforce: true)).isEmpty, isFalse, reason: 'something to store');
      expect(RequestSettings.none.baseline.enforce, isFalse);
    });

    test('is read leniently: a wrong type or a missing key means off', () {
      expect(RequestSettings.decode('{"baseline":{"enforce":true}}').baseline.enforce, isTrue);
      expect(RequestSettings.decode('{"baseline":{"enforce":"yes"}}').baseline.enforce, isFalse);
      expect(RequestSettings.decode('{"baseline":true}').baseline.enforce, isFalse);
      expect(RequestSettings.decode('{}').baseline.enforce, isFalse);
      expect(RequestSettings.decode('not json').baseline.enforce, isFalse);
    });

    test('lives beside the flow and pagination keys: changing any one keeps the others', () {
      const flow = FlowSettings(alwaysRun: true);
      const pagination = PaginationSettings(enabled: true);
      final all = const RequestSettings(timeoutSeconds: 5).withFlow(flow).withPagination(pagination).withBaseline(const BaselineSettings(enforce: true));
      expect(all.toJson().keys, containsAll(['timeoutSeconds', 'flow', 'pagination', 'baseline']));
      expect(all.withFlow(FlowSettings.none).baseline.enforce, isTrue);
      expect(all.withPagination(PaginationSettings.none).baseline.enforce, isTrue);
      expect(all.withTimeoutSeconds(null).baseline.enforce, isTrue);
      expect(all.withFollowRedirects(false).baseline.enforce, isTrue);
      expect(all.withVerifySsl(false).baseline.enforce, isTrue);
      expect(all.withSendNoCacheHeader(true).baseline.enforce, isTrue);
      expect(all.withoutOverrides().baseline.enforce, isTrue);
      expect(all.withoutOverrides().flow, flow);
      final off = all.withBaseline(BaselineSettings.none);
      expect(off.flow, flow);
      expect(off.pagination, pagination);
      expect(off.timeoutSeconds, 5);
    });

    test('two settings are equal when their baseline settings are', () {
      const on = RequestSettings(baseline: BaselineSettings(enforce: true));
      expect(on, const RequestSettings(baseline: BaselineSettings(enforce: true)));
      expect(on, isNot(RequestSettings.none));
      expect(on.hashCode, const RequestSettings(baseline: BaselineSettings(enforce: true)).hashCode);
    });

    test('is saved with the request, and removed with it when it is turned off', () async {
      await repos.requestSettingsRepository.save(request, const RequestSettings(baseline: BaselineSettings(enforce: true)));
      expect((await repos.requestSettingsRepository.get(request)).baseline.enforce, isTrue);
      await repos.requestSettingsRepository.save(request, const RequestSettings());
      expect((await repos.requestSettingsRepository.get(request)).baseline.enforce, isFalse);
    });
  });
}
