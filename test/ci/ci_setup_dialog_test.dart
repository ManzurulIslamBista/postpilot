// The "Set up CI" dialog opened for real, in a light and a dark theme on a desktop and a phone screen. Flutter turns a
// layout overflow into a test failure, so this proves the dialog is usable, and the flows (preview, secrets, schedule,
// production warning, save and the replace confirmation) are driven through the widgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/ci/data/ci_workflow_writer.dart';
import 'package:postpilot/features/ci/domain/entities/ci_options.dart';
import 'package:postpilot/features/ci/presentation/ci_setup_dialog.dart';
import 'package:postpilot/features/ci/presentation/ci_setup_view_model.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import '../support/in_memory_import_export_fakes.dart';

final class _Writer implements CiWorkflowWriter {
  _Writer({this.root = '/work/repo', this.results = const [WorkflowSaved('.github/workflows/postpilot.yml')]});

  final String? root;
  final List<WorkflowSaveResult> results;
  final saves = <bool>[];

  @override
  bool get canWrite => true;

  @override
  Future<String?> findRepositoryRoot(String folderPath) async => root;

  @override
  String workspacePathIn(String repositoryRoot, String workspaceFolder) => 'api/workspace.json';

  @override
  Future<bool> workspaceFileExists(String workspaceFolder) async => true;

