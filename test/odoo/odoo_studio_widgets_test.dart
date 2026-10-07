// The Payload and Check tabs, the Connect tab with both APIs, and the buttons of the request body, opened for real in a
// light and a dark theme on a desktop and a phone screen. A layout overflow, an unbounded height or a missing provider
// fails the test, so this is what proves the tabs are usable, not just compiled.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/code_block.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_check_tab.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_connect_tab.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_payload_tab.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_request_tools.dart';
import 'package:provider/provider.dart';
import '../support/drift_repos.dart';
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
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _byLabel(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
Finder _byHint(String hint) => find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith(hint));
Finder _text(String text) => find.textContaining(text, skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftRepos repos;
  late FakeOdoo odoo;
  late OdooStudioViewModel studio;
  late CollectionsViewModel collections;
  late EnvironmentsViewModel environments;

  OdooStudioViewModel newStudio({bool connect = true}) {
    final vm = OdooStudioViewModel(
      OdooClient(odoo),
      _Environments({'odooUrl': odoo.host, 'odooDb': odoo.db, 'odooApiKey': odoo.apiKey}),
      CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository),
    );
    if (connect) vm.setConnection(url: odoo.host, database: odoo.db, apiKey: odoo.apiKey);
    return vm;
  }

  setUp(() async {
    await locator.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    await repos.collectionRepository.createCollection('Odoo');
    odoo = FakeOdoo();
    studio = newStudio();
    collections = CollectionsViewModel(repos.collectionRepository, repos.requestRepository);
    environments = EnvironmentsViewModel(repos.environmentRepository, repos.globalVariableRepository);
  });

  tearDown(() async {
    studio.dispose();
    collections.dispose();
    environments.dispose();
    await locator.reset();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Widget child, {required Size size, required bool dark}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
        ChangeNotifierProvider<EnvironmentsViewModel>.value(value: environments),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: child),
      ),
    ));
    // The collections come from a database stream, which needs real time to deliver.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await _settle(tester);
  }

  /// On a phone the Payload tab shows the form or the body, one at a time.
  Future<void> openBody(WidgetTester tester) async {
    final segment = find.text('Body');
    if (segment.evaluate().isEmpty) return;
    await tester.tap(segment);
    await _settle(tester);
  }

  Future<void> openFields(WidgetTester tester) async {
    final segment = find.text('Fields');
    if (segment.evaluate().isEmpty) return;
    await tester.tap(segment);
    await _settle(tester);
  }

  Future<void> readModel(WidgetTester tester) async {
    await tester.enterText(_byLabel('Model'), 'res.partner');
    await tester.tap(find.text('Read fields'));
    await _settle(tester);
  }

  /// Narrows the list to one field, so it is on screen whatever the size of the window.
  Future<void> only(WidgetTester tester, String field) async {
    await tester.enterText(_byHint('Filter'), field);
    await _settle(tester);
  }

  Finder row(String field) => find.byKey(ValueKey('res.partner|$field'));
  Finder inRow(String field, Finder what) => find.descendant(of: row(field), matching: what);
  String body(WidgetTester tester) => tester.widget<CodeBlock>(find.byType(CodeBlock, skipOffstage: false).first).text;
  Map<String, dynamic> firstVals(WidgetTester tester) =>
      (jsonDecode(body(tester).replaceAll(RegExp(r'\{\{[^{}]+\}\}'), '0'))['vals_list'] as List).first as Map<String, dynamic>;

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      group('the Payload tab ($label)', () {
        testWidgets('is an invitation before a model is read', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          expect(find.text('Build a create or write payload'), findsOneWidget);
          expect(find.text('Read fields'), findsOneWidget);
        });

        testWidgets('reads a model, marks the required field, and builds the body as values are typed', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          expect(row('name'), findsOneWidget);
          expect(find.text(' *'), findsWidgets, reason: 'the required name is marked');
          expect(firstVals(tester), {'active': true, 'type': 'contact', 'is_company': false, 'color': 0});
          expect(_text('Required and not set: name'), findsOneWidget);

          await tester.enterText(inRow('name', find.byType(TextField)), 'Acme');
          await tester.pump();
          expect(firstVals(tester)['name'], 'Acme');
          expect(_text('Required and not set'), findsNothing);

          await only(tester, 'color');
          await tester.enterText(inRow('color', find.byType(TextField)), 'abc');
          await tester.pump();
          expect(find.text('Enter a whole number.'), findsOneWidget);
          expect(firstVals(tester).containsKey('color'), isFalse);
        });

        testWidgets('Odoo\'s own fields and the read-only ones are not offered until asked for', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          await only(tester, 'write_date');
          expect(row('write_date'), findsNothing);
          await only(tester, 'complete_name');
          expect(row('complete_name'), findsNothing);
          await tester.tap(find.text('Show read-only'));
          await _settle(tester);
          expect(row('complete_name'), findsOneWidget);
        });

        testWidgets('a switch sets a boolean and a dropdown a selection', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          await only(tester, 'is_company');
          await tester.tap(inRow('is_company', find.byType(Switch)));
          await tester.pump();
          expect(firstVals(tester)['is_company'], true);

          await only(tester, 'type');
          await tester.tap(inRow('type', find.byType(DropdownButtonFormField<String>)));
          await _settle(tester);
          await tester.tap(find.text('invoice — Invoice Address').last);
          await _settle(tester);
          expect(firstVals(tester)['type'], 'invoice');
        });

        testWidgets('a command dialog builds an x2many command, shown as a readable row', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);
          await only(tester, 'category_id');

          await tester.tap(find.text('Add command'));
          await _settle(tester);
          expect(find.text('Add a command for category_id'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Add'));
          await tester.pump();
          expect(find.text('Enter the id of the record to link.'), findsOneWidget);
          expect(find.text('Add a command for category_id'), findsOneWidget, reason: 'the dialog stays open until the command is complete');

          await tester.enterText(_byLabel('Record id'), '1');
          await tester.tap(find.widgetWithText(FilledButton, 'Add'));
          await _settle(tester);
          expect(firstVals(tester)['category_id'], [
            [4, 1],
          ]);
          expect(find.text('Link record 1'), findsOneWidget);

          await tester.tap(find.byTooltip('Remove'));
          await tester.pump();
          expect(firstVals(tester).containsKey('category_id'), isFalse);
        });

        testWidgets('loads a record, and the boxes and the body show its values', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          await tester.tap(find.text('Load from record'));
          await _settle(tester);
          await tester.enterText(_byLabel('Record id'), '2');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Load'));
          await _settle(tester);

          expect(find.widgetWithText(TextField, 'Azure Interior'), findsWidgets);
          expect(_text('Loaded record 2 of res.partner'), findsOneWidget);
          final vals = firstVals(tester);
          expect(vals['name'], 'Azure Interior');
          expect(vals['country_id'], 233);
          expect(vals['child_ids'], [
            [6, 0, [4]],
          ]);
        });

        testWidgets('write asks for the ids, and until they are typed uses the variable that stays undefined', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          await tester.tap(find.text('write'));
          await _settle(tester);
          expect(_byLabel('Records to write (ids)'), findsOneWidget);
          expect(body(tester), contains('"ids": [{{recordId}}]'));

          await tester.enterText(_byLabel('Records to write (ids)'), '7');
          await tester.pump();
          expect(jsonDecode(body(tester))['ids'], [7]);
        });

        testWidgets('Check lists what is wrong, and Create request saves the body into the collection', (tester) async {
          await pump(tester, OdooPayloadTab(viewModel: studio), size: size, dark: dark);
          await readModel(tester);

          await openBody(tester);
          await tester.tap(find.text('Check'));
          await _settle(tester);
          expect(find.textContaining('"name" (Name) is required and has no default.'), findsOneWidget);

          await openFields(tester);
          await tester.enterText(inRow('name', find.byType(TextField)), 'Acme');
          await tester.pump();
          await openBody(tester);
          await tester.tap(find.text('Check'));
          await _settle(tester);
          expect(find.text('No problems found'), findsOneWidget);

          await tester.ensureVisible(find.text('Create request from this'));
          await tester.tap(find.text('Create request from this'));
          await _settle(tester);
          expect(find.textContaining('Create res.partner (payload)'), findsWidgets);
        });
      });

      group('the Check tab ($label)', () {
        testWidgets('checks a body, offers the fix, applies it and checks again', (tester) async {
          await pump(tester, OdooCheckTab(viewModel: studio), size: size, dark: dark);
          expect(find.text('Check a request'), findsOneWidget);

          await tester.enterText(_byLabel('Model'), 'res.partner');
          await tester.enterText(_byLabel('Method'), 'create');
          await tester.enterText(_byHint('The JSON body'), '{"vals_list": [{"nmae": "A"}]}');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Check'));
          await _settle(tester);

          expect(find.textContaining('Field "nmae" does not exist on res.partner. Did you mean "name"?'), findsOneWidget);
          await tester.ensureVisible(find.text('Rename to name'));
          await tester.tap(find.text('Rename to name'));
          await _settle(tester);

          expect(find.text('No problems found'), findsOneWidget);
          final field = tester.widget<TextField>(_byHint('The JSON body'));
          expect(jsonDecode(field.controller!.text), {
            'vals_list': [
              {'name': 'A'},
            ],
          });
        });

        testWidgets('a bad example shows several kinds of problem, with Apply all fixes', (tester) async {
          await pump(tester, OdooCheckTab(viewModel: studio), size: size, dark: dark);
          await tester.enterText(_byLabel('Model'), 'res.partner');
          await tester.tap(find.text('Insert a bad example'));
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Check'));
          await _settle(tester);

          expect(find.textContaining('parnter_id'), findsWidgets);
          expect(find.textContaining('"is_company" (Is a Company) is true or false'), findsOneWidget);
          await tester.ensureVisible(find.textContaining('Apply all'));
          await tester.tap(find.textContaining('Apply all'));
          await _settle(tester);
          final field = tester.widget<TextField>(_byHint('The JSON body'));
          final vals = (jsonDecode(field.controller!.text)['vals_list'] as List).first as Map;
          expect(vals['is_company'], true);
          expect(vals.containsKey('parent_id'), isTrue, reason: 'the typo was renamed');
        });
      });

      testWidgets('the Connect tab offers both APIs ($label)', (tester) async {
        await pump(tester, OdooConnectTab(viewModel: studio), size: size, dark: dark);
        expect(find.text('API key'), findsOneWidget);
        expect(find.text('Login'), findsNothing);

        await tester.tap(find.text('Odoo ≤18 · JSON-RPC'));
        await _settle(tester);
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Password or API key'), findsOneWidget);
        expect(find.text('Log in and test'), findsOneWidget);
        expect(studio.protocol, OdooProtocol.jsonRpc);

        await tester.tap(find.text('Odoo 19+ · JSON-2'));
        await _settle(tester);
        expect(find.text('Login'), findsNothing);
        expect(find.text('Test connection'), findsOneWidget);
      });
    }
  }

  testWidgets('the Connect tab logs in to an Odoo 18 server, finds its databases and tests the login', (tester) async {
    final rpc = newStudio(connect: false);
    addTearDown(rpc.dispose);
    await pump(tester, OdooConnectTab(viewModel: rpc), size: const Size(1200, 900), dark: false);
    await tester.tap(find.text('Odoo ≤18 · JSON-RPC'));
    await _settle(tester);
    await tester.enterText(_byLabel('Server URL'), odoo.host);
    await tester.enterText(_byLabel('Login'), odoo.login);
    await tester.enterText(_byLabel('Password or API key'), odoo.password);
    await tester.pump();

    await tester.tap(find.byTooltip('Find the databases of this server'));
    await _settle(tester);
    await tester.tap(find.text('Find the databases of this server'));
    await _settle(tester);
    expect(rpc.databases, ['prod']);
    expect(find.widgetWithText(TextField, 'prod'), findsOneWidget, reason: 'the only database is filled in');

    await tester.tap(find.text('Log in and test'));
    await _settle(tester);
    expect(find.textContaining('Connected as admin · Odoo 17.0'), findsOneWidget);
    expect(odoo.authenticateCount, 1);
  });

  group('the buttons of an Odoo request body', () {
    Widget tools(String url, {void Function(String)? onReplace, void Function(String)? onInsert, String text = '{"vals": {"nmae": "A"}}'}) =>
        OdooBodyTools(url: url, bodyText: () => text, onReplaceBody: onReplace ?? (_) {}, onInsert: onInsert ?? (_) {});

    setUp(() {
      locator.registerFactory<OdooStudioViewModel>(() => newStudio());
    });

    testWidgets('are not there for a request that does not call Odoo', (tester) async {
      await pump(tester, tools('https://api.example.com/users'), size: const Size(1200, 900), dark: false);
      expect(find.text('Check against Odoo'), findsNothing);
      expect(find.text('Odoo fields'), findsNothing);
    });

    testWidgets('the check dialog reads the model from the URL, finds the typo and hands the fixed body back', (tester) async {
      String? replaced;
      await pump(tester, tools('{{odooUrl}}/json/2/res.partner/write', onReplace: (t) => replaced = t, text: '{"ids": [1], "vals": {"nmae": "A"}}'), size: const Size(1200, 900), dark: false);

      await tester.tap(find.text('Check against Odoo'));
      await _settle(tester);
      expect(find.textContaining('Field "nmae" does not exist on res.partner'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this body')).onPressed, isNull, reason: 'nothing was changed yet');

      await tester.tap(find.text('Rename to name'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Use this body'));
      await _settle(tester);

      expect(jsonDecode(replaced!), {'ids': [1], 'vals': {'name': 'A'}});
      expect(find.text('Use this body'), findsNothing, reason: 'the dialog closed');
    });

    testWidgets('the field picker lists the fields of the model and hands back the one tapped', (tester) async {
      String? inserted;
      await pump(tester, tools('{{odooUrl}}/json/2/res.partner/create', onInsert: (t) => inserted = t), size: const Size(1200, 900), dark: false);

      await tester.tap(find.text('Odoo fields'));
      await _settle(tester);
      expect(find.text('Fields of res.partner'), findsOneWidget);
      expect(find.text('complete_name'), findsOneWidget, reason: 'every field of the model is listed, with its flags');
      expect(find.text('display_name'), findsNothing, reason: 'Odoo\'s own columns are not offered');

      await tester.enterText(_byHint('Filter fields'), 'credit');
      await _settle(tester);
      await tester.tap(find.text('credit_limit'));
      await _settle(tester);

      expect(inserted, '"credit_limit": 0.0');
    });
  });
}
