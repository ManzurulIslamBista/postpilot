import 'dart:io';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/git_sync/data/repositories/drift_git_state_store.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';

/// One "app run": its own database and view model over shared storage.
final class _App {
  final AppDatabase database;
  final DriftRepos repos;
  final ShellViewModel shell;
  WorkplaceViewModel vm;

  _App._(this.database, this.repos, this.shell, this.vm);

  factory _App(WorkplaceRepositoryImpl repository, {Duration autosaveDelay = const Duration(milliseconds: 30)}) {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(database);
    final shell = ShellViewModel(repos.requestRepository);
    final vm = WorkplaceViewModel(
      repository: repository,
      backupService: repos.backupServiceWith(DriftGitStateStore(database)),
      database: database,
      shellViewModel: shell,
      autosaveDelay: autosaveDelay,
      settleDelay: const Duration(milliseconds: 20),
    );
    return _App._(database, repos, shell, vm);
  }

  Future<List<String>> collectionNames() async => [
    for (final c in await repos.collectionRepository.watchCollections().first) c.name,
  ];

  Future<List<String>> environmentNames() async => [
    for (final e in await repos.environmentRepository.watchAll().first) e.name,
  ];

  Future<String?> activeEnvironmentName() async {
    for (final e in await repos.environmentRepository.watchAll().first) {
      if (e.isActive) return e.name;
    }
    return null;
  }

  Future<Map<String, int>> collectionIds() async => {
    for (final c in await repos.collectionRepository.watchCollections().first) c.name: c.id,
  };

  /// A new view model over this same database: the app restarting without the
  /// database being wiped (as on every reload of the web build).
  WorkplaceViewModel restartedViewModel(WorkplaceRepositoryImpl repository) {
    vm.dispose();
    return WorkplaceViewModel(
      repository: repository,
      backupService: repos.backupServiceWith(DriftGitStateStore(database)),
      database: database,
      shellViewModel: shell,
      autosaveDelay: const Duration(milliseconds: 30),
      settleDelay: const Duration(milliseconds: 20),
    );
  }

  Future<void> close() async {
    await vm.saveCurrentWorkplace(); // lets a save already under way finish before the files go
    vm.dispose();
    shell.dispose();
    await database.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A test can open a second database to simulate restarting the app.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;
  late WorkplaceRepositoryImpl repository;
  late _App app;

  String folder(String name) => p.join(temp.path, name);

  List<String> namesInFile(WorkplaceEntity workplace) {
    final text = File(p.join(workplace.folderPath, 'workspace.json')).readAsStringSync();
    return [for (final c in BackupCodec.decode(text).collections) c.name];
  }

  Future<void> waitFor(bool Function() condition, {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for ${reason ?? 'condition'}');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('postpilot_workplace_vm_test_');
    repository = WorkplaceRepositoryImpl(
      storage: FileWorkplaceStorage(
        registryDirectory: Directory(p.join(temp.path, 'registry')),
        defaultWorkplacesDirectory: p.join(temp.path, 'workplaces'),
      ),
    );
    app = _App(repository);
  });

  tearDown(() async {
    await app.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// Collection [name] with one request, linked to a repository the way a connect and
  /// a first push leave it: link row, a sync base and the uids of its entities.
  Future<int> addLinkedCollection(String name, {String sha = 'sha-1'}) async {
    final id = await app.repos.collectionRepository.createCollection(name);
    final request = await app.repos.requestRepository.createRequest(collectionId: id, name: '$name request');
    final link = await app.database.gitLinksDao.insertLink(
      GitLinksCompanion.insert(
        collectionId: id,
        provider: 'github',
        owner: 'acme',
        repo: name.toLowerCase(),
        branch: 'main',
        lastSyncedSha: Value(sha),
      ),
    );
    await app.database.gitLinksDao.replaceBase(link, [
      GitBaseEntriesCompanion.insert(
        linkId: link,
        uid: 'uid-$name',
        path: 'collection.json',
        blobSha: 'blob-$name',
        docJson: '{"uid":"uid-$name"}',
      ),
    ]);
    await app.database.entityUidsDao.put('collection', id, 'uid-$name');
    await app.database.entityUidsDao.put('request', request, 'uid-$name-request');
    return id;
  }

  /// Everything Git knows about collection [name], as the sync engine would read it.
  Future<Map<String, Object?>> gitStateOf(String name) async {
    final loaded = (await app.repos.loader.loadAll()).where((c) => c.collection.name == name).firstOrNull;
    if (loaded == null) return {'present': false};
    final link = await app.database.gitLinksDao.findByCollection(loaded.collection.id);
    return {
      'present': true,
      'link': link == null ? null : '${link.owner}/${link.repo}@${link.branch} sha=${link.lastSyncedSha}',
      'base': link == null
          ? null
          : [for (final b in await app.database.gitLinksDao.baseEntries(link.id)) '${b.uid}:${b.blobSha}'],
      'uid': await app.database.entityUidsDao.uidOf('collection', loaded.collection.id),
      'requestUid': await app.database.entityUidsDao.uidOf('request', loaded.requests.single.id),
    };
  }

  test('first run adopts data that predates workplaces instead of wiping it', () async {
    await app.repos.collectionRepository.createCollection('Legacy');

    await app.vm.init();

    expect(app.vm.errorMessage, isNull);
    expect(await app.collectionNames(), ['Legacy']);
    await app.repos.collectionRepository.createCollection('Second');
    await waitFor(() => namesInFile(app.vm.activeWorkplace!).length == 2, reason: 'autosave of both collections');
    expect(namesInFile(app.vm.activeWorkplace!), unorderedEquals(['Legacy', 'Second']));
  });

  test('each workplace keeps its own data when you switch between them', () async {
    await app.vm.init();
    final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
    await app.repos.collectionRepository.createCollection('Alpha');
    final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));

    expect(await app.collectionNames(), isEmpty, reason: 'a new workplace starts empty');
    expect(namesInFile(a), ['Alpha'], reason: 'the workplace you leave is saved first');
    await app.repos.collectionRepository.createCollection('Beta');

    await app.vm.switchWorkplace(a);

    expect(app.vm.errorMessage, isNull);
    expect(app.vm.activeWorkplace?.id, a.id);
    expect(await app.collectionNames(), ['Alpha']);
    expect(namesInFile(b), ['Beta']);
  });

  test('autosave mirrors edits, so reloading the file after a restart loses nothing', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Edited after start');
    await waitFor(() => namesInFile(app.vm.activeWorkplace!).contains('Edited after start'), reason: 'autosave');
    await app.close();

    // A fresh process: empty database, same files on disk.
    app = _App(repository);
    await app.vm.init();

    expect(app.vm.errorMessage, isNull);
    expect(await app.collectionNames(), ['Edited after start']);
  });

