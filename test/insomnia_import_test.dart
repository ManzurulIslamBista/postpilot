import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/imported_collection.dart';
import 'package:postpilot/features/import_export/domain/services/insomnia_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_insomnia_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'support/in_memory_import_export_fakes.dart';

Map<String, dynamic> _workspace(String id, String name, {String scope = 'collection'}) =>
    {'_id': id, '_type': 'workspace', 'parentId': null, 'name': name, 'scope': scope};

Map<String, dynamic> _group(String id, String parent, String name, {num sort = 0, Map<String, dynamic>? auth, List<Map<String, dynamic>>? headers}) => {
      '_id': id,
      '_type': 'request_group',
      'parentId': parent,
      'name': name,
      'metaSortKey': sort,
      'environment': {},
      'authentication': ?auth,
      'headers': ?headers,
    };

Map<String, dynamic> _request(
  String id,
  String parent,
  String name, {
  String method = 'GET',
  String url = 'https://api.test/x',
  num sort = 0,
  List<Map<String, dynamic>> headers = const [],
  List<Map<String, dynamic>> parameters = const [],
  Map<String, dynamic> body = const {},
  Map<String, dynamic> auth = const {},
}) =>
    {
      '_id': id,
      '_type': 'request',
      'parentId': parent,
      'name': name,
      'method': method,
      'url': url,
      'metaSortKey': sort,
      'headers': headers,
      'parameters': parameters,
      'body': body,
      'authentication': auth,
    };

Map<String, dynamic> _environment(String id, String parent, String name, Map<String, dynamic> data, {num sort = 0}) =>
    {'_id': id, '_type': 'environment', 'parentId': parent, 'name': name, 'data': data, 'metaSortKey': sort};

String _export(List<Map<String, dynamic>> resources) =>
    jsonEncode({'_type': 'export', '__export_format': 4, '__export_source': 'insomnia.desktop.app:v2023.5.8', 'resources': resources});

ImportedFolder _folder(List<ImportedItem> items, String name) => items.whereType<ImportedFolder>().firstWhere((f) => f.name == name);

ImportedRequest _req(List<ImportedItem> items, String name) => items.whereType<ImportedRequest>().firstWhere((r) => r.name == name);

/// A realistic workspace: nested folders, several body and auth kinds, a base
/// environment with a sub-environment, and items listed out of display order.
String _petStoreExport() => _export([
      _request('req_create', 'fld_pets', 'Create pet',
          method: 'POST',
          url: '{{ _.base_url }}/pets',
          sort: -50,
          headers: [
            {'name': 'Content-Type', 'value': 'application/json'},
          ],
          body: {'mimeType': 'application/json', 'text': '{"name": "{{ _.pet_name }}"}'},
          auth: {'type': 'basic', 'username': 'admin', 'password': '{{ _.admin_password }}'}),
      _request('req_list', 'fld_pets', 'List pets',
          url: '{{ _.base_url }}/pets',
          sort: -100,
          headers: [
            {'name': 'Accept', 'value': 'application/json'},
            {'name': 'X-Debug', 'value': '1', 'disabled': true},
            {'name': '', 'value': 'ignored'},
          ],
          parameters: [
            {'name': 'limit', 'value': '10'},
            {'name': 'cursor', 'value': 'abc', 'disabled': true},
          ],
          auth: {'type': 'bearer', 'token': '{{ _.token }}', 'prefix': ''}),
      _request('req_health', 'wrk_1', 'Health', url: 'https://health.example.com/', sort: -5),
      _request('req_key', 'fld_admin', 'Stats',
          url: '{{ _.base_url }}/admin/stats',
          auth: {'type': 'apikey', 'key': 'X-API-Key', 'value': '{{ _.api_key }}', 'addTo': 'header'}),
      _request('req_form', 'fld_admin', 'Login',
          method: 'POST',
          url: '{{ _.base_url }}/login',
          sort: 1,
          body: {
            'mimeType': 'application/x-www-form-urlencoded',
            'params': [
              {'name': 'user', 'value': 'ann'},
              {'name': 'remember', 'value': 'yes', 'disabled': true},
            ],
          }),
      _group('fld_admin', 'fld_pets', 'Admin', sort: -1),
      _group('fld_pets', 'wrk_1', 'Pets', sort: -10),
      _environment('env_dev', 'env_base', 'Development', {'base_url': 'https://dev.example.com', 'debug': true}, sort: 2),
      _environment('env_base', 'wrk_1', 'Base Environment', {
        'base_url': 'https://petstore.example.com',
        'token': 'abc',
        'db': {'host': 'localhost', 'port': 5432},
        'tags': ['a', 'b'],
      }),
      _workspace('wrk_1', 'Pet Store'),
    ]);

