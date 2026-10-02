import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_result.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/script_run_result.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

const _collectionId = 7;

ApiResponseEntity _response(String body, {int status = 200}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: '',
      headers: const {},
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: const Duration(milliseconds: 5),
    );

EnvironmentVariableEntity _envVar(int id, String key, String value, {bool enabled = true}) =>
    EnvironmentVariableEntity(id: id, environmentId: 1, key: key, value: value, isSecret: false, enabled: enabled);

GlobalVariableEntity _globalVar(int id, String key, String value, {bool enabled = true}) =>
    GlobalVariableEntity(id: id, key: key, value: value, isSecret: false, enabled: enabled);

void main() {
  group('RunRequestScriptsUseCase', () {
    test('returns an empty result when the request has no scripts', () async {
      final result = await _Harness().run(1, '{}');

      expect(result.isEmpty, isTrue);
    });

    test('a value extracted by one request resolves in the next request\'s assertion', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'data.id', variableKey: 'userId')]);
      harness.scripts.set(2, assertions: [
        AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.id', expected: '{{userId}}'),
      ]);

      final login = await harness.run(1, '{"data":{"id":42}}');
      final fetch = await harness.run(2, '{"data":{"id":42}}');

      expect(login.extracted.single.ok, isTrue);
      expect(fetch.assertions.single.passed, isTrue);
      expect(fetch.assertions.single.name, 'data.id equals {{userId}}');
    });

    test('a disabled environment variable is re-enabled when an extractor writes it', () async {
      final harness = _Harness(environment: [_envVar(1, 'token', 'old', enabled: false)]);
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'token', variableKey: 'token')]);

      final result = await harness.run(1, '{"token":"fresh"}');

      expect(result.extracted.single.ok, isTrue);
      expect(await harness.environment.getActiveVariables(), {'token': 'fresh'});
    });

    test('with a duplicated key the extractor updates the row the resolver reads', () async {
      final harness = _Harness(environment: [_envVar(1, 'token', 'stale'), _envVar(2, 'token', 'older')]);
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'token', variableKey: 'token')]);

      await harness.run(1, '{"token":"fresh"}');

      expect(await harness.environment.getActiveVariables(), {'token': 'fresh'});
      expect(harness.environment.variables.map((v) => v.value), ['stale', 'fresh']);
    });

    test('an enabled duplicate is updated in preference to a later disabled one', () async {
      final harness = _Harness(environment: [_envVar(1, 'token', 'a'), _envVar(2, 'token', 'b', enabled: false)]);
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'token', variableKey: 'token')]);

      await harness.run(1, '{"token":"fresh"}');

      expect(await harness.environment.getActiveVariables(), {'token': 'fresh'});
      expect(harness.environment.variables.map((v) => (v.value, v.enabled)), [('fresh', true), ('b', false)]);
    });

    test('a disabled global is re-enabled when a global extractor writes it', () async {
      final harness = _Harness(globals: [_globalVar(1, 'token', 'old', enabled: false)]);
      harness.scripts.set(1, extractors: [
        ExtractorEntity(path: 'token', scope: ExtractorScope.global, variableKey: 'token'),
      ]);

      final result = await harness.run(1, '{"token":"fresh"}');

      expect(result.extracted.single.ok, isTrue);
      expect(await harness.globals.getEnabledMap(), {'token': 'fresh'});
    });

    test('rejects a name the resolver could never match, and writes nothing', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'token', variableKey: 'access token')]);

      final result = await harness.run(1, '{"token":"t"}');

      expect(result.extracted.single.ok, isFalse);
      expect(result.extracted.single.error, ExtractorEntity(variableKey: 'access token').keyError);
      expect(harness.environment.variables, isEmpty);
    });

    test('accepts names with hyphens and dots', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [
        ExtractorEntity(path: 'token', variableKey: 'access-token'),
        ExtractorEntity(path: 'id', variableKey: 'user.id'),
      ]);

      final result = await harness.run(1, '{"token":"t","id":9}');

      expect(result.extracted.every((e) => e.ok), isTrue);
      expect(await harness.environment.getActiveVariables(), {'access-token': 't', 'user.id': '9'});
    });

    test('rejects a blank path instead of copying the whole body', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(variableKey: 'body')]);

      final result = await harness.run(1, '{"token":"t"}');

      expect(result.extracted.single.error, 'Enter a JSON path');
      expect(harness.environment.variables, isEmpty);
    });

    test('reports a missing active environment', () async {
      final harness = _Harness();
      harness.environment.active = null;
      harness.scripts.set(1, extractors: [ExtractorEntity(path: 'token', variableKey: 'token')]);

      final result = await harness.run(1, '{"token":"t"}');

      expect(result.extracted.single.error, 'No active environment');
    });

    test('an extractor path resolves through the ordinary scopes', () async {
      final harness = _Harness(environment: [_envVar(1, 'field', 'data.id')]);
      harness.scripts.set(1, extractors: [ExtractorEntity(path: '{{field}}', variableKey: 'userId')]);

      final result = await harness.run(1, '{"data":{"id":42}}');

      expect(result.extracted.single.ok, isTrue);
      expect(await harness.environment.getActiveVariables(), {'field': 'data.id', 'userId': '42'});
    });

    test('a path left unresolved is reported as not found, not read as something else', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(path: '{{field}}', variableKey: 'userId')]);

      final result = await harness.run(1, '{"data":{"id":42}}');

      expect(result.extracted.single.ok, isFalse);
      expect(result.extracted.single.error, 'Not found in response');
      expect(harness.environment.variables, isEmpty);
    });
  });

  group('RunRequestScriptsUseCase with data variables', () {
    test('a column resolves in an assertion\'s expected value and path, above the environment\'s variable', () async {
      final harness = _Harness(environment: [_envVar(1, 'id', 'from-environment')]);
      harness.scripts.set(1, assertions: [
        AssertionEntity(type: AssertionType.jsonPathEquals, path: '{{field}}', expected: '{{id}}'),
      ]);

      final withRow = await harness.run(1, '{"data":{"id":"7"}}', dataVariables: {'field': 'data.id', 'id': '7'});
      final withoutRow = await harness.run(1, '{"data":{"id":"7"}}');

      expect(withRow.assertions.single.passed, isTrue);
      expect(withRow.assertions.single.name, '{{field}} equals {{id}}');
      expect(withoutRow.assertions.single.passed, isFalse, reason: 'the row belongs to one run only');
    });

    test('a column resolves in an extractor\'s path, and the value is saved as usual', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(path: '{{field}}', variableKey: 'userId')]);

      final result = await harness.run(1, '{"data":{"id":42}}', dataVariables: {'field': 'data.id'});

      expect(result.extracted.single.ok, isTrue);
      expect(result.extracted.single.value, '42');
      expect(await harness.environment.getActiveVariables(), {'userId': '42'});
    });

    test('a column that leaves an extractor path blank is rejected instead of copying the whole body', () async {
      final harness = _Harness();
      harness.scripts.set(1, extractors: [ExtractorEntity(path: '{{field}}', variableKey: 'body')]);

      final result = await harness.run(1, '{"token":"t"}', dataVariables: {'field': ''});

      expect(result.extracted.single.error, 'Enter a JSON path');
      expect(harness.environment.variables, isEmpty);
    });

    test('a column beats a variable of the same name that an earlier request extracted', () async {
      final harness = _Harness(environment: [_envVar(1, 'userId', 'stale')]);
      harness.scripts.set(1, assertions: [
        AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.id', expected: '{{userId}}'),
      ]);

      final result = await harness.run(1, '{"data":{"id":42}}', dataVariables: {'userId': '42'});

      expect(result.assertions.single.passed, isTrue);
    });

    test('an environment value that references a column sees the row in the assertion too', () async {
      final harness = _Harness(environment: [_envVar(1, 'expectedName', 'name-{{id}}')]);
      harness.scripts.set(1, assertions: [
        AssertionEntity(type: AssertionType.jsonPathEquals, path: 'name', expected: '{{expectedName}}'),
      ]);

      final result = await harness.run(1, '{"name":"name-9"}', dataVariables: {'id': '9'});

      expect(result.assertions.single.passed, isTrue);
    });
  });

  group('CollectionRunResult.passed', () {
    const summary = RequestSummaryEntity(id: 1, folderId: null, name: 'r', method: HttpMethod.get);
    const passingTest = AssertionResult(name: 't', passed: true, actual: '');
    const failingTest = AssertionResult(name: 't', passed: false, actual: '');
    const savedVariable = ExtractionResult(key: 'k', scope: ExtractorScope.environment, value: 'v');
    const failedVariable =
        ExtractionResult(key: 'k', scope: ExtractorScope.environment, error: 'No active environment');

    CollectionRunResult result({
      int status = 200,
      List<AssertionResult> tests = const [],
      List<ExtractionResult> variables = const [],
    }) =>
        CollectionRunResult(
          request: summary,
          response: _response('{}', status: status),
          scripts: ScriptRunResult(assertions: tests, extracted: variables),
        );

    test('without tests it follows the HTTP status', () {
      expect(result().passed, isTrue);
      expect(result(status: 500).passed, isFalse);
    });

    test('with tests it follows them, even on a non-2xx status', () {
      expect(result(status: 404, tests: [passingTest]).passed, isTrue);
      expect(result(tests: [passingTest, failingTest]).passed, isFalse);
    });

    test('a failed extraction fails the request with or without tests', () {
      expect(result(variables: [savedVariable]).passed, isTrue);
      expect(result(variables: [failedVariable]).passed, isFalse);
      expect(result(tests: [passingTest], variables: [failedVariable]).passed, isFalse);
      expect(result(status: 500, variables: [savedVariable]).passed, isFalse);
    });

    test('a request that threw has no scripts and did not pass', () {
      expect(const CollectionRunResult(request: summary, error: 'boom').passed, isFalse);
    });
  });
}

