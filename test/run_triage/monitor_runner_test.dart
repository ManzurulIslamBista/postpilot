// One monitored run on a real (in-memory) database with the real runner and a scripted server: which requests are sent
// and which are left out by the production lock, what the stored record says, and that the active environment is never
// switched behind the person's back.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/run_triage/data/run_record_repository_impl.dart';
import 'package:postpilot/features/run_triage/domain/entities/monitor_config.dart';
import 'package:postpilot/features/run_triage/domain/services/monitor_runner.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

final class _Server implements ApiClient {
  final sent = <String>[];
  int Function(String method, String url) status = (_, _) => 200;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add('${spec.method} ${spec.url}');
    return ApiHttpResponse(
      statusCode: status(spec.method, spec.url),
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode('{"ok":true}'),
      duration: const Duration(milliseconds: 25),
    );
  }
}

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late _Server server;
  late RunRecordRepositoryImpl records;
  late int shop;
  late int staging;
  late int production;
  var words = <String>[];
  var hosts = <String>[];
  var now = DateTime.utc(2026, 10, 6, 10);

  setUp(() async {
    words = [];
    hosts = [];
    now = DateTime.utc(2026, 10, 6, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    server = _Server();
    records = RunRecordRepositoryImpl(db.runRecordsDao);
    shop = await repos.collectionRepository.createCollection('Shop');
    staging = await repos.environmentRepository.create('Staging');
    production = await repos.environmentRepository.create('Production');
    Future<void> variable(int env, String key, String value) => repos.environmentRepository.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: value, isSecret: false, enabled: true),
        );
    await variable(staging, 'host', 'https://staging.shop.test');
    await variable(production, 'host', 'https://api.shop.test');
    await repos.environmentRepository.setActive(staging);
    await addRequest(repos, shop, 'List orders', url: '{{host}}/orders');
    await addRequest(repos, shop, 'Create order', method: HttpMethod.post, url: '{{host}}/orders', body: const RequestBody(type: BodyType.raw, rawText: '{"x":1}'));
    await addRequest(repos, shop, 'Partners', method: HttpMethod.post, url: '{{host}}/json/2/res.partner/search_read');
    await addRequest(repos, shop, 'Remove order', method: HttpMethod.delete, url: '{{host}}/orders/1');
  });
  tearDown(() => db.close());

  MonitorRunner runner() {
    final resolver = BuildVariableResolverUseCase(
      repos.collectionVariableRepository,
      repos.environmentRepository,
      repos.globalVariableRepository,
      repos.defaultsRepository,
    );
    final send = SendRequestUseCase(server, resolver, _NoHistory(), repos.collectionAuthRepository);
    final scripts = RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository);
    return MonitorRunner(
      runner: CollectionRunnerService.withFolders(repos.requestRepository, send, scripts, repos.collectionRepository, (_) async {}),
      collections: repos.collectionRepository,
      environments: repos.environmentRepository,
      resolver: resolver,
      records: records,
      productionWords: () => words,
      productionHosts: () => hosts,
      now: () {
        final t = now;
        now = now.add(const Duration(seconds: 2));
        return t;
      },
    );
  }

  test('in a staging environment every request is sent and the run is stored as a monitor run', () async {
    final result = await runner().run(shop, const MonitorConfig(enabled: true));
    expect(server.sent, [
      'GET https://staging.shop.test/orders',
      'POST https://staging.shop.test/orders',
      'POST https://staging.shop.test/json/2/res.partner/search_read',
      'DELETE https://staging.shop.test/orders/1',
    ]);
    expect((result.isPassing, result.ranNothing, result.skippedByLock, result.failed), (true, false, 0, 0));
    final stored = (await records.byId(result.recordId!))!;
    expect(stored.doc.trigger, 'monitor');
    expect(stored.doc.environment, 'Staging');
    expect((stored.doc.passed, stored.doc.failed, stored.doc.skipped), (4, 0, 0));
    expect(stored.doc.results.map((r) => r.name), ['List orders', 'Create order', 'Partners', 'Remove order']);
    expect(stored.doc.results.first.url, '{{host}}/orders', reason: 'the address as written, never a resolved one');
    expect(stored.doc.durationMs, 2000);
  });

  test('a chosen production environment: reads are sent to its host, writes and deletes are left out and listed', () async {
    final result = await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Production'));
    expect(server.sent, ['GET https://api.shop.test/orders', 'POST https://api.shop.test/json/2/res.partner/search_read']);
    expect((result.skippedByLock, result.isPassing, result.ranNothing), (2, true, false));
    final stored = (await records.byId(result.recordId!))!;
    expect(stored.doc.environment, 'Production');
    expect((stored.doc.passed, stored.doc.failed, stored.doc.skipped), (2, 0, 2));
    final skipped = stored.doc.results.where((r) => r.isSkipped).toList();
    expect(skipped.map((r) => r.name), ['Create order', 'Remove order']);
    expect(skipped.first.skipped, startsWith('Left out by the monitor: it changes data and the environment looks like production.'));
    expect(skipped.last.skipped, contains('it deletes data'));
    expect(skipped.every((r) => r.passed), isTrue, reason: 'left out is not failed');
  });

  test('the chosen environment does not become the active one', () async {
    await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Production'));
    expect((await repos.environmentRepository.watchActive().first)?.name, 'Staging');
  });

  test('a production environment that is active counts, whichever environment was chosen (its variables stay visible)', () async {
    await repos.environmentRepository.setActive(production);
    final result = await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Staging'));
    expect(result.skippedByLock, 2);
    expect(server.sent, ['GET https://staging.shop.test/orders', 'POST https://staging.shop.test/json/2/res.partner/search_read']);
    // And with no environment chosen the active one is used.
    server.sent.clear();
    await runner().run(shop, const MonitorConfig(enabled: true));
    expect(server.sent, ['GET https://api.shop.test/orders', 'POST https://api.shop.test/json/2/res.partner/search_read']);
  });

  test('your own words and hosts from Settings > Safety are honoured', () async {
    words = ['stage'];
    final renamed = await repos.environmentRepository.create('Stage EU');
    await repos.environmentRepository.upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: renamed, key: 'host', value: 'https://eu.shop.test', isSecret: false, enabled: true));
    var result = await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Stage EU'));
    expect(result.skippedByLock, 2, reason: 'the extra production word marks the environment');

    words = [];
    hosts = ['staging.shop.test'];
    server.sent.clear();
    result = await runner().run(shop, const MonitorConfig(enabled: true));
    expect(result.skippedByLock, 2, reason: 'a production host counts under any environment name');
    expect(server.sent, ['GET https://staging.shop.test/orders', 'POST https://staging.shop.test/json/2/res.partner/search_read']);
    final reason = (await records.byId(result.recordId!))!.doc.results.firstWhere((r) => r.isSkipped).skipped!;
    expect(reason, contains('staging.shop.test is one of your production hosts'));
  });

  test('when every request would change data in production nothing is sent, and the record says why', () async {
    for (final request in await repos.requestRepository.watchByCollection(shop).first) {
      if (request.method == HttpMethod.get || request.name == 'Partners') await repos.requestRepository.deleteRequest(request.id);
    }
    final result = await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Production'));
    expect(server.sent, isEmpty);
    expect((result.ranNothing, result.isPassing, result.skippedByLock), (true, false, 2));
    final stored = (await records.byId(result.recordId!))!;
    expect((stored.doc.passed, stored.doc.failed, stored.doc.skipped), (0, 0, 2));
  });

  test('a failing request is a result: the run is not passing and the record keeps what failed', () async {
    server.status = (method, url) => url.endsWith('/orders') && method == 'GET' ? 503 : 200;
    final result = await runner().run(shop, const MonitorConfig(enabled: true));
    expect((result.isPassing, result.failed), (false, 1));
    final stored = (await records.byId(result.recordId!))!;
    expect(stored.doc.results.singleWhere((r) => r.isFailed).status, 503);
  });

  test('a run stays out of the way of a manual one: it only reads the active environment, it never writes it', () async {
    final before = (await repos.environmentRepository.watchVariables(staging).first).map((v) => '${v.key}=${v.value}').toList();
    await runner().run(shop, const MonitorConfig(enabled: true, environment: 'Production'));
    final after = (await repos.environmentRepository.watchVariables(staging).first).map((v) => '${v.key}=${v.value}').toList();
    expect(after, before);
  });

  test('an environment that was deleted is a clear error, not a silent run against the wrong one', () async {
    await expectLater(
      runner().run(shop, const MonitorConfig(enabled: true, environment: 'Gone')),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('"Gone" no longer exists'))),
    );
    expect(server.sent, isEmpty);
  });

  test('a collection that was deleted is a clear error', () async {
    await repos.collectionRepository.deleteCollection(shop);
    await expectLater(runner().run(shop, const MonitorConfig(enabled: true)), throwsA(isA<StateError>()));
  });
}
