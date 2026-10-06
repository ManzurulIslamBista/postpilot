// The OpenAPI side of the mock server, without a socket: routing, fake answers, request validation, the stateful
// resources (create, read, replace, patch, delete, reset), paging and filtering. Every expectation is worked out from
// shop_openapi_fixture.dart by hand: ids count up from 1, `limit` defaults to 5 for users and 4 for products, and so on.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_pagination.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec_handler.dart';
import 'shop_openapi_fixture.dart';

const _base = '/api/v1';

MockSpecHandler _handler({
  String? document,
  int seed = 1,
  int items = 10,
  MockPaginationStrategy pagination = MockPaginationStrategy.auto,
  bool validate = true,
}) =>
    MockSpecHandler(MockSpec.parse(document ?? shopOpenApiJson), seed: seed, seedCount: items, pagination: pagination, validateRequests: validate);

MockResponse _call(
  MockSpecHandler handler,
  String method,
  String path, {
  Map<String, List<String>> query = const {},
  Map<String, String> headers = const {},
  Object? json,
  String? text,
}) {
  final match = handler.match(method, path);
  if (match == null) throw StateError('no route for $method $path');
  return handler.respond(
    match,
    MockRequest(method: method, path: path, query: query, headers: headers, body: text ?? (json == null ? '' : jsonEncode(json))),
  );
}

Map<String, dynamic> _map(MockResponse r) => jsonDecode(r.body) as Map<String, dynamic>;
List<dynamic> _list(MockResponse r) => jsonDecode(r.body) as List<dynamic>;
List<int> _ids(MockResponse r) => [for (final u in (_map(r)['data'] as List)) (u as Map)['id'] as int];