final class _Harness {
  final _FakeScriptsRepository scripts = _FakeScriptsRepository();
  final _FakeEnvironmentRepository environment;
  final _FakeGlobalVariableRepository globals;
  late final RunRequestScriptsUseCase useCase = RunRequestScriptsUseCase(
    scripts,
    BuildVariableResolverUseCase(_FakeCollectionVariableRepository(), environment, globals),
    environment,
    globals,
  );

  _Harness({List<EnvironmentVariableEntity> environment = const [], List<GlobalVariableEntity> globals = const []})
      : environment = _FakeEnvironmentRepository([...environment]),
        globals = _FakeGlobalVariableRepository([...globals]);

  Future<ScriptRunResult> run(
    int requestId,
    String responseBody, {
    Map<String, String> dataVariables = const {},
  }) =>
      useCase(
        RunRequestScriptsParams(
          requestId: requestId,
          collectionId: _collectionId,
          response: _response(responseBody),
          dataVariables: dataVariables,
        ),
      );
}

final class _FakeScriptsRepository implements RequestScriptsRepository {
  final Map<int, RequestScriptsEntity> _byRequest = {};

  void set(int requestId, {List<AssertionEntity> assertions = const [], List<ExtractorEntity> extractors = const []}) {
    _byRequest[requestId] = RequestScriptsEntity(
      requestId: requestId,
      assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions),
      extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors),
    );
  }

  @override
  Future<RequestScriptsEntity?> get(int requestId) async => _byRequest[requestId];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Mirrors the real repository's contract: the active environment's enabled
