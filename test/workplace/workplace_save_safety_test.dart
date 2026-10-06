import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/git_sync/data/repositories/drift_git_state_store.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_storage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/domain/repositories/workplace_repository.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/drift_repos.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';

/// A real [FileWorkplaceStorage] whose writes of `workspace.json` can be made to fail, the way a full
/// disk, a locked OneDrive file or a browser store over its quota does. The unsaved-changes marker
/// lives elsewhere and keeps working, as it would on a full disk with a few bytes left.
final class _FlakyStorage implements WorkplaceStorage {
  final FileWorkplaceStorage inner;
  _FlakyStorage(this.inner);

  bool failWorkspaceWrites = false;

  @override
  Future<void> writeWorkspace(String folderPath, String json) async {
    if (failWorkspaceWrites) throw const WorkplaceException('the disk is full');
    await inner.writeWorkspace(folderPath, json);
  }

  @override
  bool get usesRealFolders => inner.usesRealFolders;
  @override
  bool get canPickFolder => inner.canPickFolder;
  @override
  bool get canRevealFolder => inner.canRevealFolder;
  @override
  String get fileManagerName => inner.fileManagerName;
  @override
  Future<String?> readRegistry() => inner.readRegistry();
  @override
  Future<void> writeRegistry(String json) => inner.writeRegistry(json);
  @override
  Future<String?> backupRegistry(String json) => inner.backupRegistry(json);
  @override
  Future<String?> readWorkspace(String folderPath) => inner.readWorkspace(folderPath);
  @override
  Future<String?> readLocalSecrets(String folderPath) => inner.readLocalSecrets(folderPath);
  @override
  Future<void> writeLocalSecrets(String folderPath, String json) => inner.writeLocalSecrets(folderPath, json);
  @override
  Future<bool> isDirty(String folderPath) => inner.isDirty(folderPath);
  @override
  Future<void> setDirty(String folderPath, bool dirty) => inner.setDirty(folderPath, dirty);
  @override
  Future<String> defaultWorkplacesDirectory() => inner.defaultWorkplacesDirectory();
  @override
  String? validateFolderPath(String folderPath) => inner.validateFolderPath(folderPath);
  @override
  Future<String?> pickFolder({String? initialPath}) => inner.pickFolder(initialPath: initialPath);
  @override
  Future<void> revealFolder(String folderPath) => inner.revealFolder(folderPath);
}

/// One "app run": its own database and view model over shared storage.
final class _App {
  final AppDatabase database;
  final DriftRepos repos;
  final ShellViewModel shell;
  WorkplaceViewModel vm;

  _App._(this.database, this.repos, this.shell, this.vm);

  static WorkplaceViewModel _viewModel(WorkplaceRepositoryImpl repository, AppDatabase database, DriftRepos repos, ShellViewModel shell, Duration delay) =>
      WorkplaceViewModel(
        repository: repository,
        backupService: repos.backupServiceWith(DriftGitStateStore(database)),
        database: database,
        shellViewModel: shell,
        autosaveDelay: delay,
        settleDelay: const Duration(milliseconds: 20),
      );

  factory _App(WorkplaceRepositoryImpl repository, {Duration autosaveDelay = const Duration(milliseconds: 30)}) {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(database);
    final shell = ShellViewModel(repos.requestRepository);
    return _App._(database, repos, shell, _viewModel(repository, database, repos, shell, autosaveDelay));
  }

  /// The app restarting over the same database, as on every reload of the web build.
  WorkplaceViewModel restarted(WorkplaceRepositoryImpl repository) {
    vm.dispose();
    return _viewModel(repository, database, repos, shell, const Duration(milliseconds: 30));
  }

  Future<List<String>> collectionNames() async => [for (final c in await repos.collectionRepository.watchCollections().first) c.name];

