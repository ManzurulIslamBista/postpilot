import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/git_sync/data/repositories/drift_git_state_store.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;
  late AppDatabase database;
  late DriftRepos repos;
  late ShellViewModel shell;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pp_w1a_warn');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    shell = ShellViewModel(repos.requestRepository);

    // A request with a credential in a header the split knows, one it does not, and a secret variable.
    final collection = await repos.collectionRepository.createCollection('Pets');
    final id = await repos.requestRepository.createRequest(collectionId: collection, name: 'Login');
    final request = (await repos.requestRepository.findById(id))!;
    await repos.requestRepository.saveRequest(request.copyWith(
      url: 'https://api.test/login',
      headers: [
        KeyValueItem(key: 'Authorization', value: 'Bearer abc'),
        KeyValueItem(key: 'X-Custom', value: _jwt),
        KeyValueItem(key: 'Accept', value: 'application/json'),
      ],
      auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'bearer-abc'),
    ));
    final env = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: env, key: 'token', value: 'tok-1', isSecret: true, enabled: true),
    );
  });

  tearDown(() async {
    shell.dispose();
    await database.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  WorkplaceViewModel viewModel({required bool keepLocal}) {
    final vm = WorkplaceViewModel(
      repository: WorkplaceRepositoryImpl(
        storage: FileWorkplaceStorage(
          registryDirectory: Directory(p.join(temp.path, 'registry')),
          defaultWorkplacesDirectory: p.join(temp.path, 'workplaces'),
        ),
        keepSecretsLocal: () => keepLocal,
      ),
      backupService: repos.backupServiceWith(DriftGitStateStore(database)),
      database: database,
      shellViewModel: shell,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test('with secrets kept local, the push warning is only about what the split could not take out', () async {
    final warned = await viewModel(keepLocal: true).secretsInWorkspace();

    expect(warned, ['Pets › Login › X-Custom header']);
  });

  test('without it, every secret is named, the unrecognised one included', () async {
    final warned = await viewModel(keepLocal: false).secretsInWorkspace();

    expect(
      warned,
      unorderedEquals([
        'Dev › token',
        'Pets › Login › Authorization header',
        'Pets › Login › auth bearerToken',
        'Pets › Login › X-Custom header',
      ]),
    );
  });
}
