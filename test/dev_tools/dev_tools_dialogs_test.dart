// Every new developer tool, opened for real in a light and a dark theme, on a
// desktop and a phone screen, with each of its tabs visited. Flutter turns a
// layout overflow, an unbounded height or a missing provider into a test
// failure, so this is what proves the dialogs are usable, not just compiled.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/ai_assistant/data/ai_client.dart';
import 'package:postpilot/features/ai_assistant/data/ai_settings_store.dart';
import 'package:postpilot/features/ai_assistant/presentation/ai_request_dialog.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/command_palette/presentation/command_palette_dialog.dart';
import 'package:postpilot/features/command_palette/presentation/palette_items.dart';
import 'package:postpilot/features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import 'package:postpilot/features/dart_codegen/presentation/view_models/api_layer_view_model.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import 'package:postpilot/features/device_helper/presentation/device_helper_dialog.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/graphql/presentation/graphql_explorer_dialog.dart';
import 'package:postpilot/features/graphql/presentation/graphql_explorer_view_model.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/import_export/domain/usecases/refresh_openapi_usecase.dart';
import 'package:postpilot/features/import_export/presentation/openapi_refresh_dialog.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_dialog.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import 'package:postpilot/features/odoo/presentation/widgets/odoo_studio_dialog.dart';
import 'package:postpilot/features/realtime/data/realtime_session.dart';
import 'package:postpilot/features/realtime/presentation/realtime_dialog.dart';
import 'package:postpilot/features/realtime/presentation/realtime_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/response_tools/presentation/widgets/response_tools_dialog.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/safety/presentation/safety_settings_pane.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/templates/domain/usecases/add_starter_template_usecase.dart';
import 'package:postpilot/features/templates/presentation/templates_dialog.dart';
import 'package:postpilot/features/tour/presentation/tour_dialog.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

final class _NoNetwork implements ApiClient {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => throw 'offline in tests';
}

final class _NoKeyStore implements AiSettingsStore {
  @override
  Future<String?> apiKey() async => null;
  @override
  Future<void> saveApiKey(String key) async {}
  @override
  Future<void> clearApiKey() async {}
  @override
  Future<String> model() async => 'claude-test';
  @override
  Future<void> saveModel(String model) async {}
}

