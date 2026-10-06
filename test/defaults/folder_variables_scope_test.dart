// Folder variables show in the hover card and the "undefined variable" check, like the other scopes.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/variable_info.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/variable_scope.dart';

import '../support/drift_repos.dart';

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int shop;
  late int outer;
  late int inner;
  late int other;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    shop = await repos.collectionRepository.createCollection('Shop');
    outer = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Outer');
    inner = await repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: outer, name: 'Inner');
    other = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Other');
  });
  tearDown(() => db.close());

  ListVariablesUseCase list() => ListVariablesUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      );

  test('a folder variable is listed with its folder, the innermost folder winning over the one above', () async {
    await repos.defaultsRepository.saveFolder(
      outer,
      LevelDefaults(variables: [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'pageSize', value: '10')]),
    );
    await repos.defaultsRepository.saveFolder(
      inner,
      LevelDefaults(variables: [DefaultVariable(key: 'region', value: 'us'), DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true)]),
    );

    final variables = await list()(shop, folderId: inner);

    expect(variables['region'], const VariableInfo(name: 'region', source: VariableSource.folder, scopeName: 'Inner', value: 'us'));
    expect(variables['pageSize']?.scopeName, 'Outer');
    expect(variables['apiKey']?.isSecret, isTrue);
    expect(variables['apiKey']?.source, VariableSource.folder);
  });

  test('ranks below the active environment and above the collection and the globals', () async {
    await repos.globalVariableRepository.upsert(GlobalVariableEntity(id: 0, key: 'v', value: 'global', isSecret: false, enabled: true));
    await repos.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'v', value: 'collection', enabled: true));
    expect((await list()(shop, folderId: inner))['v']?.source, VariableSource.collection);

    await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'v', value: 'folder')]));
    expect((await list()(shop, folderId: inner))['v']?.source, VariableSource.folder);

    final env = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: env, key: 'v', value: 'env', isSecret: false, enabled: true));
    await repos.environmentRepository.setActive(env);
    expect((await list()(shop, folderId: inner))['v']?.source, VariableSource.environment);
  });

  test('a request outside the folder, or with no folder given, does not see its variables', () async {
    await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'only', value: '1')]));

    expect((await list()(shop, folderId: other)).containsKey('only'), isFalse);
    expect((await list()(shop, folderId: outer)).containsKey('only'), isFalse, reason: 'a variable goes down the tree, not up');
    expect((await list()(shop)).containsKey('only'), isFalse);
  });

  test('a disabled folder variable is not listed', () async {
    await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'off', value: '1', enabled: false)]));
    expect((await list()(shop, folderId: inner)).containsKey('off'), isFalse);
  });

  test('changes fires when a folder variable is edited', () async {
    final fired = list().changes(shop).firstWhere((_) => true);

    await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'v', value: '1')]));

    await fired.timeout(const Duration(seconds: 5));
  });

  group('VariableScope', () {
    test('defines and describes a folder variable for the folder it is bound to, and not for another', () async {
      await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'region', value: 'us')]));
      final scope = VariableScope(list());
      addTearDown(scope.dispose);

      scope.bindCollection(shop, folderId: inner);
      await scope.refresh();
      expect(scope.isDefined('region'), isTrue);
      expect(scope.describe('region').source, VariableSource.folder);
      expect(scope.describe('region').value, 'us');

      scope.bindCollection(shop, folderId: other);
      await scope.refresh();
      expect(scope.isDefined('region'), isFalse, reason: 'a request moved to another folder stops seeing it');
      expect(scope.describe('region').isResolved, isFalse);
    });

    test('a secret folder variable is described as secret, so its value is never put on screen', () async {
      await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'token', value: 'hush', isSecret: true)]));
      final scope = VariableScope(list());
      addTearDown(scope.dispose);

      scope.bindCollection(shop, folderId: inner);
      await scope.refresh();

      expect(scope.describe('token').isSecret, isTrue);
    });

    test('picks up an edit made in the defaults dialog without being asked', () async {
      final scope = VariableScope(list());
      addTearDown(scope.dispose);
      scope.bindCollection(shop, folderId: inner);
      await scope.refresh();
      expect(scope.isDefined('late'), isFalse);

      final changed = Future<void>(() async {
        while (!scope.isDefined('late')) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'late', value: '1')]));

      await changed.timeout(const Duration(seconds: 5));
    });
  });
}
