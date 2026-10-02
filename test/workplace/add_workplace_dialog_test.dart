import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/core/widgets/gradient_button.dart';
import 'package:postpilot/features/workplace/domain/entities/push_preview.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/domain/services/workspace_diff.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:postpilot/features/workplace/presentation/widgets/add_workplace_dialog.dart';
import 'package:postpilot/features/workplace/presentation/widgets/workplace_sidebar_header.dart';
import 'package:provider/provider.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';

void main() {
  late AppDatabase database;
  late FakeWorkplaceRepository repository;
  late WorkplaceViewModel vm;
  late InMemoryDb memory;

  Future<void> open(WidgetTester tester, {bool desktop = true, String? gitRepoUrl}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FakeWorkplaceRepository(usesRealFolders: desktop, canPickFolder: desktop, gitRepoUrl: gitRepoUrl);
    memory = InMemoryDb();
    final shell = ShellViewModel(memory.requestRepository);
    vm = WorkplaceViewModel(
      repository: repository,
      backupService: memory.backupService,
      database: database,
      shellViewModel: shell,
    );
    addTearDown(() async {
      vm.dispose();
      shell.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<WorkplaceViewModel>.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const WorkplaceSidebarHeader(),
                  TextButton(onPressed: () => AddWorkplaceDialog.show(context), child: const Text('open dialog')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets('on desktop the folder can be browsed and the dialog explains existing workspaces', (tester) async {
    await open(tester);

    expect(find.text('Workplace Folder on PC'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);
    expect(find.textContaining('already contains one, it is opened as it is'), findsOneWidget);
  });

  testWidgets('on the web there is no folder to browse and the dialog says where it saves', (tester) async {
    await open(tester, desktop: false);

    expect(find.text('Workplace Storage (this browser)'), findsOneWidget);
    expect(find.text('Browse…'), findsNothing);
    expect(find.textContaining('saved in your browser'), findsOneWidget);
  });

  testWidgets('Browse puts the chosen folder into the field', (tester) async {
    await open(tester);

    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();

    expect(find.text('/picked/folder'), findsOneWidget);
    expect(find.text('Custom Path'), findsOneWidget);
  });

  testWidgets('Create Workplace validates the name before anything is created', (tester) async {
    await open(tester);

    await tester.tap(find.text('Create Workplace'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a workplace name'), findsOneWidget);
    expect(vm.workplaces, isEmpty);
  });

  testWidgets('a creation failure is shown as its own message, with the dialog still open', (tester) async {
    await open(tester);
    repository.createError = const WorkplaceException(
      'The workplace "A" already uses this folder. Choose a different folder.',
    );

    await tester.enterText(find.byType(TextField).first, 'New one');
    await tester.enterText(find.byType(TextField).at(1), '/some/folder');
    await tester.tap(find.text('Create Workplace'));
    await tester.pumpAndSettle();

    expect(find.text('The workplace "A" already uses this folder. Choose a different folder.'), findsOneWidget);
    expect(find.text('Add New Workplace'), findsOneWidget);
    // The button is usable again, so the user can fix the folder and retry.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create Workplace')).onPressed, isNotNull);
  });

  testWidgets('a successful creation closes the dialog and the new workplace becomes the open one', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'Fresh');
    await tester.enterText(find.byType(TextField).at(1), '/some/folder');
    await tester.tap(find.text('Create Workplace'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Workplace'), findsNothing);
    expect(vm.activeWorkplace?.name, 'Fresh');
    expect(find.text('Fresh'), findsWidgets);
  });

  testWidgets('the open workplace can be renamed from its settings dialog', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await vm.init();
    await tester.pumpAndSettle();
    expect(vm.activeWorkplace?.name, 'My Workplace');

    await tester.tap(find.text('My Workplace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workplace Settings…'));
    await tester.pumpAndSettle();
    expect(find.text('Workplace Settings'), findsOneWidget);
    expect(find.text('Folder on PC'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Workplace Settings'), findsNothing);
    expect(vm.activeWorkplace?.name, 'Renamed');
  });

  testWidgets('the settings dialog refuses an empty name instead of saving it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await vm.init();
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Workplace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workplace Settings…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '  ');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name for the workplace.'), findsOneWidget);
    expect(vm.activeWorkplace?.name, 'My Workplace');
  });

  testWidgets('connecting Git reveals the repository fields and demands a token', (tester) async {
    await open(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('Git Repository URL'), findsOneWidget);
    expect(find.text('GitHub Personal Access Token (classic)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Team');
    await tester.enterText(find.byType(TextField).at(1), '/some/folder');
    await tester.enterText(find.byType(TextField).at(2), 'https://github.com/o/r');
    await tester.tap(find.text('Create Workplace'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your GitHub classic token'), findsOneWidget);
    expect(vm.workplaces, isEmpty);
  });

  testWidgets('the settings dialog shows the Git fields of a connected workplace', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await vm.init();
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Workplace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workplace Settings…'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Repository URL'), findsOneWidget);
    expect(find.text('Branch'), findsOneWidget);
  });

  /// The open workplace is connected to a repository, ready to push or pull.
  Future<void> openGitWorkplace(WidgetTester tester) async {
    await open(tester, gitRepoUrl: 'acme/api');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await vm.init();
    await tester.pumpAndSettle();
    // Pushing now shows a preview first; by default there is something to push.
    repository.previewResult = const PushPreview(
      remoteExists: true,
      remoteChanged: false,
      changes: WorkspaceChangeSummary([WorkspaceChange(WorkspaceChangeKind.added, 'Request', 'Get pet', container: 'Pets')]),
      suggestedMessage: 'Add 1 request in Pets',
    );
  }

  Future<void> chooseFromMenu(WidgetTester tester, String item) async {
    await tester.tap(find.text('My Workplace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  /// The push preview dialog that follows "Sync with Git": it has changes to push, and Push confirms it.
  Future<void> confirmPushPreview(WidgetTester tester) async {
    expect(find.text('WHAT CHANGES IN THE REPOSITORY'), findsOneWidget);
    await tester.tap(find.widgetWithText(GradientButton, 'Push'));
    await tester.pumpAndSettle();
  }

  testWidgets('pushing is not interrupted when the workspace holds no secret values', (tester) async {
    await openGitWorkplace(tester);

    await chooseFromMenu(tester, 'Sync with Git');

    expect(find.text('Push secret values to Git?'), findsNothing);
    await confirmPushPreview(tester);
    expect(repository.syncCalls, 1);
    expect(repository.lastCommitMessage, 'Add 1 request in Pets', reason: 'the commit message is written from the changes');
    expect(repository.lastOverwrite, isFalse);
  });

  testWidgets('a repository that changed since the last sync blocks the push until overwrite is chosen', (tester) async {
    await openGitWorkplace(tester);
    repository.previewResult = const PushPreview(
      remoteExists: true,
      remoteChanged: true,
      changes: WorkspaceChangeSummary([WorkspaceChange(WorkspaceChangeKind.changed, 'Request', 'Get pet', container: 'Pets')]),
      suggestedMessage: 'Change 1 request in Pets',
    );

    await chooseFromMenu(tester, 'Sync with Git');

    expect(find.text('The repository has changes you do not have'), findsOneWidget);
    expect(tester.widget<GradientButton>(find.widgetWithText(GradientButton, 'Overwrite and push')).onPressed, isNull);
    await tester.tap(find.text('Overwrite their changes with mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GradientButton, 'Overwrite and push'));
    await tester.pumpAndSettle();

    expect(repository.syncCalls, 1);
    expect(repository.lastOverwrite, isTrue);
  });

  testWidgets('with nothing to push, the dialog says so and cannot push', (tester) async {
    await openGitWorkplace(tester);
    repository.previewResult = const PushPreview(remoteExists: true, remoteChanged: false, changes: WorkspaceChangeSummary([]), suggestedMessage: 'x');

    await chooseFromMenu(tester, 'Sync with Git');

    expect(find.text('Nothing to push'), findsOneWidget);
    expect(tester.widget<GradientButton>(find.widgetWithText(GradientButton, 'Push')).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.syncCalls, 0);
  });

  testWidgets('pushing a workspace with secret values asks first, and Cancel pushes nothing', (tester) async {
    await openGitWorkplace(tester);
    final testing = await memory.environmentRepository.create('Testing');
    await memory.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(
        id: 0,
        environmentId: testing,
        key: 'password',
        value: 'hunter2',
        isSecret: true,
        enabled: true,
      ),
    );
    await memory.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(
        id: 0,
        environmentId: testing,
        key: 'baseUrl',
        value: 'https://x',
        isSecret: false,
        enabled: true,
      ),
    );
    await memory.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: testing, key: 'apiKey', value: '', isSecret: true, enabled: true),
    );

    await chooseFromMenu(tester, 'Sync with Git');

    expect(find.text('Push secret values to Git?'), findsOneWidget);
    expect(
      find.textContaining('Testing › password'),
      findsOneWidget,
      reason: 'names the secret, never shows its value',
    );
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining('baseUrl'), findsNothing, reason: 'a plain variable is not a secret');
    expect(find.textContaining('apiKey'), findsNothing, reason: 'an empty secret leaks nothing');
    expect(find.textContaining('acme/api'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.syncCalls, 0);
  });

  testWidgets('"Push anyway" pushes after the warning', (tester) async {
    await openGitWorkplace(tester);
    final testing = await memory.environmentRepository.create('Testing');
    await memory.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(
        id: 0,
        environmentId: testing,
        key: 'token',
        value: 'abc',
        isSecret: true,
        enabled: true,
      ),
    );

    await chooseFromMenu(tester, 'Sync with Git');
    await tester.tap(find.text('Push anyway'));
    await tester.pumpAndSettle();
    await confirmPushPreview(tester);

    expect(repository.syncCalls, 1);
    expect(find.text('Synced successfully with Git repository!'), findsOneWidget);
  });

  testWidgets('pulling asks first because it replaces the workplace, and Cancel pulls nothing', (tester) async {
    await openGitWorkplace(tester);

    await chooseFromMenu(tester, 'Pull from Git');
    expect(find.text('Replace this workplace with the repository copy?'), findsOneWidget);
    expect(find.textContaining('Changes you have not pushed yet will be lost'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.pullCalls, 0);

    await chooseFromMenu(tester, 'Pull from Git');
    await tester.tap(find.text('Pull and replace'));
    await tester.pumpAndSettle();
    expect(repository.pullCalls, 1);
  });

  testWidgets('the sidebar menu offers a file-manager entry only where one exists', (tester) async {
    await open(tester, desktop: false);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No Workplace'));
    await tester.pumpAndSettle();

    expect(find.text('Add Workplace…'), findsOneWidget);
    expect(find.textContaining('Show in'), findsNothing);
  });
}
