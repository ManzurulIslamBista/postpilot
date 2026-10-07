// "Export for Flutter" opened for real: from the environments manager, with environments and variables to tick, secrets unticked,
// and the files listed with their warnings; on a desktop and on a phone screen.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/environments/presentation/widgets/environments_manager_dialog.dart';
import 'package:postpilot/features/flavor_export/presentation/flavor_export_dialog.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;

  EnvironmentVariableEntity variable(int env, String key, String value, {bool secret = false}) =>
      EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: value, isSecret: secret, enabled: true);

  setUp(() async {
    db = InMemoryDb();
    final dev = await db.environmentRepository.create('Development');
    final prod = await db.environmentRepository.create('Production');
    for (final (env, base, key) in [(dev, 'http://localhost:3000', 'dev-key'), (prod, 'https://api.example.com', 'prod-key')]) {
      await db.environmentRepository.upsertVariable(variable(env, 'baseUrl', base));
      await db.environmentRepository.upsertVariable(variable(env, 'apiUrl', '{{baseUrl}}/v1'));
      await db.environmentRepository.upsertVariable(variable(env, 'api_key', key));
    }
  });

  Future<void> launch(WidgetTester tester, {required Size size, required void Function(BuildContext) open}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final environments = EnvironmentsViewModel(db.environmentRepository, db.globalVariableRepository);
    final shell = ShellViewModel(db.requestRepository);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final workplace = WorkplaceViewModel(repository: FakeWorkplaceRepository(), backupService: db.backupService, database: database, shellViewModel: shell);
    addTearDown(() async {
      environments.dispose();
      workplace.dispose();
      await database.close();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvironmentsViewModel>.value(value: environments),
        ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: (context) => FilledButton(onPressed: () => open(context), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  testWidgets('lists the environments as flavors and the variables with secrets unticked, and previews the files', (tester) async {
    await launch(tester, size: const Size(1200, 900), open: FlavorExportDialog.show);
    expect(find.text('Export for Flutter'), findsOneWidget);
    expect(find.text('Development'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'dev'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'prod'), findsOneWidget);

    bool ticked(String key) => tester.widget<CheckboxListTile>(find.byKey(ValueKey('flavor-var-$key'))).value ?? false;
    expect(ticked('baseUrl'), isTrue);
    expect(ticked('apiUrl'), isTrue);
    expect(ticked('api_key'), isFalse, reason: 'it looks like a secret');
    expect(find.text('Looks like a secret: left out'), findsOneWidget);
    expect(find.byKey(const ValueKey('flavor-secret-warning')), findsNothing);

    // The file list: a .env and an env.json per flavor, AppConfig, launch configurations and the commands.
    for (final name in ['.env.dev', 'env.dev.json', '.env.prod', 'env.prod.json', 'app_config.dart', 'launch.json', 'flutter_run_commands.txt']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    expect(find.text('Save to folder…'), findsNothing, reason: 'the fake workplace cannot pick a folder');
    expect(find.text('Copy all'), findsOneWidget);
  });

  testWidgets('ticking a secret exports an empty placeholder and says why it is empty', (tester) async {
    await launch(tester, size: const Size(1200, 900), open: FlavorExportDialog.show);
    await tester.tap(find.byKey(const ValueKey('flavor-var-api_key')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('flavor-secret-warning')), findsOneWidget);
    expect(find.text('Real secrets must never go in here'), findsOneWidget);
    expect(find.text('Looks like a secret: exported as an empty placeholder'), findsOneWidget);
  });

  testWidgets('unticking an environment leaves one flavor, with plain file names', (tester) async {
    await launch(tester, size: const Size(1200, 900), open: FlavorExportDialog.show);
    final development = find.descendant(of: find.byKey(const ValueKey('flavor-env-1')), matching: find.byType(Checkbox));
    await tester.tap(development);
    await _settle(tester);
    expect(find.text('.env.dev'), findsNothing);
    expect(find.text('.env.prod'), findsNothing);
    expect(find.text('.env'), findsWidgets);
    expect(find.text('env.json'), findsWidgets);
  });

  testWidgets('a flavor name can be edited and the files follow', (tester) async {
    await launch(tester, size: const Size(1200, 900), open: FlavorExportDialog.show);
    await tester.enterText(find.widgetWithText(TextField, 'prod'), 'release');
    await _settle(tester);
    expect(find.text('.env.release'), findsWidgets);
    expect(find.text('env.release.json'), findsWidgets);
    expect(find.text('.env.prod'), findsNothing);
  });

  testWidgets('on a phone the choices and the files are two tabs', (tester) async {
    await launch(tester, size: const Size(420, 800), open: FlavorExportDialog.show);
    expect(find.widgetWithText(Tab, 'Choose'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Files'), findsOneWidget);
    expect(find.text('Environments and flavors'.toUpperCase()), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Files'));
    await _settle(tester);
    expect(find.text('.env.dev'), findsWidgets);
  });

  testWidgets('the environments manager has the entry, ticking the selected environment first', (tester) async {
    await launch(tester, size: const Size(1200, 900), open: EnvironmentsManagerDialog.show);
    expect(find.text('Export for Flutter…'), findsOneWidget);
    await tester.tap(find.text('Production'));
    await _settle(tester);
    await tester.tap(find.text('Export for Flutter…'));
    await _settle(tester);
    expect(find.text('Export for Flutter'), findsOneWidget);
    // Opened for Production: only that environment is ticked, so the files have plain names.
    expect(find.text('.env'), findsWidgets);
    expect(find.text('.env.dev'), findsNothing);
  });

  testWidgets('without environments it says what to do', (tester) async {
    db = InMemoryDb();
    await launch(tester, size: const Size(900, 700), open: FlavorExportDialog.show);
    expect(find.text('No environments yet'), findsOneWidget);
  });
}
