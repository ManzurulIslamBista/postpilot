import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/variable_scope.dart';

import 'support/drift_repos.dart';

/// The real repositories over a real database, so the change streams the
/// scope listens to are the ones the app has. Nothing here notifies the scope
/// by hand: a variable that appears must be noticed because it was written.
void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late VariableScope scope;
  late int collectionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    collectionId = await db.collectionsDao.createCollection('c');
    scope = VariableScope(
      ListVariablesUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository),
    );
    scope.bindCollection(collectionId);
    await scope.refresh();
  });

  tearDown(() async {
    scope.dispose();
    await db.close();
  });

  Future<void> until(bool Function() condition, {String? reason}) async {
    for (var i = 0; i < 300; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for the scope to notice${reason == null ? '' : ': $reason'}');
  }

  test('starts loaded, with nothing defined', () {
    expect(scope.isLoaded, isTrue);
    expect(scope.isDefined('token'), isFalse);
  });

  test('a global variable added afterwards is noticed', () async {
    await repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'token', value: 'abc', isSecret: false, enabled: true),
    );

    await until(() => scope.isDefined('token'));
    expect(scope.describe('token').value, 'abc');
  });

  test('a collection variable added or edited afterwards is noticed (it never was)', () async {
    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: collectionId, key: 'page', value: '1', enabled: true),
    );
    await until(() => scope.isDefined('page'));

    final saved = (await repos.collectionVariableRepository.watchByCollection(collectionId).first).single;
    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: saved.id, collectionId: collectionId, key: 'page', value: '2', enabled: true),
    );

    await until(() => scope.describe('page').value == '2');
  });

  test('a variable of another collection is not shown, and not mistaken for a change that matters', () async {
    final other = await db.collectionsDao.createCollection('other');

    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: other, key: 'theirs', value: '1', enabled: true),
    );
    await repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'marker', value: '1', isSecret: false, enabled: true),
    );

    await until(() => scope.isDefined('marker'), reason: 'a later write is seen');
    expect(scope.isDefined('theirs'), isFalse);
  });

  test('a variable a script extracts into the active environment turns defined, with no dialog ever opened', () async {
    final env = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.setActive(env);

    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: env, key: 'authToken', value: 'fresh', isSecret: true, enabled: true),
    );

    await until(() => scope.isDefined('authToken'));
    expect(scope.describe('authToken').value, 'fresh');
  });

  test('editing a variable of the active environment updates what the editors show', () async {
    final env = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.setActive(env);
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: env, key: 'host', value: 'one', isSecret: false, enabled: true),
    );
    await until(() => scope.describe('host').value == 'one');

    final saved = (await repos.environmentRepository.watchVariables(env).first).single;
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: saved.id, environmentId: env, key: 'host', value: 'two', isSecret: false, enabled: true),
    );

    await until(() => scope.describe('host').value == 'two');
  });

  test('switching the active environment swaps its variables in, and the old one out', () async {
    final dev = await repos.environmentRepository.create('Dev');
    final prod = await repos.environmentRepository.create('Prod');
    for (final (env, key) in [(dev, 'onlyDev'), (prod, 'onlyProd')]) {
      await repos.environmentRepository.upsertVariable(
        EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: 'v', isSecret: false, enabled: true),
      );
    }
    await repos.environmentRepository.setActive(dev);
    await until(() => scope.isDefined('onlyDev'));
    expect(scope.isDefined('onlyProd'), isFalse);

    await repos.environmentRepository.setActive(prod);

    await until(() => scope.isDefined('onlyProd') && !scope.isDefined('onlyDev'));

    // And a change inside the new one is watched, not the old one.
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: prod, key: 'addedLater', value: 'v', isSecret: false, enabled: true),
    );
    await until(() => scope.isDefined('addedLater'));
  });

  test('deactivating the environment drops its variables', () async {
    final env = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: env, key: 'gone', value: 'v', isSecret: false, enabled: true),
    );
    await repos.environmentRepository.setActive(env);
    await until(() => scope.isDefined('gone'));

    await repos.environmentRepository.clearActive();

    await until(() => !scope.isDefined('gone'));
  });

  test('listeners hear about a change, once it is real', () async {
    var heard = 0;
    scope.addListener(() => heard++);

    await repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'k', value: 'v', isSecret: false, enabled: true),
    );
    await until(() => scope.isDefined('k'));
    final afterChange = heard;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(afterChange, greaterThan(0));
    expect(heard, afterChange, reason: 'a refresh that finds nothing new does not notify');
  });

  test('a refresh awaited while another is running completes only once the state is current', () async {
    final first = scope.refresh();
    await repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'late', value: 'v', isSecret: false, enabled: true),
    );
    final second = scope.refresh();

    await Future.wait([first, second]);

    expect(scope.isDefined('late'), isTrue);
  });

  test('rebinding to another collection follows that collection', () async {
    final other = await db.collectionsDao.createCollection('other');
    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: other, key: 'fromOther', value: '1', enabled: true),
    );

    scope.bindCollection(other);
    await scope.refresh();
    expect(scope.isDefined('fromOther'), isTrue);

    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: other, key: 'second', value: '1', enabled: true),
    );
    await until(() => scope.isDefined('second'));
  });
}