void main() {
  group('Insomnia v4 export', () {
    late ParsedInsomniaExport parsed;
    late ImportedCollection collection;

    setUp(() {
      parsed = InsomniaParser.parse(_petStoreExport());
      collection = parsed.workspaces.single.collection;
    });

    test('one collection per workspace, named after it', () {
      expect(parsed.workspaces, hasLength(1));
      expect(collection.name, 'Pet Store');
    });

    test('folders nest as in Insomnia and siblings follow metaSortKey, not file order', () {
      expect(collection.items.map((i) => i.name), ['Pets', 'Health']);
      final pets = _folder(collection.items, 'Pets');
      expect(pets.children.map((c) => c.name), ['List pets', 'Create pet', 'Admin']);
      expect(_folder(pets.children, 'Admin').children.map((c) => c.name), ['Stats', 'Login']);
      expect(collection.folderCount, 2);
      expect(collection.requestCount, 5);
    });

    test('method, url with {{ _.x }} rewritten, disabled headers and params kept disabled', () {
      final list = _req(_folder(collection.items, 'Pets').children, 'List pets');

      expect(list.method, HttpMethod.get);
      expect(list.url, '{{base_url}}/pets');
      expect(list.headers.map((h) => (h.key, h.value, h.enabled)), [
        ('Accept', 'application/json', true),
        ('X-Debug', '1', false),
      ]);
      expect(list.queryParams.map((p) => (p.key, p.value, p.enabled)), [
        ('limit', '10', true),
        ('cursor', 'abc', false),
      ]);
    });

    test('bearer, basic and api key auth are mapped, template references included', () {
      final pets = _folder(collection.items, 'Pets').children;
      final list = _req(pets, 'List pets');
      final create = _req(pets, 'Create pet');
      final stats = _req(_folder(pets, 'Admin').children, 'Stats');

      expect(list.auth.type, AuthType.bearer);
      expect(list.auth.bearerToken, '{{token}}');
      expect(create.auth.type, AuthType.basic);
      expect(create.auth.basicUsername, 'admin');
      expect(create.auth.basicPassword, '{{admin_password}}');
      expect(stats.auth.type, AuthType.apiKey);
      expect(stats.auth.apiKeyName, 'X-API-Key');
      expect(stats.auth.apiKeyValue, '{{api_key}}');
      expect(stats.auth.apiKeyLocation, ApiKeyLocation.header);
    });

    test('a request with no authentication inherits', () {
      expect(_req(collection.items, 'Health').auth.type, AuthType.inherit);
    });

    test('a JSON body keeps its text, with variables rewritten', () {
      final create = _req(_folder(collection.items, 'Pets').children, 'Create pet');

      expect(create.method, HttpMethod.post);
      expect(create.body.type, BodyType.raw);
      expect(create.body.rawContentType, RawContentType.json);
      expect(create.body.rawText, '{"name": "{{pet_name}}"}');
    });

    test('a form body keeps disabled fields disabled', () {
      final pets = _folder(collection.items, 'Pets').children;
      final login = _req(_folder(pets, 'Admin').children, 'Login');

      expect(login.body.type, BodyType.urlEncoded);
      expect(login.body.urlEncodedFields.map((f) => (f.key, f.value, f.enabled)), [
        ('user', 'ann', true),
        ('remember', 'yes', false),
      ]);
    });

    test('the base environment becomes collection variables, nested keys dotted', () {
      final variables = {for (final v in collection.variables) v.key: v.value};

      expect(variables, {
        'base_url': 'https://petstore.example.com',
        'token': 'abc',
        'db.host': 'localhost',
        'db.port': '5432',
        'tags': '["a","b"]',
      });
    });

    test('a sub-environment is kept with its own values', () {
      final environment = parsed.workspaces.single.environments.single;

      expect(environment.name, 'Development');
      expect({for (final v in environment.variables) v.key: v.value}, {'base_url': 'https://dev.example.com', 'debug': 'true'});
    });
  });

  group('bodies', () {
    ImportedRequest single(Map<String, dynamic> body, {List<Map<String, dynamic>> headers = const []}) {
      final text = _export([_workspace('wrk_1', 'W'), _request('req_1', 'wrk_1', 'R', method: 'POST', body: body, headers: headers)]);
      return InsomniaParser.parse(text).workspaces.single.collection.items.single as ImportedRequest;
    }

    test('multipart keeps text parts and drops file parts', () {
      final request = single({
        'mimeType': 'multipart/form-data',
        'params': [
          {'name': 'title', 'value': 'Hello', 'type': 'text'},
          {'name': 'upload', 'type': 'file', 'fileName': '/tmp/a.png'},
        ],
      });

      expect(request.body.type, BodyType.formData);
      expect(request.body.formFields.map((f) => (f.key, f.value)), [('title', 'Hello')]);
    });

    test('a GraphQL body is split into query and variables', () {
      final request = single({
        'mimeType': 'application/graphql',
        'text': jsonEncode({'query': 'query { pets { id } }', 'variables': {'limit': 5}}),
      });

      expect(request.body.type, BodyType.graphql);
      expect(request.body.graphqlQuery, 'query { pets { id } }');
      expect(jsonDecode(request.body.graphqlVariables), {'limit': 5});
    });

    test('XML maps to the raw XML type without an extra header', () {
      final request = single({'mimeType': 'application/xml', 'text': '<a/>'});

      expect(request.body.rawContentType, RawContentType.xml);
      expect(request.headers, isEmpty);
    });

    test('a media type the raw types cannot express is sent as an explicit Content-Type header', () {
      final request = single({'mimeType': 'application/vnd.api+json', 'text': '{}'});

      expect(request.body.rawContentType, RawContentType.json);
      expect(request.headers.single.key, 'Content-Type');
      expect(request.headers.single.value, 'application/vnd.api+json');
    });

    test('an explicit Content-Type header of the request is not duplicated', () {
      final request = single(
        {'mimeType': 'application/vnd.api+json', 'text': '{}'},
        headers: [
          {'name': 'content-type', 'value': 'application/vnd.api+json'},
        ],
      );

      expect(request.headers, hasLength(1));
    });

    test('a body without a media type is sniffed, an empty body is none', () {
      expect(single({'text': '{"a":1}'}).body.rawContentType, RawContentType.json);
      expect(single({'text': 'hello'}).body.rawContentType, RawContentType.text);
      expect(single({}).body.type, BodyType.none);
      expect(single({'mimeType': 'application/octet-stream', 'fileName': '/tmp/x.bin'}).body.type, BodyType.none);
    });

    test('uuid and now tags become the built-in dynamic variables', () {
      final text = _export([
        _workspace('wrk_1', 'W'),
        _request('req_1', 'wrk_1', 'R',
            url: 'https://x.io/{% uuid \'v4\' %}?t={% now \'unix\', \'\', \'\' %}',
            body: {'mimeType': 'text/plain', 'text': "{% now 'iso-8601', '', '' %}"}),
      ]);
      final request = InsomniaParser.parse(text).workspaces.single.collection.items.single as ImportedRequest;

      expect(request.url, r'https://x.io/{{$guid}}?t={{$timestamp}}');
      expect(request.body.rawText, r'{{$isoTimestamp}}');
    });
  });

  group('auth', () {
    RequestAuth probe(Map<String, dynamic> auth) {
      final text = _export([_workspace('wrk_1', 'W'), _request('req_1', 'wrk_1', 'R', auth: auth)]);
      final request = InsomniaParser.parse(text).workspaces.single.collection.items.single as ImportedRequest;
      return request.auth;
    }

    test('OAuth 2 grants the app can run keep their endpoints and credentials', () {
      final auth = probe({
        'type': 'oauth2',
        'grantType': 'client_credentials',
        'accessTokenUrl': 'https://auth.example.com/token',
        'clientId': 'id',
        'clientSecret': 'secret',
        'scope': 'read write',
        'credentialsInBody': true,
      });

      expect(auth.type, AuthType.oauth2);
      expect(auth.oauth2GrantType, OAuth2GrantType.clientCredentials);
      expect(auth.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(auth.oauth2ClientId, 'id');
      expect(auth.oauth2Scope, 'read write');
      expect(auth.oauth2ClientAuthentication, OAuth2ClientAuthentication.body);
    });

    test('authorization_code maps to the PKCE flow, and implicit falls back to a pasted bearer token', () {
      expect(probe({'type': 'oauth2', 'grantType': 'authorization_code'}).oauth2GrantType, OAuth2GrantType.authorizationCodePkce);
      final implicit = probe({'type': 'oauth2', 'grantType': 'implicit'});
      expect(implicit.type, AuthType.bearer);
      expect(implicit.bearerToken, '{{token}}');
    });

    test('digest and AWS IAM', () {
      expect(probe({'type': 'digest', 'username': 'u', 'password': 'p'}).type, AuthType.digest);
      final aws = probe({'type': 'iam', 'accessKeyId': 'AK', 'secretAccessKey': 'SK', 'region': 'eu-west-1', 'service': 's3'});
      expect(aws.type, AuthType.awsSignatureV4);
      expect(aws.awsRegion, 'eu-west-1');
      expect(aws.awsService, 's3');
    });

    test('auth kinds the app has no equivalent for, and disabled auth, become No Auth', () {
      expect(probe({'type': 'hawk', 'id': 'x'}).type, AuthType.none);
      expect(probe({'type': 'bearer', 'token': 't', 'disabled': true}).type, AuthType.none);
      expect(probe({'type': 'none'}).type, AuthType.none);
    });

    test('a folder\'s auth and headers flow down to requests that set none of their own', () {
      final text = _export([
        _workspace('wrk_1', 'W'),
        _group('fld_1', 'wrk_1', 'Secured',
            auth: {'type': 'bearer', 'token': 'folder-token'},
            headers: [
              {'name': 'X-Team', 'value': 'blue'},
              {'name': 'X-Shared', 'value': 'from-folder'},
            ]),
        _request('req_a', 'fld_1', 'Inherits'),
        _request('req_b', 'fld_1', 'Own auth',
            auth: {'type': 'basic', 'username': 'u', 'password': 'p'},
            headers: [
              {'name': 'x-shared', 'value': 'own'},
            ]),
      ]);
      final items = (InsomniaParser.parse(text).workspaces.single.collection.items.single as ImportedFolder).children;
      final inherits = _req(items, 'Inherits');
      final own = _req(items, 'Own auth');

      expect(inherits.auth.type, AuthType.bearer);
      expect(inherits.auth.bearerToken, 'folder-token');
      expect(inherits.headers.map((h) => (h.key, h.value)), [('X-Team', 'blue'), ('X-Shared', 'from-folder')]);
      expect(own.auth.type, AuthType.basic);
      expect(own.headers.map((h) => (h.key, h.value)), [('X-Team', 'blue'), ('x-shared', 'own')]);
    });
  });

  group('shape of the export', () {
    test('several workspaces give several collections, each with its own environments', () {
      final text = _export([
        _workspace('wrk_a', 'Alpha'),
        _workspace('wrk_b', 'Beta'),
        _request('req_a', 'wrk_a', 'A1'),
        _request('req_b', 'wrk_b', 'B1'),
        _environment('env_a', 'wrk_a', 'Base', {'a': '1'}),
        _environment('env_a_prod', 'env_a', 'Prod', {'a': '2'}),
      ]);
      final parsed = InsomniaParser.parse(text);

      expect(parsed.workspaces.map((w) => w.collection.name), ['Alpha', 'Beta']);
      expect(parsed.workspaces.first.environments.single.name, 'Prod');
      expect(parsed.workspaces.last.environments, isEmpty);
    });

    test('a request whose workspace is not in the file lands in a collection of its own', () {
      final text = _export([_request('req_1', 'wrk_gone', 'Lonely')]);
      final parsed = InsomniaParser.parse(text);

      expect(parsed.workspaces.single.collection.name, 'Imported from Insomnia');
      expect((parsed.workspaces.single.collection.items.single as ImportedRequest).name, 'Lonely');
    });

    test('requests of other kinds (gRPC, WebSocket) are left out', () {
      final text = _export([
        _workspace('wrk_1', 'W'),
        {'_id': 'greq_1', '_type': 'grpc_request', 'parentId': 'wrk_1', 'name': 'rpc'},
        {'_id': 'ws_1', '_type': 'websocket_request', 'parentId': 'wrk_1', 'name': 'socket'},
        _request('req_1', 'wrk_1', 'Plain'),
      ]);

      expect(InsomniaParser.parse(text).workspaces.single.collection.items.map((i) => i.name), ['Plain']);
    });

    test('a document that is not an Insomnia export is rejected', () {
      expect(() => InsomniaParser.parse('{"hello": "world"}'), throwsA(isA<ImportException>()));
      expect(() => InsomniaParser.parse('   '), throwsA(isA<ImportException>()));
      expect(() => InsomniaParser.parse('[1, 2]'), throwsA(isA<ImportException>()));
    });

    test('an export with no workspace, folder or request is rejected', () {
      expect(() => InsomniaParser.parse(_export([])), throwsA(isA<ImportException>()));
    });

    test('an Insomnia design document is rejected with a hint', () {
      expect(
        () => InsomniaParser.parse('type: spec.insomnia.rest/5.0\nname: Spec\n'),
        throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('design document'))),
      );
    });
  });

  group('Insomnia v5 YAML', () {
    const yaml = r'''
type: collection.insomnia.rest/5.0
name: Bookshop
meta:
  id: wrk_5
  created: 1700000000000
collection:
  - url: https://api.bookshop.test/health
    name: Health
    meta:
      id: req_h
      sortKey: -1
    method: GET
  - name: Books
    meta:
      id: fld_books
      sortKey: -3
    authentication:
      type: bearer
      token: '{{ _.token }}'
    children:
      - url: '{{ _.base_url }}/books'
        name: Add book
        meta:
          id: req_add
          sortKey: -1
        method: POST
        headers:
          - name: X-Trace
            value: on
            disabled: true
        parameters:
          - name: draft
            value: "true"
        body:
          mimeType: application/json
          text: |-
            {"title": "Dune"}
      - url: '{{ _.base_url }}/books'
        name: List books
        meta:
          id: req_list
          sortKey: -2
        method: GET
        authentication:
          type: none
environments:
  name: Base Environment
  meta:
    id: env_base
  data:
    base_url: https://api.bookshop.test
    token: t0ken
  subEnvironments:
    - name: Staging
      meta:
        id: env_stage
      data:
        base_url: https://staging.bookshop.test
''';

    late ParsedInsomniaWorkspace workspace;

    setUp(() => workspace = InsomniaParser.parse(yaml).workspaces.single);

    test('the collection tree, ordered by sortKey', () {
      expect(workspace.collection.name, 'Bookshop');
      expect(workspace.collection.items.map((i) => i.name), ['Books', 'Health']);
      final books = _folder(workspace.collection.items, 'Books');
      expect(books.children.map((c) => c.name), ['List books', 'Add book']);
    });

    test('requests keep body, disabled headers, params and folder auth', () {
      final add = _req(_folder(workspace.collection.items, 'Books').children, 'Add book');

      expect(add.method, HttpMethod.post);
      expect(add.url, '{{base_url}}/books');
      expect(add.headers.single.enabled, isFalse);
      expect(add.queryParams.single.key, 'draft');
      expect(add.body.rawText, '{"title": "Dune"}');
      expect(add.auth.type, AuthType.bearer);
      expect(add.auth.bearerToken, '{{token}}');
    });

    test('an explicit "none" beats the folder\'s auth', () {
      final list = _req(_folder(workspace.collection.items, 'Books').children, 'List books');

      expect(list.auth.type, AuthType.none);
    });

    test('environments: base data becomes variables, subEnvironments are kept', () {
      expect({for (final v in workspace.collection.variables) v.key: v.value}, {
        'base_url': 'https://api.bookshop.test',
        'token': 't0ken',
      });
      expect(workspace.environments.single.name, 'Staging');
      expect(workspace.environments.single.variables.single.value, 'https://staging.bookshop.test');
    });
  });

  group('import into the database', () {
    late InMemoryDb db;
    late ImportInsomniaUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportInsomniaUseCase(db.writer, db.collectionRepository, db.environmentRepository);
    });

    test('creates the collection tree, variables and environments and reports the counts', () async {
      final summary = await useCase(_petStoreExport());

      expect(summary.format, ImportFormat.insomnia);
      expect(summary.collectionName, 'Pet Store');
      expect(summary.folders, 2);
      expect(summary.requests, 5);
      expect(summary.environments, 1);

      final collectionId = summary.collectionIds.single;
      expect(db.collections.single.name, 'Pet Store');
      final folders = {for (final f in db.folders) f.name: f};
      expect(folders['Admin']!.parentFolderId, folders['Pets']!.id);
      expect(folders['Pets']!.parentFolderId, isNull);

      final create = db.requestsOf(collectionId).firstWhere((r) => r.name == 'Create pet');
      expect(create.folderId, folders['Pets']!.id);
      expect(create.method, HttpMethod.post);
      expect(create.body.rawText, '{"name": "{{pet_name}}"}');
      expect(create.auth.type, AuthType.basic);
      expect(db.requestsOf(collectionId).firstWhere((r) => r.name == 'Health').folderId, isNull);

      expect(db.variables.where((v) => v.collectionId == collectionId).map((v) => v.key), contains('base_url'));
      expect(db.environments.single.name, 'Pet Store - Development');
      expect(db.environmentVariables.map((v) => v.key), ['base_url', 'debug']);
      expect(db.environments.single.isActive, isFalse);
    });

    test('several workspaces give several collections', () async {
      final text = _export([
        _workspace('wrk_a', 'Alpha'),
        _workspace('wrk_b', 'Beta'),
        _request('req_a', 'wrk_a', 'A1'),
        _request('req_b', 'wrk_b', 'B1'),
      ]);
      final summary = await useCase(text);

      expect(summary.collectionIds, hasLength(2));
      expect(summary.collectionName, isNull);
      expect(db.collections.map((c) => c.name), ['Alpha', 'Beta']);
      expect(summary.requests, 2);
    });

    test('a write that fails midway leaves nothing behind', () async {
      db.failSaveRequestOnCall = 3;

      await expectLater(useCase(_petStoreExport()), throwsA(isA<StateError>()));

      expect(db.collections, isEmpty);
      expect(db.requests, isEmpty);
      expect(db.folders, isEmpty);
      expect(db.environments, isEmpty);
    });

    test('a failure while creating environments also removes the collections already written', () async {
      db.failCreateEnvironmentOnCall = 1;

      await expectLater(useCase(_petStoreExport()), throwsA(isA<StateError>()));

      expect(db.collections, isEmpty);
      expect(db.requests, isEmpty);
      expect(db.environments, isEmpty);
    });

    test('unrelated data is untouched', () async {
      final existing = await db.collectionRepository.createCollection('Mine');

      await useCase(_petStoreExport());

      expect(db.collections.map((c) => c.name), ['Mine', 'Pet Store']);
      expect(existing, db.collections.first.id);
    });
  });
}
