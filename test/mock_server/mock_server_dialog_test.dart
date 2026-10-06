// A separate file from the socket tests: a test suite that uses the widget test
// binding gets a fake HttpClient that answers 400 to everything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_dialog.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';

void main() {
  late InMemoryDb db;

  setUp(() async {
    await locator.reset();
    db = InMemoryDb();
    await db.collectionRepository.createCollection('Shop');
  });
  tearDown(() => locator.reset());

  Future<MockServerViewModel> open(WidgetTester tester) async {
    final vm = MockServerViewModel(BuildMockRoutesUseCase(db.loader, db.exampleRepository));
    locator.registerSingleton<MockServerViewModel>(vm);
    final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
    addTearDown(collections.dispose);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<CollectionsViewModel>.value(
      value: collections,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: (context) => FilledButton(onPressed: () => MockServerDialog.show(context), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return vm;
  }

  testWidgets('says that every website can read the answers until an origin is given', (tester) async {
    final vm = await open(tester);
    expect(find.text('Every website can read these answers'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Allowed origin'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Allowed origin'), 'http://localhost:5173');
    await tester.pump();
    expect(vm.allowedOrigin, 'http://localhost:5173');
    expect(find.text('Every website can read these answers'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Allowed origin'), '*');
    await tester.pump();
    expect(find.text('Every website can read these answers'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'CORS'));
    await tester.pump();
    expect(find.text('Every website can read these answers'), findsNothing);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Allowed origin')).enabled, isFalse);
  });
}