/// rows, the last row winning for a repeated key.
final class _FakeEnvironmentRepository implements EnvironmentRepository {
  EnvironmentEntity? active = const EnvironmentEntity(id: 1, name: 'dev', isActive: true);
  final List<EnvironmentVariableEntity> variables;
  int _nextId = 100;

  _FakeEnvironmentRepository(this.variables);

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(active);

  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) =>
      Stream.value([for (final v in variables) if (v.environmentId == environmentId) v]);

  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) async {
    if (variable.id != 0) {
      variables[variables.indexWhere((v) => v.id == variable.id)] = variable;
      return;
    }
    variables.add(EnvironmentVariableEntity(
      id: _nextId++,
      environmentId: variable.environmentId,
      key: variable.key,
      value: variable.value,
      isSecret: variable.isSecret,
      enabled: variable.enabled,
    ));
  }

  @override
  Future<Map<String, String>> getActiveVariables() async => {
        for (final v in variables.where((v) => v.enabled && v.environmentId == active?.id)) v.key: v.value,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeGlobalVariableRepository implements GlobalVariableRepository {
  final List<GlobalVariableEntity> variables;
  int _nextId = 200;

  _FakeGlobalVariableRepository(this.variables);

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(List.of(variables));

  @override
  Future<void> upsert(GlobalVariableEntity variable) async {
    if (variable.id != 0) {
      variables[variables.indexWhere((v) => v.id == variable.id)] = variable;
      return;
    }
    variables.add(GlobalVariableEntity(
      id: _nextId++,
      key: variable.key,
      value: variable.value,
      isSecret: variable.isSecret,
      enabled: variable.enabled,
    ));
  }

  @override
  Future<Map<String, String>> getEnabledMap() async => {for (final v in variables.where((v) => v.enabled)) v.key: v.value};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeCollectionVariableRepository implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