const _jsonBody = '{"data":{"items":[{"id":1,"name":"Ann","created_at":1700000000,"token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwiZXhwIjoxNzAwMDAwMDAwfQ.sig"},{"id":2,"name":"Bob"}]},"ok":true}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDb db;
  late int requestId;
  late ApiResponseEntity response;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await locator.reset();
    db = InMemoryDb();
    final collection = await db.collectionRepository.createCollection('Shop');
    requestId = await addRequest(db, collection, 'List users', url: '{{baseUrl}}/users');
    response = ApiResponseEntity(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList(utf8.encode(_jsonBody)),
      duration: const Duration(milliseconds: 87),
    );
    final history = ResponseHistory()..record(requestId, response);
    final loader = db.loader;
    final resolver = BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
    locator
      ..registerSingleton<ResponseHistory>(history)
      ..registerSingleton<RequestRepository>(db.requestRepository)
      // The command palette lists every request through this loader.
      ..registerSingleton<CollectionLoader>(loader)
      ..registerSingleton<RequestScriptsRepository>(db.scriptsRepository)
      ..registerSingleton<ResponseExampleRepository>(db.exampleRepository)
      ..registerSingleton<ApiClient>(_NoNetwork())
      ..registerSingleton<BuildVariableResolverUseCase>(resolver)
      ..registerSingleton<SafetyPrefs>(SafetyPrefs())
      ..registerSingleton<ProductionGuard>(ProductionGuard(db.environmentRepository, SafetyPrefs()))
      ..registerSingleton<AiSettingsStore>(_NoKeyStore())
      ..registerSingleton<AiClient>(AiClient(_NoNetwork(), _NoKeyStore()))
      ..registerFactory<ApiLayerViewModel>(() => ApiLayerViewModel(BuildApiLayerUseCase(loader, db.exampleRepository)))
      ..registerFactory<OdooStudioViewModel>(
        () => OdooStudioViewModel(OdooClient(_NoNetwork()), db.environmentRepository, CreateOdooWorkspaceUseCase(db.environmentRepository, db.collectionRepository, db.requestRepository)),
      )
      ..registerSingleton<MockServerViewModel>(MockServerViewModel(BuildMockRoutesUseCase(loader, db.exampleRepository)))
      ..registerFactory<RealtimeViewModel>(() => RealtimeViewModel(const RealtimeConnector(), () => resolver(0)))
      ..registerFactory<GraphqlExplorerViewModel>(() => GraphqlExplorerViewModel(_NoNetwork(), () => resolver(0)))
      ..registerSingleton<AddStarterTemplateUseCase>(AddStarterTemplateUseCase(db.writer, db.environmentRepository))
      ..registerSingleton<RefreshOpenApiUseCase>(RefreshOpenApiUseCase(db.collectionRepository, db.requestRepository));
  });

  tearDown(() async {
    await locator.reset();
  });

  /// Opens [open] from a button in a themed app, with every provider the real shell supplies.
  Future<void> launch(WidgetTester tester, void Function(BuildContext) open, {required Size size, required bool dark}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = ShellViewModel(db.requestRepository);
    final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
    final environments = EnvironmentsViewModel(db.environmentRepository, db.globalVariableRepository);
    // Never initialised: it only has to exist, because the file pickers read what the platform can do.
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final workplace = WorkplaceViewModel(repository: FakeWorkplaceRepository(), backupService: db.backupService, database: database, shellViewModel: shell);
    addTearDown(() async {
      collections.dispose();
      environments.dispose();
      workplace.dispose();
      await database.close();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ShellViewModel>.value(value: shell),
        ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
        ChangeNotifierProvider<EnvironmentsViewModel>.value(value: environments),
        ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: Builder(builder: (context) => Center(child: FilledButton(onPressed: () => open(context), child: const Text('open'))))),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  final dialogs = <String, void Function(BuildContext)>{
    'Dart Studio': (c) => DartStudioDialog.show(c, initialJson: _jsonBody, initialName: 'User'),
    'Odoo Studio': (c) => OdooStudioDialog.show(c),
    'Mock server': (c) => MockServerDialog.show(c),
    'Realtime': (c) => RealtimeDialog.show(c, initialUrl: 'wss://echo.websocket.org'),
    'GraphQL explorer': (c) => GraphqlExplorerDialog.show(c, initialUrl: 'https://countries.trevorblades.com/graphql'),
    'Device helper': (c) => DeviceHelperDialog.show(c, initialUrl: 'http://localhost:3000/api'),
    'Starter templates': (c) => TemplatesDialog.show(c),
    'Quick tour': (c) => TourDialog.show(c),
    'Update from OpenAPI': (c) => OpenApiRefreshDialog.show(c),
    'AI request': (c) => AiRequestDialog.show(c),
    'Response tools': (c) => ResponseToolsDialog.show(c, requestId: requestId, requestName: 'List users', response: response),
  };

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';
      for (final entry in dialogs.entries) {
        testWidgets('${entry.key} opens and every tab renders ($label)', (tester) async {
          await launch(tester, entry.value, size: size, dark: dark);
          expect(find.byType(Dialog), findsWidgets);
          final tabs = find.byType(Tab);
          final count = tabs.evaluate().length;
          for (var i = 0; i < count; i++) {
            await tester.ensureVisible(tabs.at(i));
            await tester.tap(tabs.at(i), warnIfMissed: false);
            await _settle(tester);
          }
        });
      }

      testWidgets('Command palette finds tools and requests ($label)', (tester) async {
        await launch(
          tester,
          (c) => CommandPaletteDialog.show(c, items: [...PaletteItems.tools(), ...PaletteItems.app(newRequest: () {}, toggleSidebar: () {}, openImport: () {})], loadMore: PaletteItems.requests),
          size: size,
          dark: dark,
        );
        // Requests load in the background; typing finds a tool, then a request by its URL.
        await tester.enterText(find.byType(TextField), 'odoo');
        await _settle(tester);
        expect(find.textContaining('Odoo Studio'), findsWidgets);
        await tester.enterText(find.byType(TextField), 'users');
        await _settle(tester);
        expect(find.text('List users'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'zzzzqqq');
        await _settle(tester);
        expect(find.textContaining('Nothing matches'), findsOneWidget);
      });
    }
  }

  testWidgets('Safety settings pane renders and toggles', (tester) async {
    await launch(tester, (c) => showDialog<void>(context: c, builder: (_) => const Dialog(child: SizedBox(width: 600, height: 500, child: SingleChildScrollView(child: SafetySettingsPane())))), size: const Size(900, 700), dark: false);
    expect(find.text('Production lock'), findsOneWidget);
    expect(find.text('Keep secrets on this device'), findsOneWidget);
    final prefs = locator<SafetyPrefs>();
    expect(prefs.confirmProductionWrites, isTrue);
    await tester.tap(find.byType(Switch).first);
    await _settle(tester);
    expect(prefs.confirmProductionWrites, isFalse);
  });
}

/// Frames and animations run, without waiting forever on a spinner that never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
