// The History panel's model over a real (in-memory SQLite) database: list, search, filters, the entry on show
// and what can be done with it.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/history/data/repositories/history_repository_impl.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_filter.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_store.dart';
import 'package:postpilot/features/history/domain/services/history_body_diff.dart';
import 'package:postpilot/features/history/domain/services/history_template_expander.dart';
import 'package:postpilot/features/history/presentation/view_models/history_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

import '../support/drift_repos.dart';

final class _Context implements HistoryContextSource {
  String collectionName = 'Shop';

  @override
  Future<HistoryContext> of(ApiRequestEntity request) async => HistoryContext(collectionName: collectionName, environmentName: 'Staging');
}

/// Only the narrow interface: what the app's old repository gave, and what many fakes still are.
final class _SummaryOnly implements HistoryRepository {
  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => Stream.value([
        HistoryEntryEntity(id: 1, method: 'POST', url: 'https://api.test/users', statusCode: 201, durationMs: 40, sentAt: DateTime(2026, 10, 6, 9)),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  final now = DateTime(2026, 10, 6, 15);
  late AppDatabase db;
  late DriftRepos repos;
  late _Context context;
  late HistoryRepositoryImpl store;
  late int shop;
  late HistoryViewModel vm;
  final sent = <ApiRequestEntity>[];
  final saved = <({String name, Uint8List bytes})>[];
  Future<ApiResponseEntity> Function(ApiRequestEntity request) sender = (_) async => throw StateError('no sender set');

  HistoryViewModel makeVm({HistoryRepository? repository, Future<String> Function(ApiRequestEntity)? resolvedCurl}) => HistoryViewModel(
        repository ?? store,
        requests: repos.requestRepository,
        collections: repos.collectionRepository,
        examples: repos.exampleRepository,
        send: (request) {
          sent.add(request);
          return sender(request);
        },
        saveFile: ({required fileName, required bytes, required mimeType}) async {
          saved.add((name: fileName, bytes: bytes));
          return '/downloads/$fileName';
        },
        expanderFor: (collectionId) async => HistoryTemplateExpander.safe(const VariableResolver.layered([
          {'baseUrl': 'https://api.test', 'apiToken': 'tok-secret-123456'},
        ])),
        resolvedCurl: resolvedCurl,
        clock: () => now,
        searchDebounce: Duration.zero,
      );

  setUp(() async {
    sent.clear();
    saved.clear();
    sender = (_) async => throw StateError('no sender set');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    context = _Context();
    store = HistoryRepositoryImpl(db.historyDao, context: context);
    shop = await repos.collectionRepository.createCollection('Shop');
    vm = makeVm();
  });
  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<void> settle() => pumpEventQueue(times: 100);

  /// Records one send and returns the id of its entry; [at] moves it to another moment.
  Future<int> record(
    String url, {
    int? status = 200,
    String? body = '{"ok":true}',
    HttpMethod method = HttpMethod.get,
    String name = 'Request',
    int? requestId,
    DateTime? at,
    List<KeyValueItem> headers = const [],
    RequestBody requestBody = RequestBody.empty,
    String contentType = 'application/json',
    String? error,
  }) async {
    final request = ApiRequestEntity(
      id: requestId ?? 0,
      collectionId: shop,
      folderId: null,
      name: name,
      method: method,
      url: url,
      headers: headers,
      queryParams: const [],
      body: requestBody,
      auth: const RequestAuth(type: AuthType.none),
    );
    await store.recordCapture(
      method: method.label,
      url: url,
      statusCode: status,
      durationMs: 30,
      capture: HistoryCapture(
        request: request,
        responseBytes: body == null ? const [] : utf8.encode(body),
        responseContentType: contentType,
        statusMessage: status == null ? '' : 'OK',
        error: error,
      ),
    );
    final id = (await db.select(db.historyEntries).get()).map((e) => e.id).reduce((a, b) => a > b ? a : b);
    if (at != null) {
      await db.customStatement('UPDATE history_entries SET sent_at = ? WHERE id = ?', [at.millisecondsSinceEpoch ~/ 1000, id]);
      db.markTablesUpdated([db.historyEntries]);
    }
    await settle();
    return id;
  }

  HistoryEntryEntity entry(int id) => vm.entries.firstWhere((e) => e.id == id);

  group('the list', () {
    test('groups entries by day under Today, Yesterday and dated headers, newest first', () async {
      final a = await record('https://api.test/a', at: DateTime(2026, 10, 6, 9));
      final b = await record('https://api.test/b', at: DateTime(2026, 10, 5, 22));
      final c = await record('https://api.test/c', at: DateTime(2026, 9, 28, 8));
      final d = await record('https://api.test/d', at: DateTime(2025, 12, 31, 8));
      final e = await record('https://api.test/e', at: DateTime(2026, 10, 6, 14));

      final labels = [
        for (final item in vm.items)
          switch (item) {
            HistoryDayHeader(:final label, :final count) => '$label ($count)',
            HistoryEntryItem(:final entry) => entry.url.split('/').last,
          },
      ];

      expect(labels, ['Today (2)', 'e', 'a', 'Yesterday (1)', 'b', 'Mon 28 Sep (1)', 'c', 'Wed 31 Dec 2025 (1)', 'd']);
      expect([a, b, c, d, e], everyElement(isPositive));
    });

    test('day labels: today, yesterday, this year without the year, other years with it', () {
      expect(HistoryViewModel.dayLabel(DateTime(2026, 10, 6, 0, 1), now), 'Today');
      expect(HistoryViewModel.dayLabel(DateTime(2026, 10, 5, 23, 59), now), 'Yesterday');
      expect(HistoryViewModel.dayLabel(DateTime(2026, 10, 4), now), 'Sun 4 Oct');
      expect(HistoryViewModel.dayLabel(DateTime(2026, 1, 1), now), 'Thu 1 Jan');
      expect(HistoryViewModel.dayLabel(DateTime(2025, 10, 6), now), 'Mon 6 Oct 2025');
    });

    test('lists the methods and collections that occur, for the filter menus', () async {
      await record('https://api.test/a', method: HttpMethod.delete);
      await record('https://api.test/b', method: HttpMethod.get);
      await record('https://api.test/c', method: HttpMethod.get);
      await record('https://api.test/d', method: HttpMethod.post);

      expect(vm.methods, ['GET', 'POST', 'DELETE']);
      expect(vm.collections, [(id: shop, name: 'Shop')]);
    });
  });

  group('search', () {
    test('a word of the URL narrows the list at once, a word of a body once typing pauses', () async {
      final users = await record('https://api.test/users', body: '{"city":"Lisbon"}', name: 'List users');
      final orders = await record('https://api.test/orders', body: '{"city":"Porto"}', name: 'List orders');

      vm.setQuery('orders');
      expect(vm.visible.map((e) => e.id), [orders], reason: 'the summary is matched in memory, with no wait');

      vm.setQuery('Lisbon');
      expect(vm.visible, isEmpty, reason: 'the body is not in the summary: it is searched after the pause');
      await settle();
      expect(vm.visible.map((e) => e.id), [users]);

      vm.setQuery('list');
      await settle();
      expect(vm.visible.map((e) => e.id), [orders, users], reason: 'the request names');
      expect(vm.needle, 'list');
    });

    test('an old search never overwrites a newer one', () async {
      final users = await record('https://api.test/users', body: '{"city":"Lisbon"}');
      await record('https://api.test/orders', body: '{"city":"Porto"}');

      vm.setQuery('lisbon');
      vm.setQuery('porto');
      await settle();

      expect(vm.visible.map((e) => e.url), ['https://api.test/orders']);
      expect(users, isPositive);
    });

    test('the status code is a search word too', () async {
      final bad = await record('https://api.test/a', status: 502);
      await record('https://api.test/b', status: 200);

      vm.setQuery('502');
      await settle();

      expect(vm.visible.map((e) => e.id), [bad]);
    });

    test('filters and the search narrow together, and clearing shows everything again', () async {
      await record('https://api.test/a', status: 500, method: HttpMethod.post, at: DateTime(2026, 10, 6, 10));
      final fiveHundredGet = await record('https://api.test/b', status: 500, method: HttpMethod.get, at: DateTime(2026, 10, 6, 11));
      await record('https://api.test/c', status: 404, method: HttpMethod.get, at: DateTime(2026, 10, 6, 12));
      final old = await record('https://api.test/d', status: 500, method: HttpMethod.get, at: DateTime(2026, 9, 1));

      vm.setStatusClass(HistoryStatusClass.serverError);
      expect(vm.visible, hasLength(3));
      vm.setMethod('GET');
      expect(vm.visible.map((e) => e.id).toSet(), {fiveHundredGet, old});
      vm.setRange(HistoryRange.today);
      expect(vm.visible.map((e) => e.id), [fiveHundredGet]);
      vm.setCollection(shop);
      expect(vm.visible.map((e) => e.id), [fiveHundredGet]);
      vm.setCollection(shop + 99);
      expect(vm.visible, isEmpty);
      expect(vm.filter.isActive, isTrue);

      vm.clearFilters();

      expect(vm.visible, hasLength(4));
      expect(vm.filter.isActive, isFalse);
    });
  });

  group('the entry on show', () {
    test('selecting loads what was sent and what came back; another selection replaces it', () async {
      final first = await record('https://api.test/a', body: '{"a":1}');
      final second = await record('https://api.test/b', body: '{"b":2}');

      await vm.select(first);
      expect(vm.selected!.id, first);
      expect(vm.detail!.responseText, '{"a":1}');
      expect(vm.detail!.request.url, 'https://api.test/a');

      await vm.select(second);
      expect(vm.detail!.responseText, '{"b":2}');

      await vm.select(null);
      expect(vm.selected, isNull);
      expect(vm.detail, isNull);
    });

    test('an entry that is pruned while on show is let go of', () async {
      final id = await record('https://api.test/a');
      await vm.select(id);

      await store.clear();
      await settle();

      expect(vm.selectedId, isNull);
      expect(vm.detail, isNull);
    });

    test('with only the narrow repository the list still works and entries just have no details', () async {
      vm.dispose();
      vm = makeVm(repository: _SummaryOnly());
      await settle();

      expect(vm.hasDetails, isFalse);
      expect(vm.entries.single.url, 'https://api.test/users');
      await vm.select(1);
      expect(vm.detail, isNull);
      expect(vm.detailLoading, isFalse);

      final id = await vm.openAsNewRequest(vm.entries.single, collectionId: shop);

      final created = (await repos.requestRepository.findById(id))!;
      expect((created.name, created.method, created.url), ('POST https://api.test/users', HttpMethod.post, 'https://api.test/users'));
    });

    test('resetting the view goes back to the whole list with nothing selected', () async {
      final id = await record('https://api.test/a');
      await vm.select(id);
      vm.setQuery('zzz');
      vm.toggleSelecting();

      vm.resetView();

      expect((vm.selectedId, vm.filter.isActive, vm.selecting, vm.notice), (null, false, false, null));
      expect(vm.visible, hasLength(1));
    });
  });

  group('opening an entry again', () {
    test('goes to the collection it was sent from when that still exists under the same name', () async {
      final id = await record('https://api.test/a');
      final snapshot = await vm.snapshotOf(entry(id));

      expect(await vm.originCollectionOf(snapshot), shop);

      await repos.collectionRepository.renameCollection(shop, 'Shop v2');
      expect(await vm.originCollectionOf(snapshot), isNull, reason: 'the same id under another name may be another collection');

      await repos.collectionRepository.renameCollection(shop, 'Shop');
      await repos.collectionRepository.deleteCollection(shop);
      expect(await vm.originCollectionOf(snapshot), isNull);
    });

    test('an entry that kept no details has no origin, so the person has to choose', () async {
      await store.record(method: 'GET', url: 'https://api.test/old', statusCode: 200, durationMs: 1, responseHeaders: const {});
      await settle();

      final snapshot = await vm.snapshotOf(vm.entries.single);

      expect(await vm.originCollectionOf(snapshot), isNull);
    });

    test('saves a new request with the whole snapshot (masked values empty) and never touches the original', () async {
      final originalId = await repos.requestRepository.createRequest(collectionId: shop, name: 'Create user');
      final original = ApiRequestEntity(
        id: originalId,
        collectionId: shop,
        folderId: null,
        name: 'Create user',
        method: HttpMethod.post,
        url: '{{baseUrl}}/users',
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}'), KeyValueItem(key: 'X-Api-Key', value: 'literal-key-value-1')],
        queryParams: const [],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"Ann","password":"p4ssw0rd!"}'),
        auth: const RequestAuth(type: AuthType.none),
      );
      await repos.requestRepository.saveRequest(original);
      final id = await record(
        '{{baseUrl}}/users',
        method: HttpMethod.post,
        name: 'Create user',
        requestId: originalId,
        headers: original.headers,
        requestBody: original.body,
      );

      final newId = await vm.openAsNewRequest(entry(id), collectionId: shop, copy: true);

      final created = (await repos.requestRepository.findById(newId))!;
      expect(newId, isNot(originalId));
      expect(created.name, 'Create user (from history)');
      expect(created.collectionId, shop);
      expect(created.method, HttpMethod.post);
      expect(created.url, '{{baseUrl}}/users');
      expect({for (final h in created.headers) h.key: h.value}, {'Authorization': 'Bearer {{token}}', 'X-Api-Key': ''});
      expect(created.body.rawText, '{"name":"Ann","password":""}');
      final untouched = (await repos.requestRepository.findById(originalId))!;
      expect(untouched.name, 'Create user');
      expect(untouched.headers.last.value, 'literal-key-value-1');
    });

    test('"Open as new request" keeps the request\'s own name', () async {
      final id = await record('https://api.test/a', name: 'List things');

      final newId = await vm.openInBuilder(entry(id), collectionId: shop);

      expect((await repos.requestRepository.findById(newId))!.name, 'List things');
    });
  });

