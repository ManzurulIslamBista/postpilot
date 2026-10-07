// "Generate tests from OpenAPI…": paste or open a document, preview, tick, write. Both themes, desktop and phone width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/tool_dialog.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/generated_case.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/openapi_test_generator.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/generate_openapi_tests_usecase.dart';
import 'package:postpilot/features/test_suggestions/presentation/view_models/openapi_tests_view_model.dart';
import 'package:postpilot/features/test_suggestions/presentation/widgets/openapi_tests_dialog.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'openapi_specs.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;
  late int collection;
  late List<(int, int, int)> written; // collection id, cases written, cases left out
  late OpenApiTestsViewModel vm;
  String? fileText;
  String? downloaded;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = InMemoryDb();
    collection = await db.collectionRepository.createCollection('Pets');
    written = [];
    fileText = petShopSpec;
    downloaded = inventorySpec;
    vm = OpenApiTestsViewModel(
      collectionId: collection,
      read: (text) async => OpenApiTestGenerator.generate(text),
      write: (id, suite, selection) async {
        written.add((id, selection.cases.length, selection.skipped));
        return GeneratedTestsResult(folderName: 'Tests', created: selection.cases.length, gated: selection.changesDataCount, variablesAdded: const ['baseUrl', 'allowDataChanging']);
      },
    );
  });

  tearDown(() => vm.dispose());

  Future<void> open(WidgetTester tester, {required Size size, required bool dark}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
    addTearDown(collections.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<CollectionsViewModel>.value(
      value: collections,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => ToolDialog.show(
                  context,
                  (_) => OpenApiTestsDialog(viewModel: vm, pickFile: () async => fileText, download: (url) async => downloaded!),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  /// Scrolls the dialog until [finder] is built and on screen: the lower parts of the preview are lazy at phone height.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    // Back to the top first: the item may be above what is built now, and scrolling only goes one way.
    await tester.drag(scrollable, const Offset(0, 100000), warnIfMissed: false);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 300, scrollable: scrollable, maxScrolls: 60);
    // Built is not yet on screen: bring it fully into view so a tap on it lands.
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText?.startsWith('Or paste') == true), text);
    await _settle(tester);
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('a pasted document is previewed with counts per category, and written as ticked ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        expect(find.text('Generate tests from OpenAPI'), findsOneWidget);
        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Preview')).onPressed, isNull, reason: 'nothing to read yet');

        await paste(tester, petShopSpec);
        await tester.tap(find.text('Preview'));
        await _settle(tester);

        await reveal(tester, find.text('Contract · 5'));
        expect(find.text('Pet Shop: 39 requests from 5 operations'), findsOneWidget);
        expect(find.text('Contract · 5'), findsOneWidget);
        expect(find.text('Negative · 13'), findsOneWidget);
        expect(find.text('Boundary · 13'), findsOneWidget);
        expect(find.text('Auth · 8'), findsOneWidget);
        await reveal(tester, find.text('39 will be written.'));
        expect(find.text('39 will be written.'), findsOneWidget);
        await reveal(tester, find.textContaining('24 of them change data'));
        expect(find.textContaining('24 of them change data'), findsOneWidget);
        expect(find.textContaining('allowDataChanging'), findsWidgets);
        await reveal(tester, find.text('GET /pets (contract)'));
        expect(find.text('GET /pets (contract)'), findsOneWidget);

        // Unticking a category narrows what is written.
        await reveal(tester, find.text('Boundary · 13'));
        await tester.tap(find.text('Boundary · 13'));
        await _settle(tester);
        await reveal(tester, find.text('26 will be written.'));
        expect(find.text('26 will be written.'), findsOneWidget);
        expect(find.text('Generate 26 requests'), findsOneWidget);

        await tester.tap(find.text('Generate 26 requests'));
        await _settle(tester);
        expect(written, [(collection, 26, 0)]);
        expect(find.text('Created 26 requests in "Tests"'), findsOneWidget);
        expect(find.textContaining('24 of them change data'), findsNothing, reason: 'the preview is replaced by the result');
        expect(find.textContaining('Added the collection variables baseUrl and allowDataChanging.'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
      });

      testWidgets('the cap leaves cases out, contracts first, and a bad cap is told ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        await paste(tester, petShopSpec);
        await tester.tap(find.text('Preview'));
        await _settle(tester);

        await reveal(tester, find.widgetWithText(TextField, '200'));
        await tester.enterText(find.widgetWithText(TextField, '200'), '10');
        await _settle(tester);
        await reveal(tester, find.textContaining('10 will be written; 29 more are left out by the limit'));
        expect(find.textContaining('10 will be written; 29 more are left out by the limit'), findsOneWidget);
        expect(find.text('Generate 10 requests'), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextField, '10'), 'lots');
        await _settle(tester);
        await reveal(tester, find.text('Enter a whole number, 1 or more.'));
        expect(find.text('Enter a whole number, 1 or more.'), findsOneWidget);
        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate 10 requests')).onPressed, isNull);

        await tester.enterText(find.widgetWithText(TextField, 'lots'), '0');
        await _settle(tester);
        expect(find.text('Enter a whole number, 1 or more.'), findsOneWidget);
      });

      testWidgets('a document that cannot be read is told, with no preview ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        await paste(tester, '{"hello": 1}');
        await tester.tap(find.text('Preview'));
        await _settle(tester);
        expect(find.textContaining('The document could not be read'), findsOneWidget);
        expect(find.textContaining('requests from'), findsNothing);
      });

      testWidgets('Open file and Download fill the document in ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        await tester.tap(find.text('Open file…'));
        await _settle(tester);
        await tester.tap(find.text('Preview'));
        await _settle(tester);
        expect(find.text('Pet Shop: 39 requests from 5 operations'), findsOneWidget);

        await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Document address'), 'https://api.test/openapi.json');
        await tester.tap(find.text('Download'));
        await _settle(tester);
        expect(find.textContaining('requests from'), findsNothing, reason: 'a new document is a new preview, not yet made');
        await tester.tap(find.text('Preview'));
        await _settle(tester);
        expect(find.text('Inventory: 25 requests from 3 operations'), findsOneWidget);
      });

      testWidgets('nothing is written when the person closes without generating ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        await paste(tester, inventorySpec);
        await tester.tap(find.text('Preview'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Close'));
        await _settle(tester);
        expect(written, isEmpty);
      });
    }
  }

  test('the view model keeps the cap and the ticks as the person set them', () async {
    await vm.preview();
    expect(vm.canGenerate, isFalse, reason: 'no document yet');
    vm.setSpec(inventorySpec);
    await vm.preview();
    expect(vm.selection!.cases.length, 25);
    vm.setCap('5');
    expect(vm.selection!.cases.length, 5);
    expect(vm.selection!.skipped, 20);
    vm.setCap('x');
    expect(vm.capError, isNotNull);
    expect(vm.canGenerate, isFalse);
    expect(vm.cap, 5, reason: 'a bad cap changes nothing');
    vm.setCap('100');
    expect(vm.capError, isNull);
    expect(vm.selection!.cases.length, 25);
    vm.toggleCategory(TestCategory.contract);
    vm.toggleCategory(TestCategory.negative);
    vm.toggleCategory(TestCategory.boundary);
    vm.toggleCategory(TestCategory.auth);
    expect(vm.selection!.cases, isEmpty);
    expect(vm.canGenerate, isFalse, reason: 'nothing ticked');
    vm.setSpec('changed');
    expect(vm.suite, isNull, reason: 'a different document is a different preview');
  });
}
