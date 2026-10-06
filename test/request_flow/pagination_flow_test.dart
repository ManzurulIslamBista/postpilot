// Fetch all pages through the engine, one strategy at a time, against a fake paged API.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_report.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_executor.dart';
import 'package:postpilot/features/request_flow/domain/services/odoo_count.dart';
import 'flow_support.dart';

List<int> _range(int from, int to) => [for (var i = from; i <= to; i++) i];

Object? _body(FlowOutcome outcome) => jsonDecode(utf8.decode(outcome.response!.bodyBytes));

void main() {
  late FakeFlowClock clock;
  late FlowExecutor executor;

  setUp(() {
    clock = FakeFlowClock();
    executor = FlowExecutor(clock: clock, random: () => 1);
  });

  Future<FlowOutcome> run(
    FakeServer server,
    PaginationSettings pagination, {
    FlowSettings flow = const FlowSettings(),
    String url = 'https://api.test/items',
    HttpMethod method = HttpMethod.get,
    List<KeyValueItem> query = const [],
    Object? body,
    Map<String, String> variables = const {},
  }) =>
      executor.execute(
        request: flowRequest(url: url, method: method, queryParams: query, body: body == null ? const RequestBody() : jsonBody(body)),
        flow: flow,
        pagination: pagination.copyWith(enabled: true),
        send: server.send,
        context: flowContext(variables: variables),
      );

  group('Link header', () {
    // 12 items in pages of 5, 5 and 2.
    FakeServer api({bool relative = false}) => FakeServer((url, request, call) {
          final page = int.parse(url.queryParameters['page'] ?? '1');
          final items = switch (page) { 1 => _range(1, 5), 2 => _range(6, 10), _ => _range(11, 12) };
          final base = relative ? '/items' : 'https://api.test/items';
          return responded(jsonResponse(items, headers: {
            'Link': page < 3 ? '<$base?page=${page + 1}>; rel="next", <$base?page=3>; rel="last"' : '<$base?page=1>; rel="first"',
          }));
        });

    test('follows rel="next" to the end and returns one array', () async {
      final server = api();

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.linkHeader));

      expect(_body(outcome), _range(1, 12));
      expect(server.urls.map((u) => u.toString()), [
        'https://api.test/items',
        'https://api.test/items?page=2',
        'https://api.test/items?page=3',
      ]);
      final pages = outcome.report.pages!;
      expect((pages.pages, pages.items, pages.stop), (3, 12, PaginationStop.lastPage));
      expect(pages.badge, '3 pages, 12 items');
      expect(pages.complete, isTrue);
      expect(outcome.report.failure, isNull);
      expect(outcome.response!.statusCode, 200);
    });

    test('a relative link is resolved against the page it came from', () async {
      final server = api(relative: true);

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.linkHeader));

      expect(_body(outcome), _range(1, 12));
      expect(server.urls[1].toString(), 'https://api.test/items?page=2');
    });

    test('the next link is found among several, in any case, quoted or not', () async {
      final server = FakeServer((url, request, call) => call == 1
          ? responded(jsonResponse([1], headers: {'link': '<https://api.test/a>; rel=prev, <https://api.test/items?p=2>; REL="Next last"'}))
          : responded(jsonResponse([2])));

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.linkHeader));

      expect(_body(outcome), [1, 2]);
    });

    test('a query row of the request that the link sets itself is replaced, the others stay', () async {
      final server = FakeServer((url, request, call) => call == 1
          ? responded(jsonResponse([1], headers: {'Link': '<https://api.test/items?page=2&limit=1>; rel="next"'}))
          : responded(jsonResponse([2])));

      await run(
        server,
        const PaginationSettings(kind: PaginationKind.linkHeader),
        query: [KeyValueItem(key: 'page', value: '1'), KeyValueItem(key: 'api_key', value: 'k')],
      );

      final second = server.urls[1].queryParametersAll;
      expect(second['page'], ['2']);
      expect(second['limit'], ['1']);
      expect(second['api_key'], ['k'], reason: 'the credential row is kept');
    });
  });

  group('next URL in the body', () {
    FakeServer api(String Function(int page) next) => FakeServer((url, request, call) {
          final page = int.parse(url.queryParameters['page'] ?? '1');
          final last = page == 3;
          return responded(jsonResponse({
            'total': 6,
            'items': [page * 2 - 1, page * 2],
            'next': last ? null : next(page + 1),
          }));
        });

    test('follows an absolute URL, merges the items under the same path and keeps the rest of the first page', () async {
      final server = api((p) => 'https://api.test/items?page=$p');

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'items', nextPath: 'next'));

      expect(_body(outcome), {
        'total': 6,
        'items': [1, 2, 3, 4, 5, 6],
        'next': 'https://api.test/items?page=2',
      });
      expect(outcome.report.pages!.badge, '3 pages, 6 items');
    });

    test('follows a relative URL', () async {
      final server = api((p) => '/items?page=$p');

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'items', nextPath: 'next'));

      expect((_body(outcome) as Map)['items'], [1, 2, 3, 4, 5, 6]);
    });

    test('reads a link where an API keeps it: OData, HAL, nested objects', () async {
      final odata = FakeServer((url, request, call) => call == 1
          ? responded(jsonResponse({'value': [1], '@odata.nextLink': 'https://api.test/items?skip=1'}))
          : responded(jsonResponse({'value': [2]})));
      final hal = FakeServer((url, request, call) => call == 1
          ? responded(jsonResponse({'_embedded': {'orders': [1]}, '_links': {'next': {'href': '/items?page=2'}}}))
          : responded(jsonResponse({'_embedded': {'orders': [2]}, '_links': {}})));

      final a = await run(odata, const PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'value', nextPath: '["@odata.nextLink"]'));
      final b = await run(hal, const PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: '_embedded.orders', nextPath: '_links.next.href'));

      expect((_body(a) as Map)['value'], [1, 2]);
      expect(((_body(b) as Map)['_embedded'] as Map)['orders'], [1, 2]);
    });

    test('a has-more field that says false ends the walk even when a link is there', () async {
      final server = FakeServer((url, request, call) =>
          responded(jsonResponse({'items': [call], 'next': 'https://api.test/items?page=${call + 1}', 'has_more': call < 2})));

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'items', nextPath: 'next', hasMorePath: 'has_more'),
      );

      expect(server.requests, hasLength(2));
      expect(outcome.report.pages!.stop, PaginationStop.lastPage);
    });
  });

  group('cursor / token', () {
    FakeServer api() => FakeServer((url, request, call) {
          final token = url.queryParameters['pageToken'];
          final index = token == null ? 0 : int.parse(token.substring(1)) - 1;
          return responded(jsonResponse({
            'data': [index * 2 + 1, index * 2 + 2],
            if (index < 2) 'nextPageToken': 't${index + 2}',
          }));
        });

    test('sends the token back as a query parameter until none comes', () async {
      final server = api();

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.cursor, itemsPath: 'data', nextPath: 'nextPageToken', param: 'pageToken'),
      );

      expect((_body(outcome) as Map)['data'], [1, 2, 3, 4, 5, 6]);
      expect(server.urls.map((u) => u.queryParameters['pageToken']), [null, 't2', 't3']);
      expect(outcome.report.pages!.stop, PaginationStop.lastPage);
    });

    test('writes the token into a JSON body at the path given (a GraphQL-style cursor)', () async {
      final server = FakeServer((url, request, call) {
        final index = call - 1;
        return responded(jsonResponse({
          'items': [index],
          'cursor': index < 2 ? 'c${index + 1}' : '',
        }));
      });

      final outcome = await run(
        server,
        const PaginationSettings(
          kind: PaginationKind.cursor,
          itemsPath: 'items',
          nextPath: 'cursor',
          param: 'variables.after',
          location: PageParamLocation.body,
        ),
        method: HttpMethod.post,
        flow: const FlowSettings(repeatUnsafe: true),
        body: {'query': 'q', 'variables': {'first': 1}},
      );

      expect((_body(outcome) as Map)['items'], [0, 1, 2]);
      expect(server.bodyOf(1), {'query': 'q', 'variables': {'first': 1, 'after': 'c1'}});
      expect(server.bodyOf(2), {'query': 'q', 'variables': {'first': 1, 'after': 'c2'}});
    });

    test('a has_more flag of false ends it although a token is present', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({
            'rows': [call],
            'next_cursor': 'x$call',
            'has_more': call < 2,
          })));

      await run(
        server,
        const PaginationSettings(
          kind: PaginationKind.cursor,
          itemsPath: 'rows',
          nextPath: 'next_cursor',
          param: 'cursor',
          hasMorePath: 'has_more',
        ),
      );

      expect(server.requests, hasLength(2));
    });

    test('a token seen twice stops the walk (cycle guard) instead of looping', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'data': [call], 'nextPageToken': 'same'})));

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.cursor, itemsPath: 'data', nextPath: 'nextPageToken', param: 'pageToken', maxPages: 50),
      );

      // Page 1 asks for 'same', page 2 answers with 'same' again, which was already used.
      expect(server.requests, hasLength(2));
      final pages = outcome.report.pages!;
      expect(pages.stop, PaginationStop.cycle);
      expect(pages.pages, 2);
      expect(pages.complete, isFalse);
      expect(outcome.report.notes.single, contains('already sent'));
    });
  });

  group('page number', () {
    FakeServer api({required int pages, bool tellTotal = true}) => FakeServer((url, request, call) {
          final page = int.parse(url.queryParameters['page'] ?? '1');
          return responded(jsonResponse({
            'page': page,
            if (tellTotal) 'total_pages': pages,
            'results': page <= pages ? [page * 10, page * 10 + 1] : [],
          }));
        });

    test('counts up to the total number of pages and sends no request past it', () async {
      final server = api(pages: 4);

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page', totalPath: 'total_pages'),
      );

      expect(server.requests, hasLength(4));
      expect((_body(outcome) as Map)['results'], [10, 11, 20, 21, 30, 31, 40, 41]);
      expect(server.urls.map((u) => u.queryParameters['page']), [null, '2', '3', '4']);
    });

    test('without a total it goes on until an empty page, which is left out', () async {
      final server = api(pages: 3, tellTotal: false);

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page'));

      expect(server.requests, hasLength(4));
      expect((_body(outcome) as Map)['results'], hasLength(6));
      expect(outcome.report.pages!.stop, PaginationStop.emptyPage);
      expect(outcome.report.pages!.pages, 3);
      expect(outcome.report.pages!.complete, isTrue);
    });

    test('the page the request asks for is where it starts counting', () async {
      final server = api(pages: 4);

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page', totalPath: 'total_pages'),
        query: [KeyValueItem(key: 'page', value: '3')],
      );

      expect(server.urls.map((u) => u.queryParameters['page']), ['3', '4']);
      expect(outcome.report.pages!.pages, 2);
    });

    test('a 0-based API starts at the first page it is told', () async {
      final server = FakeServer((url, request, call) {
        final page = int.parse(url.queryParameters['page'] ?? '0');
        return responded(jsonResponse({'page': page, 'total_pages': 3, 'results': [page]}));
      });

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page', totalPath: 'total_pages', firstPage: 0),
      );

      expect(server.urls.map((u) => u.queryParameters['page']), [null, '1', '2']);
      expect((_body(outcome) as Map)['results'], [0, 1, 2]);
    });

    test('the page parameter row of the request is replaced, not added twice', () async {
      final server = api(pages: 2);

      await run(
        server,
        const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page', totalPath: 'total_pages'),
        query: [KeyValueItem(key: 'page', value: '1'), KeyValueItem(key: 'size', value: '2')],
      );

      expect(server.requests[1].queryParams.where((p) => p.key == 'page').map((p) => p.value), ['2']);
      expect(server.urls[1].queryParametersAll['page'], ['2']);
      expect(server.urls[1].queryParameters['size'], '2');
    });

    test('a server that ignores the page parameter is noticed by its repeated items', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'results': [1, 2, 3]})));

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.page, itemsPath: 'results', param: 'page', maxPages: 100),
      );

      expect(server.requests, hasLength(2));
      expect((_body(outcome) as Map)['results'], [1, 2, 3], reason: 'the repeated page is not added');
      expect(outcome.report.pages!.stop, PaginationStop.cycle);
      expect(outcome.report.notes.single, contains('ignore the page parameter'));
    });
  });

  group('offset and limit', () {
    test('adds the page size to the offset until the total is reached', () async {
      final server = FakeServer((url, request, call) {
        final offset = int.parse(url.queryParameters['offset'] ?? '0');
        final items = _range(offset + 1, (offset + 2).clamp(0, 5));
        return responded(jsonResponse({'total': 5, 'items': items}));
      });

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.offset, itemsPath: 'items', param: 'offset', limitParam: 'limit', totalPath: 'total'),
        query: [KeyValueItem(key: 'limit', value: '2')],
      );

      expect(server.urls.map((u) => u.queryParameters['offset']), [null, '2', '4']);
      expect((_body(outcome) as Map)['items'], _range(1, 5));
    });

    test('without a limit field it steps by the number of items a page held', () async {
      final server = FakeServer((url, request, call) {
        final offset = int.parse(url.queryParameters['offset'] ?? '0');
        return responded(jsonResponse({'total': 6, 'items': offset >= 6 ? [] : _range(offset + 1, offset + 3)}));
      });

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.offset, itemsPath: 'items', param: 'offset', totalPath: 'total'),
      );

      expect(server.urls.map((u) => u.queryParameters['offset']), [null, '3']);
      expect((_body(outcome) as Map)['items'], _range(1, 6));
    });

    // An Odoo search_read over JSON-2: the answer is a bare array and there is no total.
    FakeServer odoo(int records) => FakeServer((url, request, call) {
          final body = FakeServer.jsonBodyOf(request) as Map;
          final offset = body['offset'] as int? ?? 0;
          final limit = body['limit'] as int;
          return responded(jsonResponse([for (var i = offset; i < offset + limit && i < records; i++) {'id': i + 1}]));
        });

    test('an Odoo search_read pages by offset in the body and stops at a page shorter than the limit', () async {
      final server = odoo(7);

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.offset, itemsPath: '', param: 'offset', limitParam: 'limit', location: PageParamLocation.body),
        url: 'https://odoo.test/json/2/res.partner/search_read',
        method: HttpMethod.post,
        flow: const FlowSettings(repeatUnsafe: true),
        body: {'domain': <Object>[], 'fields': ['name'], 'limit': 3},
      );

      expect(server.requests, hasLength(3));
      expect([for (var i = 0; i < 3; i++) (server.bodyOf(i) as Map)['offset']], [null, 3, 6]);
      expect((_body(outcome) as List).map((r) => (r as Map)['id']), _range(1, 7));
      expect(outcome.report.pages!.stop, PaginationStop.lastPage);
      // The rest of the body (domain, fields, limit) is carried over on every page.
      expect((server.bodyOf(2) as Map)['fields'], ['name']);
    });

    test('when the last page is exactly full, one more request finds the empty page', () async {
      final server = odoo(6);

      final outcome = await run(
        server,
        const PaginationSettings(kind: PaginationKind.offset, itemsPath: '', param: 'offset', limitParam: 'limit', location: PageParamLocation.body),
        url: 'https://odoo.test/json/2/res.partner/search_read',
        method: HttpMethod.post,
        flow: const FlowSettings(repeatUnsafe: true),
        body: {'domain': <Object>[], 'limit': 3},
      );

      expect(server.requests, hasLength(3));
      expect(_body(outcome), hasLength(6));
      expect(outcome.report.pages!.stop, PaginationStop.emptyPage);
    });

    test('a JSON-RPC execute_kw keeps its offset in the kwargs, found by a path', () async {
      final server = FakeServer((url, request, call) {
        final body = FakeServer.jsonBodyOf(request) as Map;
        final kwargs = ((body['params'] as Map)['args'] as List)[6] as Map;
        final offset = kwargs['offset'] as int? ?? 0;
        return responded(jsonResponse({'jsonrpc': '2.0', 'id': 1, 'result': [for (var i = offset; i < offset + 2 && i < 3; i++) i]}));
      });

      final outcome = await run(
        server,
        const PaginationSettings(
          kind: PaginationKind.offset,
          itemsPath: 'result',
          param: 'params.args[6].offset',
          limitParam: 'params.args[6].limit',
          location: PageParamLocation.body,
        ),
        url: 'https://odoo.test/jsonrpc',
        method: HttpMethod.post,
        flow: const FlowSettings(repeatUnsafe: true),
        body: {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': ['db', 2, 'key', 'res.partner', 'search_read', [[]], {'limit': 2}],
          },
        },
      );

      expect((_body(outcome) as Map)['result'], [0, 1, 2]);
      expect(server.requests, hasLength(2));
    });
  });

  group('Odoo search_count', () {
    const strategy = PaginationSettings(
      kind: PaginationKind.offset,
      itemsPath: '',
      param: 'offset',
      limitParam: 'limit',
      location: PageParamLocation.body,
      countTotal: true,
    );
    const odooUrl = 'https://odoo.test/json/2/res.partner/search_read';
    final searchBody = {
      'domain': [
        ['active', '=', true],
      ],
      'fields': ['name'],
      'context': {'lang': 'en_US'},
      'limit': 3,
    };

    FakeServer odooWithCount(int records, {Object? count}) => FakeServer((url, request, call) {
          final body = FakeServer.jsonBodyOf(request) as Map;
          if (url.path.endsWith('/search_count')) {
            return count == null ? responded(jsonResponse(records)) : responded(count is int ? textResponse('', status: count) : jsonResponse(count));
          }
          final offset = body['offset'] as int? ?? 0;
          final limit = body['limit'] as int;
          return responded(jsonResponse([for (var i = offset; i < offset + limit && i < records; i++) {'id': i + 1}]));
        });

    Future<FlowOutcome> runOdoo(FakeServer server, {PaginationSettings settings = strategy, String url = odooUrl}) => run(
          server,
          settings,
          url: url,
          method: HttpMethod.post,
          flow: const FlowSettings(repeatUnsafe: true),
          body: searchBody,
        );

    test('asks the same model and domain how many there are, then numbers the pages and ends exactly at the last', () async {
      final server = odooWithCount(9);

      final outcome = await runOdoo(server);

      expect(server.urls.map((u) => u.path), [
        '/json/2/res.partner/search_read',
        '/json/2/res.partner/search_count',
        '/json/2/res.partner/search_read',
        '/json/2/res.partner/search_read',
      ]);
      expect(server.bodyOf(1), {
        'domain': [
          ['active', '=', true],
        ],
        'context': {'lang': 'en_US'},
      }, reason: 'the fields and the limit are not part of a count');
      expect(_body(outcome), hasLength(9));
      expect([for (final a in outcome.report.attempts) a.label], ['request', 'search_count', 'page 2/3', 'page 3/3']);
      expect(outcome.report.pages!.stop, PaginationStop.lastPage, reason: 'no request for an empty page after the last full one');
      expect(outcome.report.notes, isEmpty);
    });

    test('the count request is a POST to the same host with the same headers and authentication', () async {
      final server = odooWithCount(3);

      await runOdoo(server);

      expect(server.requests[1].method, HttpMethod.post);
      expect(server.requests[1].url, 'https://odoo.test/json/2/res.partner/search_count');
      expect(server.requests[1].headers, server.requests[0].headers);
      expect(server.requests[1].auth, server.requests[0].auth);
    });

    test('a count that cannot be read is a note, and the walk goes on by the short-page rule', () async {
      for (final broken in <Object?>[500, 'many', null]) {
        final server = FakeServer((url, request, call) {
          final body = FakeServer.jsonBodyOf(request) as Map;
          if (url.path.endsWith('/search_count')) {
            return broken == 500 ? responded(textResponse('', status: 500)) : responded(jsonResponse(broken ?? 'x'));
          }
          final offset = body['offset'] as int? ?? 0;
          return responded(jsonResponse([for (var i = offset; i < offset + 3 && i < 7; i++) {'id': i}]));
        });

        final outcome = await runOdoo(server);

        expect(_body(outcome), hasLength(7), reason: '$broken');
        expect(outcome.report.notes.single, contains('record count could not be read'), reason: '$broken');
        expect(outcome.report.pages!.stop, PaginationStop.lastPage, reason: '$broken');
        expect(outcome.report.failure, isNull, reason: '$broken');
      }
    });

    test('asked of anything but a JSON-2 search_read, it says so and does not count', () async {
      final server = FakeServer((url, request, call) {
        final body = FakeServer.jsonBodyOf(request) as Map;
        final offset = body['offset'] as int? ?? 0;
        return responded(jsonResponse([for (var i = offset; i < offset + 3 && i < 4; i++) i]));
      });

      final outcome = await runOdoo(server, url: 'https://odoo.test/web/dataset/call_kw/res.partner/search_read');

      expect(server.urls.map((u) => u.path).toSet(), {'/web/dataset/call_kw/res.partner/search_read'});
      expect(outcome.report.notes.single, contains('only for an Odoo JSON-2 search_read'));
    });

    test('a total the page itself gives wins over the count', () async {
      final server = FakeServer((url, request, call) {
        final body = FakeServer.jsonBodyOf(request) as Map;
        if (url.path.endsWith('/search_count')) return responded(jsonResponse(99));
        final offset = body['offset'] as int? ?? 0;
        return responded(jsonResponse({'length': 6, 'records': [for (var i = offset; i < offset + 3 && i < 6; i++) i]}));
      });

      final outcome = await runOdoo(server, settings: strategy.copyWith(itemsPath: 'records', totalPath: 'length'));

      expect(server.requests, hasLength(3), reason: 'the count, then two pages: 6 is where the page says it ends, not 99');
      expect(outcome.report.pages!.pages, 2);
    });

    test('a count does not change what an ordinary offset walk does', () async {
      final server = odooWithCount(7);

      final outcome = await runOdoo(server, settings: strategy.copyWith(countTotal: false));

      expect(server.urls.any((u) => u.path.endsWith('/search_count')), isFalse);
      expect(_body(outcome), hasLength(7));
    });
  });

  group('limits', () {
    FakeServer endless() => FakeServer((url, request, call) =>
        responded(jsonResponse({'items': [call], 'next': 'https://api.test/items?page=${call + 1}'})));

    const strategy = PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'items', nextPath: 'next');

    test('stops at the page limit and says the server has more', () async {
      final server = endless();

      final outcome = await run(server, strategy.copyWith(maxPages: 3));

      expect(server.requests, hasLength(3));
      final pages = outcome.report.pages!;
      expect((pages.pages, pages.stop, pages.complete), (3, PaginationStop.maxPages, false));
      expect(outcome.report.notes.single, contains('page limit'));
      expect((_body(outcome) as Map)['items'], [1, 2, 3]);
    });

    test('the default is 20 pages and no setting goes past 500', () async {
      final server = endless();

      await run(server, strategy);

      expect(server.requests, hasLength(20));
      expect(strategy.copyWith(maxPages: 100000).maxPages, 500);
      expect(PaginationSettings.fromJson({'maxPages': 100000}).maxPages, 500);
      expect(PaginationSettings.fromJson({'maxPages': 0}).maxPages, PaginationSettings.defaultMaxPages);
    });

    test('stops when the pages together pass the size limit, leaving that page out', () async {
      final big = 'x' * (600 * 1024);
      final server = FakeServer((url, request, call) =>
          responded(jsonResponse({'items': ['$big$call'], 'next': 'https://api.test/items?page=${call + 1}'})));

      final outcome = await run(server, strategy.copyWith(maxMegabytes: 1));

      expect(server.requests, hasLength(2));
      final pages = outcome.report.pages!;
      expect((pages.pages, pages.stop), (1, PaginationStop.sizeCap));
      expect(outcome.report.notes.single, contains('1 MB'));
      expect(((_body(outcome) as Map)['items'] as List), hasLength(1));
    });

    test('waits between pages as asked, and not before the first', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({
            'items': [call],
            'next': call < 3 ? 'https://api.test/items?page=${call + 1}' : null,
          })));

      await run(server, strategy.copyWith(delayMs: 250));

      expect(clock.waits, [250, 250]);
    });

    test('never follows a next-page link to another host, so credentials stay where they belong', () async {
      final server = FakeServer((url, request, call) =>
          responded(jsonResponse({'items': [call], 'next': 'https://evil.example/steal?page=2'})));

      final outcome = await run(server, strategy);

      expect(server.requests, hasLength(1));
      expect(outcome.report.pages!.stop, PaginationStop.crossOrigin);
      expect(outcome.report.notes.single, contains('evil.example'));
      expect(outcome.report.failure, isNull);
    });

    test('a link on the same host but another port or scheme is another origin too', () async {
      for (final next in ['https://api.test:8443/items?page=2', 'http://api.test/items?page=2']) {
        final server = FakeServer((url, request, call) => responded(jsonResponse({'items': [1], 'next': next})));

        final outcome = await run(server, strategy);

        expect(server.requests, hasLength(1), reason: next);
        expect(outcome.report.pages!.stop, PaginationStop.crossOrigin, reason: next);
      }
    });

    test('a link or token holding {{ is never used, so a response cannot pull a variable into the next request', () async {
      final link = FakeServer((url, request, call) =>
          responded(jsonResponse({'items': [1], 'next': 'https://api.test/items?k={{apiKey}}'})));
      final token = FakeServer((url, request, call) => responded(jsonResponse({'items': [1], 'cursor': '{{apiKey}}'})));

      final a = await run(link, strategy, variables: const {'apiKey': 'SECRET'});
      final b = await run(
        token,
        const PaginationSettings(kind: PaginationKind.cursor, itemsPath: 'items', nextPath: 'cursor', param: 'c'),
        variables: const {'apiKey': 'SECRET'},
      );

      expect(link.requests, hasLength(1));
      expect(token.requests, hasLength(1));
      expect(a.report.pages!.stop, PaginationStop.unreadable);
      expect(b.report.pages!.stop, PaginationStop.unreadable);
      expect(a.report.notes.single, isNot(contains('SECRET')));
    });
  });

  group('when it cannot go on', () {
    const strategy = PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'items', nextPath: 'next');
    FakeServer failingAt(int page, FlowExchange failure) => FakeServer((url, request, call) => call == page
        ? failure
        : responded(jsonResponse({'items': [call], 'next': call < 5 ? 'https://api.test/items?page=${call + 1}' : null})));

    test('a page that answers 500 fails the request, with what was fetched until then', () async {
      final server = failingAt(3, responded(textResponse('', status: 500)));

      final outcome = await run(server, strategy);

      expect(outcome.failed, isTrue);
      expect(outcome.report.failure, contains('Page 3 failed: HTTP 500'));
      expect(outcome.report.failure, contains('2 pages, 2 items'));
      expect((_body(outcome) as Map)['items'], [1, 2]);
      expect(outcome.error, isNull, reason: 'the first pages are a result');
      expect(outcome.report.pages!.stop, PaginationStop.failed);
    });

    test('a page that cannot be reached fails it the same way', () async {
      final server = failingAt(2, failed("Couldn't reach api.test"));

      final outcome = await run(server, strategy);

      expect(outcome.report.failure, contains("Page 2 failed: Couldn't reach api.test"));
      expect(outcome.report.failure, contains('1 page, 1 item'));
      expect((_body(outcome) as Map)['items'], [1]);
    });

    test('a page that is retried keeps going: retry applies to each page on its own', () async {
      var secondTries = 0;
      final server = FakeServer((url, request, call) {
        final page = int.parse(url.queryParameters['page'] ?? '1');
        if (page == 2 && secondTries++ == 0) return responded(textResponse('', status: 503));
        return responded(jsonResponse({'items': [page], 'next': page < 3 ? 'https://api.test/items?page=${page + 1}' : null}));
      });
      const retry = RetryPolicy(enabled: true, maxRetries: 2, backoff: BackoffKind.fixed, delayMs: 1000, jitter: false);

      final outcome = await run(server, strategy, flow: const FlowSettings(retry: retry));

      expect((_body(outcome) as Map)['items'], [1, 2, 3]);
      expect([for (final a in outcome.report.attempts) a.label], [
        'request',
        'page 2',
        'page 2, attempt 2/3 after 1 s',
        'page 3',
      ]);
      expect(outcome.report.retries, 1);
    });

    test('a first answer that is not a success is returned as it is, with a note', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('nope', status: 404)));

      final outcome = await run(server, strategy);

      expect(server.requests, hasLength(1));
      expect(outcome.response!.statusCode, 404);
      expect(outcome.report.pages, isNull);
      expect(outcome.report.notes.single, contains('HTTP 404'));
    });

    test('a first answer that is not JSON cannot be merged, and fails with the reason', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('<html>')));

      final outcome = await run(server, strategy);

      expect(outcome.report.failure, contains('not JSON'));
      expect(outcome.response!.statusCode, 200, reason: 'the response is still shown');
    });

    test('an items path that is not in the first answer fails with the path named', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'rows': [1]})));

      final outcome = await run(server, strategy);

      expect(outcome.report.failure, contains('"items"'));
      expect(outcome.report.failure, contains('Change the items path'));
      expect(server.requests, hasLength(1));
    });

    test('a strategy that is not filled in fails with what is missing', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'items': [1]})));

      final outcome = await run(server, const PaginationSettings(kind: PaginationKind.cursor, itemsPath: 'items'));

      expect(outcome.report.failure, contains('not set up'));
      expect(outcome.report.failure, contains('token'));
    });

    test('a later page without the items array ends the walk quietly', () async {
      final server = FakeServer((url, request, call) => call == 1
          ? responded(jsonResponse({'items': [1], 'next': 'https://api.test/items?page=2'}))
          : responded(jsonResponse({'oops': true})));

      final outcome = await run(server, strategy);

      expect(outcome.report.pages!.stop, PaginationStop.unreadable);
      expect(outcome.report.pages!.pages, 1);
      expect(outcome.report.failure, isNull);
      expect(outcome.report.notes.single, contains('Page 2 has no array'));
    });

    test('a POST is not paged without the tick, a PATCH neither', () async {
      for (final method in [HttpMethod.post, HttpMethod.patch]) {
        final server = FakeServer((url, request, call) =>
            responded(jsonResponse({'items': [1], 'next': 'https://api.test/items?page=2'})));

        final outcome = await run(server, strategy, method: method);

        expect(server.requests, hasLength(1), reason: method.label);
        expect(outcome.report.pages, isNull, reason: method.label);
        expect(outcome.report.notes.single, contains(method.label));
      }
    });
  });

  group('the merged response', () {
    const strategy = PaginationSettings(kind: PaginationKind.nextUrl, itemsPath: 'data.items', nextPath: 'next');

    test('is one response: the first page\'s status, headers and other fields, the items of every page, summed time', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse(
            {
              'meta': {'count': 99},
              'data': {'items': [call * 10, call * 10 + 1], 'kind': 'list'},
              'next': call < 3 ? 'https://api.test/items?page=${call + 1}' : null,
            },
            headers: {'Content-Type': 'application/json', 'Content-Length': '1', 'X-Page': '$call'},
            duration: Duration(milliseconds: 100 * call),
          )));

      final outcome = await run(server, strategy);
      final response = outcome.response!;
      final body = _body(outcome) as Map;

      expect(body['meta'], {'count': 99});
      expect((body['data'] as Map)['kind'], 'list');
      expect((body['data'] as Map)['items'], [10, 11, 20, 21, 30, 31]);
      expect(response.statusCode, 200);
      expect(response.headers['X-Page'], '1', reason: 'headers are the first page\'s');
      expect(response.headers['Content-Length'], '${response.bodyBytes.length}', reason: 'the stale length is replaced');
      expect(response.duration, const Duration(milliseconds: 600));
      expect(response.truncated, isFalse);
    });

    test('keeps the order of the items across pages', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({
            'data': {'items': [for (var i = 0; i < 4; i++) 'p$call-$i']},
            'next': call < 4 ? 'https://api.test/items?page=${call + 1}' : null,
          })));

      final outcome = await run(server, strategy);

      final items = ((_body(outcome) as Map)['data'] as Map)['items'] as List;
      expect(items, hasLength(16));
      expect(items.first, 'p1-0');
      expect(items[4], 'p2-0');
      expect(items.last, 'p4-3');
    });

    test('can be read by the assertions that poll uses, since it is an ordinary response', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({
            'data': {'items': [call]},
            'next': call < 2 ? 'https://api.test/items?page=2' : null,
          })));

      final outcome = await run(server, strategy);

      expect(outcome.response!.isSuccess, isTrue);
      expect(outcome.report.summary, '2 pages, 2 items');
      expect(outcome.report.isNoteworthy, isTrue);
    });

    test('a single page is still one page: nothing to fetch beyond it', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'data': {'items': [1, 2]}, 'next': null})));

      final outcome = await run(server, strategy);

      expect(server.requests, hasLength(1));
      expect(outcome.report.pages!.badge, '1 page, 2 items');
      expect(outcome.report.pages!.complete, isTrue);
    });
  });

  group('OdooCount.requestFor', () {
    ApiRequestEntity? countFor(ApiRequestEntity request, [Map<String, String> variables = const {}]) =>
        OdooCount.requestFor(request, VariableResolver(variables));

    test('turns a JSON-2 search_read into the search_count of the same model and domain, keeping the rest of the URL', () {
      final count = countFor(flowRequest(
        url: '{{baseUrl}}/json/2/res.partner/search_read?db=prod',
        method: HttpMethod.post,
        body: jsonBody({'domain': [['id', '>', 3]], 'fields': ['name'], 'limit': 5, 'offset': 10, 'order': 'id'}),
      ))!;

      expect(count.url, '{{baseUrl}}/json/2/res.partner/search_count?db=prod');
      expect(jsonDecode(count.body.rawText), {
        'domain': [['id', '>', 3]],
      });
    });

    test('reads a body that is only valid once its variables are filled in', () {
      final count = countFor(
        flowRequest(
          url: 'https://odoo.test/json/2/res.partner/search_read',
          method: HttpMethod.post,
          body: const RequestBody(type: BodyType.raw, rawText: '{"domain": {{domain}}, "limit": 3}'),
        ),
        const {'domain': '[["active","=",true]]'},
      )!;

      expect(jsonDecode(count.body.rawText), {
        'domain': [['active', '=', true]],
      });
    });

    test('is null for anything else: a GET, another method, another route, a body that is not JSON', () {
      const url = 'https://odoo.test/json/2/res.partner/search_read';
      expect(countFor(flowRequest(url: url, body: jsonBody({'domain': <Object>[]}))), isNull);
      expect(countFor(flowRequest(url: 'https://odoo.test/json/2/res.partner/search', method: HttpMethod.post, body: jsonBody({'domain': <Object>[]}))), isNull);
      expect(countFor(flowRequest(url: 'https://odoo.test/json/2/res.partner/search_read_group', method: HttpMethod.post, body: jsonBody({'domain': <Object>[]}))), isNull);
      expect(countFor(flowRequest(url: 'https://odoo.test/jsonrpc', method: HttpMethod.post, body: jsonBody({'domain': <Object>[]}))), isNull);
      expect(
        countFor(flowRequest(url: url, method: HttpMethod.post, body: const RequestBody(type: BodyType.raw, rawText: 'not json'))),
        isNull,
      );
      expect(countFor(flowRequest(url: url, method: HttpMethod.post)), isNull, reason: 'no raw body at all');
    });
  });
}
