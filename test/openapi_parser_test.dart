import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/constants/app_constants.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_parser.dart';

void main() {
  group('OpenAPI 3 JSON', () {
    const json = r'''
    {
      "openapi": "3.0.3",
      "info": { "title": "Pet Store" },
      "servers": [{ "url": "https://api.example.com/v1/" }],
      "tags": [{ "name": "pets" }, { "name": "users" }],
      "components": {
        "securitySchemes": { "bearerAuth": { "type": "http", "scheme": "bearer" } },
        "schemas": {
          "NewPet": {
            "type": "object",
            "properties": {
              "name": { "type": "string", "example": "Rex" },
              "age": { "type": "integer" },
              "tags": { "type": "array", "items": { "type": "string" } },
              "owner": { "$ref": "#/components/schemas/Owner" }
            }
          },
          "Owner": { "type": "object", "properties": { "email": { "type": "string", "format": "email" } } }
        }
      },
      "security": [{ "bearerAuth": [] }],
      "paths": {
        "/pets": {
          "get": {
            "tags": ["pets"],
            "summary": "List pets",
            "parameters": [
              { "name": "limit", "in": "query", "schema": { "type": "integer", "default": 20 } },
              { "name": "status", "in": "query", "required": true, "schema": { "type": "string", "enum": ["available", "sold"] } },
              { "name": "X-Trace", "in": "header", "schema": { "type": "string" } }
            ]
          },
          "post": {
            "tags": ["pets"],
            "operationId": "createPet",
            "requestBody": { "content": { "application/json": { "schema": { "$ref": "#/components/schemas/NewPet" } } } }
          }
        },
        "/pets/{petId}": {
          "parameters": [{ "name": "petId", "in": "path", "required": true, "schema": { "type": "string" } }],
          "delete": { "tags": ["pets"], "security": [] }
        },
        "/health": { "get": {} }
      }
    }
    ''';

    test('name, folders from tags, untagged at root', () {
      final parsed = OpenApiParser.parse(json);
      expect(parsed.name, 'Pet Store');
      expect(parsed.folders.map((f) => f.name), ['pets']);
      expect(parsed.folders.single.requests, hasLength(3));
      expect(parsed.rootRequests.single.name, 'GET /health');
      expect(parsed.rootRequests.single.method, HttpMethod.get);
      expect(parsed.baseUrl, 'https://api.example.com/v1');
      expect(parsed.rootRequests.single.url, '{{baseUrl}}/health');
    });

    test('summary > operationId > METHOD /path naming, and path params become {{placeholders}}', () {
      final requests = OpenApiParser.parse(json).folders.single.requests;
      expect(requests.map((r) => r.name), ['List pets', 'createPet', 'DELETE /pets/{petId}']);
      expect(requests.map((r) => r.method), [HttpMethod.get, HttpMethod.post, HttpMethod.delete]);
      expect(requests[2].url, '{{baseUrl}}/pets/{{petId}}');
    });

    test('query and header parameters map to lists; required ones enabled, defaults/enums as values', () {
      final list = OpenApiParser.parse(json).folders.single.requests[0];
      expect(list.queryParams.map((p) => p.key), ['limit', 'status']);
      expect(list.queryParams[0].value, '20');
      expect(list.queryParams[0].enabled, isFalse);
      expect(list.queryParams[1].value, 'available');
      expect(list.queryParams[1].enabled, isTrue);
      expect(list.headers.single.key, 'X-Trace');
    });

    test('JSON request body is a schema-derived skeleton following \$refs', () {
      final create = OpenApiParser.parse(json).folders.single.requests[1];
      expect(create.body.type, BodyType.raw);
      expect(create.body.rawContentType, RawContentType.json);
      final body = jsonDecode(create.body.rawText) as Map<String, dynamic>;
      expect(body['name'], 'Rex');
      expect(body['age'], 0);
      expect(body['tags'], ['string']);
      expect((body['owner'] as Map)['email'], 'user@example.com');
    });

    test('global bearer security applies unless the operation opts out with security: []', () {
      final requests = OpenApiParser.parse(json).folders.single.requests;
      expect(requests[0].auth.type, AuthType.bearer);
      expect(requests[0].auth.bearerToken, '{{token}}');
      expect(requests[2].auth.type, AuthType.none);
    });
  });

  group('OpenAPI 3 YAML', () {
    const yaml = '''
openapi: 3.1.0
info:
  title: Login API
servers:
  - url: https://{region}.example.com
    variables:
      region:
        default: eu
components:
  securitySchemes:
    apiKey:
      type: apiKey
      in: header
      name: X-Api-Key
    cookieKey:
      type: apiKey
      in: cookie
      name: session
paths:
  /login:
    post:
      summary: Log in
      security:
        - cookieKey: []
        - apiKey: []
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties:
                username:
                  type: string
                password:
                  type: string
                  format: password
  /upload:
    post:
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                title:
                  type: string
                file:
                  type: string
                  format: binary
''';

    test('parses YAML, substitutes server variable defaults, and puts untagged requests at root', () {
      final parsed = OpenApiParser.parse(yaml);
      expect(parsed.name, 'Login API');
      expect(parsed.folders, isEmpty);
      expect(parsed.rootRequests.map((r) => r.name), ['Log in', 'POST /upload']);
      expect(parsed.baseUrl, 'https://eu.example.com');
      expect(parsed.rootRequests[0].url, '{{baseUrl}}/login');
    });

    test('form bodies map to urlencoded / form-data and skip binary fields', () {
      final requests = OpenApiParser.parse(yaml).rootRequests;
      expect(requests[0].body.type, BodyType.urlEncoded);
      expect(requests[0].body.urlEncodedFields.map((f) => f.key), ['username', 'password']);
      expect(requests[1].body.type, BodyType.formData);
      expect(requests[1].body.formFields.map((f) => f.key), ['title']);
    });

    test('unsupported cookie apiKey is skipped in favour of the header apiKey', () {
      final login = OpenApiParser.parse(yaml).rootRequests[0];
      expect(login.auth.type, AuthType.apiKey);
      expect(login.auth.apiKeyName, 'X-Api-Key');
      expect(login.auth.apiKeyLocation, ApiKeyLocation.header);
      expect(login.auth.apiKeyValue, '{{apiKey}}');
    });

    test('operations without any security declaration inherit from the collection', () {
      expect(OpenApiParser.parse(yaml).rootRequests[1].auth.type, AuthType.inherit);
    });
  });

  group('Swagger 2.0', () {
    const swagger = r'''
    {
      "swagger": "2.0",
      "info": { "title": "Legacy" },
      "host": "legacy.example.com",
      "basePath": "/api",
      "schemes": ["http"],
      "securityDefinitions": { "basicAuth": { "type": "basic" } },
      "security": [{ "basicAuth": [] }],
      "definitions": {
        "User": { "type": "object", "properties": { "id": { "type": "integer" }, "name": { "type": "string" } } }
      },
      "paths": {
        "/users/{id}": {
          "put": {
            "tags": ["Users"],
            "summary": "Update user",
            "consumes": ["application/json"],
            "parameters": [
              { "name": "id", "in": "path", "required": true, "type": "integer" },
              { "name": "body", "in": "body", "schema": { "$ref": "#/definitions/User" } }
            ]
          }
        },
        "/avatar": {
          "post": {
            "tags": ["Users"],
            "parameters": [
              { "name": "caption", "in": "formData", "type": "string", "default": "hi" },
              { "name": "image", "in": "formData", "type": "file" }
            ]
          }
        }
      }
    }
    ''';

    test('host + basePath + scheme form the base URL', () {
      final parsed = OpenApiParser.parse(swagger);
      expect(parsed.name, 'Legacy');
      final update = parsed.folders.single.requests[0];
      expect(parsed.folders.single.name, 'Users');
      expect(update.name, 'Update user');
      expect(update.method, HttpMethod.put);
      expect(parsed.baseUrl, 'http://legacy.example.com/api');
      expect(update.url, '{{baseUrl}}/users/{{id}}');
    });

    test('body parameter with a definitions ref becomes a JSON skeleton', () {
      final update = OpenApiParser.parse(swagger).folders.single.requests[0];
      expect(update.body.type, BodyType.raw);
      expect(jsonDecode(update.body.rawText), {'id': 0, 'name': 'string'});
    });

    test('formData with a file parameter becomes multipart form-data without the file field', () {
      final avatar = OpenApiParser.parse(swagger).folders.single.requests[1];
      expect(avatar.body.type, BodyType.formData);
      expect(avatar.body.formFields.single.key, 'caption');
      expect(avatar.body.formFields.single.value, 'hi');
    });

    test('basic security definition maps to Basic auth', () {
      final update = OpenApiParser.parse(swagger).folders.single.requests[0];
      expect(update.auth.type, AuthType.basic);
      expect(update.auth.basicUsername, '{{username}}');
    });
  });

  test('rejects documents without an openapi/swagger version field', () {
    expect(() => OpenApiParser.parse('{"info": {"title": "x"}}'), throwsA(isA<ImportException>()));
    expect(() => OpenApiParser.parse('   '), throwsA(isA<ImportException>()));
  });

  test('recursive schemas terminate', () {
    const yaml = '''
openapi: 3.0.0
info: { title: Tree }
components:
  schemas:
    Node:
      type: object
      properties:
        value: { type: string }
        children: { type: array, items: { \$ref: '#/components/schemas/Node' } }
paths:
  /tree:
    post:
      requestBody:
        content:
          application/json:
            schema: { \$ref: '#/components/schemas/Node' }
''';
    final body = jsonDecode(OpenApiParser.parse(yaml).rootRequests.single.body.rawText) as Map;
    expect(body['value'], 'string');
    expect(body['children'], []);
  });

  group('schema examples stay bounded', () {
    Object? bodyOf(String yaml) => jsonDecode(OpenApiParser.parse(yaml).rootRequests.single.body.rawText);

    test('a self-reference wrapped in allOf is cut instead of overflowing the stack', () {
      const yaml = r'''
openapi: 3.0.0
info: { title: Tree }
components:
  schemas:
    Category:
      type: object
      properties:
        name: { type: string }
        parent:
          allOf:
            - $ref: '#/components/schemas/Category'
          nullable: true
        children:
          type: array
          items:
            allOf:
              - $ref: '#/components/schemas/Category'
paths:
  /categories:
    post:
      requestBody:
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Category' }
''';
      expect(bodyOf(yaml), {'name': 'string', 'children': []});
    });

    test('a cycle reachable only through allOf wrappers is cut at its second visit', () {
      const yaml = r'''
openapi: 3.0.0
info: { title: Wrapped }
components:
  schemas:
    A:
      type: object
      properties:
        b: { allOf: [ { $ref: '#/components/schemas/B' } ] }
    B:
      type: object
      properties:
        c: { allOf: [ { $ref: '#/components/schemas/C' } ] }
    C:
      type: object
      properties:
        b: { allOf: [ { $ref: '#/components/schemas/B' } ] }
paths:
  /a:
    post:
      requestBody:
        content:
          application/json:
            schema: { $ref: '#/components/schemas/A' }
''';
      expect(bodyOf(yaml), {
        'b': {'c': {}},
      });
    });

    test('an allOf loop between schemas terminates', () {
      const yaml = r'''
openapi: 3.0.0
info: { title: Loop }
components:
  schemas:
    A: { allOf: [ { $ref: '#/components/schemas/B' } ] }
    B: { allOf: [ { $ref: '#/components/schemas/A' } ] }
paths:
  /a:
    post:
      requestBody:
        content:
          application/json:
            schema: { $ref: '#/components/schemas/A' }
''';
      expect(() => OpenApiParser.parse(yaml), returnsNormally);
    });

    test('schemas that fan out exponentially are capped', () {
      final schemas = StringBuffer();
      for (var i = 0; i < 25; i++) {
        schemas.writeln('    S$i:\n      type: object\n      properties:');
        schemas.writeln(
          i < 24
              ? "        a: { \$ref: '#/components/schemas/S${i + 1}' }\n        b: { \$ref: '#/components/schemas/S${i + 1}' }"
              : '        leaf: { type: string }',
        );
      }
      final yaml = '''
openapi: 3.0.0
info: { title: Chain }
components:
  schemas:
$schemas
paths:
  /s:
    post:
      requestBody:
        content:
          application/json:
            schema: { \$ref: '#/components/schemas/S0' }
''';
      final rawText = OpenApiParser.parse(yaml).rootRequests.single.body.rawText;
      expect(rawText, isNotEmpty);
      expect(rawText.length, lessThan(100000));
    });

    test('percent-encoded \$refs resolve to the decoded schema name', () {
      const swagger = r'''
      {
        "swagger": "2.0",
        "info": { "title": "Encoded" },
        "host": "api.example.com",
        "definitions": {
          "Result\u00abUser\u00bb": { "type": "object", "properties": { "ok": { "type": "boolean" } } },
          "Pet Store": { "type": "object", "properties": { "count": { "type": "integer" } } }
        },
        "paths": {
          "/result": { "post": { "parameters": [
            { "name": "b", "in": "body", "schema": { "$ref": "#/definitions/Result%C2%ABUser%C2%BB" } }
          ] } },
          "/store": { "post": { "parameters": [
            { "name": "b", "in": "body", "schema": { "$ref": "#/definitions/Pet%20Store" } }
          ] } }
        }
      }
      ''';
      final requests = OpenApiParser.parse(swagger).rootRequests;
      expect(jsonDecode(requests[0].body.rawText), {'ok': true});
      expect(jsonDecode(requests[1].body.rawText), {'count': 0});
    });
  });

  group('base URL and URL placeholders', () {
    test('relative and missing servers still get a {{baseUrl}} prefix', () {
      const relative = r'''
openapi: 3.0.2
info: { title: Petstore }
servers:
  - url: /api/v3
paths:
  /pet: { get: {} }
''';
      final withServer = OpenApiParser.parse(relative);
      expect(withServer.baseUrl, '/api/v3');
      expect(withServer.rootRequests.single.url, '{{baseUrl}}/pet');

      final withoutServer = OpenApiParser.parse('openapi: 3.0.0\ninfo: { title: x }\npaths:\n  /a: { get: {} }');
      expect(withoutServer.baseUrl, isEmpty);
      expect(withoutServer.rootRequests.single.url, '{{baseUrl}}/a');
    });

    test('path parameter names the variable resolver could not match are sanitised', () {
      final url = OpenApiParser.parse(r'''
openapi: 3.0.0
info: { title: Graph }
paths:
  /users/{user-id}/messages/{message.id}: { get: {} }
''').rootRequests.single.url;
      expect(url, '{{baseUrl}}/users/{{user_id}}/messages/{{message_id}}');
      expect(AppConstants.variablePattern.allMatches(url).map((m) => m[1]), ['baseUrl', 'user_id', 'message_id']);
    });

    test('Swagger 2 without a single declared scheme is http for local hosts and https otherwise', () {
      String baseOf(String host, [String schemes = '']) =>
          OpenApiParser.parse('{"swagger": "2.0", "info": {"title": "x"}, "host": "$host", $schemes "paths": {}}').baseUrl;

      expect(baseOf('localhost:8080'), 'http://localhost:8080');
      expect(baseOf('192.168.1.5:3000'), 'http://192.168.1.5:3000');
      expect(baseOf('api.example.com'), 'https://api.example.com');
      expect(baseOf('localhost.example.com'), 'https://localhost.example.com');
      expect(baseOf('api.example.com', '"schemes": ["http", "https"],'), 'https://api.example.com');
      expect(baseOf('localhost:8080', '"schemes": ["https"],'), 'https://localhost:8080');
    });
  });

  group('request media type', () {
    test('vendor and non-raw media types are sent as an explicit Content-Type header', () {
      const yaml = r'''
openapi: 3.0.0
info: { title: Media }
paths:
  /patch:
    patch:
      requestBody:
        content:
          application/json-patch+json:
            schema: { type: array, items: { type: string } }
  /csv:
    post:
      requestBody:
        content:
          text/csv:
            schema: { type: string, example: 'a,b' }
  /json:
    post:
      requestBody:
        content:
          application/json;charset=UTF-8:
            schema: { type: object, properties: { x: { type: string } } }
  /any:
    post:
      requestBody:
        content:
          '*/*':
            schema: { type: string, example: hi }
''';
      final requests = {for (final r in OpenApiParser.parse(yaml).rootRequests) r.url: r};
      Map<String, String> headersOf(String path) => {for (final h in requests['{{baseUrl}}$path']!.headers) h.key: h.value};

      expect(headersOf('/patch'), {'Content-Type': 'application/json-patch+json'});
      expect(headersOf('/csv'), {'Content-Type': 'text/csv'});
      expect(requests['{{baseUrl}}/csv']!.body.rawContentType, RawContentType.text);
      expect(headersOf('/json'), isEmpty);
      expect(headersOf('/any'), isEmpty);
    });

    test('Swagger 2 operation-level consumes replaces the document-level list', () {
      const swagger = r'''
      {
        "swagger": "2.0",
        "info": { "title": "Consumes" },
        "host": "api.example.com",
        "consumes": ["application/json"],
        "paths": {
          "/import": { "post": { "consumes": ["text/csv"], "parameters": [
            { "name": "b", "in": "body", "schema": { "type": "string" }, "x-example": "a,b" }
          ] } },
          "/plain": { "post": { "parameters": [
            { "name": "b", "in": "body", "schema": { "type": "object", "properties": { "x": { "type": "string" } } } }
          ] } }
        }
      }
      ''';
      final requests = OpenApiParser.parse(swagger).rootRequests;
      expect(requests[0].body.rawContentType, RawContentType.text);
      expect(requests[0].headers.single.key, 'Content-Type');
      expect(requests[0].headers.single.value, 'text/csv');
      expect(requests[1].body.rawContentType, RawContentType.json);
      expect(requests[1].headers, isEmpty);
    });
  });

  group('OAuth2 security schemes', () {
    const yaml = r'''
openapi: 3.0.0
info: { title: OAuth }
components:
  securitySchemes:
    cc:
      type: oauth2
      flows:
        clientCredentials:
          tokenUrl: https://auth.example.com/token
          scopes: { read: r, write: w }
    code:
      type: oauth2
      flows:
        implicit: { authorizationUrl: 'https://auth.example.com/implicit', scopes: { read: r } }
        authorizationCode:
          authorizationUrl: https://auth.example.com/authorize
          tokenUrl: https://auth.example.com/token
          scopes: { read: r, admin: a }
    pw:
      type: oauth2
      flows:
        password: { tokenUrl: 'https://auth.example.com/token', scopes: { all: x } }
    implicit:
      type: oauth2
      flows:
        implicit: { authorizationUrl: 'https://auth.example.com/implicit', scopes: { read: r } }
    oidc:
      type: openIdConnect
      openIdConnectUrl: https://auth.example.com/.well-known/openid-configuration
paths:
  /cc: { get: { security: [ { cc: [read] } ] } }
  /code: { get: { security: [ { code: [admin] } ] } }
  /pw: { get: { security: [ { pw: [] } ] } }
  /implicit: { get: { security: [ { implicit: [read] } ] } }
  /oidc: { get: { security: [ { oidc: [] } ] } }
''';
    late final requests = OpenApiParser.parse(yaml).rootRequests;

    test('client credentials keep the token URL and only the scopes the operation asks for', () {
      final auth = requests[0].auth;
      expect(auth.type, AuthType.oauth2);
      expect(auth.oauth2GrantType, OAuth2GrantType.clientCredentials);
      expect(auth.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(auth.oauth2Scope, 'read');
      expect(auth.oauth2ClientId, '{{clientId}}');
      expect(auth.oauth2ClientSecret, '{{clientSecret}}');
    });

    test('authorization code maps to PKCE and skips the implicit flow declared before it', () {
      final auth = requests[1].auth;
      expect(auth.type, AuthType.oauth2);
      expect(auth.oauth2GrantType, OAuth2GrantType.authorizationCodePkce);
      expect(auth.oauth2AuthorizationUrl, 'https://auth.example.com/authorize');
      expect(auth.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(auth.oauth2Scope, 'admin');
      expect(auth.oauth2ClientSecret, isEmpty);
    });

    test('password grant gets credential placeholders and, without requested scopes, every declared scope', () {
      final auth = requests[2].auth;
      expect(auth.oauth2GrantType, OAuth2GrantType.password);
      expect(auth.oauth2Username, '{{username}}');
      expect(auth.oauth2Password, '{{password}}');
      expect(auth.oauth2Scope, 'all');
    });

    test('implicit-only and openIdConnect schemes fall back to a bearer token', () {
      for (final auth in [requests[3].auth, requests[4].auth]) {
        expect(auth.type, AuthType.bearer);
        expect(auth.bearerToken, '{{token}}');
      }
    });

    test('Swagger 2 flow names map onto the same grants', () {
      const swagger = r'''
      {
        "swagger": "2.0",
        "info": { "title": "S2 OAuth" },
        "host": "api.example.com",
        "securityDefinitions": {
          "app": { "type": "oauth2", "flow": "application", "tokenUrl": "https://auth.example.com/token", "scopes": { "read": "r" } },
          "code": { "type": "oauth2", "flow": "accessCode", "authorizationUrl": "https://auth.example.com/authorize", "tokenUrl": "https://auth.example.com/token", "scopes": { "read": "r" } }
        },
        "paths": {
          "/app": { "get": { "security": [ { "app": ["read"] } ] } },
          "/code": { "get": { "security": [ { "code": ["read"] } ] } }
        }
      }
      ''';
      final swaggerRequests = OpenApiParser.parse(swagger).rootRequests;
      expect(swaggerRequests[0].auth.oauth2GrantType, OAuth2GrantType.clientCredentials);
      expect(swaggerRequests[0].auth.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(swaggerRequests[1].auth.oauth2GrantType, OAuth2GrantType.authorizationCodePkce);
      expect(swaggerRequests[1].auth.oauth2AuthorizationUrl, 'https://auth.example.com/authorize');
    });
  });
}