  @override
  Future<WorkflowSaveResult> save(String repositoryRoot, String yaml, {bool overwrite = false}) async {
    saves.add(overwrite);
    return results[(saves.length - 1).clamp(0, results.length - 1)];
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  late InMemoryDb db;
  late int stagingId;

  setUp(() async {
    db = InMemoryDb();
    final collection = await db.collectionRepository.createCollection('Shop');
    expect(collection, isPositive);
    final staging = stagingId = await db.environmentRepository.create('Staging');
    db.environments[0] = EnvironmentEntity(id: staging, name: 'Staging', isActive: true);
    final production = await db.environmentRepository.create('Production');
    EnvironmentVariableEntity variable(int env, String key, {bool secret = false, bool enabled = true}) =>
        EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: secret ? '' : 'x', isSecret: secret, enabled: enabled);
    await db.environmentRepository.upsertVariable(variable(staging, 'baseUrl'));
    await db.environmentRepository.upsertVariable(variable(staging, 'odooApiKey', secret: true));
    await db.environmentRepository.upsertVariable(variable(staging, 'db.password', secret: true));
    await db.environmentRepository.upsertVariable(variable(staging, 'oldKey', secret: true, enabled: false));
    await db.environmentRepository.upsertVariable(variable(production, 'prodKey', secret: true));
    await db.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'sharedToken', value: '', isSecret: true, enabled: true));
  });

  CiSetupViewModel makeVm(_Writer writer, {String? folder = '/work/repo/api'}) => CiSetupViewModel(
        environments: db.environmentRepository,
        globals: db.globalVariableRepository,
        collections: db.collectionRepository,
        writer: writer,
        project: CiProject(folderPath: folder, name: 'API'),
      );

  Future<void> launch(WidgetTester tester, CiSetupViewModel vm, {required Size size, required bool dark, String? collection}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => CiSetupDialog(viewModel: vm, collectionName: collection)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _settle(tester);
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('shows the workflow, then the GitLab job and the script ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark, collection: 'Shop');
        expect(find.text('Set up CI'), findsOneWidget);
        // The active environment, the collection the dialog was opened from and the repository's path are preselected.
        expect(vm.options.environment, 'Staging');
        expect(vm.options.collection, 'Shop');
        expect(vm.options.workspacePath, 'api/workspace.json');
        expect(find.textContaining('name: PostPilot API tests'), findsOneWidget);
        expect(find.textContaining('--env Staging'), findsOneWidget);
        expect(find.textContaining('--collection Shop'), findsOneWidget);
        expect(find.textContaining('api/workspace.json'), findsWidgets);

        await tapText(tester, 'GitLab CI');
        expect(find.textContaining('postpilot-api-tests:'), findsOneWidget);
        await tapText(tester, 'Shell script');
        expect(find.textContaining('#!/usr/bin/env bash'), findsOneWidget);
      });

      testWidgets('lists the secrets to create by name: enabled secrets of the environment and the globals ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark);
        expect([for (final s in vm.options.secrets) s.secretName], ['ODOO_API_KEY', 'DB_PASSWORD', 'SHARED_TOKEN']);
        expect(find.text('ODOO_API_KEY'), findsWidgets);
        expect(find.text('DB_PASSWORD'), findsWidgets);
        expect(find.text('SHARED_TOKEN'), findsWidgets);
        // The disabled variable and the other environment's secret are not asked for.
        expect(find.textContaining('OLD_KEY'), findsNothing);
        expect(find.textContaining('PROD_KEY'), findsNothing);
        expect(find.textContaining('POSTPILOT_VAR_odooApiKey: \${{ secrets.ODOO_API_KEY }}'), findsOneWidget);
      });

      testWidgets('switching the environment changes the secrets ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark);
        vm.setEnvironment('Production');
        await _settle(tester);
        expect([for (final s in vm.options.secrets) s.secretName], ['PROD_KEY', 'SHARED_TOKEN']);
        // Production looks like production: the lock stays on and the dialog says what that means.
        expect(find.textContaining('This environment looks like production'), findsOneWidget);
      });

      testWidgets('a custom cron is checked as it is typed and the file waits for a valid one ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark);
        await tester.ensureVisible(find.text('No schedule'));
        await tester.tap(find.text('No schedule'));
        await _settle(tester);
        await tester.tap(find.text('Custom cron…').last);
        await _settle(tester);
        final cron = find.widgetWithText(TextField, 'Cron expression (UTC)');
        await tester.ensureVisible(cron);
        await tester.enterText(cron, '* * * * *');
        await _settle(tester);
        expect(find.textContaining('every 1 minute'), findsWidgets);
        expect(find.text('Fix this to see the file'), findsOneWidget);
        await tester.enterText(cron, '*/15 8-18 * * 1-5');
        await _settle(tester);
        expect(find.text('Fix this to see the file'), findsNothing);
        expect(find.textContaining("- cron: '*/15 8-18 * * 1-5'"), findsOneWidget);
      });

      testWidgets('allowing production shows a red warning and writes the flag ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark);
        expect(find.textContaining('--allow-production'), findsNothing);
        await tapText(tester, 'Allow production');
        expect(find.text('Production can be changed by every run'), findsOneWidget);
        expect(find.textContaining('--allow-production'), findsWidgets);
        expect(vm.options.allowProduction, isTrue);
      });

      testWidgets('an issue needs a schedule ($label)', (tester) async {
        final vm = makeVm(_Writer());
        await launch(tester, vm, size: size, dark: dark);
        expect(find.text('Choose a schedule first.'), findsOneWidget);
        vm.setSchedule(CiSchedulePreset.daily);
        await _settle(tester);
        expect(find.text('Choose a schedule first.'), findsNothing);
        await tapText(tester, 'Open a GitHub issue when a scheduled run fails');
        expect(vm.options.openIssueOnFailure, isTrue);
        expect(find.textContaining('Open or update an issue'), findsOneWidget);
      });

      testWidgets('saving writes the workflow and says what to do next ($label)', (tester) async {
        final writer = _Writer();
        final vm = makeVm(writer);
        await launch(tester, vm, size: size, dark: dark);
        await tester.tap(find.text('Save to .github/workflows/'));
        await _settle(tester);
        expect(writer.saves, [false]);
        expect(find.textContaining('Saved .github/workflows/postpilot.yml'), findsOneWidget);
        expect(find.textContaining('Commit and push it'), findsOneWidget);
      });

      testWidgets('a different file is only replaced after the person confirms ($label)', (tester) async {
        final writer = _Writer(results: const [WorkflowNeedsConfirmation('.github/workflows/postpilot.yml'), WorkflowSaved('.github/workflows/postpilot.yml', replaced: true)]);
        final vm = makeVm(writer);
        await launch(tester, vm, size: size, dark: dark);

        // Cancel: nothing is replaced.
        await tester.tap(find.text('Save to .github/workflows/'));
        await _settle(tester);
        expect(find.text('Replace the existing workflow?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await _settle(tester);
        expect(writer.saves, [false]);

        // Confirm: saved again, this time allowed to overwrite.
        await tester.tap(find.text('Save to .github/workflows/'));
        await _settle(tester);
        await tester.tap(find.text('Replace it'));
        await _settle(tester);
        expect(writer.saves, [false, false, true]);
        expect(find.textContaining('Replaced .github/workflows/postpilot.yml'), findsOneWidget);
      });
    }
  }

  testWidgets('outside a Git repository the file can only be copied, and the dialog says why', (tester) async {
    final writer = _Writer(root: null);
    final vm = makeVm(writer);
    await launch(tester, vm, size: const Size(1200, 900), dark: false);
    expect(find.textContaining('not inside a Git repository'), findsWidgets);
    expect(vm.canSaveToRepository, isFalse);
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save to .github/workflows/'));
    expect(save.onPressed, isNull);
    // The workflow is still there to copy.
    expect(find.textContaining('name: PostPilot API tests'), findsOneWidget);
  });

  testWidgets('the shell script and the GitLab job have no Save button, only Copy', (tester) async {
    final vm = makeVm(_Writer());
    await launch(tester, vm, size: const Size(1200, 900), dark: false);
    await tapText(tester, 'GitLab CI');
    expect(find.text('Save to .github/workflows/'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('the dialog never shows a secret value, only names', (tester) async {
    // The variables have a value set in the store; none of them may reach the screen.
    await db.environmentRepository.upsertVariable(EnvironmentVariableEntity(
      id: 0,
      environmentId: stagingId,
      key: 'liveKey',
      value: 'fake_secret_ThisMustNeverAppear1234567890',
      isSecret: true,
      enabled: true,
    ));
    final vm = makeVm(_Writer());
    await launch(tester, vm, size: const Size(1200, 900), dark: false);
    expect(find.textContaining('ThisMustNeverAppear'), findsNothing);
    for (final target in CiTarget.values) {
      vm.setTarget(target);
      await _settle(tester);
      expect(vm.text, isNot(contains('ThisMustNeverAppear')));
    }
  });
}
