import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_exporter.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_openapi_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'support/in_memory_import_export_fakes.dart';

const _methodsWithoutBody = {'get', 'head', 'delete', 'options'};

ApiRequestEntity _request(
  String name,
  String url, {
  HttpMethod method = HttpMethod.get,
  int? folderId,
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> query = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(),
}) =>
    ApiRequestEntity(
      id: 0,
      collectionId: 1,
      folderId: folderId,
      name: name,
      method: method,
      url: url,
      headers: headers,
      queryParams: query,
      body: body,
      auth: auth,
    );

CollectionVariableEntity _variable(String key, String value, {bool enabled = true}) =>
    CollectionVariableEntity(id: 0, collectionId: 1, key: key, value: value, enabled: enabled);

const _folders = [
  FolderEntity(id: 1, collectionId: 1, parentFolderId: null, name: 'Pets'),
  FolderEntity(id: 2, collectionId: 1, parentFolderId: 1, name: 'Admin'),
  FolderEntity(id: 3, collectionId: 1, parentFolderId: null, name: 'Users'),
];

final _variables = [
  _variable('baseUrl', 'https://api.example.com/v1/'),
  _variable('other', 'https://other.example.org'),
  _variable('token', 'super-secret'),
  _variable('disabledBase', 'https://disabled.example.com', enabled: false),
];

