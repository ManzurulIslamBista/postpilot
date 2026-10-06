import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_storage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:postpilot/features/workplace/presentation/widgets/workplace_sidebar_header.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';

/// A real [FileWorkplaceStorage] whose `workspace.json` writes can be made to fail.
final class _FlakyStorage implements WorkplaceStorage {
  final FileWorkplaceStorage inner;
  _FlakyStorage(this.inner);

  bool failWrites = false;

  @override
  Future<void> writeWorkspace(String folderPath, String json) async {
    if (failWrites) throw const WorkplaceException('the disk is full');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the sidebar shows why the workspace file could not be saved, and drops the message once it can be', timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('pp_w1a_banner');
    final storage = _FlakyStorage(FileWorkplaceStorage(
      registryDirectory: Directory(p.join(temp.path, 'registry')),
      defaultWorkplacesDirectory: p.join(temp.path, 'workplaces'),
    ));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final memory = InMemoryDb();
    final shell = ShellViewModel(memory.requestRepository);
    final vm = WorkplaceViewModel(
      repository: WorkplaceRepositoryImpl(storage: storage),
      backupService: memory.backupService,
      database: database,
      shellViewModel: shell,
    );
    addTearDown(() async {
      vm.dispose();
      shell.dispose();
      // The database was used under real async (runAsync), so it has to be closed there too.
      await tester.runAsync(database.close);
      temp.deleteSync(recursive: true);
    });

    await tester.runAsync(vm.init);
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkplaceViewModel>.value(
        value: vm,
        child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: WorkplaceSidebarHeader())),
      ),
    );
    expect(find.textContaining('Could not save workspace file'), findsNothing);

    storage.failWrites = true;
    await tester.runAsync(vm.saveCurrentWorkplace);
    await tester.pump();

    expect(find.text('Could not save workspace file: the disk is full'), findsOneWidget);

    storage.failWrites = false;
    await tester.runAsync(vm.saveCurrentWorkplace);
    await tester.pump();

    expect(find.textContaining('Could not save workspace file'), findsNothing);
  });
}
