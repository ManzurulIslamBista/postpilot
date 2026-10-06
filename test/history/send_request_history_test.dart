// What a real send (the use case, the real repositories, a real in-memory database) leaves in History, and how
// much of a collection run reaches it.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/history/data/repositories/history_repository_impl.dart';
import 'package:postpilot/features/history/data/repository_history_context_source.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/history/domain/services/history_run_budget.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

import '../support/drift_repos.dart';

const _mask = '••••••';

final class _Client implements ApiClient {
  final List<ApiRequestSpec> sent = [];
  Object? failWith;
  int Function(ApiRequestSpec spec) status = (_) => 200;
  String Function(ApiRequestSpec spec) body = (_) => '{"ok":true}';

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    final failure = failWith;
    if (failure != null) throw failure;
    return ApiHttpResponse(
      statusCode: status(spec),
      statusMessage: 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode(body(spec)),
      duration: const Duration(milliseconds: 40),
    );
  }
}

final class _SummaryOnly implements HistoryRepository {
  final List<({String method, String url, int? status})> calls = [];

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async =>
      calls.add((method: method, url: url, status: statusCode));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late HistoryRepositoryImpl store;
  late _Client client;
  late BuildVariableResolverUseCase resolver;
  late SendRequestUseCase send;
  late int shop;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    store = HistoryRepositoryImpl(
      db.historyDao,
      context: RepositoryHistoryContextSource(
        collections: repos.collectionRepository,
        environments: repos.environmentRepository,
        globals: repos.globalVariableRepository,
        collectionAuth: repos.collectionAuthRepository,
      ),
    );
    client = _Client();
    resolver = BuildVariableResolverUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository);
    send = SendRequestUseCase(client, resolver, store, repos.collectionAuthRepository);
    shop = await repos.collectionRepository.createCollection('Shop');
    final env = await repos.environmentRepository.create('Production');
    await repos.environmentRepository.setActive(env);
    Future<void> variable(String key, String value, {bool secret = false}) => repos.environmentRepository.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: value, isSecret: secret, enabled: true),
        );
    await variable('baseUrl', 'https://api.test');
    await variable('apiToken', 'tok-prod-secret-123456', secret: true);
    await variable('customerNo', 'CUST-777-ABC', secret: true);
  });
  tearDown(() => db.close());

  Future<ApiRequestEntity> request({String path = '/users', HttpMethod method = HttpMethod.post}) async {
    final id = await repos.requestRepository.createRequest(collectionId: shop, name: 'Create user');
    return ApiRequestEntity(
      id: id,
      collectionId: shop,
      folderId: null,
      name: 'Create user',
      method: method,
      url: '{{baseUrl}}$path',
      headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{apiToken}}')],
      queryParams: const [],
      body: const RequestBody(type: BodyType.raw, rawText: '{"name":"Ann"}'),
      auth: const RequestAuth(type: AuthType.none),
    );
  }

  Future<String> everythingStored() async {
    final out = StringBuffer();
    for (final table in ['history_entries', 'history_payloads']) {
      for (final row in await db.customSelect('SELECT * FROM $table').get()) {
        for (final value in row.data.values) {
          out.writeln(value is Uint8List ? utf8.decode(value, allowMalformed: true) : '$value');
        }
      }
    }
    return out.toString();
  }

  test('a send records the request as saved with its collection and environment, and the response with no secret in it', () async {
    final saved = await request();
    client.body = (_) => '{"echo":"tok-prod-secret-123456","customer":"CUST-777-ABC","ok":true}';

    await send(saved);

    expect(client.sent.single.headers['Authorization'], 'Bearer tok-prod-secret-123456', reason: 'the real send carries the real token');
    final entry = (await store.watchAll().first).single;
    expect((entry.method, entry.url, entry.statusCode, entry.durationMs), ('POST', '{{baseUrl}}/users', 200, 40));
    expect(entry.meta!.requestId, saved.id);
    expect(entry.meta!.requestName, 'Create user');
    expect(entry.meta!.collectionId, shop);
    expect(entry.meta!.collectionName, 'Shop');
    expect(entry.meta!.environmentName, 'Production');
    final detail = (await store.detailOf(entry.id))!;
    expect({for (final h in detail.request.headers) h.key: h.value}, {'Authorization': 'Bearer {{apiToken}}'});
    expect(detail.responseText, '{"echo":"$_mask","customer":"$_mask","ok":true}');
    final stored = await everythingStored();
    expect(stored, isNot(contains('tok-prod-secret-123456')));
    expect(stored, isNot(contains('CUST-777-ABC')));
    expect(stored, contains('{{apiToken}}'));
  });

  test('a send that gets no answer is recorded as a failure with its reason; one that is cancelled is not recorded', () async {
    final saved = await request(path: '/down');

    client.failWith = const NetworkException(
      'connection refused',
      kind: NetworkErrorKind.connectionError,
      summary: "Couldn't reach api.test: the connection was refused.",
    );
    await expectLater(send(saved), throwsA(isA<NetworkException>()));
    client.failWith = const NetworkException('cancelled', kind: NetworkErrorKind.cancelled);
    await expectLater(send(saved), throwsA(isA<NetworkException>()));

    final entries = await store.watchAll().first;
    expect(entries, hasLength(1));
    expect(entries.single.statusCode, isNull);
    expect(entries.single.isFailure, isTrue);
    expect(entries.single.url, '{{baseUrl}}/down');
    expect(entries.single.meta!.error, "Couldn't reach api.test: the connection was refused.");
  });

  test('a request that is not even sent (an undefined variable) is not recorded', () async {
    final saved = await request(path: '/{{missing}}');

    await expectLater(send(saved), throwsA(isA<InvalidRequestException>()));

    expect(await store.watchAll().first, isEmpty);
    expect(client.sent, isEmpty);
  });

  test('a repository that keeps only the summary still gets every send and every failure through record()', () async {
    final summary = _SummaryOnly();
    final plain = SendRequestUseCase(client, resolver, summary, repos.collectionAuthRepository);
    final saved = await request();

    await plain(saved);
    client.failWith = const NetworkException('refused', kind: NetworkErrorKind.connectionError);
    await expectLater(plain(saved), throwsA(isA<NetworkException>()));

    expect(summary.calls.map((c) => (c.method, c.url, c.status)), [('POST', '{{baseUrl}}/users', 200), ('POST', '{{baseUrl}}/users', null)]);
  });

  group('a collection run', () {
    test('the budget of a run lets a sample of the successes and more of the failures through, then no more', () async {
      final saved = await request();
      final budget = HistoryRunBudget(limit: 3, okLimit: 2);

      for (var i = 0; i < 5; i++) {
        await send(saved, historyRun: budget);
      }
      client.status = (_) => 500;
      await send(saved, historyRun: budget);
      await send(saved, historyRun: budget);

      final statuses = (await store.watchAll().first).map((e) => e.statusCode).toList();
      expect(statuses, [500, 200, 200]);
      await send(saved);
      expect(await store.watchAll().first, hasLength(4), reason: 'a send outside a run is never held back');
    });

    test('a long run puts at most 20 successes and 50 entries in all into History', () async {
      for (var i = 0; i < 30; i++) {
        final id = await repos.requestRepository.createRequest(collectionId: shop, name: 'Request $i');
        await repos.requestRepository.saveRequest(ApiRequestEntity(
          id: id,
          collectionId: shop,
          folderId: null,
          name: 'Request $i',
          method: HttpMethod.get,
          url: 'https://api.test/item/$i',
          headers: const [],
          queryParams: const [],
          body: RequestBody.empty,
          auth: const RequestAuth(type: AuthType.none),
        ));
      }
      // The first fifteen requests of a pass succeed, the rest fail.
      client.status = (spec) => int.parse(spec.url.split('/').last) < 15 ? 200 : 500;
      final runner = CollectionRunnerService(
        repos.requestRepository,
        send,
        RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository),
      );

      final results = await runner.run(shop, options: const CollectionRunOptions(iterations: 3)).toList();

      expect(results, hasLength(90), reason: 'every request of the run was sent');
      expect(client.sent, hasLength(90));
      final entries = await store.watchAll().first;
      expect(entries, hasLength(50));
      expect(entries.where((e) => e.statusCode == 200), hasLength(20));
      expect(entries.where((e) => e.statusCode == 500), hasLength(30));

      // The next run starts with a budget of its own: its 15 successes and 15 failures all fit.
      await runner.run(shop, options: const CollectionRunOptions()).toList();
      expect(await store.watchAll().first, hasLength(80));
    });
  });
}
