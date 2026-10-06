// The tests of the collection and its folders run for every request below them, before the request's own.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/script_run_result.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

ApiResponseEntity _response(int status, {Object? body, Map<String, String> headers = const {}}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: '',
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body == null ? '' : jsonEncode(body))),
      duration: const Duration(milliseconds: 5),
    );

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int shop;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    shop = await repos.collectionRepository.createCollection('Shop');
  });
  tearDown(() => db.close());

  BuildVariableResolverUseCase buildResolver() => BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      );

  RunRequestScriptsUseCase scripts() => RunRequestScriptsUseCase(
        repos.scriptsRepository,
        buildResolver(),
        repos.environmentRepository,
        repos.globalVariableRepository,
        const AssertionEvaluator(),
        ResolveRequestDefaultsUseCase(repos.defaultsRepository),
      );

  Future<int> folder(String name, {int? parent}) =>
      repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: parent, name: name);

  Future<void> ownTests(int requestId, {List<AssertionEntity> assertions = const [], List<ExtractorEntity> extractors = const []}) =>
      repos.scriptsRepository.save(RequestScriptsEntity(
        requestId: requestId,
        assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions),
        extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors),
      ));

  Future<ScriptRunResultView> run(int requestId, ApiResponseEntity response, {int? folderId}) async {
    final result = await scripts()(RunRequestScriptsParams(requestId: requestId, collectionId: shop, response: response, folderId: folderId));
    return ScriptRunResultView(result);
  }

  test('the collection\'s checks run first, then each folder\'s from the outermost, then the request\'s own', () async {
    final a = await folder('A');
    final b = await folder('B', parent: a);
    await repos.defaultsRepository.saveCollection(shop, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusIn2xx)]));
    await repos.defaultsRepository.saveFolder(a, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.headerExists, path: 'X-Trace')]));
    await repos.defaultsRepository.saveFolder(b, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: 'ok')]));
    final id = await addRequest(repos, shop, 'Get', folderId: b);
    await ownTests(id, assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]);

    final result = await run(id, _response(200, body: {'status': 'ok'}, headers: {'X-Trace': 'abc'}), folderId: b);

    expect(result.origins, ['collection "Shop"', 'folder "A"', 'folder "B"', null]);
    expect(result.names, ['Status is 2xx', 'Header X-Trace exists', 'Body contains "ok"', 'Status equals 200']);
    expect(result.passed, [true, true, true, true]);
  });

  test('a failing inherited check fails the request and says where it comes from', () async {
    await repos.defaultsRepository.saveCollection(shop, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusIn2xx)]));
    final id = await addRequest(repos, shop, 'Get');

    final result = (await run(id, _response(500))).raw;

    expect(result.failedCount, 1);
    expect(result.hasFailures, isTrue);
    expect(result.assertions.single.origin, 'collection "Shop"');
    expect(result.assertions.single.actual, '500');
  });

  test('a request with no tests of its own still gets the inherited ones; one with none anywhere gets an empty result', () async {
    final a = await folder('A');
    await repos.defaultsRepository.saveFolder(a, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusIn2xx)]));
    final inside = await addRequest(repos, shop, 'Inside', folderId: a);
    final outside = await addRequest(repos, shop, 'Outside');

    expect((await run(inside, _response(200), folderId: a)).raw.assertions, hasLength(1));
    expect((await run(outside, _response(200))).raw.isEmpty, isTrue);
  });

  test('inherited extractors save variables before the request\'s own, in the same order', () async {
    final a = await folder('A');
    await repos.defaultsRepository.saveCollection(
      shop,
      LevelDefaults(extractors: [ExtractorEntity(path: r'$.token', variableKey: 'token', scope: ExtractorScope.global)]),
    );
    await repos.defaultsRepository.saveFolder(
      a,
      LevelDefaults(extractors: [ExtractorEntity(path: r'$.user', variableKey: 'userId', scope: ExtractorScope.global)]),
    );
    final id = await addRequest(repos, shop, 'Get', folderId: a);
    await ownTests(id, extractors: [ExtractorEntity(path: r'$.order', variableKey: 'orderId', scope: ExtractorScope.global)]);

    final result = (await run(id, _response(200, body: {'token': 't-1', 'user': 'u-7', 'order': 'o-9'}), folderId: a)).raw;

    expect(result.extracted.map((e) => (e.key, e.value, e.origin)), [
      ('token', 't-1', 'collection "Shop"'),
      ('userId', 'u-7', 'folder "A"'),
      ('orderId', 'o-9', null),
    ]);
    final globals = {for (final g in await repos.globalVariableRepository.watchAll().first) g.key: g.value};
    expect(globals, {'token': 't-1', 'userId': 'u-7', 'orderId': 'o-9'});
  });

  test('{{variables}} in an inherited check resolve with the variables of the folder the request is in', () async {
    final a = await folder('A');
    await repos.defaultsRepository.saveFolder(a, LevelDefaults(variables: [DefaultVariable(key: 'expectedId', value: '42')]));
    await repos.defaultsRepository.saveCollection(
      shop,
      LevelDefaults(assertions: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'id', expected: '{{expectedId}}')]),
    );
    final inside = await addRequest(repos, shop, 'Inside', folderId: a);
    final outside = await addRequest(repos, shop, 'Outside');

    expect((await run(inside, _response(200, body: {'id': 42}), folderId: a)).passed, [true]);
    expect((await run(outside, _response(200, body: {'id': 42}))).passed, [false],
        reason: 'outside the folder {{expectedId}} is not defined, so nothing equals it');
  });

  test('a request that moved is judged by the tests of its new folder, whatever folder the caller still has', () async {
    final a = await folder('A');
    final b = await folder('B');
    await repos.defaultsRepository.saveFolder(a, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]));
    await repos.defaultsRepository.saveFolder(b, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '201')]));
    final id = await addRequest(repos, shop, 'Get', folderId: b);

    final result = await run(id, _response(201), folderId: a);

    expect(result.names, ['Status equals 201']);
    expect(result.origins, ['folder "B"']);
  });

  group('in a collection run', () {
    test('the results carry the origin and the failure lines say where an inherited check comes from', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]));
      await repos.defaultsRepository.saveFolder(a, LevelDefaults(assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: 'nope')]));
      await addRequest(repos, shop, 'Get', folderId: a);
      final send = SendRequestUseCase(
        _FixedClient(),
        buildResolver(),
        _NoHistory(),
        repos.collectionAuthRepository,
        null,
        null,
        const RequestSpecBuilder(),
        ResolveRequestDefaultsUseCase(repos.defaultsRepository),
      );
      final runner = CollectionRunnerService(repos.requestRepository, send, scripts());

      final results = await runner.run(shop).toList();

      expect(results, hasLength(1));
      final result = results.single;
      expect(result.passed, isFalse);
      expect(result.assertionCount, 2);
      expect(result.passedAssertionCount, 1);
      expect(result.failures, ['Body contains "nope" (from folder "A")']);
    });
  });
}

/// The pieces of a result a test reads, in order.
final class ScriptRunResultView {
  final ScriptRunResult raw;
  ScriptRunResultView(this.raw);

  List<String?> get origins => [for (final a in raw.assertions) a.origin];
  List<String> get names => [for (final a in raw.assertions) a.name];
  List<bool> get passed => [for (final a in raw.assertions) a.passed];
}

final class _FixedClient implements ApiClient {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => const ApiHttpResponse(
        statusCode: 200,
        statusMessage: 'OK',
        headers: {},
        bodyBytes: [123, 125],
        duration: Duration.zero,
      );
}

final class _NoHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
