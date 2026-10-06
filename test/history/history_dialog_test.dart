// The History panel as a person uses it: light and dark, a wide window and a phone, with in-memory fakes (the widget
// tester's clock does not run SQLite).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/presentation/view_models/history_view_model.dart';
import 'package:postpilot/features/history/presentation/widgets/history_dialog.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';

import '../support/in_memory_import_export_fakes.dart';
import 'support/in_memory_history_store.dart';

const _mask = '••••••';
const _wide = Size(1200, 900);
const _phone = Size(420, 900);

/// The in-memory requests, plus the one stream the shell opens a tab with.
final class _Requests implements RequestRepository {
  final RequestRepository inner;
  _Requests(this.inner);

  @override
  Stream<ApiRequestEntity?> watchById(int id) => Stream.fromFuture(inner.findById(id));

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) =>
      inner.createRequest(collectionId: collectionId, folderId: folderId, name: name);

  @override
  Future<void> saveRequest(ApiRequestEntity request) => inner.saveRequest(request);

  @override
  Future<ApiRequestEntity?> findById(int id) => inner.findById(id);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => inner.watchByCollection(collectionId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _ProductionEnvironment implements EnvironmentRepository {
  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(const EnvironmentEntity(id: 1, name: 'Production', isActive: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  final now = DateTime(2026, 10, 6, 16);
  late InMemoryDb memory;
  late _Requests requests;
  late CollectionsViewModel collections;
  late ShellViewModel shell;
  late int shopId;
  late int blogId;
  late InMemoryHistoryStore store;
  late HistoryViewModel vm;
  final sent = <ApiRequestEntity>[];
  final exported = <String>[];
  String? copied;

  HistoryEntryMeta meta({
    int? requestId,
    String name = 'Request',
    int? collectionId,
    String? collectionName = 'Shop',
    int? bytes,
    String? message = 'OK',
    String? error,
    bool hasBody = true,
  }) =>
      HistoryEntryMeta(
        requestId: requestId,
        requestName: name,
        collectionId: collectionId ?? shopId,
        collectionName: collectionName,
        environmentName: 'Staging',
        responseBytes: bytes,
        statusMessage: message,
        error: error,
        hasResponseBody: hasBody,
      );

  HistoryEntryEntity entry(int id, String method, String url, int? status, DateTime at, {HistoryEntryMeta? meta, int? ms = 30}) =>
      HistoryEntryEntity(id: id, method: method, url: url, statusCode: status, durationMs: ms, sentAt: at, meta: meta);

  HistoryDetail detail(
    HistoryEntryMeta meta,
    HttpMethod method,
    String url, {
    List<KeyValueItem> headers = const [],
    RequestBody body = RequestBody.empty,
    RequestAuth auth = const RequestAuth(type: AuthType.none),
    String? response,
    String contentType = 'application/json',
  }) =>
      HistoryDetail(
        request: HistoryRequestSnapshot(meta: meta, method: method, url: url, headers: headers, body: body, auth: auth),
        responseText: response,
        responseContentType: response == null ? null : contentType,
      );

  setUp(() async {
    await locator.reset();
    sent.clear();
    exported.clear();
    copied = null;
    memory = InMemoryDb();
    requests = _Requests(memory.requestRepository);
    shopId = await memory.collectionRepository.createCollection('Shop');
    blogId = await memory.collectionRepository.createCollection('Blog');
    collections = CollectionsViewModel(memory.collectionRepository, requests);
    shell = ShellViewModel(requests);

    final ordersMeta = meta(requestId: 77, name: 'Place order', bytes: 1200, message: 'Internal Server Error');
    final usersMeta = meta(name: 'List users', bytes: 4300);
    final deleteMeta = meta(name: 'Remove user', bytes: 0, hasBody: false, message: 'No Content');
    final downMeta = meta(name: 'Ping', error: "Couldn't reach api.test: the connection was refused.", message: null, hasBody: false);
    store = InMemoryHistoryStore(
      entries: [
        entry(5, 'GET', 'https://api.test/legacy', 200, DateTime(2026, 10, 6, 15, 30)),
        entry(4, 'GET', 'https://api.test/down', null, DateTime(2026, 10, 6, 15), meta: downMeta, ms: null),
        entry(3, 'POST', 'https://api.test/orders', 500, DateTime(2026, 10, 6, 14, 3, 22), meta: ordersMeta),
        entry(2, 'GET', 'https://api.test/users', 200, DateTime(2026, 10, 6, 9), meta: usersMeta, ms: 120),
        entry(1, 'DELETE', 'https://api.test/users/7', 204, DateTime(2026, 10, 5, 18, 30), meta: deleteMeta, ms: 45),
      ],
      details: {
        4: detail(downMeta, HttpMethod.get, 'https://api.test/down'),
        3: detail(
          ordersMeta,
          HttpMethod.post,
          'https://api.test/orders',
          headers: [KeyValueItem(key: 'X-Trace', value: 'abc-123'), KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}')],
          body: const RequestBody(type: BodyType.raw, rawText: '{"sku":"A1"}'),
          response: '{"error":"payment gateway timeout"}',
        ),
        2: detail(usersMeta, HttpMethod.get, 'https://api.test/users', response: '{"items":[{"city":"Lisbon"}]}'),
        1: detail(deleteMeta, HttpMethod.delete, 'https://api.test/users/7'),
      },
    );
    vm = HistoryViewModel(
      store,
      requests: requests,
      collections: memory.collectionRepository,
      examples: memory.exampleRepository,
      send: (request) async {
        sent.add(request);
        return ApiResponseEntity(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: Uint8List(0), duration: const Duration(milliseconds: 9));
      },
      saveFile: ({required fileName, required bytes, required mimeType}) async {
        exported.add(String.fromCharCodes(bytes));
        return '/downloads/$fileName';
      },
      expanderFor: null,
      clock: () => now,
      searchDebounce: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    vm.dispose();
    collections.dispose();
    shell.dispose();
    await locator.reset();
  });

  Widget host({bool dark = false}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<HistoryViewModel>.value(value: vm),
          ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
          ChangeNotifierProvider<ShellViewModel>.value(value: shell),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: Builder(builder: (context) => TextButton(onPressed: () => HistoryDialog.show(context), child: const Text('open'))),
          ),
        ),
      );

  Future<void> openHistory(WidgetTester tester, {Size size = _wide, bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(host(dark: dark));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// A choice in a popup menu: its label sits under an IgnorePointer, so the tap lands on the menu item around it.
  Future<void> chooseFromMenu(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> pickRow(WidgetTester tester, String url) async {
    await tester.tap(find.text(url));
    await tester.pumpAndSettle();
  }

  List<String> markedTexts(WidgetTester tester) {
    final out = <String>[];
    void visit(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.style?.backgroundColor != null && span.text != null) out.add(span.text!);
      span.children?.forEach(visit);
    }

    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      visit(text.text);
    }
    return out;
  }

  Finder rich(String text) => find.textContaining(text);

  group('the list', () {
    for (final dark in [false, true]) {
      for (final size in [_wide, _phone]) {
        final label = '${dark ? 'dark' : 'light'}, ${size.width.toInt()} px';

        testWidgets('shows every entry with method, status, time, duration and size, grouped by day ($label)', (tester) async {
          await openHistory(tester, size: size, dark: dark);

          expect(find.text('History'), findsWidgets);
          expect(find.text('5 requests'), findsOneWidget);
          expect(find.text('TODAY'), findsOneWidget);
          expect(find.text('YESTERDAY'), findsOneWidget);
          for (final url in ['https://api.test/orders', 'https://api.test/users', 'https://api.test/users/7', 'https://api.test/down', 'https://api.test/legacy']) {
            expect(find.text(url), findsOneWidget, reason: url);
          }
          expect(find.text('POST'), findsOneWidget);
          expect(find.text('DEL'), findsOneWidget, reason: 'DELETE does not fit the badge in full');
          expect(find.text('500'), findsOneWidget);
          expect(find.text('204'), findsOneWidget);
          expect(find.text('No response'), findsOneWidget);
          expect(find.text('14:03:22'), findsOneWidget);
          expect(find.text('30 ms'), findsWidgets);
          expect(find.text('120 ms'), findsOneWidget);
          expect(find.text('1.2 KB'), findsOneWidget);
          expect(find.text('4.2 KB'), findsOneWidget);
          expect(find.text('0 B'), findsOneWidget);
          expect(find.text('Shop › Place order'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('opens an entry with its request and response, and nothing overflows ($label)', (tester) async {
          await openHistory(tester, size: size, dark: dark);

          await pickRow(tester, 'https://api.test/orders');

          expect(find.text('Sent from Shop › Place order'), findsOneWidget);
          expect(find.text('Edit & re-send'), findsOneWidget);
          expect(find.text('Re-send as is'), findsOneWidget);
          expect(find.text('Open as new request'), findsOneWidget);
          expect(find.text('HEADERS'), findsOneWidget, reason: 'section titles are set in capitals');
          expect(rich('X-Trace: '), findsOneWidget);
          expect(rich('Authorization: '), findsOneWidget);
          expect(rich('Bearer {{token}}'), findsOneWidget);
          expect(rich('"sku"'), findsOneWidget);

          await tester.tap(find.text('Response'));
          await tester.pumpAndSettle();

          expect(rich('payment gateway timeout'), findsOneWidget);
          expect(find.textContaining('Response headers are not kept in History'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('an empty history says what will show up here', (tester) async {
      store.entries.clear();
      store.emit();
      await openHistory(tester);

      expect(find.text('No requests sent yet'), findsOneWidget);
      expect(find.text('Nothing sent yet'), findsOneWidget);
    });

    testWidgets('a wide window shows the list and the entry side by side, a narrow one swaps them and Back returns', (tester) async {
      await openHistory(tester);
      expect(find.text('Pick a request'), findsOneWidget);
      await pickRow(tester, 'https://api.test/orders');
      expect(find.text('Edit & re-send'), findsOneWidget);
      expect(find.text('https://api.test/users'), findsOneWidget, reason: 'the list is still there');

      vm.resetView();
      await tester.pumpWidget(const SizedBox());
      await openHistory(tester, size: _phone);
      expect(find.text('Pick a request'), findsNothing);
      await pickRow(tester, 'https://api.test/orders');
      expect(find.text('Edit & re-send'), findsOneWidget);
      expect(find.text('https://api.test/users'), findsNothing, reason: 'the entry replaced the list');

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pumpAndSettle();

      expect(find.text('https://api.test/users'), findsOneWidget);
      expect(find.text('Edit & re-send'), findsNothing);
    });

    testWidgets('an entry that kept no details says so and still offers its method and URL', (tester) async {
      await openHistory(tester);

      await pickRow(tester, 'https://api.test/legacy');

      expect(find.textContaining('Only the summary of this request was kept'), findsOneWidget);
      expect(find.text('Edit & re-send'), findsOneWidget);
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();
      expect(find.text('No response body kept'), findsOneWidget);
    });

    testWidgets('a send that got no response shows the reason on the Response tab', (tester) async {
      await openHistory(tester);

      await pickRow(tester, 'https://api.test/down');
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't reach api.test: the connection was refused."), findsOneWidget);
    });

    testWidgets('a request whose credentials were masked says so', (tester) async {
      store.details[3] = detail(
        store.entries[2].meta!,
        HttpMethod.post,
        'https://api.test/orders',
        headers: [KeyValueItem(key: 'X-Api-Key', value: _mask)],
        response: '{}',
      );
      await openHistory(tester);

      await pickRow(tester, 'https://api.test/orders');

      expect(find.textContaining('Passwords and tokens in this request were masked'), findsOneWidget);
    });
  });

  group('search and filters', () {
    testWidgets('typing marks the match in the list and narrows it; a word of a body finds its entry once typing pauses', (tester) async {
      await openHistory(tester);

      await tester.enterText(find.byType(TextField).first, 'USERS');
      await tester.pump();

      expect(find.textContaining('api.test/orders'), findsNothing);
      final marks = markedTexts(tester);
      expect(marks, isNotEmpty);
      expect(marks, everyElement('users'));
      expect(find.text('2 of 5 requests'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'lisbon');
      await tester.pump();
      expect(find.textContaining('api.test/users'), findsNothing, reason: 'the body is searched after a pause');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.textContaining('api.test/users'), findsOneWidget);
      expect(find.text('1 of 5 requests'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear the search'));
      await tester.pump();
      expect(find.text('5 requests'), findsOneWidget);
    });

    testWidgets('a status filter narrows the list and Clear filters brings everything back', (tester) async {
      await openHistory(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
      await chooseFromMenu(tester, '5xx');

      expect(find.text('Status: 5xx'), findsOneWidget);
      expect(find.text('https://api.test/orders'), findsOneWidget);
      expect(find.text('https://api.test/users'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('https://api.test/users'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('method, collection and day filters are offered from what is in the list', (tester) async {
      await openHistory(tester);

      await tester.tap(find.text('Method'));
      await tester.pumpAndSettle();
      expect(find.text('DELETE'), findsOneWidget);
      await chooseFromMenu(tester, 'POST');
      expect(find.text('https://api.test/orders'), findsOneWidget);
      expect(find.text('https://api.test/users'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collection'));
      await tester.pumpAndSettle();
      await chooseFromMenu(tester, 'Shop');
      expect(find.text('Collection: Shop'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('When'));
      await tester.pumpAndSettle();
      await chooseFromMenu(tester, 'Today');
      expect(find.text('https://api.test/users/7'), findsNothing, reason: 'it was sent yesterday');
      expect(find.text('https://api.test/orders'), findsOneWidget);
    });

    testWidgets('a search with no result says so and offers to clear it', (tester) async {
      await openHistory(tester);

      await tester.enterText(find.byType(TextField).first, 'no such thing');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.tap(find.text('Clear filters').last);
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsNothing);
    });
  });

  group('opening an entry as a request', () {
    testWidgets('"Open as new request" goes into the collection it was sent from, opens a tab and closes the panel', (tester) async {
      store.entries[2] = entry(3, 'POST', 'https://api.test/orders', 500, DateTime(2026, 10, 6, 14, 3, 22), meta: meta(name: 'Place order', collectionId: blogId, collectionName: 'Blog'));
      store.details[3] = detail(store.entries[2].meta!, HttpMethod.post, 'https://api.test/orders', body: const RequestBody(type: BodyType.raw, rawText: '{"sku":"A1"}'));
      store.emit();
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/orders');

      await tester.tap(find.text('Open as new request'));
      await tester.pumpAndSettle();

      final created = memory.requests.single;
      expect((created.collectionId, created.name, created.method, created.url), (blogId, 'Place order', HttpMethod.post, 'https://api.test/orders'));
      expect(created.body.rawText, '{"sku":"A1"}');
      expect(shell.selectedRequestId, created.id);
      expect(find.byType(HistoryDialog), findsNothing);
      expect(find.text('Open in which collection?'), findsNothing);
    });

    testWidgets('"Edit & re-send" opens a copy named as one, beside the original', (tester) async {
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/orders');

      await tester.tap(find.text('Edit & re-send'));
      await tester.pumpAndSettle();

      final created = memory.requests.single;
      expect(created.name, 'Place order (from history)');
      expect(created.collectionId, shopId);
      expect(created.headers.map((h) => h.key), ['X-Trace', 'Authorization']);
      expect(shell.selectedRequestId, created.id);
    });

    testWidgets('when its collection is gone the person chooses: nothing is picked for them, and Cancel creates nothing', (tester) async {
      store.entries[2] = entry(3, 'POST', 'https://api.test/orders', 500, DateTime(2026, 10, 6, 14, 3, 22), meta: meta(name: 'Place order', collectionId: 999, collectionName: 'Deleted'));
      store.details[3] = detail(store.entries[2].meta!, HttpMethod.post, 'https://api.test/orders');
      store.emit();
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/orders');

      await tester.tap(find.text('Open as new request'));
      await tester.pumpAndSettle();

      expect(find.text('Open in which collection?'), findsOneWidget);
      expect(find.textContaining('not there any more'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Open here')).onPressed, isNull, reason: 'no collection is chosen yet');
      expect(memory.requests, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(memory.requests, isEmpty);
      expect(find.byType(HistoryDialog), findsOneWidget, reason: 'backing out leaves the panel open');

      await tester.tap(find.text('Open as new request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open here'));
      await tester.pumpAndSettle();

      expect(memory.requests.single.collectionId, blogId);
      expect(shell.selectedRequestId, memory.requests.single.id);
    });

    testWidgets('an entry that kept no details also asks which collection, and on a fresh install makes "My collection"', (tester) async {
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/legacy');

      await tester.tap(find.text('Open as new request'));
      await tester.pumpAndSettle();

      expect(find.text('Open in which collection?'), findsOneWidget);
      expect(find.textContaining('did not keep which collection'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      memory.collections.clear();
      collections.dispose();
      collections = CollectionsViewModel(memory.collectionRepository, requests);
      await tester.pumpWidget(const SizedBox());
      vm.resetView();
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/legacy');
      await tester.tap(find.text('Open as new request'));
      await tester.pumpAndSettle();

      expect(memory.collections.map((c) => c.name), ['My collection']);
      final created = memory.requests.single;
      expect((created.name, created.method, created.url, created.collectionId), ('GET https://api.test/legacy', HttpMethod.get, 'https://api.test/legacy', memory.collections.single.id));
    });
  });

  group('re-sending as is', () {
    setUp(() async {
      locator.registerSingleton<ProductionGuard>(ProductionGuard(_ProductionEnvironment(), SafetyPrefs()));
    });

    testWidgets('a request that changes data in production is asked about first: Cancel sends nothing, Send anyway sends', (tester) async {
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/orders');

      await tester.tap(find.text('Re-send as is'));
      await tester.pumpAndSettle();

      expect(find.text('Send to Production?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.tap(find.text('Re-send as is'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send anyway'));
      await tester.pumpAndSettle();

      expect(sent.single.url, 'https://api.test/orders');
      expect(sent.single.method, HttpMethod.post);
      expect(sent.single.body.rawText, '{"sku":"A1"}');
      expect(find.textContaining('Sent again: 200 OK in 9 ms'), findsOneWidget);
    });

    testWidgets('a read goes straight out, even in production', (tester) async {
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/users');

      await tester.tap(find.text('Re-send as is'));
      await tester.pumpAndSettle();

      expect(find.text('Send to Production?'), findsNothing);
      expect(sent.single.method, HttpMethod.get);
    });

    testWidgets('a request whose passwords were masked asks before it goes out with them empty', (tester) async {
      store.details[2] = detail(store.entries[3].meta!, HttpMethod.get, 'https://api.test/users', headers: [KeyValueItem(key: 'X-Api-Key', value: _mask)], response: '{}');
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/users');

      await tester.tap(find.text('Re-send as is'));
      await tester.pumpAndSettle();

      expect(find.text('Send with masked values left empty?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.tap(find.text('Re-send as is'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send anyway'));
      await tester.pumpAndSettle();

      expect(sent.single.headers.single.value, '');
    });
  });

  group('copy as cURL', () {
    testWidgets('puts the template form on the clipboard and says what it left out', (tester) async {
      await openHistory(tester);
      await pickRow(tester, 'https://api.test/orders');

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy as cURL'));
      await tester.pumpAndSettle();

      expect(
        copied,
        "curl --location --request POST 'https://api.test/orders' \\\n"
        "--header 'X-Trace: abc-123' \\\n"
        "--header 'Authorization: Bearer {{token}}' \\\n"
        "--header 'Content-Type: application/json' \\\n"
        "--data-raw '{\"sku\":\"A1\"}'",
      );
      expect(find.textContaining('{{variables}} are left as written'), findsOneWidget);
    });
  });

  group('compare and export', () {
    testWidgets('two ticked entries are compared: the changed fields are listed', (tester) async {
      store.details[2] = detail(store.entries[3].meta!, HttpMethod.get, 'https://api.test/users', response: '{"items":[{"city":"Lisbon"}],"total":1}');
      store.entries[2] = entry(3, 'GET', 'https://api.test/users', 200, DateTime(2026, 10, 6, 14), meta: meta(name: 'List users'));
      store.details[3] = detail(store.entries[2].meta!, HttpMethod.get, 'https://api.test/users', response: '{"items":[{"city":"Porto"}],"total":2}');
      await openHistory(tester);

      await tester.tap(find.byTooltip('Select requests to compare or export'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Compare')).onPressed, isNull);
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Compare'));
      await tester.pumpAndSettle();

      expect(find.text('Compare responses'), findsOneWidget);
      expect(find.text('2 changed'), findsOneWidget);
      expect(rich('items[0].city'), findsOneWidget);
      expect(find.text('OLDER'), findsOneWidget);
      expect(find.text('NEWER'), findsOneWidget);
    });

    testWidgets('Export HAR writes the entries shown and says where the file went', (tester) async {
      await openHistory(tester);

      await tester.tap(find.byTooltip('Export as HAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export the 5 shown as HAR'));
      await tester.pumpAndSettle();

      expect(exported, hasLength(1));
      expect(exported.single, contains('"version": "1.2"'));
      expect(exported.single, contains('"name": "PostPilot"'));
      expect(find.textContaining('Exported 5 requests to /downloads/postpilot-history-2026-10-06.har'), findsOneWidget);
    });
  });

  group('clearing the history', () {
    testWidgets('asks first; Cancel keeps everything, Clear history empties it', (tester) async {
      await openHistory(tester);

      await tester.tap(find.byTooltip('Clear history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete all 5 recorded requests'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.clears, 0);
      expect(find.text('https://api.test/orders'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();

      expect(store.clears, 1);
      expect(find.text('No requests sent yet'), findsOneWidget);
    });
  });
}
