// What the Headers, Auth and Tests tabs of a request show of what it inherits.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/defaults/presentation/view_models/inherited_defaults_view_model.dart';
import 'package:postpilot/features/defaults/presentation/widgets/request_inherited_sections.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:provider/provider.dart';

import '../support/in_memory_import_export_fakes.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  late InMemoryDb db;
  late int shop;
  late int orders;
  late int publicFolder;

  setUp(() async {
    db = InMemoryDb();
    shop = await db.collectionRepository.createCollection('Shop');
    orders = await db.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
    publicFolder = await db.collectionRepository.createFolder(collectionId: shop, name: 'Public');
    await db.defaultsRepository.saveCollection(
      shop,
      LevelDefaults(
        headers: [_h('X-Tenant', 'acme'), _h('Authorization', 'Bearer top-secret-token-value'), _h('X-Trace', 'on')],
        assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      ),
    );
    await db.defaultsRepository.saveFolder(
      orders,
      LevelDefaults(
        headers: [_h('X-Api-Version', '2')],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'orders-token'),
        extractors: [ExtractorEntity(path: r'$.id', variableKey: 'orderId')],
      ),
    );
    await db.defaultsRepository.saveFolder(publicFolder, const LevelDefaults(auth: RequestAuth(type: AuthType.none)));
  });

  Future<InheritedDefaultsViewModel> bound(WidgetTester tester, {int? folderId}) async {
    final vm = InheritedDefaultsViewModel(ResolveRequestDefaultsUseCase(db.defaultsRepository));
    addTearDown(vm.dispose);
    vm.bind(shop, folderId: folderId);
    await tester.pump();
    await tester.pump();
    return vm;
  }

  Future<void> pump(WidgetTester tester, Widget child, {InheritedDefaultsViewModel? vm}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget body = Scaffold(body: SingleChildScrollView(child: child));
    if (vm != null) body = ChangeNotifierProvider<InheritedDefaultsViewModel>.value(value: vm, child: body);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: body));
    await tester.pumpAndSettle();
  }

  group('headers', () {
    testWidgets('lists what the request inherits, with where each comes from, and hides a secret value', (tester) async {
      final vm = await bound(tester, folderId: orders);
      await pump(tester, RequestInheritedHeaders(requestHeaders: const [], onChanged: (_) {}), vm: vm);

      expect(find.text('X-Tenant'), findsOneWidget);
      expect(find.text('X-Api-Version'), findsOneWidget);
      expect(find.text('from collection "Shop"'), findsNWidgets(3));
      expect(find.text('from folder "Orders"'), findsOneWidget);
      expect(find.textContaining('top-secret-token-value'), findsNothing, reason: 'the value of an Authorization header is not shown');
    });

    testWidgets('Override adds a row with the same name and value to the request, ready to be edited', (tester) async {
      final vm = await bound(tester);
      List<KeyValueItem>? changed;
      final own = [_h('X-Existing', '1')];
      await pump(tester, RequestInheritedHeaders(requestHeaders: own, onChanged: (items) => changed = items), vm: vm);

      await tester.tap(find.widgetWithText(TextButton, 'Override').first);
      await tester.pump();

      expect(changed!.map((h) => (h.key, h.value, h.enabled)), [('X-Existing', '1', true), ('X-Tenant', 'acme', true)]);
    });

    testWidgets('Turn off adds a disabled row of that name: the way to not send an inherited header', (tester) async {
      final vm = await bound(tester);
      List<KeyValueItem>? changed;
      await pump(tester, RequestInheritedHeaders(requestHeaders: const [], onChanged: (items) => changed = items), vm: vm);

      await tester.tap(find.widgetWithText(TextButton, 'Turn off').last);
      await tester.pump();

      expect(changed!.single.key, 'X-Trace');
      expect(changed!.single.enabled, isFalse);
    });

    testWidgets('a header the request overrides or switches off is shown struck through with that said, and offers no actions', (tester) async {
      final vm = await bound(tester);
      await pump(
        tester,
        RequestInheritedHeaders(
          requestHeaders: [_h('x-tenant', 'globex'), _h('X-TRACE', '', enabled: false)],
          onChanged: (_) {},
        ),
        vm: vm,
      );

      expect(find.text('overridden here'), findsOneWidget);
      expect(find.text('switched off here'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Override'), findsOneWidget, reason: 'only Authorization is left to override');
    });

    testWidgets('shows nothing when the request inherits no header, or when there is no view model at all', (tester) async {
      final empty = InMemoryDb();
      final id = await empty.collectionRepository.createCollection('Empty');
      final vm = InheritedDefaultsViewModel(ResolveRequestDefaultsUseCase(empty.defaultsRepository));
      addTearDown(vm.dispose);
      vm.bind(id);
      await tester.pump();
      await tester.pump();
      await pump(tester, RequestInheritedHeaders(requestHeaders: const [], onChanged: (_) {}), vm: vm);
      expect(find.text('INHERITED HEADERS'), findsNothing);

      await pump(tester, RequestInheritedHeaders(requestHeaders: const [], onChanged: (_) {}));
      expect(find.text('INHERITED HEADERS'), findsNothing);
    });

    testWidgets('a request moved to another folder shows what its new folder passes down', (tester) async {
      final vm = await bound(tester, folderId: orders);
      vm.bind(shop, folderId: publicFolder);
      await tester.pump();
      await tester.pump();
      await pump(tester, RequestInheritedHeaders(requestHeaders: const [], onChanged: (_) {}), vm: vm);

      expect(find.text('X-Api-Version'), findsNothing);
      expect(find.text('X-Tenant'), findsOneWidget);
    });
  });

  group('auth', () {
    testWidgets('says which auth a request that inherits sends, and from where, and Override copies it into the request', (tester) async {
      final vm = await bound(tester, folderId: orders);
      RequestAuth? overridden;
      await pump(tester, RequestInheritedAuth(auth: const RequestAuth(type: AuthType.inherit), onOverride: (a) => overridden = a), vm: vm);

      expect(find.text('Sends Bearer Token from the folder "Orders".'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Override'));
      await tester.pump();
      expect(overridden?.type, AuthType.bearer);
      expect(overridden?.bearerToken, 'orders-token');
    });

    testWidgets('says so when a folder sets No Auth, or when nothing sets any', (tester) async {
      final none = await bound(tester, folderId: publicFolder);
      await pump(tester, RequestInheritedAuth(auth: const RequestAuth(type: AuthType.inherit), onOverride: (_) {}), vm: none);
      expect(find.text('The folder "Public" sets No Auth, so none is sent.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Override'), findsNothing);

      final empty = InMemoryDb();
      final id = await empty.collectionRepository.createCollection('Empty');
      final vm = InheritedDefaultsViewModel(ResolveRequestDefaultsUseCase(empty.defaultsRepository));
      addTearDown(vm.dispose);
      vm.bind(id);
      await tester.pump();
      await tester.pump();
      await pump(tester, RequestInheritedAuth(auth: const RequestAuth(type: AuthType.inherit), onOverride: (_) {}), vm: vm);
      expect(find.textContaining('sets authentication, so none is sent'), findsOneWidget);
    });

    testWidgets('a request with an auth of its own shows nothing about the inherited one', (tester) async {
      final vm = await bound(tester, folderId: orders);
      await pump(tester, RequestInheritedAuth(auth: const RequestAuth(type: AuthType.basic), onOverride: (_) {}), vm: vm);

      expect(find.textContaining('Sends'), findsNothing);
    });
  });

  group('tests', () {
    testWidgets('lists each level\'s checks and extractors read-only, the collection first, with its origin', (tester) async {
      final vm = await bound(tester, folderId: orders);
      await pump(tester, const RequestInheritedTests(), vm: vm);

      expect(find.text('Inherited tests'), findsOneWidget);
      expect(find.text('Status is 2xx'), findsOneWidget);
      expect(find.textContaining('{{orderId}}'), findsOneWidget);
      final collection = tester.getTopLeft(find.text('from collection "Shop"')).dy;
      final folder = tester.getTopLeft(find.text('from folder "Orders"')).dy;
      expect(collection, lessThan(folder));
      expect(find.byType(TextField), findsNothing, reason: 'nothing here can be edited');
    });

    testWidgets('shows nothing when no level has any', (tester) async {
      final vm = await bound(tester, folderId: publicFolder);
      await db.defaultsRepository.saveCollection(shop, LevelDefaults.empty);
      await vm.refresh();
      await pump(tester, const RequestInheritedTests(), vm: vm);

      expect(find.text('Inherited tests'), findsNothing);
    });
  });
}
