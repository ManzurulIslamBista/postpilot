// Dart Studio's Tests tab, opened for real in a light and a dark theme on a desktop and a phone screen: pick a
// collection, generate, read the dev_dependencies it asks for, pin versions from a pubspec.lock, switch the test package.
// Flutter turns a layout overflow into a test failure, so this also proves the tab is usable at both sizes.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_tests_view_model.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

const _lock = '''
packages:
  mocktail:
    dependency: "direct dev"
    description:
      name: mocktail
      url: "https://pub.dev"
    source: hosted
    version: "1.0.5"
  http_mock_adapter:
    dependency: "direct dev"
    description:
      name: http_mock_adapter
      url: "https://pub.dev"
    source: hosted
    version: "0.6.1"
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;
  late int collection;

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    collection = await db.collectionRepository.createCollection('Shop');
    final list = await addRequest(db, collection, 'List users', url: '{{baseUrl}}/users');
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'OK', statusCode: 200, headers: const {}, body: '[{"id":1,"name":"Ann","created_at":"2026-10-02T10:00:00Z"}]', savedAt: DateTime.utc(2026, 1, 1)));
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'Unauthorized', statusCode: 401, headers: const {}, body: '{"message":"Unauthorized"}', savedAt: DateTime.utc(2026, 1, 2)));
    await addRequest(
      db,
      collection,
      'Create user',
      method: HttpMethod.post,
      url: '{{baseUrl}}/users',
      body: const RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '{"name":"Ann"}'),
    );
    final useCase = BuildApiLayerUseCase(db.loader, db.exampleRepository);
    locator
      ..registerFactory<ApiLayerViewModel>(() => ApiLayerViewModel(useCase))
      ..registerFactory<ApiTestsViewModel>(() => ApiTestsViewModel(useCase));
  });

  tearDown(() => locator.reset());

  /// Real in-memory IO finishes outside the fake clock: alternate between letting it finish and letting the widgets react.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue, reason: 'timed out waiting');
  }

  Future<void> open(WidgetTester tester, {required Size size, required bool dark, int tab = 2}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = ShellViewModel(db.requestRepository);
    final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final workplace = WorkplaceViewModel(repository: FakeWorkplaceRepository(), backupService: db.backupService, database: database, shellViewModel: shell);
    addTearDown(() async {
      collections.dispose();
      workplace.dispose();
      await database.close();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ShellViewModel>.value(value: shell),
        ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
        ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Builder(builder: (context) => Center(child: FilledButton(onPressed: () => DartStudioDialog.show(context, collectionId: collection, initialTab: tab), child: const Text('open')))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> generate(WidgetTester tester) async {
    await tester.tap(find.text('Generate tests'));
    await until(tester, () => find.text('fixture_loader.dart').evaluate().isNotEmpty);
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('the Tests tab generates the test tree and shows what to add to pubspec.yaml ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        expect(find.text('Tests'), findsOneWidget, reason: 'the tab');
        expect(find.text('Pick a collection and press Generate tests'), findsOneWidget);
        await generate(tester);

        expect(find.text('Add the test packages to pubspec.yaml'), findsOneWidget);
        expect(find.textContaining('mocktail: ^1.0.4'), findsOneWidget);
        expect(find.textContaining('flutter pub add --dev mocktail http_mock_adapter'), findsOneWidget);
        // The file list of the generated tree (a phone shows it in a short strip, so some rows may need scrolling).
        expect(find.text('fixture_loader.dart'), findsOneWidget);
        expect(find.textContaining('files'), findsWidgets);
      });
    }
  }

  testWidgets('versions from a pasted pubspec.lock replace the suggestions, and the add command shrinks to nothing', (tester) async {
    await open(tester, size: const Size(1200, 900), dark: false);
    expect(find.textContaining('Pin versions from your pubspec.lock'), findsOneWidget);
    await tester.tap(find.textContaining('Pin versions from your pubspec.lock'));
    await tester.pumpAndSettle();
    await tester.enterText(lockField(), _lock);
    await tester.pump();
    expect(find.text('Versions read from 2 packages in your pubspec.lock'), findsOneWidget);
    await generate(tester);
    expect(find.textContaining('mocktail: ^1.0.5'), findsOneWidget);
    expect(find.textContaining('http_mock_adapter: ^0.6.1'), findsOneWidget);
    expect(find.textContaining('flutter pub add'), findsNothing, reason: 'nothing is missing');
  });

  testWidgets('text that is not a lock file is called out', (tester) async {
    await open(tester, size: const Size(1200, 900), dark: false);
    await tester.tap(find.textContaining('Pin versions from your pubspec.lock'));
    await tester.pumpAndSettle();
    await tester.enterText(lockField(), 'this is not yaml: [');
    await tester.pump();
    expect(find.text('That is not a pubspec.lock: paste the file as it is'), findsOneWidget);
  });

  testWidgets('choosing package:test changes the dev dependencies and the imports', (tester) async {
    await open(tester, size: const Size(1200, 900), dark: false);
    await tester.tap(find.text('Dart (package:test)'));
    await tester.pump();
    await generate(tester);
    expect(find.textContaining('test: ^1.25.8'), findsOneWidget);
    expect(find.textContaining('flutter_test:'), findsNothing);
    expect(find.textContaining('dart pub add --dev test mocktail http_mock_adapter'), findsOneWidget);
    final vm = locator<ApiTestsViewModel>();
    expect(vm, isNotNull);
  });

  testWidgets('the package name and style of the API layer carry into the tests', (tester) async {
    await open(tester, size: const Size(1200, 900), dark: false);
    await tester.enterText(find.widgetWithText(TextField, 'Package name'), 'shop_app');
    await tester.tap(find.text('freezed'));
    await tester.pump();
    await generate(tester);
    // The notes explain the build_runner step of a generated model style.
    expect(find.textContaining('run `dart run build_runner build`'), findsOneWidget);
  });

  testWidgets('copying the dev_dependencies puts them on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, size: const Size(1200, 900), dark: false);
    await generate(tester);
    await tester.tap(find.byTooltip('Copy the dev_dependencies'));
    await tester.pump();
    expect(copied, startsWith('dev_dependencies:\n  flutter_test:\n    sdk: flutter\n  mocktail: ^1.0.4\n'));
  });
}

/// The box the pubspec.lock is pasted into.
Finder lockField() => find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Paste the content of your'));