void main() {
  group('routing', () {
    final h = _handler();

    test('matches under the document\'s base path, and without it', () {
      expect(h.match('GET', '$_base/users')!.key, 'GET /users');
      expect(h.match('GET', '/users')!.key, 'GET /users', reason: 'a client that was given the host only still gets its answer');
      expect(h.match('PATCH', '$_base/users'), isNull);
      expect(h.match('GET', '$_base/nothing'), isNull);
    });

    test('a static segment beats a parameter, parameters are captured', () {
      expect(h.match('GET', '$_base/users/me')!.key, 'GET /users/me');
      final one = h.match('GET', '$_base/users/5')!;
      expect(one.key, 'GET /users/:id');
      expect(one.pathParams, {'id': '5'});
      final order = h.match('GET', '$_base/users/5/orders/9')!;
      expect(order.pathParams, {'userId': '5', 'orderId': '9'});
      expect(h.match('GET', '$_base/users/a%20b')!.pathParams, {'id': 'a b'});
    });

    test('methodsFor lists what the path answers, for a 405', () {
      expect(h.methodsFor('$_base/users'), unorderedEquals(['GET', 'POST']));
      expect(h.methodsFor('$_base/users/1'), unorderedEquals(['GET', 'PUT', 'PATCH', 'DELETE']));
      expect(h.methodsFor('$_base/nothing'), isEmpty);
    });

    test('the route list names parameters with a colon and shows the base path', () {
      final byKey = {for (final r in h.routes) r.key: r};
      expect(byKey['GET /users/:id']!.path, '/api/v1/users/:id');
      expect(byKey['GET /users/:id']!.title, 'One user');
      expect(byKey['POST /users']!.status, 201);
      expect(byKey['GET /users']!.note, 'stateful');
      expect(byKey['GET /stats']!.note, '');
    });
  });

  group('paging a list wrapped in an envelope', () {
    test('page 1 of the users: the first five, with the meta the schema asks for', () {
      final r = _call(_handler(), 'GET', '$_base/users');
      expect(r.status, 200);
      expect(r.isJson, isTrue);
      final body = _map(r);
      expect(_ids(r), [1, 2, 3, 4, 5]);
      expect(body['total'], 10);
      expect(body['page'], 1);
      expect(body['limit'], 5);
      expect(body['totalPages'], 2);
      expect(r.headers['x-total-count'], '10');
      expect(r.headers['link'], allOf(contains('rel="next"'), contains('page=2'), isNot(contains('rel="prev"'))));
    });

    test('page 2 is the rest, and points back', () {
      final r = _call(_handler(), 'GET', '$_base/users', query: {'page': ['2']});
      expect(_ids(r), [6, 7, 8, 9, 10]);
      expect(_map(r)['page'], 2);
      expect(r.headers['link'], allOf(contains('rel="prev"'), isNot(contains('rel="next"'))));
    });

    test('the limit parameter sets the page size, and the schema maximum caps it', () {
      final h = _handler();
      final three = _call(h, 'GET', '$_base/users', query: {'limit': ['3'], 'page': ['2']});
      expect(_ids(three), [4, 5, 6]);
      expect(_map(three)['totalPages'], 4);
      final capped = _call(h, 'GET', '$_base/users', query: {'limit': ['100']});
      expect(_map(capped)['limit'], 20, reason: 'maximum: 20');
      expect(_ids(capped), hasLength(10));
    });

    test('a page past the end is empty, not an error', () {
      final r = _call(_handler(), 'GET', '$_base/users', query: {'page': ['9']});
      expect(_ids(r), isEmpty);
      expect(_map(r)['total'], 10);
    });

    test('forced strategies: page, offset and no paging, whatever the document declares', () {
      final page = _call(_handler(pagination: MockPaginationStrategy.page), 'GET', '$_base/products', query: {'page': ['2'], 'limit': ['3']});
      expect([for (final p in _list(page)) (p as Map)['sku']], hasLength(3));
      expect(page.headers['link'], allOf(contains('page=3'), contains('rel="prev"')));
      final offset = _call(_handler(pagination: MockPaginationStrategy.offset), 'GET', '$_base/products', query: {'offset': ['8'], 'limit': ['5']});
      expect(_list(offset), hasLength(2), reason: 'only ten items, from the ninth on');
      final none = _call(_handler(pagination: MockPaginationStrategy.none), 'GET', '$_base/products', query: {'limit': ['2']});
      expect(_list(none), hasLength(10));
      expect(none.headers.containsKey('x-total-count'), isFalse);
    });
  });

  group('cursor paging of a plain list', () {
    test('following the next link visits every product once', () {
      final h = _handler();
      final seen = <String>[];
      var query = <String, List<String>>{};
      var pages = 0;
      while (true) {
        final r = _call(h, 'GET', '$_base/products', query: query);
        pages++;
        seen.addAll([for (final p in _list(r)) (p as Map)['sku'] as String]);
        final next = RegExp(r'cursor=([^&>]+)').firstMatch(r.headers['link'] ?? '');
        if (!(r.headers['link'] ?? '').contains('rel="next"') || next == null) break;
        query = {'cursor': [Uri.decodeQueryComponent(next[1]!)]};
        expect(pages, lessThan(10), reason: 'must terminate');
      }
      // Ten products, four to a page.
      expect(pages, 3);
      expect(seen, hasLength(10));
      expect(seen.toSet(), hasLength(10));
    });

    test('a cursor is an opaque token that round trips, and a foreign one means the start', () {
      expect(MockPagination.decodeCursor(MockPagination.encodeCursor(40)), 40);
      expect(MockPagination.encodeCursor(40), isNot(contains('40')));
      expect(MockPagination.decodeCursor('not-a-cursor!'), 0);
      expect(MockPagination.decodeCursor(null), 0);
      expect(MockPagination.decodeCursor(''), 0);
    });

    test('products come with sku in the declared pattern and two tags', () {
      final r = _call(_handler(), 'GET', '$_base/products');
      expect(_list(r), hasLength(4));
      for (final p in _list(r).cast<Map>()) {
        expect(p['sku'], matches(RegExp(r'^[A-Z]{3}-\d{4}$')));
        expect(p['tags'], hasLength(2));
        expect(p['category'], isIn(['books', 'games']));
      }
    });
  });

  group('filtering', () {
    test('a query parameter that names a field keeps the items whose field equals it', () {
      final h = _handler();
      final all = _call(h, 'GET', '$_base/users', query: {'limit': ['20']});
      final everyone = (_map(all)['data'] as List).cast<Map>();
      final admins = everyone.where((u) => u['role'] == 'admin').length;
      final filtered = _call(h, 'GET', '$_base/users', query: {'limit': ['20'], 'role': ['admin']});
      expect((_map(filtered)['data'] as List).cast<Map>().every((u) => u['role'] == 'admin'), isTrue);
      expect(_map(filtered)['total'], admins);
      expect(admins, inInclusiveRange(1, 9), reason: 'the fake roles alternate: both exist among ten users');
      // Two values are either/or; a value nobody has is an empty list.
      final both = _call(h, 'GET', '$_base/users', query: {'limit': ['20'], 'role': ['admin', 'member']});
      expect(_map(both)['total'], 10);
      final none = _call(h, 'GET', '$_base/users', query: {'role': ['nonexistent']});
      expect(_map(none)['total'], 0);
      expect(_ids(none), isEmpty);
    });

    test('a parameter that names no field filters nothing', () {
      final r = _call(_handler(), 'GET', '$_base/users', query: {'colour': ['green']});
      expect(_map(r)['total'], 10);
    });

    test('filtering happens before paging, and by a text value for booleans and numbers', () {
      final h = _handler();
      final all = (_map(_call(h, 'GET', '$_base/users', query: {'limit': ['20']}))['data'] as List).cast<Map>();
      final age = all.first['age'];
      final same = all.where((u) => u['age'] == age).length;
      final r = _call(h, 'GET', '$_base/users', query: {'age': ['$age']});
      expect(_map(r)['total'], same);
    });
  });

  group('checking the request against the operation', () {
    final h = _handler();

    test('a query parameter of the wrong type answers 400 in the document\'s own error shape', () {
      final r = _call(h, 'GET', '$_base/users', query: {'page': ['abc']});
      expect(r.status, 400);
      final body = _map(r);
      // The Error schema of the document: code, message and a list of details.
      expect(body.keys, unorderedEquals(['code', 'message', 'details']));
      expect(body['code'], 400);
      expect(body['message'], 'query.page: must be an integer, got "abc"');
      expect(body['details'], [
        {'field': 'query.page', 'message': 'must be an integer, got "abc"'},
      ]);
    });

    test('missing required body fields: each one is listed', () {
      final r = _call(h, 'POST', '$_base/users', json: <String, dynamic>{});
      expect(r.status, 400);
      final body = _map(r);
      expect(body['message'], r'$.name: is required (and 1 more)');
      expect([for (final d in body['details'] as List) (d as Map)['field']], [r'$.name', r'$.email']);
    });

    test('limits and enums in the body', () {
      Map<String, dynamic> post(Map<String, dynamic> user) => _map(_call(h, 'POST', '$_base/users', json: user));
      expect(post({'name': 'A', 'email': 'a@b.c'})['message'], r'$.name: must be at least 2 characters');
      expect(post({'name': 'Ann', 'email': 'a@b.c', 'age': 5})['message'], r'$.age: must be at least 18');
      expect(post({'name': 'Ann', 'email': 'a@b.c', 'role': 'root'})['message'], r'$.role: must be one of admin, member');
      expect(post({'name': 'Ann', 'email': 'a@b.c', 'age': 'old'})['message'], r'$.age: must be an integer');
      expect(post({'name': 'Ann', 'email': 'a@b.c', 'tags': 'x'})['message'], r'$.tags: must be an array');
      // `null` is fine for the nullable nickname, and an unknown property is not rejected.
      expect(_call(h, 'POST', '$_base/users', json: {'name': 'Ann', 'email': 'a@b.c', 'nickname': null, 'extra': 1}).status, 201);
    });

    test('a body that is not JSON, and a missing required body', () {
      expect(_map(_call(h, 'POST', '$_base/users', text: 'abc'))['message'], r'$: the request body is not valid JSON');
      expect(_map(_call(h, 'POST', '$_base/users'))['message'], r'$: a request body is required');
    });

    test('a path parameter of the wrong type', () {
      final r = _call(h, 'GET', '$_base/users/abc');
      expect(r.status, 400);
      expect(_map(r)['message'], 'path.id: must be an integer, got "abc"');
    });

    test('required query and header parameters, and their limits', () {
      final r = _call(h, 'GET', '$_base/search');
      expect(r.status, 400);
      expect([for (final d in _map(r)['details'] as List) (d as Map)['field']], ['query.q', 'header.X-Tenant']);
      expect(_map(_call(h, 'GET', '$_base/search', query: {'q': ['a']}, headers: {'X-Tenant': 't'}))['message'], 'query.q: must be at least 2 characters');
      expect(_map(_call(h, 'GET', '$_base/search', query: {'q': ['ab'], 'size': ['100']}, headers: {'x-tenant': 't'}))['message'], 'query.size: must be at most 50');
      final ok = _call(h, 'GET', '$_base/search', query: {'q': ['ab']}, headers: {'x-tenant': 'acme'});
      expect(ok.status, 200);
      expect(_map(ok)['hits'], hasLength(3));
    });

    test('an operation that declares no error uses the error schema of another one', () {
      // listProducts declares no 400; the document's Error schema (declared elsewhere) gives the shape.
      final r = _call(h, 'GET', '$_base/products', query: {'limit': ['x']});
      expect(r.status, 400);
      expect(_map(r).keys, unorderedEquals(['code', 'message', 'details']));
      expect(_map(r)['code'], 400);
    });

    test('with checking off, anything is accepted', () {
      final loose = _handler(validate: false);
      expect(_call(loose, 'POST', '$_base/users', json: <String, dynamic>{}).status, 201);
      expect(_call(loose, 'GET', '$_base/users', query: {'page': ['abc']}).status, 200);
    });

    test('a document with no error schema gets a plain error body', () {
      final doc = jsonEncode({
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'paths': {
          '/x': {
            'post': {
              'requestBody': {
                'required': true,
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'required': ['a'],
                      'properties': {
                        'a': {'type': 'string'},
                      },
                    },
                  },
                },
              },
              'responses': {
                '200': {'description': 'ok'},
              },
            },
          },
        },
      });
      final r = _call(_handler(document: doc), 'POST', '/x', json: <String, dynamic>{});
      expect(r.status, 400);
      expect(_map(r), {
        'error': 'Bad Request',
        'message': r'$.a: is required',
        'status': 400,
        'details': [
          {'field': r'$.a', 'message': 'is required'},
        ],
      });
    });

    test('the status is 422 when that is the one the document declares', () {
      final doc = jsonEncode({
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'paths': {
          '/x': {
            'get': {
              'parameters': [
                {'name': 'n', 'in': 'query', 'required': true, 'schema': {'type': 'integer'}},
              ],
              'responses': {
                '200': {'description': 'ok'},
                '422': {
                  'description': 'bad',
                  'content': {
                    'application/json': {
                      'schema': {
                        'type': 'object',
                        'properties': {
                          'title': {'type': 'string'},
                          'detail': {'type': 'string'},
                          'errors': {'type': 'array', 'items': {'type': 'string'}},
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      });
      final r = _call(_handler(document: doc), 'GET', '/x');
      expect(r.status, 422);
      expect(_map(r)['title'], 'Unprocessable Entity');
      expect(_map(r)['detail'], 'query.n: is required');
      expect(_map(r)['errors'], ['query.n: is required']);
    });
  });

  group('stateful resources: users', () {
    test('create, read, replace, patch and delete, each visible in the next call', () {
      final h = _handler();
      Map<String, dynamic> user(int id) => _map(_call(h, 'GET', '$_base/users/$id'));

      // POST: a generated id (the highest was 10), the body on top of fake data, no write-only property in the answer.
      final created = _call(h, 'POST', '$_base/users', json: {'name': 'Zed', 'email': 'zed@x.io', 'age': 30, 'password': 'hunter2'});
      expect(created.status, 201);
      final zed = _map(created);
      expect(zed['id'], 11);
      expect([zed['name'], zed['email'], zed['age']], ['Zed', 'zed@x.io', 30]);
      expect(zed.containsKey('password'), isFalse);
      expect(DateTime.tryParse(zed['createdAt'] as String), isNotNull);

      // GET one and the list reflect it.
      expect(user(11)['name'], 'Zed');
      final list = _call(h, 'GET', '$_base/users', query: {'page': ['3'], 'limit': ['5']});
      expect(_ids(list), [11]);
      expect(_map(list)['total'], 11);
      expect(_map(_call(h, 'GET', '$_base/users', query: {'limit': ['20']})).toString().contains('hunter2'), isFalse);

      // PUT replaces, keeping the id.
      final put = _call(h, 'PUT', '$_base/users/11', json: {'name': 'Zed Z', 'email': 'z@x.io'});
      expect(put.status, 200);
      expect([_map(put)['id'], _map(put)['name'], _map(put)['email']], [11, 'Zed Z', 'z@x.io']);
      expect(user(11)['name'], 'Zed Z');

      // PATCH merges.
      final patch = _call(h, 'PATCH', '$_base/users/11', json: {'age': 41});
      expect([_map(patch)['age'], _map(patch)['name']], [41, 'Zed Z']);
      expect(user(11)['age'], 41);

      // DELETE answers 204 with no body, and the item is gone.
      final deleted = _call(h, 'DELETE', '$_base/users/11');
      expect(deleted.status, 204);
      expect(deleted.body, isEmpty);
      final gone = _call(h, 'GET', '$_base/users/11');
      expect(gone.status, 404);
      expect(_map(gone)['code'], 404);
      expect(_map(gone)['message'], 'No user with id "11".');
      expect(_map(_call(h, 'GET', '$_base/users'))['total'], 10);
    });

    test('deleting from the middle leaves a gap that is not reused; a new item gets the next number up', () {
      final h = _handler();
      expect(_call(h, 'DELETE', '$_base/users/3').status, 204);
      expect(_ids(_call(h, 'GET', '$_base/users')), [1, 2, 4, 5, 6]);
      expect(_map(_call(h, 'GET', '$_base/users'))['total'], 9);
      final created = _map(_call(h, 'POST', '$_base/users', json: {'name': 'Ann', 'email': 'a@b.c'}));
      expect(created['id'], 11);
      expect(_call(h, 'GET', '$_base/users/3').status, 404);
    });

    test('an unknown id is a 404 for GET, PUT, PATCH and DELETE', () {
      final h = _handler();
      expect(_call(h, 'GET', '$_base/users/99').status, 404);
      expect(_call(h, 'PUT', '$_base/users/99', json: {'name': 'Ann', 'email': 'a@b.c'}).status, 404);
      expect(_call(h, 'PATCH', '$_base/users/99', json: {'age': 20}).status, 404);
      expect(_call(h, 'DELETE', '$_base/users/99').status, 404);
    });

    test('PATCH may send just a few fields; the required ones are only for POST and PUT', () {
      final h = _handler();
      expect(_call(h, 'PATCH', '$_base/users/2', json: {'age': 22}).status, 200);
      expect(_call(h, 'PUT', '$_base/users/2', json: {'age': 22}).status, 400);
    });

    test('reset puts everything back to the starting data', () {
      final h = _handler();
      _call(h, 'POST', '$_base/users', json: {'name': 'Ann', 'email': 'a@b.c'});
      _call(h, 'DELETE', '$_base/users/1');
      expect(h.store.itemCount, 10);
      h.resetData();
      expect(h.store.itemCount, 0, reason: 'seeded again on the next request');
      expect(_ids(_call(h, 'GET', '$_base/users')), [1, 2, 3, 4, 5]);
      expect(_call(h, 'GET', '$_base/users/11').status, 404);
    });

    test('the number of starting items is a setting', () {
      expect(_map(_call(_handler(items: 0), 'GET', '$_base/users'))['total'], 0);
      expect(_map(_call(_handler(items: 0), 'POST', '$_base/users', json: {'name': 'Ann', 'email': 'a@b.c'}))['id'], 1);
      expect(_map(_call(_handler(items: 3), 'GET', '$_base/users'))['total'], 3);
    });

    test('the same seed starts with the same users, another seed with others', () {
      final a = _call(_handler(seed: 4), 'GET', '$_base/users').body;
      expect(_call(_handler(seed: 4), 'GET', '$_base/users').body, a);
      expect(_call(_handler(seed: 5), 'GET', '$_base/users').body, isNot(a));
    });

    test('each user is a valid User: id, createdAt, required fields, and no password', () {
      for (final u in (_map(_call(_handler(), 'GET', '$_base/users'))['data'] as List).cast<Map>()) {
        expect(u['id'], isA<int>());
        expect(u['name'], isA<String>());
        expect(u['email'], contains('@'));
        expect(u['age'], inInclusiveRange(18, 80));
        expect(u.containsKey('password'), isFalse);
      }
    });
  });

  group('stateful resources: nested and text-keyed', () {
    test('orders belong to their user: each parent has its own list', () {
      final h = _handler();
      final first = _call(h, 'GET', '$_base/users/1/orders');
      expect([for (final o in _list(first)) (o as Map)['id']], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(first.headers.containsKey('x-total-count'), isFalse, reason: 'no paging parameters declared');

      final created = _call(h, 'POST', '$_base/users/1/orders', json: {'total': 20});
      expect(created.status, 201);
      expect([_map(created)['id'], _map(created)['total'], _map(created)['currency']], [11, 20, 'EUR']);
      expect(_list(_call(h, 'GET', '$_base/users/1/orders')), hasLength(11));
      expect(_list(_call(h, 'GET', '$_base/users/2/orders')), hasLength(10));
      expect(_call(h, 'GET', '$_base/users/1/orders/11').status, 200);
      expect(_call(h, 'GET', '$_base/users/1/orders/3').status, 200);
      expect(_call(h, 'GET', '$_base/users/2/orders/11').status, 404);
      expect(_call(h, 'POST', '$_base/users/1/orders', json: <String, dynamic>{}).status, 400, reason: 'total is required');
    });

    test('products are found by their sku and removed by it', () {
      final h = _handler();
      final skus = [for (final p in _list(_call(h, 'GET', '$_base/products'))) (p as Map)['sku'] as String];
      expect(skus, hasLength(4));
      final one = _call(h, 'GET', '$_base/products/${skus[1]}');
      expect(one.status, 200);
      expect(_map(one)['sku'], skus[1]);
      expect(_call(h, 'DELETE', '$_base/products/${skus[1]}').status, 204);
      expect(_call(h, 'GET', '$_base/products/${skus[1]}').status, 404);
      expect(_call(h, 'GET', '$_base/products/ZZZ-0000').status, 404);

      final created = _call(h, 'POST', '$_base/products', json: {'title': 'New book', 'category': 'books'});
      expect(created.status, 201);
      expect(_map(created)['sku'], matches(RegExp(r'^[A-Z]{3}-\d{4}$')));
      expect(_map(created)['title'], 'New book');
      expect(_call(h, 'GET', '$_base/products').headers['x-total-count'], '10', reason: '10 - 1 + 1');
    });

    test('products filtered by category', () {
      final r = _call(_handler(), 'GET', '$_base/products', query: {'category': ['books'], 'limit': ['10']});
      expect(_list(r), isNotEmpty);
      expect(_list(r).every((p) => (p as Map)['category'] == 'books'), isTrue);
    });
  });

  group('operations that are not part of a resource', () {
    test('the example of the document is the answer', () {
      final r = _call(_handler(), 'GET', '$_base/users/me');
      expect(_map(r), {'id': 99, 'name': 'Me Myself', 'email': 'me@shop.test', 'role': 'admin'});
    });

    test('a fake of the schema within its limits, the same on every call', () {
      final h = _handler();
      final first = _map(_call(h, 'GET', '$_base/stats'));
      expect(first['visitors'], inInclusiveRange(100, 200));
      expect(first['revenue'], inInclusiveRange(10, 20));
      expect(first['online'], isA<bool>());
      expect(_call(h, 'GET', '$_base/stats').body, jsonEncode(first));
      expect(_call(_handler(seed: 2), 'GET', '$_base/stats').body, isNot(jsonEncode(first)));
    });

    test('an answer without a body is empty', () {
      final r = _call(_handler(), 'GET', '$_base/ping');
      expect(r.status, 204);
      expect(r.body, isEmpty);
    });

    test('a fake object whose property is named like the path parameter echoes it', () {
      final doc = jsonEncode({
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'paths': {
          '/things/{thingId}': {
            'get': {
              'parameters': [
                {'name': 'thingId', 'in': 'path', 'required': true, 'schema': {'type': 'integer'}},
              ],
              'responses': {
                '200': {
                  'description': 'ok',
                  'content': {
                    'application/json': {
                      'schema': {
                        'type': 'object',
                        'properties': {
                          'thingId': {'type': 'integer'},
                          'name': {'type': 'string'},
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      });
      expect(_map(_call(_handler(document: doc), 'GET', '/things/42'))['thingId'], 42);
    });

    test('text/plain answers are text, not JSON', () {
      final doc = jsonEncode({
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'paths': {
          '/robots': {
            'get': {
              'responses': {
                '200': {
                  'description': 'ok',
                  'content': {
                    'text/plain': {
                      'schema': {'type': 'string', 'example': 'User-agent: *'},
                    },
                  },
                },
              },
            },
          },
        },
      });
      final r = _call(_handler(document: doc), 'GET', '/robots');
      expect(r.body, 'User-agent: *');
      expect(r.headers['content-type'], 'text/plain');
    });
  });

  group('envelopes', () {
    final doc = jsonEncode({
      'openapi': '3.0.0',
      'info': {'title': 'Widgets'},
      'paths': {
        '/widgets': {
          'get': {
            'parameters': [
              {'name': 'offset', 'in': 'query', 'schema': {'type': 'integer'}},
              {'name': 'limit', 'in': 'query', 'schema': {'type': 'integer', 'default': 4}},
            ],
            'responses': {
              '200': {
                'description': 'ok',
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'properties': {
                        'items': {'type': 'array', 'items': {r'$ref': '#/components/schemas/Widget'}},
                        'count': {'type': 'integer'},
                        'hasMore': {'type': 'boolean'},
                        'next': {'type': 'string', 'nullable': true},
                        'previous': {'type': 'string', 'nullable': true},
                      },
                    },
                  },
                },
              },
            },
          },
        },
        '/widgets/{id}': {
          'get': {
            'parameters': [
              {'name': 'id', 'in': 'path', 'required': true, 'schema': {'type': 'integer'}},
            ],
            'responses': {
              '200': {
                'description': 'ok',
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'properties': {
                        'data': {r'$ref': '#/components/schemas/Widget'},
                        'ok': {'type': 'boolean'},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      'components': {
        'schemas': {
          'Widget': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'label': {'type': 'string'},
            },
          },
        },
      },
    });

    test('a list envelope gets count, hasMore, next and previous from the page', () {
      final h = _handler(document: doc);
      final r = _call(h, 'GET', '/widgets', query: {'offset': ['4'], 'limit': ['3']});
      final body = _map(r);
      expect([for (final w in body['items'] as List) (w as Map)['id']], [5, 6, 7]);
      expect(body['count'], 10);
      expect(body['hasMore'], isTrue);
      expect(body['next'], '/widgets?offset=7&limit=3');
      expect(body['previous'], '/widgets?offset=1&limit=3');
      final last = _map(_call(h, 'GET', '/widgets', query: {'offset': ['8']}));
      expect(last['hasMore'], isFalse);
      expect(last['next'], isNull);
      expect((last['items'] as List), hasLength(2));
    });

    test('an item envelope wraps the item and fakes its other properties', () {
      final r = _map(_call(_handler(document: doc), 'GET', '/widgets/3'));
      expect((r['data'] as Map)['id'], 3);
      expect(r['ok'], isTrue);
    });
  });

  group('Swagger 2', () {
    final h = _handler(document: shopSwagger2Json);

    test('a list with the limit default of the parameter, under the basePath', () {
      final r = _call(h, 'GET', '/v2/pets');
      expect(r.status, 200);
      // `limit` defaults to 3 and the document pages by limit alone.
      expect([for (final p in _list(r)) (p as Map)['id']], [1, 2, 3]);
    });

    test('the body parameter is validated, and the created pet comes back with an id', () {
      expect(_call(h, 'POST', '/v2/pets', json: <String, dynamic>{}).status, 400);
      final created = _call(h, 'POST', '/v2/pets', json: {'name': 'Rex'});
      expect(created.status, 201);
      expect([_map(created)['id'], _map(created)['name']], [11, 'Rex']);
      expect(_map(_call(h, 'GET', '/v2/pets/11'))['name'], 'Rex');
    });
  });

  group('the whole summary', () {
    test('counts operations and resources for the dialog', () {
      final h = _handler();
      expect(h.summary, '17 operations, 3 resources with data in memory');
      expect(h.families.map((f) => f.collectionTemplate), unorderedEquals(['/users', '/users/{userId}/orders', '/products']));
    });
  });
}
