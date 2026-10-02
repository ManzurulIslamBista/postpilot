import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/variable_info.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';

import 'support/in_memory_import_export_fakes.dart';

void main() {
  late InMemoryDb db;
  late ListVariablesUseCase list;

  setUp(() {
    db = InMemoryDb();
    list = ListVariablesUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
  });

  void global(String key, String value, {bool secret = false, bool enabled = true}) =>
      db.globals.add(GlobalVariableEntity(id: db.nextId(), key: key, value: value, isSecret: secret, enabled: enabled));

  void collection(int collectionId, String key, String value, {bool enabled = true}) => db.variables.add(
    CollectionVariableEntity(id: db.nextId(), collectionId: collectionId, key: key, value: value, enabled: enabled),
  );

  int environment(String name, {required bool active}) {
    final id = db.nextId();
    db.environments.add(EnvironmentEntity(id: id, name: name, isActive: active));
    return id;
  }

  void envVar(int environmentId, String key, String value, {bool secret = false, bool enabled = true}) =>
      db.environmentVariables.add(
        EnvironmentVariableEntity(
          id: db.nextId(),
          environmentId: environmentId,
          key: key,
          value: value,
          isSecret: secret,
          enabled: enabled,
        ),
      );

  test('the active environment wins over the collection, which wins over the globals', () async {
    global('host', 'global-host');
    collection(1, 'host', 'collection-host');
    envVar(environment('Testing', active: true), 'host', 'env-host');

    final host = (await list(1))['host']!;

    expect(host.source, VariableSource.environment);
    expect(host.value, 'env-host');
    expect(host.scopeName, 'Testing');
  });

  test('without an active environment the collection beats the globals', () async {
    global('host', 'global-host');
    collection(1, 'host', 'collection-host');
    envVar(environment('Staging', active: false), 'host', 'ignored: not the active one');

    final host = (await list(1))['host']!;

    expect(host.source, VariableSource.collection);
    expect(host.value, 'collection-host');
  });

  test('each name carries the scope that actually supplies it', () async {
    global('g', '1');
    collection(1, 'c', '2');
    envVar(environment('Testing', active: true), 'e', '3');

    final vars = await list(1);

    expect(vars['g']!.source, VariableSource.global);
    expect(vars['c']!.source, VariableSource.collection);
    expect(vars['e']!.source, VariableSource.environment);
    expect(vars.keys, unorderedEquals(['g', 'c', 'e']));
  });

  test('disabled variables and other collections\' variables are not visible', () async {
    global('off', 'x', enabled: false);
    collection(1, 'off-too', 'x', enabled: false);
    collection(2, 'elsewhere', 'x');
    envVar(environment('Testing', active: true), 'env-off', 'x', enabled: false);

    expect(await list(1), isEmpty);
  });

  test('a secret keeps its flag, so a hover can hide the value', () async {
    envVar(environment('Testing', active: true), 'token', 's3cret', secret: true);
    global('g-secret', 'also-hidden', secret: true);
    global('plain', 'visible');

    final vars = await list(1);

    expect(vars['token']!.isSecret, isTrue);
    expect(vars['g-secret']!.isSecret, isTrue);
    expect(vars['plain']!.isSecret, isFalse);
  });
}