  group('re-sending as is', () {
    test('asks first, and does not send when the answer is no', () async {
      final id = await record('https://api.test/a', method: HttpMethod.post);
      ApiRequestEntity? asked;

      await vm.resendAsIs(entry(id), confirm: (request) async {
        asked = request;
        return false;
      });

      expect(asked!.url, 'https://api.test/a');
      expect(sent, isEmpty);
      expect(vm.sending, isFalse);
      expect(vm.notice, isNull);
    });

    test('sends the stored request (its own id and collection while they exist, masked values empty) and shows the new entry', () async {
      final requestId = await repos.requestRepository.createRequest(collectionId: shop, name: 'Create user');
      final id = await record(
        '{{baseUrl}}/users',
        method: HttpMethod.post,
        name: 'Create user',
        requestId: requestId,
        headers: [KeyValueItem(key: 'X-Api-Key', value: 'literal-key-value-1'), KeyValueItem(key: 'Accept', value: '*/*')],
        requestBody: const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
      );
      await vm.select(id);
      sender = (request) async {
        // What a real send does: it records itself.
        await store.recordCapture(
          method: request.method.label,
          url: request.url,
          statusCode: 201,
          durationMs: 12,
          capture: HistoryCapture(request: request, responseBytes: utf8.encode('{"id":9}'), responseContentType: 'application/json'),
        );
        return ApiResponseEntity(statusCode: 201, statusMessage: 'Created', headers: const {}, bodyBytes: Uint8List(0), duration: const Duration(milliseconds: 12));
      };

      await vm.resendAsIs(entry(id), confirm: (_) async => true);
      await settle();

      final request = sent.single;
      expect((request.id, request.collectionId, request.method, request.url), (requestId, shop, HttpMethod.post, '{{baseUrl}}/users'));
      expect({for (final h in request.headers) h.key: h.value}, {'X-Api-Key': '', 'Accept': '*/*'});
      expect(request.body.rawText, '{"a":1}');
      expect(vm.notice!.kind, HistoryNoticeKind.success);
      expect(vm.notice!.message, startsWith('Sent again: 201 Created in 12 ms'));
      expect(vm.sending, isFalse);
      expect(vm.entries, hasLength(2));
      expect(vm.selectedId, vm.entries.first.id, reason: 'the entry the send added is the one on show');
      expect(vm.selectedId, isNot(id));
    });

    test('a request that was deleted is sent without an id, and a failure is told in one masked line', () async {
      final id = await record('https://api.test/a', requestId: 4242);
      sender = (_) async => throw const NetworkException(
            'refused',
            kind: NetworkErrorKind.connectionError,
            summary: "Couldn't reach https://api.test/a?token=abcdefghijk123 : the connection was refused.",
          );

      await vm.resendAsIs(entry(id), confirm: (_) async => true);

      expect(sent.single.id, 0);
      expect(vm.notice!.kind, HistoryNoticeKind.error);
      expect(vm.notice!.message, isNot(contains('abcdefghijk123')));
      expect(vm.notice!.message, contains('the connection was refused'));
      expect(vm.sending, isFalse);
    });
  });

