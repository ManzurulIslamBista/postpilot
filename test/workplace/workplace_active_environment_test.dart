import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
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
import 'package:postpilot/features/workplace/data/storage/workplace_token_store.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';

final class _Tokens implements WorkplaceTokenStore {
  @override
  Future<String?> read(String workplaceId) async => null;
  @override
  Future<void> write(String workplaceId, String token) async {}
  @override
  Future<void> delete(String workplaceId) async {}
}

/// GitHub holding one file for o/r: `GET` returns it (404 while there is none), `PUT` replaces it.
final class _GitHub implements HttpClientAdapter {
  String? text;
  int version = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    ResponseBody json(int status, Object body) =>
        ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    final path = o.uri.path;
    if (path == '/repos/o/r') return json(200, {'default_branch': 'main'});
    if (path.startsWith('/repos/o/r/branches/')) return json(200, {});
    if (path == '/repos/o/r/contents/workspace.json') {
      if (o.method == 'GET') {
        if (text == null) return json(404, {'message': 'Not Found'});
        return json(200, {'content': base64Encode(utf8.encode(text!)), 'encoding': 'base64', 'sha': 'sha$version'});
      }
      text = utf8.decode(base64Decode((o.data as Map)['content'] as String));
      return json(200, {'content': {'sha': 'sha${++version}'}});
    }
    return json(500, {'message': 'unexpected ${o.method} $path'});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;
  late _GitHub github;
  late WorkplaceRepositoryImpl repository;
  late AppDatabase database;
  late DriftRepos repos;
  late ShellViewModel shell;
  late WorkplaceViewModel vm;

  WorkplaceViewModel newViewModel() => WorkplaceViewModel(
        repository: repository,
        backupService: repos.backupServiceWith(DriftGitStateStore(database)),
        database: database,
        shellViewModel: shell,
        autosaveDelay: const Duration(milliseconds: 30),
        settleDelay: const Duration(milliseconds: 20),
      );

  Future<String?> activeEnvironment() async => (await repos.environmentRepository.watchActive().first)?.name;

  /// An environment called [name], made active.
  Future<void> activate(String name) async {
    final id = await repos.environmentRepository.create(name);
    await repos.environmentRepository.setActive(id);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pp_w1a_env');
    github = _GitHub();
    repository = WorkplaceRepositoryImpl(
      dio: Dio()..httpClientAdapter = github,
      tokens: _Tokens(),
      storage: FileWorkplaceStorage(
        registryDirectory: Directory(p.join(temp.path, 'registry')),
        defaultWorkplacesDirectory: p.join(temp.path, 'workplaces'),
      ),
    );
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    shell = ShellViewModel(repos.requestRepository);
    vm = newViewModel();
  });

  tearDown(() async {
    await vm.saveCurrentWorkplace();
    vm.dispose();
    shell.dispose();
    await database.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('switching to another workplace and back keeps the environment that was active, per workplace', () async {
    await vm.init();
    final a = await vm.createWorkplace(name: 'A', folderPath: p.join(temp.path, 'a'));
    await activate('Testing');
    final b = await vm.createWorkplace(name: 'B', folderPath: p.join(temp.path, 'b'));
    expect(await activeEnvironment(), isNull, reason: 'B is empty');
    await activate('Prod');

    await vm.switchWorkplace(a);
    expect(await activeEnvironment(), 'Testing');

    await vm.switchWorkplace(b);
    expect(await activeEnvironment(), 'Prod');

    await vm.switchWorkplace(a);
    expect(await activeEnvironment(), 'Testing');
    expect(vm.errorMessage, isNull);
  });

  test('a workplace with no active environment still has none after a switch', () async {
    await vm.init();
    final a = await vm.createWorkplace(name: 'A', folderPath: p.join(temp.path, 'a'));
    await repos.environmentRepository.create('Testing'); // exists, but not selected
    final b = await vm.createWorkplace(name: 'B', folderPath: p.join(temp.path, 'b'));
    await activate('Prod');

    await vm.switchWorkplace(a);

    expect(await activeEnvironment(), isNull);
    await vm.switchWorkplace(b);
    expect(await activeEnvironment(), 'Prod');
  });

  test('the choice is saved with the workplace on this device, never in the shared workspace.json', () async {
    await vm.init();
    final a = await vm.createWorkplace(name: 'A', folderPath: p.join(temp.path, 'a'));
    await activate('Testing');
    await vm.saveCurrentWorkplace();

    final stored = (await repository.getWorkplaces()).firstWhere((w) => w.id == a.id);
    expect(stored.activeEnvironment, 'Testing');
    final file = jsonDecode(File(p.join(a.folderPath, 'workspace.json')).readAsStringSync()) as Map<String, dynamic>;
    expect((file['workplace'] as Map)['activeEnvironment'], isNull);
    expect(((file['environments'] as List).single as Map)['name'], 'Testing', reason: 'the environment itself is shared');
  });

  test('a database rebuilt from the file at start selects the environment again', () async {
    await vm.init();
    await repos.collectionRepository.createCollection('Shop');
    await activate('Testing');
    await vm.saveCurrentWorkplace();
    vm.dispose();
    await database.close();

    // A fresh database, as after the browser dropped it: the file brings everything back but the selection.
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    vm = newViewModel();
    await vm.init();

    expect(vm.errorMessage, isNull);
    expect(await activeEnvironment(), 'Testing');
  });

  test('a pull keeps the environment selected', () async {
    await vm.init();
    final workplace = await vm.createWorkplace(
      name: 'G',
      folderPath: p.join(temp.path, 'g'),
      gitRepoUrl: 'o/r',
      gitBranch: 'main',
      gitToken: 'ghp_x',
    );
    await activate('Testing');
    await vm.saveCurrentWorkplace();
    // A teammate pushed: the repository's file has the environment and a collection of theirs.
    github.text = BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: const [BackupEnvironment(name: 'Testing')],
      collections: const [BackupCollection(name: 'Theirs')],
    ));
    github.version++;

    await vm.pullFromGit();

    expect(vm.errorMessage, isNull);
    expect([for (final c in await repos.collectionRepository.watchCollections().first) c.name], ['Theirs']);
    expect(await activeEnvironment(), 'Testing');
    expect(vm.activeWorkplace?.id, workplace.id);
  });
}
