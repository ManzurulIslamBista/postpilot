import 'dart:io';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/data/repositories/collection_auth_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_variable_repository_impl.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/documentation/data/repositories/documentation_repository_impl.dart';
import 'package:postpilot/features/documentation/data/repositories/tag_repository_impl.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/environments/data/repositories/environment_repository_impl.dart';
import 'package:postpilot/features/environments/data/repositories/global_variable_repository_impl.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_scripts_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/response_example_repository_impl.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/settings/data/repositories/request_settings_repository_impl.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/in_memory_import_export_fakes.dart';

/// The real repositories over a real (in-memory SQLite) database.
final class _Repos implements RepositoryBundle {
  _Repos(AppDatabase database)
      : collectionRepository = CollectionRepositoryImpl(database.collectionsDao),
        requestRepository = RequestRepositoryImpl(database.requestsDao),
        collectionVariableRepository = CollectionVariableRepositoryImpl(database.collectionVariablesDao),
        collectionAuthRepository = CollectionAuthRepositoryImpl(database.collectionAuthDao),
        scriptsRepository = RequestScriptsRepositoryImpl(database.requestScriptsDao),
        exampleRepository = ResponseExampleRepositoryImpl(database.responseExamplesDao),
        environmentRepository = EnvironmentRepositoryImpl(database.environmentsDao),
        globalVariableRepository = GlobalVariableRepositoryImpl(database.globalVariablesDao),
        requestSettingsRepository = RequestSettingsRepositoryImpl(database.requestSettingsDao),
        documentationRepository = DocumentationRepositoryImpl(database.entityDocsDao),
        tagRepository = TagRepositoryImpl(database.entityTagsDao);

  @override
  final CollectionRepository collectionRepository;
  @override
  final RequestRepository requestRepository;
  @override
  final CollectionVariableRepository collectionVariableRepository;
  @override
  final CollectionAuthRepository collectionAuthRepository;
  @override
  final RequestScriptsRepository scriptsRepository;
  @override
  final ResponseExampleRepository exampleRepository;
  @override
  final EnvironmentRepository environmentRepository;
  @override
  final GlobalVariableRepository globalVariableRepository;
  @override
  final RequestSettingsRepository requestSettingsRepository;
  @override
  final DocumentationRepository documentationRepository;
  @override
  final TagRepository tagRepository;
}

/// One "app run": its own database and view model over shared storage.
final class _App {
  final AppDatabase database;
  final _Repos repos;
  final ShellViewModel shell;
  WorkplaceViewModel vm;

  _App._(this.database, this.repos, this.shell, this.vm);

  factory _App(WorkplaceRepositoryImpl repository) {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = _Repos(database);
    final shell = ShellViewModel(repos.requestRepository);
    final vm = WorkplaceViewModel(
      repository: repository,
      backupService: repos.backupService,
      database: database,
      shellViewModel: shell,
      autosaveDelay: const Duration(milliseconds: 30),
      settleDelay: const Duration(milliseconds: 20),
    );
    return _App._(database, repos, shell, vm);
  }

  Future<List<String>> collectionNames() async =>
      [for (final c in await repos.collectionRepository.watchCollections().first) c.name];

  Future<List<String>> environmentNames() async => [for (final e in await repos.environmentRepository.watchAll().first) e.name];

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
      backupService: repos.backupService,
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
    final snapshot = BackupSnapshot(exportedAt: DateTime.utc(2026, 1, 1), collections: const [BackupCollection(name: 'From a git pull')]);
    File(p.join(workplace.folderPath, 'workspace.json')).writeAsStringSync(BackupCodec.encode(snapshot));

    app.vm = app.restartedViewModel(repository);
    await app.vm.init();

    expect(await app.collectionNames(), ['From a git pull']);
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
    await app.database.into(app.database.entityTags).insert(EntityTagsCompanion.insert(kind: 'collection', localId: 1, tag: 'stale'));
    await app.database.into(app.database.entityDocs).insert(EntityDocsCompanion.insert(kind: 'collection', localId: 1, markdown: const Value('stale')));

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
      environments: const [BackupEnvironment(name: 'Testing'), BackupEnvironment(name: 'Production')],
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
    expect(await app.vm.getDefaultWorkplacesDirectory(workplaceName: 'Team A'), p.join(temp.path, 'workplaces', 'Team_A'));
  });
}
