import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/git_sync/data/repositories/drift_git_state_store.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/domain/entities/storage_usage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/repositories/workplace_repository.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';

/// Only what `WorkplaceViewModel.init` reads, plus the budget the web storage reports.
final class _CappedRepository implements WorkplaceRepository, WorkplaceStorageBudget {
  _CappedRepository(this.usage);

  StorageUsage? usage;
  int measured = 0;
  final workplace = WorkplaceEntity(
    id: 'w1',
    name: 'Mine',
    folderPath: 'PostPilot/Mine',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<List<WorkplaceEntity>> getWorkplaces() async => [workplace];

  @override
  Future<WorkplaceEntity?> getActiveWorkplace() async => workplace;

  @override
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace) async => WorkplaceContent.empty(workplace);

  @override
  Future<StorageUsage?> storageUsage(WorkplaceEntity workplace) async {
    measured++;
    return usage;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const cap = 4 * 1024 * 1024;

  Future<(WorkplaceViewModel, Future<void> Function())> start(_CappedRepository repository) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(database);
    final shell = ShellViewModel(repos.requestRepository);
    final vm = WorkplaceViewModel(
      repository: repository,
      backupService: repos.backupServiceWith(DriftGitStateStore(database)),
      database: database,
      shellViewModel: shell,
      autosaveDelay: const Duration(days: 1),
      settleDelay: const Duration(milliseconds: 5),
    );
    await vm.init();
    return (
      vm,
      () async {
        vm.dispose();
        shell.dispose();
        await database.close();
      },
    );
  }

  test('a workspace file at 3.4 MB of the 4 MB cap is reported as a warning once the workplace is open', () async {
    final repository = _CappedRepository(const StorageUsage(usedBytes: 3565158, limitBytes: cap));
    final (vm, close) = await start(repository);
    addTearDown(close);

    expect(vm.storageWarning, isNotNull);
    expect(vm.storageWarning!.label, '3.4 MB of 4 MB');
  });

  test('a small workspace file gives no warning', () async {
    final repository = _CappedRepository(const StorageUsage(usedBytes: 200 * 1024, limitBytes: cap));
    final (vm, close) = await start(repository);
    addTearDown(close);

    expect(repository.measured, greaterThan(0), reason: 'it was measured');
    expect(vm.storageWarning, isNull);
  });

  test('a store without a cap (a real folder) gives no warning', () async {
    final (vm, close) = await start(_CappedRepository(null));
    addTearDown(close);

    expect(vm.storageWarning, isNull);
  });
}