  test('a restart over the same database keeps row ids and the active environment', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Shop');
    final testing = await app.repos.environmentRepository.create('Testing');
    await app.repos.environmentRepository.setActive(testing);
    await waitFor(() => namesInFile(app.vm.activeWorkplace!).contains('Shop'), reason: 'autosave');
    await app.vm.saveCurrentWorkplace();
    final idsBefore = await app.collectionIds();

    app.vm = app.restartedViewModel(repository);
    await app.vm.init();

    expect(app.vm.errorMessage, isNull);
    expect(await app.activeEnvironmentName(), 'Testing', reason: 'reloading must not forget the chosen environment');
    expect(await app.collectionIds(), idsBefore, reason: 'the database was not rebuilt from the file');
  });

  test('after the database was rebuilt from the file, the next restart no longer rebuilds it', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Shop');
    await app.repos.environmentRepository.create('Testing');
    await waitFor(() => namesInFile(app.vm.activeWorkplace!).contains('Shop'), reason: 'autosave');
    await app.close();

    // A fresh database is rebuilt from the file at start...
    app = _App(repository);
    await app.vm.init();
    expect(await app.collectionNames(), ['Shop']);
    final testing = (await app.repos.environmentRepository.watchAll().first).single.id;
    await app.repos.environmentRepository.setActive(testing);
    final idsAfterRebuild = await app.collectionIds();

    // ...and that rebuild wrote its new ids back, so this restart finds them equal.
    app.vm = app.restartedViewModel(repository);
    await app.vm.init();

    expect(await app.activeEnvironmentName(), 'Testing');
    expect(await app.collectionIds(), idsAfterRebuild);
  });

  test('a file changed from outside still replaces the database at start', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Before');
    await waitFor(() => namesInFile(app.vm.activeWorkplace!).contains('Before'), reason: 'autosave');
    await app.vm.saveCurrentWorkplace();
    final workplace = app.vm.activeWorkplace!;
    final snapshot = BackupSnapshot(
      exportedAt: DateTime.utc(2026, 1, 1),
      collections: const [BackupCollection(name: 'From a git pull')],
    );
    File(p.join(workplace.folderPath, 'workspace.json')).writeAsStringSync(BackupCodec.encode(snapshot));

    app.vm = app.restartedViewModel(repository);
    await app.vm.init();

    expect(await app.collectionNames(), ['From a git pull']);
  });

  test(
    'a collection linked to Git is still linked, with its sync state, after switching workplaces and back',
    () async {
      await app.vm.init();
      final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
      await addLinkedCollection('Shop');
      final before = await gitStateOf('Shop');
      final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));

      expect(await gitStateOf('Shop'), {'present': false}, reason: "A's collection must not show up in B");
      await addLinkedCollection('Blog', sha: 'sha-blog');

      await app.vm.switchWorkplace(a);
      expect(await gitStateOf('Shop'), before);
      expect(await gitStateOf('Blog'), {'present': false});

      await app.vm.switchWorkplace(b);
      expect(await gitStateOf('Blog'), containsPair('link', 'acme/blog@main sha=sha-blog'));
      expect(await gitStateOf('Shop'), {'present': false});
    },
  );

  test('several linked collections in one workplace each keep their own link through a switch', () async {
    await app.vm.init();
    final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
    await addLinkedCollection('Shop', sha: 'sha-shop');
    await addLinkedCollection('Blog', sha: 'sha-blog');
    final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));

    await app.vm.switchWorkplace(a);

    expect((await gitStateOf('Shop'))['link'], 'acme/shop@main sha=sha-shop');
    expect((await gitStateOf('Blog'))['link'], 'acme/blog@main sha=sha-blog');
    expect((await gitStateOf('Shop'))['base'], ['uid-Shop:blob-Shop']);
    expect((await gitStateOf('Blog'))['base'], ['uid-Blog:blob-Blog']);
    expect(b.id, isNot(a.id));
  });

  test('a push or pull (the sync state changing) is mirrored to the file, so a restart finds it', () async {
    await app.vm.init();
    final collection = await addLinkedCollection('Shop');
    await waitFor(
      () => File(p.join(app.vm.activeWorkplace!.folderPath, 'workspace.json')).readAsStringSync().contains('sha-1'),
      reason: 'autosave of the link',
    );

    final link = (await app.database.gitLinksDao.findByCollection(collection))!;
    await app.database.gitLinksDao.updateLink(link.id, const GitLinksCompanion(lastSyncedSha: Value('sha-after-push')));
    await waitFor(
      () => File(
        p.join(app.vm.activeWorkplace!.folderPath, 'workspace.json'),
      ).readAsStringSync().contains('sha-after-push'),
      reason: 'autosave of the push',
    );
    await app.close();

    // A fresh database, as after the browser dropped it: the file brings the link back.
    app = _App(repository);
    await app.vm.init();

    expect((await gitStateOf('Shop'))['link'], 'acme/shop@main sha=sha-after-push');
  });

  test('a workspace file written before collections could be linked still opens', () async {
    await app.vm.init();
    final workplace = await app.vm.createWorkplace(name: 'Old', folderPath: folder('old'));
    await app.vm.switchWorkplace(app.vm.workplaces.first); // leaves 'Old' saved; its file is free to replace
    final plain = BackupSnapshot(
      exportedAt: DateTime.utc(2026, 1, 1),
      collections: const [BackupCollection(name: 'Plain')],
    );
    File(p.join(workplace.folderPath, 'workspace.json')).writeAsStringSync(BackupCodec.encode(plain));

    await app.vm.switchWorkplace(workplace);

    expect(app.vm.errorMessage, isNull);
    expect(await app.collectionNames(), ['Plain']);
  });

  test('leaving the app saves what is pending at once instead of waiting out the autosave delay', () async {
    await app.close();
    app = _App(repository, autosaveDelay: const Duration(seconds: 30)); // far longer than the test
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Typed just before closing');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(namesInFile(app.vm.activeWorkplace!), isEmpty, reason: 'the debounce has not fired yet');

    app.vm.didChangeAppLifecycleState(AppLifecycleState.paused);

    await waitFor(
      () => namesInFile(app.vm.activeWorkplace!).contains('Typed just before closing'),
      reason: 'the flush',
    );
  });

  test('coming back to the foreground does not save anything on its own', () async {
    await app.vm.init();
    final before = File(p.join(app.vm.activeWorkplace!.folderPath, 'workspace.json')).readAsStringSync();

    app.vm.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(File(p.join(app.vm.activeWorkplace!.folderPath, 'workspace.json')).readAsStringSync(), before);
  });

  test('swapping the database never autosaves the half-emptied state over a workplace file', () async {
    await app.vm.init();
    final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
    await app.repos.collectionRepository.createCollection('Alpha');
    final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));

    await app.vm.switchWorkplace(a);
    await app.vm.switchWorkplace(b);
    await Future<void>.delayed(const Duration(milliseconds: 300)); // several autosave periods

    expect(namesInFile(a), ['Alpha']);
    expect(namesInFile(b), isEmpty);
  });

  test('a damaged workspace.json aborts the switch and leaves everything as it was', () async {
    await app.vm.init();
    final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
    await app.repos.collectionRepository.createCollection('Alpha');
    final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));
    await app.vm.switchWorkplace(a);
    final damaged = File(p.join(b.folderPath, 'workspace.json'))..writeAsStringSync('{ not json');

    await app.vm.switchWorkplace(b);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(app.vm.errorMessage, contains('not a valid PostPilot workspace'));
    expect(app.vm.activeWorkplace?.id, a.id);
    expect(await app.collectionNames(), ['Alpha']);
    expect(damaged.readAsStringSync(), '{ not json', reason: 'the damaged file is not overwritten');
    expect((await repository.getActiveWorkplace())?.id, a.id);
  });

  test('deleting the open workplace loads the next one instead of leaving stale data behind', () async {
    await app.vm.init();
    final fallback = app.vm.activeWorkplace!;
    final b = await app.vm.createWorkplace(name: 'B', folderPath: folder('b'));
    await app.repos.collectionRepository.createCollection('Beta');

    await app.vm.deleteWorkplace(b.id);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(app.vm.errorMessage, isNull);
    expect(app.vm.activeWorkplace?.id, fallback.id);
    expect(await app.collectionNames(), isEmpty, reason: "B's data must not leak into the workplace that replaced it");
    expect(namesInFile(fallback), isEmpty);
    expect(namesInFile(b), ['Beta'], reason: "the deleted workplace's files stay on disk, up to date");
  });

  test("a workplace's tags and descriptions do not leak into the next workplace", () async {
    await app.vm.init();
    await app.database
        .into(app.database.entityTags)
        .insert(EntityTagsCompanion.insert(kind: 'collection', localId: 1, tag: 'stale'));
    await app.database
        .into(app.database.entityDocs)
        .insert(EntityDocsCompanion.insert(kind: 'collection', localId: 1, markdown: const Value('stale')));

    await app.vm.createWorkplace(name: 'Next', folderPath: folder('next'));

    expect(await app.database.select(app.database.entityTags).get(), isEmpty);
    expect(await app.database.select(app.database.entityDocs).get(), isEmpty);
  });

  test('a rejected new workplace reports why and keeps the current one open', () async {
    await app.vm.init();
    final a = await app.vm.createWorkplace(name: 'A', folderPath: folder('a'));
    await app.repos.collectionRepository.createCollection('Alpha');

    await expectLater(app.vm.createWorkplace(name: 'Dup', folderPath: folder('a')), throwsA(isA<WorkplaceException>()));

    expect(app.vm.errorMessage, contains('already uses this folder'));
    expect(app.vm.isBusy, isFalse);
    expect(app.vm.activeWorkplace?.id, a.id);
    expect(await app.collectionNames(), ['Alpha']);
  });

  test('adding a folder that already holds a workspace.json opens it with its collections and environments', () async {
    final existing = folder('flowpros');
    Directory(existing).createSync();
    final seed = BackupSnapshot(
      exportedAt: DateTime.utc(2026, 1, 1),
      collections: const [BackupCollection(name: 'FlowPros Mobile API')],
      environments: const [
        BackupEnvironment(name: 'Testing'),
        BackupEnvironment(name: 'Production'),
      ],
    );
    File(p.join(existing, 'workspace.json')).writeAsStringSync(BackupCodec.encode(seed));
    await app.vm.init();

    await app.vm.createWorkplace(name: 'FlowPros', folderPath: existing);

    expect(app.vm.errorMessage, isNull);
    expect(await app.collectionNames(), ['FlowPros Mobile API']);
    expect(await app.environmentNames(), ['Testing', 'Production']);
  });

  test('exposes what the platform storage can do, for the UI', () async {
    expect(app.vm.usesRealFolders, isTrue);
    expect(app.vm.fileManagerName, isNotEmpty);
    expect(
      await app.vm.getDefaultWorkplacesDirectory(workplaceName: 'Team A'),
      p.join(temp.path, 'workplaces', 'Team_A'),
    );
  });
}
