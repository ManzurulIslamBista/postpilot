// A request that turned on "Enforce baseline in runs" gets one more result row in the collection runner, and the row
// fails the request on a breaking change. The editor's own send is left alone.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/baseline_guard.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'baseline_support.dart';
import 'response_fixtures.dart';

/// Answers by path with a body the test can change between runs.
final class _Server implements ApiClient {
  final bodies = <String, Object?>{};
  int status = 200;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => ApiHttpResponse(
        statusCode: status,
        statusMessage: status == 200 ? 'OK' : 'Error',
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
        bodyBytes: utf8.encode(jsonEncode(bodies[Uri.parse(spec.url).path] ?? {})),
        duration: const Duration(milliseconds: 20),
      );
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
  late InMemoryDb db;
  late InMemoryBaselines baselines;
  late _Server server;
  late CollectionRunnerService runner;
  late int collection;
  late int enforcing;
  late int plain;

  const good = {'id': 1, 'name': 'Ann', 'tags': ['a']};

  setUp(() async {
    db = InMemoryDb();
    baselines = InMemoryBaselines();
    server = _Server()
      ..bodies['/users'] = good
      ..bodies['/groups'] = good;
    collection = await db.collectionRepository.createCollection('Shop');
    enforcing = await addRequest(db, collection, 'Users', url: 'https://api.test/users');
    plain = await addRequest(db, collection, 'Groups', url: 'https://api.test/groups');
    // Both were recorded when the answer was good; only "Users" asks for the baseline to be enforced.
    for (final id in [enforcing, plain]) {
      await baselines.save(id, BaselineRecorder.record(response(good)));
    }
    db.requestSettings[enforcing] = const RequestSettings(baseline: BaselineSettings(enforce: true));

    final resolver = BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
    final scripts = RunRequestScriptsUseCase(
      db.scriptsRepository,
      resolver,
      db.environmentRepository,
      db.globalVariableRepository,
      const AssertionEvaluator(),
      null,
      BaselineGuard(baselines, db.requestSettingsRepository),
    );
    runner = CollectionRunnerService.withFolders(
      db.requestRepository,
      SendRequestUseCase(server, resolver, _NoHistory(), db.collectionAuthRepository),
      scripts,
      db.collectionRepository,
      (_) async {},
    );
  });

  Future<Map<String, CollectionRunResult>> run() async {
    final results = await runner.run(collection).toList();
    return {for (final r in results) r.request.name: r};
  }

  test('an unchanged answer passes, and says how many breaking changes it found', () async {
    final results = await run();
    final row = results['Users']!.scripts!.assertions.single;
    expect(row.name, 'Baseline: 0 breaking changes');
    expect(row.passed, isTrue);
    expect(results['Users']!.passed, isTrue);
  });

  test('a breaking change fails the request, with the reason in its failures', () async {
    server.bodies['/users'] = {'id': 1, 'tags': ['a']}; // name was removed
    final result = (await run())['Users']!;
    expect(result.scripts!.assertions.single.name, 'Baseline: 1 breaking change');
    expect(result.scripts!.assertions.single.actual, 'body.name was removed.');
    expect(result.passed, isFalse);
    expect(result.failures, ['Baseline: 1 breaking change']);
  });

  test('a change that cannot break a client still passes', () async {
    server.bodies['/users'] = {...good, 'nickname': 'A'}; // a new field
    final result = (await run())['Users']!;
    expect(result.scripts!.assertions.single.name, 'Baseline: 0 breaking changes');
    expect(result.scripts!.assertions.single.actual, '1 non-breaking, 0 info');
    expect(result.passed, isTrue);
  });

  test('a request that does not enforce its baseline gets no row, drift or not', () async {
    server.bodies['/groups'] = {'id': 'one'};
    final result = (await run())['Groups']!;
    expect(result.scripts?.assertions ?? const [], isEmpty);
    expect(result.passed, isTrue);
  });

  test('enforcing without a recorded baseline fails, and says how to fix it', () async {
    await baselines.delete(enforcing);
    final result = (await run())['Users']!;
    final row = result.scripts!.assertions.single;
    expect(row.name, 'Baseline: none recorded');
    expect(row.passed, isFalse);
    expect(result.passed, isFalse);
  });

  test('a status that changed class is one breaking change', () async {
    server.status = 503;
    final result = (await run())['Users']!;
    expect(result.scripts!.assertions.single.name, 'Baseline: 1 breaking change');
    expect(result.passed, isFalse);
  });

  test('the row comes after the request\'s own tests and does not replace them', () async {
    db.scripts[enforcing] = RequestScriptsEntity(requestId: enforcing, assertionsJson: shopAssertions);
    final result = (await run())['Users']!;
    expect(result.scripts!.assertions.map((a) => a.name), ['Status is 2xx', 'Baseline: 0 breaking changes']);
  });

  test('the editor\'s send adds no baseline row: the response shows its drift in a chip instead', () async {
    final resolver = BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
    final scripts = RunRequestScriptsUseCase(
      db.scriptsRepository,
      resolver,
      db.environmentRepository,
      db.globalVariableRepository,
      const AssertionEvaluator(),
      null,
      BaselineGuard(baselines, db.requestSettingsRepository),
    );
    final result = await scripts(RunRequestScriptsParams(
      requestId: enforcing,
      collectionId: collection,
      response: response({'broken': true}),
    ));
    expect(result.assertions, isEmpty);
  });
}