/// A collection that touches every part of the exporter.
List<ApiRequestEntity> _petStoreRequests() => [
      _request('List pets', '{{baseUrl}}/pets?limit=10',
          folderId: 1,
          headers: [
            KeyValueItem(key: 'Accept', value: 'application/json'),
            KeyValueItem(key: 'X-Trace', value: 'abc'),
            KeyValueItem(key: 'X-Debug', value: '1', enabled: false),
          ],
          query: [
            KeyValueItem(key: 'status', value: 'available'),
            KeyValueItem(key: 'debug', value: 'true', enabled: false),
          ]),
      _request('Get pet', '{{baseUrl}}/pets/{{petId}}', folderId: 1, auth: RequestAuth.none),
      _request('Create pet', '{{baseUrl}}/pets',
          method: HttpMethod.post,
          folderId: 1,
          headers: [KeyValueItem(key: 'Content-Type', value: 'application/json')],
          body: const RequestBody(
            type: BodyType.raw,
            rawText: '{"name": "Rex", "age": 3, "price": 9.5, "vaccinated": true, "tags": ["a"], "owner": {"email": "a@b.c"}}',
          ),
          auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-API-Key', apiKeyValue: '{{token}}')),
      _request('Update pet', '{{baseUrl}}/pets/{{id}}',
          method: HttpMethod.put,
          folderId: 1,
          body: const RequestBody(type: BodyType.raw, rawText: '{"age": {{age}}, "name": "{{name}}"}')),
      _request('Remove pet', '{{baseUrl}}/pets/:petId', method: HttpMethod.delete, folderId: 2),
      _request('Login', '{{baseUrl}}/login',
          method: HttpMethod.post,
          folderId: 3,
          body: RequestBody(
            type: BodyType.urlEncoded,
            urlEncodedFields: [
              KeyValueItem(key: 'user', value: 'ann'),
              KeyValueItem(key: 'remember', value: 'yes', enabled: false),
            ],
          ),
          auth: const RequestAuth(type: AuthType.basic, basicUsername: 'u', basicPassword: 'p')),
      _request('Upload', '{{baseUrl}}/upload',
          method: HttpMethod.post,
          body: RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Hello')])),
      _request('Search', '{{baseUrl}}/graphql',
          method: HttpMethod.post,
          body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'query { pets { id } }', graphqlVariables: '{"limit": 5}')),
      _request('Other host', '{{other}}/status',
          auth: const RequestAuth(
            type: AuthType.oauth2,
            oauth2GrantType: OAuth2GrantType.clientCredentials,
            oauth2AccessTokenUrl: '{{other}}/oauth/token',
            oauth2Scope: 'read write',
          )),
      _request('Health', 'https://status.example.net/health'),
      _request('Notes', '{{baseUrl}}/notes',
          method: HttpMethod.post, body: const RequestBody(type: BodyType.raw, rawContentType: RawContentType.text, rawText: 'hello')),
      _request('Body on GET', '{{baseUrl}}/probe', body: const RequestBody(type: BodyType.raw, rawText: '{"a":1}')),
      _request('Duplicate', '{{baseUrl}}/pets'),
      _request('No URL', ''),
    ];

OpenApiExport _exportPetStore() => OpenApiExporter.export(
      collectionName: 'Pet Store',
      folders: _folders,
      requests: _petStoreRequests(),
      variables: _variables,
      collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
    );

Map<String, dynamic> _decode(OpenApiExport export) => jsonDecode(export.text) as Map<String, dynamic>;

Map<String, dynamic> _operation(Map<String, dynamic> doc, String path, String method) =>
    ((doc['paths'] as Map<String, dynamic>)[path] as Map<String, dynamic>)[method] as Map<String, dynamic>;

List<Map<String, dynamic>> _parameters(Map<String, dynamic> operation) =>
    [for (final p in (operation['parameters'] as List? ?? const [])) p as Map<String, dynamic>];

/// The invariants OpenAPI 3.0 validators check, applied to the whole document.
void _expectStructurallyValid(Map<String, dynamic> doc) {
  expect(doc['openapi'], '3.0.3');
  final info = doc['info'] as Map<String, dynamic>;
  expect(info['title'], isA<String>());
  expect(info['version'], isA<String>());
  final paths = doc['paths'] as Map<String, dynamic>;
  final schemes = ((doc['components'] as Map<String, dynamic>?)?['securitySchemes'] as Map<String, dynamic>?) ?? const {};
  final operationIds = <String>{};
  final serverUrls = [for (final s in (doc['servers'] as List? ?? const [])) (s as Map)['url']];
  expect(serverUrls.every((u) => u is String && u.isNotEmpty), isTrue);

  void expectSecurityKnown(Object? security) {
    for (final requirement in (security as List? ?? const [])) {
      for (final name in (requirement as Map).keys) {
        expect(schemes, contains(name), reason: 'security scheme "$name" is referenced but not defined');
      }
    }
  }

  expectSecurityKnown(doc['security']);
  for (final MapEntry(key: path, value: item) in paths.entries) {
    expect(path, startsWith('/'));
    final templated = RegExp(r'\{([^{}/]+)\}').allMatches(path).map((m) => m[1]!).toSet();
    for (final MapEntry(key: method, value: operation) in (item as Map<String, dynamic>).entries) {
      final op = operation as Map<String, dynamic>;
      expect(op['responses'], isNotEmpty, reason: '$method $path has no responses');
      if (op.containsKey('operationId')) expect(operationIds.add(op['operationId'] as String), isTrue, reason: 'duplicate operationId');
      if (_methodsWithoutBody.contains(method)) expect(op, isNot(contains('requestBody')), reason: '$method $path has a body');
      final parameters = _parameters(op);
      final seen = <String>{};
      for (final p in parameters) {
        expect(seen.add('${p['in']}:${p['name']}'), isTrue, reason: 'duplicate parameter ${p['name']} on $method $path');
        expect(['path', 'query', 'header', 'cookie'], contains(p['in']));
        expect(p['schema'], isNotNull);
        if (p['in'] == 'path') expect(p['required'], isTrue);
        if (p['in'] == 'header') expect(['accept', 'content-type', 'authorization'], isNot(contains((p['name'] as String).toLowerCase())));
      }
      final declaredPath = parameters.where((p) => p['in'] == 'path').map((p) => p['name']).toSet();
      expect(declaredPath, templated, reason: 'path parameters of $method $path do not match its template');
      expectSecurityKnown(op['security']);
    }
  }
}

void main() {
  group('OpenAPI export of a full collection', () {
    late OpenApiExport export;
    late Map<String, dynamic> doc;

    setUp(() {
      export = _exportPetStore();
      doc = _decode(export);
    });

    test('is a structurally valid OpenAPI 3.0.3 document', () => _expectStructurallyValid(doc));

    test('counts what was written and what was left out', () {
      expect(export.operations, 12);
      // "Duplicate" repeats GET /pets, "No URL" has none.
      expect(export.skipped, 2);
    });

    test('the title is the collection name', () {
      expect((doc['info'] as Map)['title'], 'Pet Store');
    });

    test('the most used origin is servers[0]; the rest are listed too', () {
      final servers = [for (final s in doc['servers'] as List) (s as Map)['url']];

      expect(servers.first, 'https://api.example.com/v1');
      expect(servers, containsAll(['https://other.example.org', 'https://status.example.net']));
      expect(servers, hasLength(3));
    });

    test('an operation on another origin carries its own servers override', () {
      expect(_operation(doc, '/status', 'get')['servers'], [
        {'url': 'https://other.example.org'},
      ]);
      expect(_operation(doc, '/health', 'get')['servers'], [
        {'url': 'https://status.example.net'},
      ]);
      expect(_operation(doc, '/pets', 'get'), isNot(contains('servers')));
    });

    test('paths drop the query string and turn {{var}}, {var} and :var into path parameters of one spelling', () {
      final paths = (doc['paths'] as Map<String, dynamic>).keys.toList();

      expect(paths, containsAll(['/pets', '/pets/{petId}', '/login', '/upload', '/graphql', '/status', '/health', '/notes', '/probe']));
      expect(paths.where((p) => p.startsWith('/pets/')), ['/pets/{petId}']);
      final item = (doc['paths'] as Map<String, dynamic>)['/pets/{petId}'] as Map<String, dynamic>;
      expect(item.keys, unorderedEquals(['get', 'put', 'delete']));
      expect(_parameters(item['put'] as Map<String, dynamic>).single['name'], 'petId');
    });

    test('query params and headers become parameters: enabled ones required, disabled ones optional', () {
      final byName = {for (final p in _parameters(_operation(doc, '/pets', 'get'))) '${p['in']}:${p['name']}': p};

      expect(byName.keys, unorderedEquals(['query:status', 'query:debug', 'query:limit', 'header:X-Trace', 'header:X-Debug']));
      expect(byName['query:status']!['required'], isTrue);
      expect(byName['query:debug']!['required'], isFalse);
      expect(byName['query:limit']!['required'], isTrue);
      expect(byName['query:limit']!['schema'], {'type': 'integer'});
      expect(byName['query:limit']!['example'], 10);
      expect(byName['query:debug']!['schema'], {'type': 'boolean'});
      expect(byName['header:X-Trace']!['example'], 'abc');
      expect(byName['header:X-Debug']!['required'], isFalse);
    });

    test('a JSON body becomes an example with an inferred schema', () {
      final body = _operation(doc, '/pets', 'post')['requestBody'] as Map<String, dynamic>;
      final media = (body['content'] as Map<String, dynamic>)['application/json'] as Map<String, dynamic>;

      expect(body['required'], isTrue);
      expect(media['example'], {
        'name': 'Rex',
        'age': 3,
        'price': 9.5,
        'vaccinated': true,
        'tags': ['a'],
        'owner': {'email': 'a@b.c'},
      });
      expect(media['schema'], {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
          'price': {'type': 'number'},
          'vaccinated': {'type': 'boolean'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'owner': {
            'type': 'object',
            'properties': {
              'email': {'type': 'string'},
            },
          },
        },
      });
    });

    test('a JSON body that is only invalid because of a bare {{variable}} is still read as JSON', () {
      final body = _operation(doc, '/pets/{petId}', 'put')['requestBody'] as Map<String, dynamic>;
      final media = (body['content'] as Map<String, dynamic>)['application/json'] as Map<String, dynamic>;

      expect(media['example'], {'age': '{{age}}', 'name': '{{name}}'});
    });

    test('form, multipart, GraphQL and plain text bodies', () {
      Map<String, dynamic> content(String path, String mediaType) =>
          (((_operation(doc, path, 'post')['requestBody'] as Map<String, dynamic>)['content'] as Map<String, dynamic>)[mediaType]) as Map<String, dynamic>;

      final form = content('/login', 'application/x-www-form-urlencoded');
      expect(form['example'], {'user': 'ann'});
      expect((form['schema'] as Map)['properties'], {
        'user': {'type': 'string'},
      });
      expect(content('/upload', 'multipart/form-data')['example'], {'title': 'Hello'});
      expect(content('/graphql', 'application/json')['example'], {
        'query': 'query { pets { id } }',
        'variables': {'limit': 5},
      });
      expect(content('/notes', 'text/plain'), {
        'schema': {'type': 'string'},
        'example': 'hello',
      });
    });

    test('a body on a method without body semantics is not exported', () {
      expect(_operation(doc, '/probe', 'get'), isNot(contains('requestBody')));
    });

    test('folders become tags, nested ones as "Parent / Child"', () {
      expect([for (final t in doc['tags'] as List) (t as Map)['name']], ['Pets / Admin', 'Pets', 'Users']);
      expect(_operation(doc, '/pets/{petId}', 'delete')['tags'], ['Pets / Admin']);
      expect(_operation(doc, '/upload', 'post'), isNot(contains('tags')));
    });

    test('operations carry the request name and a unique camelCase operationId', () {
      final operation = _operation(doc, '/pets', 'get');

      expect(operation['summary'], 'List pets');
      expect(operation['operationId'], 'listPets');
      expect(_operation(doc, '/pets/{petId}', 'delete')['operationId'], 'removePet');
    });

    test('the collection auth is the document-wide security, requests differing from it override it', () {
      expect(doc['security'], [
        {'bearerAuth': <String>[]},
      ]);
      expect(_operation(doc, '/pets', 'get'), isNot(contains('security')));
      expect(_operation(doc, '/pets/{petId}', 'get')['security'], isEmpty);
      expect(_operation(doc, '/pets', 'post')['security'], [
        {'apiKeyAuth': <String>[]},
      ]);
      expect(_operation(doc, '/login', 'post')['security'], [
        {'basicAuth': <String>[]},
      ]);
    });

    test('security schemes are defined once, and never carry secrets', () {
      final schemes = (doc['components'] as Map<String, dynamic>)['securitySchemes'] as Map<String, dynamic>;

      expect(schemes['bearerAuth'], {'type': 'http', 'scheme': 'bearer'});
      expect(schemes['basicAuth'], {'type': 'http', 'scheme': 'basic'});
      expect(schemes['apiKeyAuth'], {'type': 'apiKey', 'name': 'X-API-Key', 'in': 'header'});
      expect(export.text, isNot(contains('super-secret')));
    });

    test('an OAuth 2 flow keeps its resolved token URL and scopes', () {
      final schemes = (doc['components'] as Map<String, dynamic>)['securitySchemes'] as Map<String, dynamic>;

      expect(schemes['oauth2Auth'], {
        'type': 'oauth2',
        'flows': {
          'clientCredentials': {
            'tokenUrl': 'https://other.example.org/oauth/token',
            'scopes': {'read': '', 'write': ''},
          },
        },
      });
      expect(_operation(doc, '/status', 'get')['security'], [
        {
          'oauth2Auth': ['read', 'write'],
        },
      ]);
    });

    test('an API key parameter is not also listed as a header parameter', () {
      final request = _request('Keyed', 'https://a.test/x',
          headers: [KeyValueItem(key: 'x-api-key', value: 'abc'), KeyValueItem(key: 'X-Other', value: '1')],
          auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-API-Key', apiKeyValue: 'abc'));
      final result = _decode(OpenApiExporter.export(collectionName: 'K', folders: const [], requests: [request]));

      expect(_parameters(_operation(result, '/x', 'get')).map((p) => p['name']), ['X-Other']);
    });
  });

  group('import of the exported document', () {
    test('round-trips through OpenApiParser: same requests, folders from tags, base URL from servers[0]', () {
      final export = _exportPetStore();
      final parsed = OpenApiParser.parse(export.text);

      expect(parsed.name, 'Pet Store');
      expect(parsed.baseUrl, 'https://api.example.com/v1');
      final requests = [...parsed.rootRequests, for (final f in parsed.folders) ...f.requests];
      expect(requests, hasLength(export.operations));
      expect(parsed.folders.map((f) => f.name), unorderedEquals(['Pets', 'Pets / Admin', 'Users']));

      final byName = {for (final r in requests) r.name: r};
      expect(byName['Get pet']!.url, '{{baseUrl}}/pets/{{petId}}');
      expect(byName['List pets']!.queryParams.map((p) => (p.key, p.enabled)), [('status', true), ('debug', false), ('limit', true)]);
      expect(byName['Create pet']!.auth.type, AuthType.apiKey);
      expect(byName['Create pet']!.auth.apiKeyName, 'X-API-Key');
      expect(jsonDecode(byName['Create pet']!.body.rawText), containsPair('name', 'Rex'));
      expect(byName['Login']!.body.urlEncodedFields.single.key, 'user');
      expect(byName['Get pet']!.auth.type, AuthType.none);
    });
  });

  group('edge cases', () {
    test('a digit run beyond int64 or a decimal beyond double stays a string instead of failing the export', () {
      final huge = '9' * 400;
      final export = OpenApiExporter.export(
        collectionName: 'Numbers',
        folders: const [],
        requests: [
          _request('Account', 'https://a.test/accounts?account=12345678901234567890&n=42&price=9.5&big=$huge.5&neg=-7'),
        ],
      );
      final doc = _decode(export);

      final byName = {for (final p in _parameters(_operation(doc, '/accounts', 'get'))) '${p['name']}': p};
      expect(byName['account']!['schema'], {'type': 'string'});
      expect(byName['account']!['example'], '12345678901234567890');
      expect(byName['big']!['schema'], {'type': 'string'});
      expect(byName['big']!['example'], '$huge.5');
      expect(byName['n']!['schema'], {'type': 'integer'});
      expect(byName['n']!['example'], 42);
      expect(byName['neg']!['example'], -7);
      expect(byName['price']!['schema'], {'type': 'number'});
      expect(byName['price']!['example'], 9.5);
      expect(export.operations, 1);
    });

    test('an empty collection is still a valid document', () {
      final export = OpenApiExporter.export(collectionName: '', folders: const [], requests: const []);
      final doc = _decode(export);

      _expectStructurallyValid(doc);
      expect((doc['info'] as Map)['title'], 'API');
      expect(doc['paths'], isEmpty);
      expect(doc, isNot(contains('servers')));
      expect(doc, isNot(contains('components')));
      expect(export.operations, 0);
    });

    test('with no variable for {{baseUrl}} the paths are written without a server', () {
      final export = OpenApiExporter.export(
        collectionName: 'No base',
        folders: const [],
        requests: [_request('Users', '{{baseUrl}}/users'), _request('User', '{{baseUrl}}/users/{{id}}')],
      );
      final doc = _decode(export);

      _expectStructurallyValid(doc);
      expect(doc, isNot(contains('servers')));
      expect((doc['paths'] as Map).keys, ['/users', '/users/{id}']);
    });

    test('a disabled variable does not resolve the base URL', () {
      final export = OpenApiExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [_request('Users', '{{disabledBase}}/users')],
        variables: _variables,
      );

      expect(_decode(export), isNot(contains('servers')));
    });

    test('servers used equally often keep the order they first appear in', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [
        _request('One', 'https://zeta.test/1'),
        _request('Two', 'https://alpha.test/2'),
        _request('Three', 'https://mid.test/3'),
        _request('Four', 'https://mid.test/4'),
      ]));

      expect([for (final s in doc['servers'] as List) (s as Map)['url']], ['https://mid.test', 'https://zeta.test', 'https://alpha.test']);
    });

    test('a URL with no scheme is read as http://, like when it is sent', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [_request('Local', 'localhost:3000/api/ping')]));

      expect((doc['servers'] as List).single, {'url': 'http://localhost:3000'});
      expect((doc['paths'] as Map).keys, ['/api/ping']);
    });

    test('a variable host is resolved, an unresolvable one leaves the server out', () {
      final doc = _decode(OpenApiExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [_request('A', 'https://{{host}}/a'), _request('B', 'https://{{missing}}/b')],
        variables: [_variable('host', 'api.example.com')],
      ));

      expect((doc['servers'] as List).single, {'url': 'https://api.example.com'});
      expect(_operation(doc, '/b', 'get'), isNot(contains('servers')));
    });

    test('same-named auth of different configurations gets numbered scheme keys', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [
        _request('One', 'https://a.test/1', auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-One')),
        _request('Two', 'https://a.test/2', auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-Two', apiKeyLocation: ApiKeyLocation.query)),
        _request('Three', 'https://a.test/3', auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-One')),
      ]));

      _expectStructurallyValid(doc);
      final schemes = (doc['components'] as Map<String, dynamic>)['securitySchemes'] as Map<String, dynamic>;
      expect(schemes.keys, ['apiKeyAuth', 'apiKeyAuth2']);
      expect((_operation(doc, '/3', 'get')['security'] as List).single, {'apiKeyAuth': <String>[]});
    });

    test('digest, JWT and AWS auth map to their scheme types', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [
        _request('D', 'https://a.test/d', auth: const RequestAuth(type: AuthType.digest)),
        _request('J', 'https://a.test/j', auth: const RequestAuth(type: AuthType.jwtBearer)),
        _request('A', 'https://a.test/a', auth: const RequestAuth(type: AuthType.awsSignatureV4)),
      ]));

      _expectStructurallyValid(doc);
      final schemes = (doc['components'] as Map<String, dynamic>)['securitySchemes'] as Map<String, dynamic>;
      expect(schemes['digestAuth'], {'type': 'http', 'scheme': 'digest'});
      expect(schemes['jwtAuth'], {'type': 'http', 'scheme': 'bearer', 'bearerFormat': 'JWT'});
      expect((schemes['awsSigV4Auth'] as Map)['x-amazon-apigateway-authtype'], 'awsSigv4');
    });

    test('operation ids stay unique when names collide or are unusable', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [
        _request('Get user', 'https://a.test/1'),
        _request('get   USER!', 'https://a.test/2'),
        _request('???', 'https://a.test/3'),
        _request('42 things', 'https://a.test/4'),
      ]));

      _expectStructurallyValid(doc);
      final ids = [for (final p in (doc['paths'] as Map<String, dynamic>).keys) _operation(doc, p, 'get')['operationId']];
      expect(ids, ['getUser', 'getUser2', 'get3', 'op42Things']);
    });

    test('request bodies of methods other than POST, PUT and PATCH are never exported', () {
      final doc = _decode(OpenApiExporter.export(collectionName: 'X', folders: const [], requests: [
        for (final method in HttpMethod.values)
          _request('R ${method.name}', 'https://a.test/${method.name}',
              method: method, body: const RequestBody(type: BodyType.raw, rawText: '{"a":1}')),
      ]));

      _expectStructurallyValid(doc);
      for (final method in HttpMethod.values) {
        final has = (_operation(doc, '/${method.name}', method.name)).containsKey('requestBody');
        expect(has, {HttpMethod.post, HttpMethod.put, HttpMethod.patch}.contains(method), reason: method.name);
      }
    });
  });

  group('export use case', () {
    test('reads the collection through the repositories', () async {
      final db = InMemoryDb();
      final collectionId = await db.collectionRepository.createCollection('Orders');
      await db.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: collectionId, key: 'baseUrl', value: 'https://orders.test', enabled: true));
      await db.collectionAuthRepository.setAuthJson(collectionId, const RequestAuth(type: AuthType.bearer, bearerToken: 'x').toJsonString());
      final requestId = await db.requestRepository.createRequest(collectionId: collectionId, name: 'List orders');
      await db.requestRepository.saveRequest(ApiRequestEntity(
        id: requestId,
        collectionId: collectionId,
        folderId: null,
        name: 'List orders',
        method: HttpMethod.get,
        url: '{{baseUrl}}/orders',
        headers: const [],
        queryParams: const [],
        body: RequestBody.empty,
        auth: const RequestAuth(),
      ));

      final result = await ExportOpenApiUseCase(db.loader)(collectionId);
      final doc = jsonDecode(result.text) as Map<String, dynamic>;

      expect(result.collectionName, 'Orders');
      expect(result.itemCount, 1);
      expect(result.skipped, 0);
      expect((doc['servers'] as List).single, {'url': 'https://orders.test'});
      expect(doc['security'], [
        {'bearerAuth': <String>[]},
      ]);
      expect(_operation(doc, '/orders', 'get')['summary'], 'List orders');
    });

    test('an unknown collection is a not-found error', () async {
      await expectLater(ExportOpenApiUseCase(InMemoryDb().loader)(99), throwsA(isA<NotFoundException>()));
    });
  });
}
