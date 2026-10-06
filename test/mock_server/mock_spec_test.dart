import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_resources.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec.dart';
import 'shop_openapi_fixture.dart';

void main() {
  group('OpenAPI 3', () {
    final spec = MockSpec.parse(shopOpenApiJson);
    SpecOperation op(String key) => spec.operations.firstWhere((o) => o.key == key, orElse: () => throw StateError('no $key in ${spec.operations.map((o) => o.key)}'));

    test('title, base path from the server URL, and every operation', () {
      expect(spec.title, 'Shop');
      // https://api.shop.test/api/v1 is served under /api/v1.
      expect(spec.basePath, '/api/v1');
      // /users 2, /users/{id} 4, /users/me 1, orders 2 + 1, /products 2 + 2, /search, /stats, /ping.
      expect(spec.operations, hasLength(17));
      expect(op('GET /users').operationId, 'listUsers');
      expect(op('GET /users/:id').template, '/users/{id}');
      expect(op('GET /users/:userId/orders/:orderId').segments, ['users', '{userId}', 'orders', '{orderId}']);
    });

    test('path-level parameters reach every operation of the path, and an operation sees its own', () {
      final get = op('GET /users/:id');
      final id = get.parameter('id', 'path')!;
      expect(id.required, isTrue);
      expect(id.schema['type'], 'integer');
      expect(op('DELETE /users/:id').parameter('id', 'path'), isNotNull);

      final list = op('GET /users');
      expect(list.parameter('limit', 'query')!.schema['default'], 5);
      expect(list.parameter('page', 'query')!.required, isFalse);
      final search = op('GET /search');
      expect(search.parameter('q', 'query')!.required, isTrue);
      expect(search.parameter('X-Tenant', 'header')!.required, isTrue);
    });

    test('request bodies and the answers an operation declares', () {
      final create = op('POST /users');
      expect(create.requestBody!.required, isTrue);
      expect(create.requestBody!.contentType, 'application/json');
      expect(create.success!.code, 201);
      expect(create.responseFor(400)!.schema, isNotNull);
      // No 404 and no default: nothing to fall back on.
      expect(create.responseFor(404), isNull);

      expect(op('DELETE /users/:id').success!.code, 204);
      expect(op('GET /users/:id').responseFor(404)!.schema, isNotNull);
      expect(op('GET /users/me').success!.example, containsPair('id', 99));
    });

    test('route keys name parameters with a colon', () {
      expect(spec.operations.map((o) => o.key), containsAll(['GET /users', 'PATCH /users/:id', 'POST /users/:userId/orders', 'GET /products/:sku']));
    });

    test('families: a collection with its item path, nested ones, a text id', () {
      final families = MockResources.detect(spec);
      final byCollection = {for (final f in families) f.collectionTemplate: f};
      expect(byCollection.keys, containsAll(['/users', '/users/{userId}/orders', '/products']));
      final users = byCollection['/users']!;
      expect(users.itemTemplate, '/users/{id}');
      expect(users.idField, 'id');
      expect(users.integerIds, isTrue);
      expect(users.listEnvelope!.payloadKey, 'data');
      expect(users.listEnvelope!.meta.keys, containsAll(['total', 'page', 'limit', 'totalPages']));
      expect(users.list, isNotNull);
      expect(users.create, isNotNull);
      expect(users.replace, isNotNull);
      expect(users.update, isNotNull);
      expect(users.remove, isNotNull);
      final products = byCollection['/products']!;
      // The schema has no `id`, so the id is the item path's parameter.
      expect(products.idField, 'sku');
      expect(products.integerIds, isFalse);
      expect(products.listEnvelope, isNull, reason: 'a plain array');
      expect(byCollection['/users/{userId}/orders']!.itemTemplate, '/users/{userId}/orders/{orderId}');
      // /users/me, /search, /stats and /ping are not part of any resource.
      expect(families.expand((f) => f.operations).map((o) => o.key), isNot(contains('GET /users/me')));
    });
  });

  group('Swagger 2', () {
    final spec = MockSpec.parse(shopSwagger2Json);

    test('host and basePath, parameters typed on the parameter, the body parameter, definitions', () {
      expect(spec.title, 'Pets');
      expect(spec.basePath, '/v2');
      final list = spec.operations.firstWhere((o) => o.key == 'GET /pets');
      expect(list.parameter('limit', 'query')!.schema, containsPair('default', 3));
      expect(list.parameter('limit', 'query')!.schema['type'], 'integer');
      expect(list.success!.schema!['type'], 'array');
      final add = spec.operations.firstWhere((o) => o.key == 'POST /pets');
      expect(add.requestBody!.required, isTrue);
      expect(add.requestBody!.schema, isNotNull);
      expect(add.success!.code, 201);
      // `body` is the request body, not a query or header parameter.
      expect(add.parameters, isEmpty);
    });
  });

  group('input', () {
    test('YAML reads like JSON', () {
      final spec = MockSpec.parse('''
openapi: 3.0.0
info:
  title: Tiny
paths:
  /things:
    get:
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema:
                type: array
                items:
                  type: string
''');
      expect(spec.title, 'Tiny');
      expect(spec.operations.single.key, 'GET /things');
      expect(spec.basePath, '');
    });

    test('something that is not an OpenAPI or Swagger document is refused', () {
      expect(() => MockSpec.parse('{"hello": "world"}'), throwsA(isA<ImportException>()));
      expect(() => MockSpec.parse('   '), throwsA(isA<ImportException>()));
    });

    test('server variables take their default when the base path is worked out', () {
      final spec = MockSpec.parse('{"openapi":"3.0.0","info":{"title":"V"},"servers":[{"url":"{scheme}://{host}/v1","variables":{"scheme":{"default":"https"},"host":{"default":"api.test"}}}],"paths":{}}');
      expect(spec.basePath, '/v1');
    });
  });
}
