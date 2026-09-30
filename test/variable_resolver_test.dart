import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/dynamic_variables.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';

void main() {
  group('VariableResolver', () {
    test('resolves known variables and leaves unknown ones untouched', () {
      final resolver = VariableResolver({'host': 'api.example.com', 'version': 'v2'});

      expect(resolver.resolve('https://{{host}}/{{version}}/users'), 'https://api.example.com/v2/users');
      expect(resolver.resolve('{{missing}}'), '{{missing}}');
    });

    test('resolveMap applies resolution to every value', () {
      final resolver = VariableResolver({'token': 'abc123'});
      final result = resolver.resolveMap({'Authorization': 'Bearer {{token}}'});

      expect(result['Authorization'], 'Bearer abc123');
    });

    test('layered scopes: the first scope holding a key wins', () {
      final resolver = VariableResolver.layered([
        {'host': 'env.example.com'},
        {'host': 'collection.example.com', 'token': 'collection-token'},
        {'host': 'global.example.com', 'token': 'global-token', 'region': 'eu'},
      ]);

      expect(resolver.resolve('{{host}}'), 'env.example.com');
      expect(resolver.resolve('{{token}}'), 'collection-token');
      expect(resolver.resolve('{{region}}'), 'eu');
    });

    test('layered scopes leave unknown tokens untouched', () {
      final resolver = VariableResolver.layered([
        {'a': '1'},
        {'b': '2'},
      ]);

      expect(resolver.resolve('{{a}}/{{b}}/{{c}}'), '1/2/{{c}}');
      expect(VariableResolver.layered(const []).resolve('{{a}}'), '{{a}}');
    });

    test('resolves variables referenced inside variable values, across scopes', () {
      final resolver = VariableResolver.layered([
        {'host': 'api.staging.com'},
        {'baseUrl': 'https://{{host}}/v1', 'token': 'Bearer {{raw}}'},
        {'raw': 'abc123'},
      ]);

      expect(resolver.resolve('{{baseUrl}}/users'), 'https://api.staging.com/v1/users');
      expect(resolver.resolve('{{token}}'), 'Bearer abc123');
    });

    test('resolves multi-level chains of references', () {
      final resolver = VariableResolver({
        'url': '{{protocol}}://{{host}}',
        'protocol': 'https',
        'host': '{{name}}.example.com',
        'name': 'api',
      });

      expect(resolver.resolve('{{url}}'), 'https://api.example.com');
    });

    test('self-referencing and mutually-referencing variables stay unresolved instead of looping', () {
      final resolver = VariableResolver({'a': 'x{{a}}', 'b': '{{c}}', 'c': '{{b}}'});

      expect(resolver.resolve('{{a}}'), 'x{{a}}');
      expect(resolver.resolve('{{b}}'), '{{b}}');
    });

    test('resolves names containing hyphens, dots and dollar signs', () {
      final resolver = VariableResolver({'base-url': 'https://api.example.com', 'user.id': '42', r'$region': 'eu'});

      expect(
        resolver.resolve(r'{{base-url}}/users/{{user.id}}?r={{$region}}'),
        'https://api.example.com/users/42?r=eu',
      );
    });
  });

  group('VariableResolver dynamic variables', () {
    final now = DateTime.utc(2026, 9, 30, 12);
    DynamicVariables generator([int seed = 7]) => DynamicVariables(random: Random(seed), clock: () => now);

    test('a built-in resolves when no scope defines it', () {
      final resolver = VariableResolver(const {}, generator());

      expect(resolver.resolve(r'{{$timestamp}}'), '${now.millisecondsSinceEpoch ~/ 1000}');
      expect(resolver.resolve(r'{{$isoTimestamp}}'), '2026-09-30T12:00:00.000Z');
    });

    test('every occurrence gets its own value', () {
      final resolver = VariableResolver(const {}, generator());

      final parts = resolver.resolve(r'{{$guid}}|{{$guid}}|{{$randomPassword}}|{{$randomPassword}}').split('|');

      expect(parts[0], isNot(parts[1]));
      expect(parts[2], isNot(parts[3]));
    });

    test('a variable in any scope shadows the built-in of the same name', () {
      final layered = VariableResolver.layered([
        const {},
        const {},
        {r'$guid': 'pinned'},
      ], generator());

      expect(layered.resolve(r'{{$guid}}'), 'pinned');
      expect(VariableResolver({r'$randomInt': '7'}).resolve(r'{{$randomInt}}'), '7');
    });

    test('a user variable shadows only its own exact name', () {
      final resolver = VariableResolver({r'$guid': 'pinned'}, generator());

      expect(resolver.resolve(r'{{$guid}}'), 'pinned');
      expect(resolver.resolve(r'{{$randomUUID}}'), isNot(r'{{$randomUUID}}'));
    });

    test('unknown, misspelled and malformed tokens are left as written', () {
      final resolver = VariableResolver(const {}, generator());

      for (final token in [r'{{$notABuiltIn}}', r'{{$GUID}}', r'{{guid}}', r'{{ $guid }}', r'{{$guid', r'{$guid}']) {
        expect(resolver.resolve(token), token);
      }
    });

    test('built-ins resolve inside a variable value and beside ordinary variables', () {
      final resolver = VariableResolver({'stamp': r'at {{$isoTimestamp}}', 'host': 'api.test'}, generator());

      expect(resolver.resolve('{{host}} {{stamp}}'), 'api.test at 2026-09-30T12:00:00.000Z');
    });

    test('a seeded generator makes a resolved string reproducible', () {
      const template = r'{"id":"{{$guid}}","user":"{{$randomEmail}}","n":{{$randomInt}}}';

      final first = VariableResolver(const {}, generator(3)).resolve(template);

      expect(VariableResolver(const {}, generator(3)).resolve(template), first);
      expect(first, isNot(contains('{{')));
      expect(VariableResolver(const {}, generator(4)).resolve(template), isNot(first));
    });

    test('resolveMap gives every value its own built-ins', () {
      final resolved = VariableResolver(const {}, generator()).resolveMap({'a': r'{{$guid}}', 'b': r'{{$guid}}'});

      expect(resolved['a'], isNot(resolved['b']));
    });

    test('without an injected generator the shared one is used', () {
      expect(
        VariableResolver.layered(const []).resolve(r'{{$guid}}'),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });

  group('BuildVariableResolverUseCase', () {
    const collectionId = 7;

    BuildVariableResolverUseCase buildUseCase({
      List<CollectionVariableEntity> collection = const [],
      List<EnvironmentVariableEntity> environment = const [],
      List<GlobalVariableEntity> globals = const [],
    }) =>
        BuildVariableResolverUseCase(
          _FakeCollectionVariableRepository(collection),
          _FakeEnvironmentRepository(environment),
          _FakeGlobalVariableRepository(globals),
        );

    test('environment beats collection beats global', () async {
      final useCase = buildUseCase(
        collection: [_collectionVar('host', 'collection.example.com'), _collectionVar('token', 'collection-token')],
        environment: [_envVar('host', 'env.example.com')],
        globals: [
          _globalVar('host', 'global.example.com'),
          _globalVar('token', 'global-token'),
          _globalVar('region', 'eu'),
        ],
      );

      final resolver = await useCase(collectionId);

      expect(
        resolver.resolve('{{host}} {{token}} {{region}} {{missing}}'),
        'env.example.com collection-token eu {{missing}}',
      );
    });

    test('only the request collection\'s own variables are layered in', () async {
      final useCase = buildUseCase(
        collection: [
          _collectionVar('host', 'mine.example.com'),
          _collectionVar('host', 'other.example.com', collectionId: 99),
          _collectionVar('only_other', 'x', collectionId: 99),
        ],
      );

      final resolver = await useCase(collectionId);

      expect(resolver.resolve('{{host}} {{only_other}}'), 'mine.example.com {{only_other}}');
    });

    test('disabled variables are ignored and fall through to the next scope', () async {
      final useCase = buildUseCase(
        collection: [_collectionVar('host', 'collection.example.com', enabled: false)],
        environment: [_envVar('host', 'env.example.com'), _envVar('token', 'env-token', enabled: false)],
        globals: [_globalVar('token', 'global-token'), _globalVar('region', 'eu', enabled: false)],
      );

      final resolver = await useCase(collectionId);

      expect(resolver.resolve('{{host}} {{token}} {{region}}'), 'env.example.com global-token {{region}}');
    });

    group('data variables (a collection run\'s data row)', () {
      test('sit above the environment, the collection and the globals', () async {
        final useCase = buildUseCase(
          collection: [_collectionVar('host', 'collection.example.com')],
          environment: [_envVar('host', 'env.example.com'), _envVar('token', 'env-token')],
          globals: [_globalVar('host', 'global.example.com'), _globalVar('region', 'eu')],
        );

        final resolver = await useCase(collectionId, dataVariables: {'host': 'row.example.com', 'id': '7'});

        expect(resolver.resolve('{{host}} {{id}} {{token}} {{region}}'), 'row.example.com 7 env-token eu');
      });

      test('reach the variables that reference them, in every scope', () async {
        final useCase = buildUseCase(
          collection: [_collectionVar('collectionUrl', 'https://{{tenant}}.example.com')],
          environment: [_envVar('greeting', 'hello {{name}}')],
          globals: [_globalVar('globalUrl', '{{collectionUrl}}/v1/{{id}}')],
        );

        final resolver = await useCase(collectionId, dataVariables: {'tenant': 'acme', 'name': 'Ada', 'id': '7'});

        expect(resolver.resolve('{{greeting}} {{globalUrl}}'), 'hello Ada https://acme.example.com/v1/7');
      });

      test('are optional: without them the three scopes resolve exactly as before', () async {
        final useCase = buildUseCase(
          environment: [_envVar('host', 'env.example.com')],
          globals: [_globalVar('region', 'eu')],
        );

        final withNone = await useCase(collectionId);
        final withEmpty = await useCase(collectionId, dataVariables: const {});

        expect(withNone.scopes, hasLength(3));
        expect(withEmpty.scopes, hasLength(3));
        expect(withEmpty.resolve('{{host}} {{region}} {{id}}'), 'env.example.com eu {{id}}');
      });

      test('shadow a built-in of the same name like any other variable', () async {
        final resolver = await buildUseCase()(collectionId, dataVariables: {r'$guid': 'fixed'});

        expect(resolver.resolve(r'{{$guid}}'), 'fixed');
      });
    });
  });
}

CollectionVariableEntity _collectionVar(String key, String value, {int collectionId = 7, bool enabled = true}) =>
    CollectionVariableEntity(id: 0, collectionId: collectionId, key: key, value: value, enabled: enabled);

EnvironmentVariableEntity _envVar(String key, String value, {bool enabled = true}) =>
    EnvironmentVariableEntity(id: 0, environmentId: 1, key: key, value: value, isSecret: false, enabled: enabled);

GlobalVariableEntity _globalVar(String key, String value, {bool enabled = true}) =>
    GlobalVariableEntity(id: 0, key: key, value: value, isSecret: false, enabled: enabled);

/// The fakes below mirror the repositories' documented contract: the map
/// getters are enabled-only, so the use case never sees disabled rows.
final class _FakeCollectionVariableRepository implements CollectionVariableRepository {
  final List<CollectionVariableEntity> _rows;
  const _FakeCollectionVariableRepository(this._rows);

  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async =>
      {for (final v in _rows.where((v) => v.collectionId == collectionId && v.enabled)) v.key: v.value};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeEnvironmentRepository implements EnvironmentRepository {
  final List<EnvironmentVariableEntity> _rows;
  const _FakeEnvironmentRepository(this._rows);

  @override
  Future<Map<String, String>> getActiveVariables() async =>
      {for (final v in _rows.where((v) => v.enabled)) v.key: v.value};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeGlobalVariableRepository implements GlobalVariableRepository {
  final List<GlobalVariableEntity> _rows;
  const _FakeGlobalVariableRepository(this._rows);

  @override
  Future<Map<String, String>> getEnabledMap() async => {for (final v in _rows.where((v) => v.enabled)) v.key: v.value};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