  Future<void> close() async {
    vm.dispose();
    shell.dispose();
    await database.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;
  late _FlakyStorage storage;
  late WorkplaceRepositoryImpl repository;
  late _App app;

  String folder() => app.vm.activeWorkplace!.folderPath;
  List<String> namesInFile() => [
        for (final c in BackupCodec.decode(File(p.join(folder(), 'workspace.json')).readAsStringSync()).collections) c.name,
      ];

  Future<void> waitFor(FutureOr<bool> Function() condition, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $reason');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pp_w1a_save');
    storage = _FlakyStorage(FileWorkplaceStorage(
      registryDirectory: Directory(p.join(temp.path, 'registry')),
      defaultWorkplacesDirectory: p.join(temp.path, 'workplaces'),
    ));
    repository = WorkplaceRepositoryImpl(storage: storage);
    app = _App(repository);
  });

  tearDown(() async {
    storage.failWorkspaceWrites = false;
    await app.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('a failed write of the workspace file is shown to the user, and the message goes when a save works again', () async {
    await app.vm.init();
    var notified = 0;
    app.vm.addListener(() => notified++);
    storage.failWorkspaceWrites = true;
    await app.repos.collectionRepository.createCollection('Unsaved');

    await app.vm.saveCurrentWorkplace();

    expect(app.vm.saveError, startsWith('Could not save workspace file: '));
    expect(app.vm.saveError, contains('the disk is full'));
    expect(notified, greaterThan(0), reason: 'the UI is told');

    storage.failWorkspaceWrites = false;
    await app.vm.saveCurrentWorkplace();

    expect(app.vm.saveError, isNull);
    expect(namesInFile(), ['Unsaved']);
  });

  test('autosave failures are shown too, not only the courtesy saves', () async {
    await app.vm.init();
    storage.failWorkspaceWrites = true;

    await app.repos.collectionRepository.createCollection('Edited');

    await waitFor(() => app.vm.saveError != null, 'the autosave to fail and say so');
    expect(app.vm.saveError, contains('Could not save workspace file'));
  });

  test('a file the last write never reached does not replace the newer database at the next start', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Old');
    await waitFor(() => namesInFile().contains('Old'), 'the first autosave');

    storage.failWorkspaceWrites = true; // from now on the file stays behind
    await app.repos.collectionRepository.createCollection('Newest');
    await waitFor(() => app.vm.saveError != null, 'the failed autosave');
    await waitFor(() => storage.isDirty(folder()), 'the unsaved marker');
    expect(namesInFile(), ['Old'], reason: 'the file really is behind');

    storage.failWorkspaceWrites = false; // the next run has a working disk
    app.vm = app.restarted(repository);
    await app.vm.init();

    expect(app.vm.errorMessage, isNull);
    expect(await app.collectionNames(), unorderedEquals(['Old', 'Newest']), reason: 'the database was not replaced by the older file');
    expect(namesInFile(), unorderedEquals(['Old', 'Newest']), reason: 'the file was rewritten from the database');
    await waitFor(() async => !await storage.isDirty(folder()), 'the marker to clear');
    expect(app.vm.saveError, isNull);
  });

  test('closing inside the autosave delay leaves the marker, so the typed change survives the restart', () async {
    await app.close();
    app = _App(repository, autosaveDelay: const Duration(seconds: 30));
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Old');
    await app.vm.saveCurrentWorkplace();
    expect(namesInFile(), ['Old']);

    await app.repos.collectionRepository.createCollection('Typed just before closing');
    await waitFor(() => storage.isDirty(folder()), 'the unsaved marker');
    expect(namesInFile(), ['Old'], reason: 'the debounce has not fired');

    app.vm = app.restarted(repository); // the window was closed; the database lives on
    await app.vm.init();

    expect(await app.collectionNames(), unorderedEquals(['Old', 'Typed just before closing']));
    expect(namesInFile(), unorderedEquals(['Old', 'Typed just before closing']));
    await waitFor(() async => !await storage.isDirty(folder()), 'the marker to clear');
  });

  test('after a normal save the marker is clear, so a file changed from outside still replaces the database', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Before');
    await waitFor(() => namesInFile().contains('Before'), 'autosave');
    await app.vm.saveCurrentWorkplace();
    expect(await storage.isDirty(folder()), isFalse);

    File(p.join(folder(), 'workspace.json')).writeAsStringSync(
      BackupCodec.encode(BackupSnapshot(exportedAt: DateTime.utc(2026), collections: const [BackupCollection(name: 'From a git pull')])),
    );
    app.vm = app.restarted(repository);
    await app.vm.init();

    expect(await app.collectionNames(), ['From a git pull']);
  });

  test('a marker with an empty database means the database was lost: the file is loaded, not wiped', () async {
    await app.vm.init();
    await app.repos.collectionRepository.createCollection('Precious');
    await waitFor(() => namesInFile().contains('Precious'), 'autosave');
    await app.vm.saveCurrentWorkplace();
    final workplaceFolder = folder();
    await app.close();

    await storage.setDirty(workplaceFolder, true); // left over from an earlier run
    app = _App(repository); // a fresh, empty database
    await app.vm.init();

    expect(await app.collectionNames(), ['Precious']);
    expect(namesInFile(), ['Precious']);
    await waitFor(() async => !await storage.isDirty(workplaceFolder), 'the marker to clear');
  });

  test('a repository without a marker works as before', () async {
    // The marker is optional (a test double has none): nothing here may require it.
    expect(repository, isA<WorkplaceDirtyTracking>());
    final bare = FakeWorkplaceRepository();
    expect(bare, isNot(isA<WorkplaceDirtyTracking>()));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repos = DriftRepos(database);
    final shell = ShellViewModel(repos.requestRepository);
    addTearDown(shell.dispose);
    final vm = WorkplaceViewModel(
      repository: bare,
      backupService: repos.backupServiceWith(DriftGitStateStore(database)),
      database: database,
      shellViewModel: shell,
      autosaveDelay: const Duration(milliseconds: 30),
      settleDelay: const Duration(milliseconds: 20),
    );
    addTearDown(vm.dispose);

    await vm.init();
    await repos.collectionRepository.createCollection('Plain');
    await vm.saveCurrentWorkplace();

    expect(vm.saveError, isNull);
    expect(vm.errorMessage, isNull);
  });
}
