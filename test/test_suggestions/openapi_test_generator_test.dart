import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/response_tools/domain/services/json_schema_tools.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/generated_case.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/openapi_test_generator.dart';
import 'openapi_specs.dart';

GeneratedCase _case(GeneratedSuite suite, String name) => suite.cases.firstWhere((c) => c.name == name, orElse: () => fail('no case "$name" in ${suite.cases.map((c) => c.name).toList()}'));

Map<String, dynamic> _body(GeneratedCase c) => jsonDecode(c.body.rawText) as Map<String, dynamic>;

KeyValueItem? _row(List<KeyValueItem> rows, String key) => rows.where((r) => r.key == key).firstOrNull;

List<String> _types(GeneratedCase c) => [for (final a in c.assertions) a.type.name];

Map<String, dynamic> _schemaOf(GeneratedCase c) =>
    jsonDecode(c.assertions.firstWhere((a) => a.type == AssertionType.jsonSchema).expected) as Map<String, dynamic>;

/// The Error schema of the pet shop: the importer-free ground truth, written out by hand.
const _errorSchema = {
  'type': 'object',
  'properties': {
    'code': {'type': 'integer'},
    'message': {'type': 'string'},
  },
  'required': ['code', 'message'],
};

void main() {
  group('the pet shop (OpenAPI 3.0, YAML)', () {
    final suite = OpenApiTestGenerator.generate(petShopSpec);

    test('gives exactly the cases worked out by hand, in the order of the document', () {
      expect(suite.cases.map((c) => c.name).toList(), petShopCases);
      expect(suite.name, 'Pet Shop');
      expect(suite.baseUrl, 'https://api.petshop.test/v1');
      expect(suite.notes, isEmpty);
    });

    test('counts per category and per kind of operation', () {
      expect(suite.count(TestCategory.contract), 5);
      expect(suite.count(TestCategory.negative), 13);
      expect(suite.count(TestCategory.boundary), 13);
      expect(suite.count(TestCategory.auth), 8);
      expect(suite.operationCount, 5);
      // POST /pets has 18 cases and DELETE /pets/{petId} has 6.
      expect(suite.changesDataCount, 24);
      expect(suite.cases.where((c) => c.changesData).map((c) => c.method).toSet(), {HttpMethod.post, HttpMethod.delete});
    });

    test('contract: documented status, a content type, and the response schema with allOf requireds joined', () {
      final list = _case(suite, 'GET /pets (contract)');
      expect(_types(list), ['statusEquals', 'headerExists', 'jsonSchema']);
      expect(list.assertions[0].expected, '200');
      expect(list.assertions[1].path, 'Content-Type');
      final schema = _schemaOf(list);
      expect(schema['type'], 'array');
      final pet = schema['items'] as Map<String, dynamic>;
      expect(pet['required'], ['name', 'species', 'id'], reason: 'NewPet requires name and species, the second member id');
      expect((pet['properties'] as Map).keys, ['name', 'species', 'age', 'tags', 'vaccinated', 'id']);
      expect(((pet['properties'] as Map)['species'] as Map)['enum'], ['dog', 'cat', 'bird']);
      // The schema is the real thing: it accepts a pet and rejects the ways a pet can be wrong.
      List<String> problems(Object? value) => JsonSchemaTools.validate(schema, value).map((v) => v.toString()).toList();
      expect(problems([{'name': 'Rex', 'species': 'dog', 'id': 1}]), isEmpty);
      expect(problems([{'name': 'Rex', 'species': 'dog'}]), [r'$[0]: Missing required "id"']);
      expect(problems([{'name': 'Rex', 'species': 'fish', 'id': 1}]).single, contains('Must be one of dog, cat, bird'));
    });

    test('contract: the request is valid, with the importer\'s example fitted to the limits', () {
      final create = _case(suite, 'POST /pets (contract)');
      expect(create.method, HttpMethod.post);
      expect(create.url, '{{baseUrl}}/pets');
      expect(_body(create), {'name': 'string', 'species': 'dog', 'age': 0, 'tags': ['string'], 'vaccinated': true});
      expect(create.body.type, BodyType.raw);
      expect(create.auth.type, AuthType.bearer);
      expect(create.auth.bearerToken, '{{token}}');
      expect(create.assertions[0].expected, '201');
      final list = _case(suite, 'GET /pets (contract)');
      expect(_row(list.queryParams, 'status')!.enabled, isTrue);
      expect(_row(list.queryParams, 'status')!.value, 'available');
      expect(_row(list.queryParams, 'limit')!.enabled, isFalse, reason: 'optional: off, as the importer made it');
    });

    test('contract: no content means no content-type or schema check; text is not checked against a schema', () {
      final delete = _case(suite, 'DELETE /pets/{petId} (contract)');
      expect(_types(delete), ['statusEquals']);
      expect(delete.assertions.single.expected, '204');
      final health = _case(suite, 'GET /health (contract)');
      expect(_types(health), ['statusEquals', 'headerExists']);
      expect(health.auth.type, AuthType.none, reason: 'security: [] makes it public');
      expect(suite.cases.where((c) => c.operation == 'GET /health'), hasLength(1), reason: 'public and with nothing to break');
    });

    test('path parameters stay variables in the valid request', () {
      expect(_case(suite, 'GET /pets/{petId} (contract)').url, '{{baseUrl}}/pets/{{petId}}');
    });

    test('negative: a client error (never an exact code) and the error schema of the documented 4xx', () {
      final missing = _case(suite, 'POST /pets (missing species)');
      expect(_types(missing), ['statusEquals', 'jsonSchema']);
      expect(missing.assertions.first.expected, '4xx');
      expect(_schemaOf(missing), _errorSchema, reason: '422 is the only error the document describes for POST /pets');
      expect(_body(missing), {'name': 'string', 'age': 0, 'tags': ['string'], 'vaccinated': true});
      expect(_body(_case(suite, 'POST /pets (missing name)')).containsKey('name'), isFalse);
      // GET /pets documents 400; GET /pets/{petId} documents only a 404 with a body, which is not a bad-request schema.
      expect(_schemaOf(_case(suite, 'GET /pets (missing query status)')), _errorSchema);
      expect(_types(_case(suite, 'GET /pets/{petId} (wrong type path petId)')), ['statusEquals']);
    });

    test('negative: parameters left out or of the wrong type, wrong body values, no body, broken JSON', () {
      final noStatus = _case(suite, 'GET /pets (missing query status)');
      expect(_row(noStatus.queryParams, 'status'), isNull);
      final limit = _row(_case(suite, 'GET /pets (wrong type query limit)').queryParams, 'limit')!;
      expect((limit.value, limit.enabled), ('not-a-number', true));
      expect(_case(suite, 'GET /pets/{petId} (wrong type path petId)').url, '{{baseUrl}}/pets/not-a-number');
      expect(_body(_case(suite, 'POST /pets (wrong type name)'))['name'], 12345);
      expect(_body(_case(suite, 'POST /pets (wrong type age)'))['age'], 'not-a-number');
      expect(_body(_case(suite, 'POST /pets (wrong type tags)'))['tags'], 'not-an-array');
      expect(_body(_case(suite, 'POST /pets (wrong type vaccinated)'))['vaccinated'], 'not-a-boolean');
      final empty = _case(suite, 'POST /pets (empty body)');
      expect((empty.body.type, empty.body.rawText), (BodyType.raw, ''));
      expect(_case(suite, 'POST /pets (malformed JSON)').body.rawText, '{"broken": ');
      expect(() => jsonDecode(_case(suite, 'POST /pets (malformed JSON)').body.rawText), throwsFormatException);
    });

    test('boundary: one step outside each limit', () {
      expect(_body(_case(suite, 'POST /pets (name too short)'))['name'], '');
      expect(_body(_case(suite, 'POST /pets (name too long)'))['name'], 'a' * 51);
      expect(_body(_case(suite, 'POST /pets (species not in enum)'))['species'], 'not-a-valid-value');
      expect(_body(_case(suite, 'POST /pets (age below minimum)'))['age'], -1);
      expect(_body(_case(suite, 'POST /pets (age above maximum)'))['age'], 41);
      expect((_body(_case(suite, 'POST /pets (tags too many items)'))['tags'] as List).length, 6);
      expect(_row(_case(suite, 'GET /pets (query status not in enum)').queryParams, 'status')!.value, 'not-a-valid-value');
      expect(_row(_case(suite, 'GET /pets (query limit below minimum)').queryParams, 'limit')!.value, '0');
      expect(_row(_case(suite, 'GET /pets (query limit above maximum)').queryParams, 'limit')!.value, '101');
      expect(_case(suite, 'GET /pets/{petId} (path petId below minimum)').url, '{{baseUrl}}/pets/0');
      expect(_case(suite, 'GET /pets/{petId} (path petId overflow)').url, '{{baseUrl}}/pets/9223372036854775808');
      // Past the maximum already says it, so a property with a maximum gets no separate overflow case.
      expect(suite.cases.any((c) => c.name == 'POST /pets (age overflow)'), isFalse);
      expect(suite.cases.any((c) => c.name == 'GET /pets (query limit overflow)'), isFalse);
      expect(_case(suite, 'POST /pets (name too short)').assertions.first.expected, '4xx');
    });

    test('auth: none and malformed credentials, expecting 401 or 403 when the document names neither', () {
      final none = _case(suite, 'GET /pets (no credentials)');
      expect(none.auth.type, AuthType.none);
      expect(_types(none), ['statusEquals'], reason: 'the document describes no 401/403 body');
      expect(none.assertions.single.expected, '401, 403');
      final bad = _case(suite, 'GET /pets (malformed token)');
      expect((bad.auth.type, bad.auth.bearerToken), (AuthType.bearer, 'malformed.token'));
      expect(bad.assertions.single.expected, '401, 403');
      expect(suite.cases.where((c) => c.operation == 'GET /health' && c.category == TestCategory.auth), isEmpty);
    });

    test('the valid parts of a case are not touched by the mutation: only one thing differs', () {
      final valid = _case(suite, 'POST /pets (contract)');
      final broken = _case(suite, 'POST /pets (age above maximum)');
      expect(broken.url, valid.url);
      expect(broken.auth.bearerToken, valid.auth.bearerToken);
      expect({..._body(broken)}..remove('age'), {..._body(valid)}..remove('age'));
    });

    test('every case has at least one assertion and a non-empty expectation text', () {
      for (final c in suite.cases) {
        expect(c.assertions, isNotEmpty, reason: c.name);
        expect(c.expectation, isNotEmpty, reason: c.name);
      }
      expect(_case(suite, 'POST /pets (missing name)').expectation, 'Status equals 4xx · Body matches the JSON Schema');
    });
  });

  group('the inventory (Swagger 2.0, JSON)', () {
    final suite = OpenApiTestGenerator.generate(inventorySpec);

    test('gives exactly the cases worked out by hand', () {
      expect(suite.cases.map((c) => c.name).toList(), inventoryCases);
      expect(suite.name, 'Inventory');
      expect(suite.baseUrl, 'https://inventory.test/api');
      expect(suite.notes, isEmpty);
      expect(suite.count(TestCategory.contract), 3);
      expect(suite.count(TestCategory.negative), 1 + 7);
      expect(suite.count(TestCategory.boundary), 3 + 5 + 2);
      expect(suite.count(TestCategory.auth), 4);
      expect(suite.changesDataCount, 15);
    });

    test('contract: the schema of a definition built from allOf, and a body fitted to an exclusive minimum', () {
      final get = _case(suite, 'GET /items (contract)');
      expect(_types(get), ['statusEquals', 'headerExists', 'jsonSchema']);
      final item = _schemaOf(get)['items'] as Map<String, dynamic>;
      expect(item['required'], ['sku', 'price', 'updatedAt']);
      expect(((item['properties'] as Map)['updatedAt'] as Map)['format'], 'date-time');
      final problems = JsonSchemaTools.validate(_schemaOf(get), [{'sku': 'ABC', 'price': 1.5, 'updatedAt': '2026-01-01T00:00:00Z'}]);
      expect(problems, isEmpty);
      expect(JsonSchemaTools.validate(_schemaOf(get), [{'sku': 'ABC', 'price': 1.5}]).single.message, 'Missing required "updatedAt"');
      // The importer's placeholder price is 0.0, which `exclusiveMinimum: true` forbids: it is moved to 1.
      expect(_body(_case(suite, 'POST /items (contract)')), {'sku': 'string', 'price': 1, 'stock': 0});
      expect(_case(suite, 'POST /items (contract)').assertions[0].expected, '201');
    });

    test('negative: the error schema comes from default when no 400 or 422 is documented', () {
      final wrong = _case(suite, 'GET /items (wrong type query page)');
      expect(_types(wrong), ['statusEquals', 'jsonSchema']);
      expect(_schemaOf(wrong)['required'], ['title']);
      final inPost = _case(suite, 'POST /items (missing price)');
      expect(_schemaOf(inPost)['required'], ['title']);
      expect(_body(inPost), {'sku': 'string', 'stock': 0});
      expect(_row(_case(suite, 'GET /items (wrong type query page)').queryParams, 'page')!.value, 'not-a-number');
    });

    test('boundary: exclusive minimum is violated at the boundary itself, int32 overflows at 2^31', () {
      expect(_body(_case(suite, 'POST /items (price below minimum)'))['price'], 0);
      expect(_body(_case(suite, 'POST /items (stock below minimum)'))['stock'], -1);
      expect(_body(_case(suite, 'POST /items (stock overflow)'))['stock'], 2147483648);
      expect(_body(_case(suite, 'POST /items (sku too short)'))['sku'], 'aa');
      expect(_body(_case(suite, 'POST /items (sku too long)'))['sku'], 'a' * 13);
      expect(_row(_case(suite, 'GET /items (query page overflow)').queryParams, 'page')!.value, '9223372036854775808');
      expect(_row(_case(suite, 'GET /items (query page below minimum)').queryParams, 'page')!.value, '0');
      expect(_case(suite, 'GET /items/{sku} (path sku too short)').url, '{{baseUrl}}/items/aa');
      expect(_case(suite, 'GET /items/{sku} (path sku too long)').url, '{{baseUrl}}/items/${'a' * 13}');
      expect(suite.cases.any((c) => c.name == 'POST /items (price overflow)'), isFalse, reason: 'only whole numbers overflow');
    });

    test('auth: an API key header, none or invalid; the default response describes the failure', () {
      final none = _case(suite, 'GET /items (no credentials)');
      expect(none.auth.type, AuthType.none);
      expect(_types(none), ['statusEquals', 'jsonSchema']);
      expect(none.assertions.first.expected, '401, 403');
      final bad = _case(suite, 'GET /items (malformed token)');
      expect((bad.auth.type, bad.auth.apiKeyName, bad.auth.apiKeyValue), (AuthType.apiKey, 'X-API-Key', 'invalid'));
      expect(_types(_case(suite, 'POST /items (no credentials)')), ['statusEquals'], reason: 'POST documents only a 400 and a 201');
      expect(suite.cases.where((c) => c.operation == 'GET /items/{sku}' && c.category == TestCategory.auth), isEmpty);
    });
  });

  group('limits of the generator, on a document built to hit each one', () {
    const edge = r'''
{
  "openapi": "3.0.1",
  "info": {"title": "Edge", "version": "1"},
  "servers": [{"url": "https://edge.test"}],
  "paths": {
    "/users": {
      "post": {
        "summary": "Create user",
        "requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/User"}}}},
        "responses": {
          "200": {"description": "ok", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/User"}}}},
          "201": {"description": "created", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/User"}}}},
          "default": {"description": "err"}
        }
      }
    },
    "/search": {
      "get": {
        "summary": "Search",
        "parameters": [{"name": "q", "in": "query", "required": true, "schema": {"type": "string", "maxLength": 70000}}],
        "responses": {"default": {"description": "any"}}
      }
    },
    "/login": {
      "post": {
        "summary": "Form login",
        "requestBody": {"content": {"application/x-www-form-urlencoded": {"schema": {"type": "object", "required": ["user"], "properties": {"user": {"type": "string"}}}}}},
        "responses": {"204": {"description": "ok"}}
      }
    },
    "/tree": {
      "get": {
        "summary": "Tree",
        "responses": {"200": {"description": "ok", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/Node"}}}}}
      }
    },
    "/cookie": {
      "get": {"summary": "Cookie", "security": [{"sessionCookie": []}], "responses": {"200": {"description": "ok"}}}
    }
  },
  "components": {
    "securitySchemes": {"sessionCookie": {"type": "apiKey", "name": "sid", "in": "cookie"}},
    "schemas": {
      "User": {
        "type": "object",
        "required": ["email", "address"],
        "properties": {
          "id": {"type": "integer", "readOnly": true},
          "email": {"type": "string", "format": "email"},
          "password": {"type": "string", "writeOnly": true, "minLength": 8},
          "address": {"type": "object", "required": ["street"], "properties": {"street": {"type": "string"}, "zip": {"type": "string"}}}
        }
      },
      "Node": {"type": "object", "required": ["name"], "properties": {"name": {"type": "string"}, "children": {"type": "array", "items": {"$ref": "#/components/schemas/Node"}}}}
    }
  }
}
''';
    final suite = OpenApiTestGenerator.generate(edge);

    test('the cases and the notes', () {
      expect(suite.cases.map((c) => c.name).toList(), [
        'POST /users (contract)',
        'POST /users (missing email)',
        'POST /users (missing address)',
        'POST /users (missing address.street)',
        'POST /users (wrong type email)',
        'POST /users (wrong type password)',
        'POST /users (wrong type address)',
        'POST /users (empty body)',
        'POST /users (malformed JSON)',
        'POST /users (password too short)',
        'GET /search (contract)',
        'GET /search (missing query q)',
        'POST /login (contract)',
        'GET /tree (contract)',
        'GET /cookie (contract)',
      ]);
      expect(suite.notes, [
        'GET /search: q allows 70000 characters, too many to build a test value for.',
        'GET /cookie needs credentials, but its security scheme has no credentials the app can build, so no auth cases were made.',
      ]);
    });

    test('several success codes, or none, mean "is 2xx" rather than a code the document does not promise', () {
      expect(_types(_case(suite, 'POST /users (contract)')).first, 'statusIn2xx');
      expect(_types(_case(suite, 'GET /search (contract)')), ['statusIn2xx'], reason: 'only a default response');
      expect(_types(_case(suite, 'GET /cookie (contract)')), ['statusEquals']);
    });

    test('a read-only property is not sent, a write-only one is not expected back', () {
      final body = _body(_case(suite, 'POST /users (contract)'));
      expect(body.containsKey('id'), isFalse);
      expect(body['password'], 'stringxx', reason: 'padded to the minimum length of 8');
      final response = _schemaOf(_case(suite, 'POST /users (contract)'));
      expect((response['properties'] as Map).containsKey('password'), isFalse);
      expect((response['properties'] as Map).containsKey('id'), isTrue);
      expect(response['required'], ['email', 'address']);
    });

    test('a nested required field is left out too, one level down', () {
      final body = _body(_case(suite, 'POST /users (missing address.street)'));
      expect(body['address'], {'zip': 'string'});
      expect(_body(_case(suite, 'POST /users (missing address)')).containsKey('address'), isFalse);
    });

    test('a form body gets no JSON-only cases, and its contract is kept', () {
      final names = suite.cases.where((c) => c.operation == 'POST /login').map((c) => c.name).toList();
      expect(names, ['POST /login (contract)']);
      expect(_case(suite, 'POST /login (contract)').body.type, BodyType.urlEncoded);
    });

    test('a schema that contains itself is cut where it repeats and still validates a nested document', () {
      final tree = _schemaOf(_case(suite, 'GET /tree (contract)'));
      expect(
        JsonSchemaTools.validate(tree, {
          'name': 'root',
          'children': [
            {'name': 'leaf', 'children': <Object?>[]},
          ],
        }),
        isEmpty,
      );
      expect(JsonSchemaTools.validate(tree, {'children': <Object?>[]}).single.message, 'Missing required "name"');
    });
  });

  group('choosing what to generate', () {
    final suite = OpenApiTestGenerator.generate(petShopSpec);

    test('the default cap is 200 and everything fits under it', () {
      expect(GeneratedSuite.defaultCap, 200);
      final all = suite.select();
      expect(all.cases.length, 39);
      expect(all.skipped, 0);
    });

    test('over the cap, contracts come first, then auth, in the order of the document', () {
      final picked = suite.select(cap: 10);
      expect(picked.cases.map((c) => c.name).toList(), [
        'GET /pets (contract)',
        'GET /pets (no credentials)',
        'GET /pets (malformed token)',
        'POST /pets (contract)',
        'POST /pets (no credentials)',
        'POST /pets (malformed token)',
        'GET /pets/{petId} (contract)',
        'GET /pets/{petId} (no credentials)',
        'DELETE /pets/{petId} (contract)',
        'GET /health (contract)',
      ]);
      expect(picked.skipped, 29);
      expect(picked.changesDataCount, 4);
    });

    test('unticked categories are left out, and the cap counts only what is ticked', () {
      final negative = suite.select(categories: {TestCategory.negative});
      expect(negative.cases.length, 13);
      expect(negative.count(TestCategory.negative), 13);
      final some = suite.select(categories: {TestCategory.boundary, TestCategory.auth}, cap: 5);
      expect(some.cases.map((c) => c.name).toList(), [
        'GET /pets (no credentials)',
        'GET /pets (malformed token)',
        'POST /pets (no credentials)',
        'POST /pets (malformed token)',
        'GET /pets/{petId} (no credentials)',
      ]);
      expect(some.skipped, 16);
      expect(suite.select(categories: const {}).cases, isEmpty);
    });
  });

  group('input that is not a document', () {
    test('says so', () {
      expect(() => OpenApiTestGenerator.generate(''), throwsA(anything));
      expect(() => OpenApiTestGenerator.generate('{"hello": 1}'), throwsA(anything));
    });

    test('a document with no operations gives no cases', () {
      final suite = OpenApiTestGenerator.generate('{"openapi":"3.0.0","info":{"title":"Empty","version":"1"},"paths":{}}');
      expect(suite.cases, isEmpty);
      expect(suite.name, 'Empty');
    });
  });
}