  group('copy as cURL', () {
    test('the template form is built from the stored request: variables as written, nothing resolved', () async {
      final id = await record(
        '{{baseUrl}}/users',
        method: HttpMethod.post,
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}')],
        requestBody: const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
      );

      final curl = await vm.curlTemplate(entry(id));

      expect(
        curl,
        "curl --location --request POST '{{baseUrl}}/users' \\\n"
        "--header 'Authorization: Bearer {{token}}' \\\n"
        "--header 'Content-Type: application/json' \\\n"
        "--data-raw '{\"a\":1}'",
      );
    });

    test('the resolved form goes through the request builder\'s own generator, only when asked for', () async {
      final id = await record('{{baseUrl}}/users', headers: [KeyValueItem(key: 'X-Api-Key', value: 'literal-key-value-1')]);
      ApiRequestEntity? given;
      vm.dispose();
      vm = makeVm(resolvedCurl: (request) async {
        given = request;
        return 'curl resolved';
      });
      await settle();

      expect(await vm.curlResolved(entry(id)), 'curl resolved');
      expect(given!.url, '{{baseUrl}}/users');
      expect(given!.collectionId, shop);
      expect(given!.headers.single.value, '', reason: 'a masked value is never turned back into the mask');
    });
  });

  group('save the response as an example', () {
    test('adds the stored response to the request it came from, with its content type', () async {
      final requestId = await repos.requestRepository.createRequest(collectionId: shop, name: 'List');
      final id = await record('https://api.test/a', requestId: requestId, body: '{"items":[]}', status: 200);

      await vm.saveAsExample(entry(id));

      final examples = await repos.exampleRepository.watchByRequest(requestId).first;
      expect(examples, hasLength(1));
      expect(examples.single.statusCode, 200);
      expect(examples.single.body, '{"items":[]}');
      expect(examples.single.headers['content-type'], 'application/json');
      expect(examples.single.truncated, isFalse);
      expect(examples.single.name, startsWith('From history 20'));
      expect(vm.notice!.kind, HistoryNoticeKind.success);
      expect(await vm.canSaveExample(entry(id)), isTrue);
    });

    test('says why not when the request or the body is gone', () async {
      final gone = await record('https://api.test/a', requestId: 999, body: '{"a":1}');
      final empty = await record('https://api.test/b', requestId: null, body: null);

      expect(await vm.canSaveExample(entry(gone)), isFalse);
      expect(await vm.canSaveExample(entry(empty)), isFalse);
      await vm.saveAsExample(entry(gone));

      expect(vm.notice!.kind, HistoryNoticeKind.error);
      expect(vm.notice!.message, contains('cannot be saved as an example'));
    });
  });

  group('compare', () {
    test('two ticked entries are compared, older first, and the volatile fields can be ignored', () async {
      final older = await record('https://api.test/a', body: '{"id":1,"updated_at":"x","name":"Ann"}');
      final newer = await record('https://api.test/a', body: '{"id":1,"updated_at":"y","name":"Bea"}');
      await record('https://api.test/c', body: '{}');
      vm.toggleSelecting();

      vm.toggleChecked(newer);
      await vm.compareChecked();
      expect(vm.comparison, isNull, reason: 'it takes exactly two');
      vm.toggleChecked(older);
      await vm.compareChecked();

      var comparison = vm.comparison!;
      expect((comparison.older.id, comparison.newer.id), (older, newer));
      var diff = comparison.diff as JsonBodiesDiff;
      expect(diff.result.changes.map((c) => c.path), ['updated_at', 'name']);

      await vm.compareChecked(ignoreVolatile: true);
      comparison = vm.comparison!;
      diff = comparison.diff as JsonBodiesDiff;
      expect(comparison.ignoreVolatile, isTrue);
      expect(diff.result.changes.map((c) => c.path), ['name']);

      vm.closeComparison();
      expect(vm.comparison, isNull);
    });

    test('"Compare with..." starts with the entry ticked and says what to do next', () async {
      final id = await record('https://api.test/a');

      vm.startCompareWith(entry(id));

      expect(vm.selecting, isTrue);
      expect(vm.checked, {id});
      expect(vm.notice!.message, contains('Tick one more entry'));
    });

    test('entries that kept no body are said to have nothing to compare', () async {
      final a = await record('https://api.test/a', body: null);
      final b = await record('https://api.test/b', body: null);
      vm.toggleSelecting();
      vm.toggleChecked(a);
      vm.toggleChecked(b);

      await vm.compareChecked();

      expect(vm.comparison!.diff, isA<BodiesUnavailable>());
    });
  });

  group('HAR export', () {
    test('writes the shown entries oldest first, absolute and masked, to a file named for the day', () async {
      await record(
        '{{baseUrl}}/users',
        method: HttpMethod.post,
        at: DateTime(2026, 10, 6, 10),
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{apiToken}}')],
        body: '{"token":"tok-secret-123456","ok":true}',
      );
      await record('{{baseUrl}}/ping', at: DateTime(2026, 10, 6, 9), body: '{}');

      await vm.exportHar(selectedOnly: false);

      expect(saved.single.name, 'postpilot-history-2026-10-06.har');
      final har = jsonDecode(utf8.decode(saved.single.bytes)) as Map<String, dynamic>;
      final entries = (har['log'] as Map)['entries'] as List;
      expect(entries.map((e) => e['request']['url']), ['https://api.test/ping', 'https://api.test/users']);
      expect(entries.map((e) => e['startedDateTime']), [
        DateTime(2026, 10, 6, 9).toUtc().toIso8601String(),
        DateTime(2026, 10, 6, 10).toUtc().toIso8601String(),
      ]);
      expect(utf8.decode(saved.single.bytes), isNot(contains('tok-secret-123456')));
      expect(entries.last['request']['headers'], [
        {'name': 'Authorization', 'value': 'Bearer {{apiToken}}'},
      ]);
      expect(vm.notice!.kind, HistoryNoticeKind.success);
      expect(vm.notice!.message, contains('/downloads/postpilot-history-2026-10-06.har'));
      expect(vm.exporting, isFalse);
    });

    test('covers what the filters show, or only what is ticked, or one entry', () async {
      final a = await record('https://api.test/a', status: 500);
      await record('https://api.test/b', status: 200);
      final c = await record('https://api.test/c', status: 500);

      vm.setStatusClass(HistoryStatusClass.serverError);
      await vm.exportHar(selectedOnly: false);
      vm.toggleSelecting();
      vm.toggleChecked(c);
      await vm.exportHar(selectedOnly: true);
      await vm.exportHar(selectedOnly: false, only: entry(a));

      List<Object?> urls(int index) =>
          [for (final e in ((jsonDecode(utf8.decode(saved[index].bytes)) as Map)['log'] as Map)['entries'] as List) e['request']['url']];
      expect(urls(0), ['https://api.test/a', 'https://api.test/c']);
      expect(urls(1), ['https://api.test/c']);
      expect(urls(2), ['https://api.test/a']);
    });

    test('with nothing shown it says so instead of writing an empty file, and a failed write is told', () async {
      await record('https://api.test/a');
      vm.setQuery('nothing like this');
      await settle();

      await vm.exportHar(selectedOnly: false);

      expect(saved, isEmpty);
      expect(vm.notice!.kind, HistoryNoticeKind.info);

      vm.dispose();
      vm = HistoryViewModel(
        store,
        saveFile: ({required fileName, required bytes, required mimeType}) async => throw const FileSystemLikeException('disk full'),
      );
      await settle();
      await vm.exportHar(selectedOnly: false);
      expect(vm.notice!.kind, HistoryNoticeKind.error);
      expect(vm.notice!.message, contains('could not be written'));
      expect(vm.exporting, isFalse);
    });
  });

  group('clearing', () {
    test('empties the list and the stored details, and the model starts over', () async {
      final id = await record('https://api.test/a');
      await vm.select(id);

      await vm.clear();
      await settle();

      expect(vm.entries, isEmpty);
      expect(vm.selectedId, isNull);
      expect(await db.select(db.historyPayloads).get(), isEmpty);
    });
  });
}

final class FileSystemLikeException implements Exception {
  final String message;
  const FileSystemLikeException(this.message);
}
