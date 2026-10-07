// The "Flutter client" tab of Odoo Studio, and its twin in Dart Studio, opened for real against an in-process Odoo: load the
// models, search them, tick some, generate with and without the related models, switch the state layer, work offline from
// the model open in the Explorer. A layout overflow fails the test, so the phone-sized run proves the narrow layout too.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_flutter_client_tab.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'support/fake_odoo.dart';

final class _Environments implements EnvironmentRepository {
  final Map<String, String> variables;
  _Environments(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Frames and animations run, without waiting forever on a spinner that never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;
  late FakeOdoo odoo;
  late OdooStudioViewModel studio;

  OdooStudioViewModel newStudio({bool connect = true}) {
    final vm = OdooStudioViewModel(
      OdooClient(odoo),
      _Environments({'odooUrl': odoo.host, 'odooDb': odoo.db, 'odooApiKey': odoo.apiKey}),
      CreateOdooWorkspaceUseCase(db.environmentRepository, db.collectionRepository, db.requestRepository),
    );
    if (connect) vm.setConnection(url: odoo.host, database: odoo.db, apiKey: odoo.apiKey);
    return vm;
  }

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    odoo = FakeOdoo();
    studio = newStudio();
  });

  tearDown(() async {
    studio.dispose();
    await locator.reset();
  });

  Future<void> pump(WidgetTester tester, Widget Function(BuildContext) child, {required Size size, bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = ShellViewModel(db.requestRepository);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final workplace = WorkplaceViewModel(repository: FakeWorkplaceRepository(), backupService: db.backupService, database: database, shellViewModel: shell);
    addTearDown(() async {
      workplace.dispose();
      await database.close();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ShellViewModel>.value(value: shell),
        ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: Builder(builder: child)),
      ),
    ));
    await _settle(tester);
  }

  Finder row(String model) => find.byKey(ValueKey('model:$model'));

  Future<void> loadModels(WidgetTester tester) async {
    await tester.tap(find.text('Load models'));
    await _settle(tester);
  }

  for (final size in const [Size(1100, 800), Size(420, 800)]) {
    final label = '${size.width.toInt()}px';

    testWidgets('lists the server\'s models, filters them and generates a client for the ticked ones ($label)', (tester) async {
      await pump(tester, (_) => OdooFlutterClientTab(viewModel: studio), size: size);
      expect(find.text('No models loaded yet.'), findsOneWidget);
      await loadModels(tester);
      // On a phone the list is short: only its first rows are built.
      for (final model in size.width > 800 ? ['res.partner', 'res.country', 'res.partner.category', 'sale.order'] : ['res.partner']) {
        expect(row(model), findsOneWidget, reason: model);
      }

      await tester.enterText(find.byKey(const ValueKey('model-filter')), 'contact');
      await _settle(tester);
      expect(row('res.partner'), findsOneWidget, reason: 'its label is Contact');
      expect(row('res.partner.category'), findsOneWidget, reason: 'Contact Tag');
      expect(row('sale.order'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('model-filter')), 'zzz');
      await _settle(tester);
      expect(find.text('No model matches "zzz".'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('model-filter')), '');
      await _settle(tester);

      await tester.tap(row('res.partner'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('selected:res.partner')), findsOneWidget);

      await tester.ensureVisible(find.text('Generate'));
      await tester.tap(find.text('Generate'));
      await _settle(tester);
      // The res.partner model, the support files, the five core files, its repository and the README.
      expect(find.text('9 files'), findsOneWidget);
      // On a phone the file list is a short strip: only its first rows are built.
      for (final file in size.width > 800 ? ['odoo_client.dart', 'res_partner.dart', 'res_partner_repository.dart'] : ['res_partner.dart', 'odoo_json.dart']) {
        expect(find.text(file), findsOneWidget, reason: file);
      }
      expect(find.text('res_country.dart'), findsNothing, reason: 'related models are only added on request');
      expect(find.textContaining('point at 2 models that are not generated'), findsOneWidget);
    });
  }

  testWidgets('"Include related models" adds the many2one targets, and says which one the server would not describe', (tester) async {
    await pump(tester, (_) => OdooFlutterClientTab(viewModel: studio), size: const Size(1100, 800));
    await loadModels(tester);
    await tester.tap(row('res.partner'));
    await tester.tap(find.text('Include related models'));
    await _settle(tester);
    await tester.tap(find.text('Generate'));
    await _settle(tester);
    expect(find.text('res_country.dart'), findsOneWidget, reason: 'country_id points at res.country');
    // res.users is not known to the fake server: it is left out with a note, the rest is generated.
    expect(find.textContaining('The related model res.users was not generated'), findsOneWidget);
    expect(find.text('res_partner.dart'), findsOneWidget);
  });

  testWidgets('the state layer and the model style are chosen before generating', (tester) async {
    await pump(tester, (_) => OdooFlutterClientTab(viewModel: studio), size: const Size(1100, 800));
    await loadModels(tester);
    await tester.tap(row('res.partner'));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('state-layer')), matching: find.text('Riverpod')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('model-style')), matching: find.text('freezed')));
    await _settle(tester);
    await tester.tap(find.text('Generate'));
    await _settle(tester);
    expect(find.text('res_partner_providers.dart'), findsOneWidget);
    expect(find.text('odoo_providers.dart'), findsOneWidget);
    expect(find.textContaining('`dart pub add flutter_riverpod`'), findsOneWidget);
    expect(find.textContaining('dart run build_runner build'), findsOneWidget, reason: 'freezed needs build_runner');
  });

  testWidgets('generating with nothing ticked says what to do', (tester) async {
    await pump(tester, (_) => OdooFlutterClientTab(viewModel: studio), size: const Size(1100, 800));
    await tester.tap(find.text('Generate'));
    await _settle(tester);
    expect(find.textContaining('Tick at least one model first'), findsOneWidget);
    expect(find.text('odoo_client.dart'), findsNothing);
  });

  testWidgets('the model open in the Explorer works without a connection', (tester) async {
    final offline = newStudio(connect: false);
    addTearDown(offline.dispose);
    expect(offline.useFieldsJson('x.thing', jsonEncode(countryFields)), isTrue);
    await pump(tester, (_) => OdooFlutterClientTab(viewModel: offline), size: const Size(1100, 800));
    await tester.tap(find.text('Add the explored model (x.thing)'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('selected:x.thing')), findsOneWidget);
    await tester.tap(find.text('Generate'));
    await _settle(tester);
    expect(find.text('x_thing.dart'), findsOneWidget);
    expect(find.text('x_thing_repository.dart'), findsOneWidget);
  });

  testWidgets('a model the server cannot describe is an error that names it, and nothing is generated', (tester) async {
    await pump(tester, (_) => OdooFlutterClientTab(viewModel: studio), size: const Size(1100, 800));
    await loadModels(tester);
    await tester.tap(row('sale.order'));
    await tester.tap(find.text('Generate'));
    await _settle(tester);
    expect(find.textContaining('sale.order:'), findsWidgets);
    expect(find.text('odoo_client.dart'), findsNothing);
  });

  testWidgets('Dart Studio has the same generator in an "Odoo client" tab', (tester) async {
    locator.registerFactory<OdooStudioViewModel>(newStudio);
    await pump(
      tester,
      (context) => Center(child: FilledButton(onPressed: () => DartStudioDialog.show(context, initialTab: 3), child: const Text('open'))),
      size: const Size(1200, 900),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Odoo client'), findsWidgets);
    expect(find.text('Open Odoo Studio'), findsOneWidget);
    expect(find.textContaining('from the active environment'), findsOneWidget);
    expect(find.text('Load models'), findsOneWidget);
    await tester.tap(find.text('Load models'));
    await _settle(tester);
    expect(row('res.partner'), findsOneWidget);
  });
}
