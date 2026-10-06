// What the detector proposes for the first response of a paged API, one family of APIs at a time.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/pagination_detector.dart';
import 'flow_support.dart';

PaginationDetection? _detect(Object? json, {Map<String, String> headers = const {}, request}) =>
    PaginationDetector.detect(request ?? flowRequest(), jsonResponse(json, headers: headers));

PaginationSettings _found(Object? json, {Map<String, String> headers = const {}, request}) {
  final detection = _detect(json, headers: headers, request: request);
  expect(detection, isNotNull, reason: '$json');
  expect(detection!.settings.enabled, isFalse, reason: 'it proposes, the person confirms');
  return detection.settings;
}

void main() {
  group('a Link header', () {
    test('rel="next" on an array body', () {
      final settings = _found([1, 2], headers: {'Link': '<https://api.test/items?page=2>; rel="next"'});

      expect((settings.kind, settings.itemsPath), (PaginationKind.linkHeader, ''));
    });

    test('rel="next" on an object, with the items found under their usual name', () {
      final settings = _found({'data': [1]}, headers: {'link': '<https://api.test/items?page=2>; rel="next", <x>; rel="last"'});

      expect((settings.kind, settings.itemsPath), (PaginationKind.linkHeader, 'data'));
    });

    test('a Link with only a previous page is no sign of more', () {
      expect(_detect([1], headers: {'Link': '<https://api.test/items?page=1>; rel="prev"'}), isNull);
    });
  });

  group('a next-page URL in the body', () {
    test('`next`, `next_url`, `nextUrl` and `next_page_url` at the top', () {
      for (final key in ['next', 'next_url', 'nextUrl', 'next_page_url', 'nextLink']) {
        final settings = _found({'results': [1], key: 'https://api.test/items?page=2'});

        expect((settings.kind, settings.nextPath, settings.itemsPath), (PaginationKind.nextUrl, key, 'results'), reason: key);
      }
    });

    test('a relative URL counts', () {
      expect(_found({'items': [1], 'next': '/items?page=2'}).kind, PaginationKind.nextUrl);
    });

    test('inside meta or pagination', () {
      expect(_found({'data': [1], 'pagination': {'next_url': 'https://api.test/x'}}).nextPath, 'pagination.next_url');
      expect(_found({'data': [1], 'meta': {'next': 'https://api.test/x'}}).nextPath, 'meta.next');
    });

    test('OData: @odata.nextLink needs quoting in the path', () {
      final settings = _found({'value': [1], '@odata.nextLink': 'https://api.test/items?\$skip=1'});

      expect((settings.kind, settings.nextPath, settings.itemsPath), (PaginationKind.nextUrl, '["@odata.nextLink"]', 'value'));
    });

    test('HAL: _links.next.href', () {
      final settings = _found({'_embedded': {'orders': [{'id': 1}]}, '_links': {'next': {'href': '/orders?page=2'}}});

      expect((settings.kind, settings.nextPath, settings.itemsPath), (PaginationKind.nextUrl, '_links.next.href', '_embedded.orders'));
    });

    test('a has_more flag next to it is kept as the stop signal', () {
      final settings = _found({'items': [1], 'next': 'https://api.test/x', 'has_more': true});

      expect(settings.hasMorePath, 'has_more');
    });
  });

  group('a token', () {
    test('nextPageToken is sent back as pageToken', () {
      final settings = _found({'data': [1], 'nextPageToken': 'abc'});

      expect((settings.kind, settings.nextPath, settings.param, settings.location), (PaginationKind.cursor, 'nextPageToken', 'pageToken', PageParamLocation.query));
    });

    test('next_cursor and cursor are sent back as cursor', () {
      expect(_found({'items': [1], 'next_cursor': 'abc'}).param, 'cursor');
      expect(_found({'items': [1], 'cursor': 'abc'}).param, 'cursor');
      expect(_found({'items': [1], 'cursor': 42}).nextPath, 'cursor');
    });

    test('a `next` that is not a URL is a token', () {
      final settings = _found({'items': [1], 'next': 'c2VhcmNo'});

      expect((settings.kind, settings.nextPath, settings.param), (PaginationKind.cursor, 'next', 'cursor'));
    });

    test('a token that is null on the last page is still recognised', () {
      expect(_found({'items': [1], 'next_cursor': null}).kind, PaginationKind.cursor);
    });

    test('with has_more beside it', () {
      final settings = _found({'items': [1], 'next_cursor': 'x', 'has_more': true});

      expect((settings.kind, settings.hasMorePath), (PaginationKind.cursor, 'has_more'));
    });

    test('goes in the JSON body when the request already has that key there', () {
      final request = flowRequest(method: HttpMethod.post, body: jsonBody({'cursor': null, 'limit': 5}));

      final settings = _found({'items': [1], 'next_cursor': 'x'}, request: request);

      // The request has a `cursor` key but the detector looked for `cursor` as the parameter name: body it is.
      expect(settings.location, PageParamLocation.body);
    });
  });

  group('a page number', () {
    test('page with total_pages', () {
      final settings = _found({'page': 1, 'total_pages': 9, 'results': [1]});

      expect((settings.kind, settings.param, settings.totalPath, settings.firstPage), (PaginationKind.page, 'page', 'total_pages', 1));
    });

    test('inside meta, and under the other usual names', () {
      final settings = _found({'data': [1], 'meta': {'currentPage': 2, 'totalPages': 5}});

      expect((settings.kind, settings.totalPath), (PaginationKind.page, 'meta.totalPages'));
      expect(_found({'items': [1], 'pageNumber': 1, 'pageCount': 3}).param, 'pageNumber');
    });

    test('an API that answers page 0 counts from 0', () {
      expect(_found({'page': 0, 'total_pages': 3, 'items': [1]}).firstPage, 0);
    });

    test('page with has_more and no total', () {
      final settings = _found({'page': 1, 'has_more': true, 'items': [1]});

      expect((settings.kind, settings.totalPath, settings.hasMorePath), (PaginationKind.page, '', 'has_more'));
    });

    test('a bare `page` with nothing to tell where it ends is not enough', () {
      expect(_detect({'page': 1, 'items': [1]}), isNull);
    });
  });

  group('an offset', () {
    test('offset, limit and total', () {
      final request = flowRequest(queryParams: [KeyValueItem(key: 'limit', value: '20')]);

      final settings = _found({'offset': 0, 'limit': 20, 'total': 95, 'items': [1]}, request: request);

      expect(
        (settings.kind, settings.param, settings.limitParam, settings.totalPath, settings.location),
        (PaginationKind.offset, 'offset', 'limit', 'total', PageParamLocation.query),
      );
    });

    test('the limit is only followed when the request sets it itself', () {
      final settings = _found({'offset': 0, 'limit': 20, 'total': 95, 'items': [1]});

      expect(settings.limitParam, '');
    });

    test('skip and total_count work the same', () {
      final settings = _found({'skip': 0, 'total_count': 50, 'items': [1]});

      expect((settings.kind, settings.param, settings.totalPath), (PaginationKind.offset, 'skip', 'total_count'));
    });

    test('an offset in a JSON body is written there', () {
      final request = flowRequest(method: HttpMethod.post, body: jsonBody({'offset': 0, 'limit': 10}));

      final settings = _found({'offset': 0, 'limit': 10, 'total': 30, 'items': [1]}, request: request);

      expect((settings.location, settings.limitParam), (PageParamLocation.body, 'limit'));
    });
  });

  group('Odoo search_read', () {
    PaginationDetection? odoo(String url, Object body, [Object? response]) => PaginationDetector.detect(
          flowRequest(url: url, method: HttpMethod.post, body: jsonBody(body)),
          jsonResponse(response ?? <Object>[]),
        );

    test('JSON-2 with a limit pages by offset in the body, and is a read', () {
      final detection = odoo('https://odoo.test/json/2/res.partner/search_read', {'domain': <Object>[], 'fields': ['name'], 'limit': 80})!;
      final settings = detection.settings;

      expect(
        (settings.kind, settings.location, settings.param, settings.limitParam, settings.itemsPath, settings.totalPath),
        (PaginationKind.offset, PageParamLocation.body, 'offset', 'limit', '', ''),
      );
      expect(detection.readOnlyPost, isTrue);
      expect(detection.summary, contains('offset'));
      expect(settings.countTotal, isTrue, reason: 'JSON-2 has a search_count to ask');
      expect(detection.summary, contains('search_count'));
    });

    test('without a limit it returns everything, so there is nothing to page', () {
      expect(odoo('https://odoo.test/json/2/res.partner/search_read', {'domain': <Object>[]}), isNull);
      expect(odoo('https://odoo.test/json/2/res.partner/search_read', {'limit': 0}), isNull);
    });

    test('another JSON-2 method is not detected', () {
      expect(odoo('https://odoo.test/json/2/res.partner/search', {'limit': 5}), isNull);
    });

    test('JSON-RPC execute_kw keeps the offset in the kwargs', () {
      final settings = odoo('https://odoo.test/jsonrpc', {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': ['db', 2, 'key', 'res.partner', 'search_read', [[]], {'fields': ['name'], 'limit': 10}],
        },
      })!
          .settings;

      expect((settings.param, settings.limitParam, settings.itemsPath), ('params.args[6].offset', 'params.args[6].limit', 'result'));
      expect(settings.countTotal, isFalse, reason: 'only JSON-2 is counted');
    });

    test('JSON-RPC call_kw keeps it in params.kwargs', () {
      final settings = odoo('https://odoo.test/web/dataset/call_kw/res.partner/search_read', {
        'params': {'model': 'res.partner', 'method': 'search_read', 'args': [[]], 'kwargs': {'limit': 5}},
      })!
          .settings;

      expect((settings.param, settings.itemsPath), ('params.kwargs.offset', 'result'));
    });

    test('/web/dataset/search_read answers with records and a length', () {
      final settings = odoo('https://odoo.test/web/dataset/search_read', {
        'params': {'model': 'res.partner', 'domain': <Object>[], 'limit': 40},
      })!
          .settings;

      expect((settings.param, settings.itemsPath, settings.totalPath), ('params.offset', 'result.records', 'result.length'));
    });

    test('an execute_kw call of another method is not detected', () {
      expect(
        odoo('https://odoo.test/jsonrpc', {
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': ['db', 2, 'key', 'res.partner', 'write', [[1]], {'limit': 2}],
          },
        }),
        isNull,
      );
    });
  });

  group('where the items are', () {
    test('a top-level array', () {
      expect(_found([{'id': 1}], headers: {'Link': '<x>; rel="next"'}).itemsPath, '');
    });

    test('the usual names, then an array of objects wherever it is', () {
      expect(_found({'records': [1], 'next': '/x'}).itemsPath, 'records');
      expect(_found({'payload': {'items': [1]}, 'next': '/x'}).itemsPath, 'payload.items');
      expect(_found({'things': [{'a': 1}], 'tags': ['x'], 'next': '/x'}).itemsPath, 'things');
      expect(_found({'wrapper': {'rows2': [{'a': 1}]}, 'next': '/x'}).itemsPath, 'wrapper.rows2');
    });

    test('the largest array of objects wins when no name is usual', () {
      expect(_found({'a': [{'x': 1}], 'b': [{'x': 1}, {'x': 2}], 'next': '/x'}).itemsPath, 'b');
    });
  });

  group('nothing to find', () {
    test('a plain object, an empty list, a body that is not JSON', () {
      expect(_detect({'id': 1, 'name': 'Ada'}), isNull);
      expect(_detect([]), isNull);
      expect(PaginationDetector.detect(flowRequest(), textResponse('<html>')), isNull);
      expect(_detect({'items': [1]}), isNull, reason: 'items alone say nothing about more pages');
    });

    test('a next field that is empty is a token field with nothing in it', () {
      expect(_detect({'items': [1], 'next': ''})?.settings.kind, PaginationKind.cursor);
    });
  });

  group('the proposal is a usable strategy', () {
    test('every detected strategy passes its own check', () {
      final proposals = [
        _detect([1], headers: {'Link': '<x>; rel="next"'}),
        _detect({'items': [1], 'next': '/x'}),
        _detect({'items': [1], 'next_cursor': 'a'}),
        _detect({'items': [1], 'page': 1, 'total_pages': 2}),
        _detect({'items': [1], 'offset': 0, 'total': 4}),
      ];

      for (final proposal in proposals) {
        expect(proposal, isNotNull);
        expect(proposal!.settings.problem, isNull, reason: proposal.summary);
        expect(proposal.summary, isNotEmpty);
      }
    });
  });
}
