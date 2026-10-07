import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/import_export/domain/entities/imported_collection.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/traffic_recorder/domain/entities/recorded_exchange.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/noise_filter.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recorded_request_mapper.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recording_collection_builder.dart';
import 'package:postpilot/features/traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'exchange_fixtures.dart';

const _base = 'https://api.example.com';
const _auth = RecordedHeader('authorization', 'Bearer tokenvalue1234567890');
const _json = RecordedHeader('content-type', 'application/json');

/// A realistic session: two users fetched, one created, a login, a static file, a preflight, a health check, a refused
/// WebSocket and an order read through a versioned path.
List<RecordedExchange> session() => [
      exchange(id: 1, path: '/users?page=1', requestHeaders: const [RecordedHeader('host', '10.0.2.2:8099'), _auth, RecordedHeader('accept', 'application/json')], responseBody: '[{"id":1}]'),
      exchange(id: 2, path: '/users/42', requestHeaders: const [_auth], responseBody: '{"id":42,"name":"Ada"}'),
      exchange(id: 3, path: '/users/43', requestHeaders: const [_auth], responseBody: '{"id":43,"name":"Bob"}'),
      exchange(id: 4, path: '/users/42', status: 404, requestHeaders: const [_auth], responseBody: '{"error":"gone"}'),
      exchange(id: 5, method: 'POST', path: '/users', status: 201, requestHeaders: const [_json, _auth], requestBody: '{"name":"Ada","password":"hunter2"}', responseBody: '{"id":44}'),
      exchange(
        id: 6,
        method: 'POST',
        path: '/auth/login',
        requestHeaders: const [_json],
        requestBody: '{"email":"a@b.c","password":"pw1"}',
        responseBody: '{"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl","user":{"id":1}}',
      ),
      exchange(id: 7, path: '/static/app.js', responseHeaders: const [RecordedHeader('content-type', 'application/javascript')], responseBody: 'var a=1;'),
      exchange(id: 8, method: 'OPTIONS', path: '/users', status: 204, requestHeaders: const [RecordedHeader('access-control-request-method', 'POST')]),
      exchange(id: 9, path: '/health', responseHeaders: const [RecordedHeader('content-type', 'text/plain')], responseBody: 'ok'),
      exchange(id: 10, path: '/users?page=2', requestHeaders: const [_auth], responseBody: '[{"id":2}]'),
      exchange(id: 11, path: '/chat', status: 501, kind: RecordedKind.refused),
      exchange(id: 12, path: '/api/v1/orders/123e4567-e89b-12d3-a456-426614174000', responseBody: '{"ok":1}'),
    ];

RecordingPlan plan(List<RecordedExchange> calls, [RecordingOptions options = const RecordingOptions(collectionName: 'Recorded from api.example.com')]) =>
    RecordingCollectionBuilder.build(calls, baseUrl: _base, options: options);

List<ImportedRequest> flatten(List<ImportedItem> items) => [
      for (final item in items)
        if (item is ImportedFolder) ...flatten(item.children) else item as ImportedRequest,
    ];

void main() {
  group('RecordingCollectionBuilder with the default options', () {
    late RecordingPlan p;
    setUp(() => p = plan(session()));

    test('counts what is kept, merged and left out before anything is created', () {
      final c = p.counts;
      expect(c.selected, 12);
      expect(c.requests, 6);
      expect(c.folders, 4);
      expect(c.examples, 9);
      expect(c.merged, 3, reason: 'calls 3, 4 and 10 repeat calls 2 and 1');
      expect(c.skipped, {NoiseReason.staticAsset: 1, NoiseReason.preflight: 1, NoiseReason.notForwarded: 1});
      expect(c.skippedTotal, 3);
    });

    test('groups into folders by the first path segment, in the order the calls were first made, naming requests METHOD /path', () {
      final tree = p.collection.items;
      expect([for (final f in tree) (f as ImportedFolder).name], ['users', 'auth', 'health', 'orders']);
      expect([for (final r in flatten(tree)) r.name], [
        'GET /users',
        'GET /users/{userId}',
        'POST /users',
        'POST /auth/login',
        'GET /health',
        'GET /api/v1/orders/{orderUuid}',
      ]);
      expect([for (final r in flatten(tree)) r.method], [
        HttpMethod.get,
        HttpMethod.get,
        HttpMethod.post,
        HttpMethod.post,
        HttpMethod.get,
        HttpMethod.get,
      ]);
    });

    test('requests start with {{baseUrl}}, ids become path variables and the first call is the request', () {
      final urls = [for (final r in flatten(p.collection.items)) r.url];
      expect(urls, [
        '{{baseUrl}}/users?page=1',
        '{{baseUrl}}/users/{{userId}}',
        '{{baseUrl}}/users',
        '{{baseUrl}}/auth/login',
        '{{baseUrl}}/health',
        '{{baseUrl}}/api/v1/orders/{{orderUuid}}',
      ]);
      expect([for (final v in p.collection.variables) '${v.key}=${v.value}'], [
        'baseUrl=$_base',
        'userId=42',
        'orderUuid=123e4567-e89b-12d3-a456-426614174000',
      ]);
    });

    test('literal credentials become secret variables with empty values, in the environment', () {
      final first = flatten(p.collection.items).first;
      expect([for (final h in first.headers) '${h.key}: ${h.value}'], ['Authorization: Bearer {{token}}', 'Accept: application/json']);
      expect(p.secretVariables, ['token', 'password']);
      expect([for (final v in p.environmentVariables) (v.key, v.value, v.secret)], [
        ('baseUrl', _base, false),
        ('token', '', true),
        ('password', '', true),
      ]);
      expect(p.environmentName, 'Recorded from api.example.com');
    });

    test('a request body is kept with its secret fields turned into variables', () {
      final create = flatten(p.collection.items).firstWhere((r) => r.name == 'POST /users');
      expect(create.body.type, BodyType.raw);
      expect(create.body.rawContentType, RawContentType.json);
      expect(create.body.rawText, contains('"name": "Ada"'));
      expect(create.body.rawText, contains('"password": "{{password}}"'));
      expect(create.body.rawText, isNot(contains('hunter2')));
      final login = flatten(p.collection.items).firstWhere((r) => r.name == 'POST /auth/login');
      expect(login.body.rawText, contains('"email": "a@b.c"'));
      expect(login.body.rawText, isNot(contains('pw1')));
    });

    test('later answers of the same request become saved examples, answers are masked, a different status is its own example', () {
      List<PlannedExample> examplesOf(String name) => p.requests.firstWhere((r) => r.request.name == name).examples;
      expect([for (final e in examplesOf('GET /users')) e.name], ['200 OK', '200 OK (2)']);
      expect([for (final e in examplesOf('GET /users/{userId}')) '${e.name}:${e.status}'], ['200 OK:200', '200 OK (2):200', '404 Not Found:404']);
      final login = examplesOf('POST /auth/login').single;
      expect(login.body, contains('"access_token":"••••••"'));
      expect(login.body, isNot(contains('eyJ')));
      expect(login.headers['content-type'], 'application/json');
      expect(p.requests.firstWhere((r) => r.request.name == 'GET /users/{userId}').calls, 3);
    });

    test('no status check unless it was asked for, and then the first call\'s status', () {
      expect(p.requests.every((r) => r.assertedStatus == null), isTrue);
      final withChecks = plan(session(), const RecordingOptions(addStatusAssertions: true));
      expect([for (final r in withChecks.requests) r.assertedStatus], [200, 200, 201, 200, 200, 200]);
    });

    test('a plan is the same whatever order the calls are given in', () {
      final shuffled = plan(session().reversed.toList());
      expect([for (final r in flatten(shuffled.collection.items)) r.name], [for (final r in flatten(p.collection.items)) r.name]);
    });
  });

  group('RecordingCollectionBuilder options', () {
    test('merging off keeps every call as its own request with the ids it had', () {
      final p = plan(session(), const RecordingOptions(mergeDuplicates: false));
      expect(p.counts.requests, 9);
      expect(p.counts.merged, 0);
      final names = [for (final r in flatten(p.collection.items)) r.name];
      expect(names.where((n) => n == 'GET /users/42'), hasLength(2));
      expect(names, contains('GET /users/43'));
      expect(p.collection.variables.map((v) => v.key), ['baseUrl']);
    });

    test('folders off puts everything at the top level', () {
      final p = plan(session(), const RecordingOptions(groupIntoFolders: false));
      expect(p.counts.folders, 0);
      expect(p.collection.items.every((i) => i is ImportedRequest), isTrue);
      expect(p.collection.items, hasLength(6));
    });

    test('each noise switch brings its calls back', () {
      final p = plan(session(), const RecordingOptions(skipAssets: false, skipPreflights: false));
      final names = [for (final r in flatten(p.collection.items)) r.name];
      expect(names, containsAll(['GET /static/app.js', 'OPTIONS /users']));
      expect(p.counts.skipped, {NoiseReason.notForwarded: 1});
    });

    test('a method PostPilot cannot send is skipped, not turned into a GET', () {
      final p = plan([exchange(method: 'PURGE', path: '/cache'), exchange(id: 2)]);
      expect(p.counts.skipped[NoiseReason.unsupportedMethod], 1);
      expect(p.counts.requests, 1);
    });

    test('nothing worth keeping gives an empty plan', () {
      final p = plan([exchange(path: '/a.png'), exchange(id: 2, kind: RecordedKind.refused)]);
      expect(p.isEmpty, isTrue);
      expect(p.counts.skippedTotal, 2);
    });

    test('root-level and versioned paths are filed sensibly', () {
      expect(RecordingCollectionBuilder.folderOf('/'), isNull);
      expect(RecordingCollectionBuilder.folderOf('/42'), isNull);
      expect(RecordingCollectionBuilder.folderOf('/api'), isNull);
      expect(RecordingCollectionBuilder.folderOf('/api/v2/users/7?x=1'), 'users');
      expect(RecordingCollectionBuilder.folderOf('/users/1'), 'users');
    });
  });

  group('RecordedRequestMapper', () {
    RequestDraft map(RecordedExchange e, {bool template = true}) =>
        RecordedRequestMapper.map(e, baseUrl: _base, templatePath: template);

    test('secret query parameters become variables named after the parameter, the rest stays', () {
      final d = map(exchange(path: '/search?q=cats&api_key=SECRET123&token=abc&page=2'));
      expect(d.url, '{{baseUrl}}/search?q=cats&api_key={{apiKey}}&token={{token}}&page=2');
      expect(d.secretVariables, {'apiKey', 'token'});
    });

    test('credential headers become variables: bearer, basic, API keys and cookies', () {
      final d = map(exchange(requestHeaders: const [
        RecordedHeader('authorization', 'Basic dXNlcjpwYXNz'),
        RecordedHeader('x-api-key', 'k_live_abcdefghijklmnop'),
        RecordedHeader('cookie', 'sid=abc123'),
        RecordedHeader('cookie', 'theme=dark'),
        RecordedHeader('x-request-id', 'r-1'),
      ]));
      expect([for (final h in d.headers) '${h.key}: ${h.value}'], [
        'Authorization: Basic {{basicCredentials}}',
        'X-Api-Key: {{apiKey}}',
        'Cookie: {{cookie}}',
        'X-Request-Id: r-1',
      ]);
      expect(d.secretVariables, {'basicCredentials', 'apiKey', 'cookie'});
    });

    test('a header that already is a variable is left as written', () {
      final d = map(exchange(requestHeaders: const [RecordedHeader('authorization', 'Bearer {{token}}')]));
      expect(d.headers.single.value, 'Bearer {{token}}');
      expect(d.secretVariables, isEmpty);
    });

    test('transport headers go, and so does the recorder\'s own address in Origin and Referer, but a web app\'s origin stays', () {
      final d = map(exchange(requestHeaders: const [
        RecordedHeader('host', '10.0.2.2:8099'),
        RecordedHeader('content-length', '5'),
        RecordedHeader('connection', 'keep-alive'),
        RecordedHeader('accept-encoding', 'gzip'),
        RecordedHeader('origin', 'http://10.0.2.2:8099'),
        RecordedHeader('referer', 'http://10.0.2.2:8099/page'),
        RecordedHeader('user-agent', 'MyApp/1.0'),
      ]));
      expect([for (final h in d.headers) h.key], ['User-Agent']);
      final web = map(exchange(requestHeaders: const [RecordedHeader('host', '10.0.2.2:8099'), RecordedHeader('origin', 'https://app.example.com')]));
      expect(web.headers.single.value, 'https://app.example.com');
    });

    test('a form body keeps its fields and hides the secret ones', () {
      final d = map(exchange(
        method: 'POST',
        requestHeaders: const [RecordedHeader('content-type', 'application/x-www-form-urlencoded')],
        requestBody: 'grant_type=password&username=ada&password=pw%21&scope=a%20b',
      ));
      expect(d.body.type, BodyType.urlEncoded);
      expect([for (final f in d.body.urlEncodedFields) '${f.key}=${f.value}'], ['grant_type=password', 'username=ada', 'password={{password}}', 'scope=a b']);
      expect(d.secretVariables, {'password'});
    });

    test('a body that cannot be replayed is left out and says why', () {
      final multipart = map(exchange(
        method: 'POST',
        requestHeaders: const [RecordedHeader('content-type', 'multipart/form-data; boundary=xyz')],
        requestBody: '--xyz\r\ncontent-disposition: form-data; name="a"\r\n\r\n1\r\n--xyz--',
      ));
      expect(multipart.bodyOmitted, BodyOmitted.multipart);
      expect(multipart.body.type, BodyType.none);
      expect(multipart.headers, isEmpty, reason: 'the boundary belonged to the recorded body');
      final binary = map(exchange(
        method: 'POST',
        requestHeaders: const [RecordedHeader('content-type', 'image/png')],
        rawRequestBody: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      ));
      expect(binary.bodyOmitted, BodyOmitted.binary);
      final cut = map(exchange(method: 'POST', requestHeaders: const [_json], requestBody: '{"a":', requestTruncated: true));
      expect(cut.bodyOmitted, BodyOmitted.tooLarge);
      expect(cut.body.type, BodyType.none);
    });

    test('a numeric secret such as a pin is replaced too, an ordinary count is not', () {
      final d = map(exchange(method: 'POST', requestHeaders: const [_json], requestBody: '{"pin":1234,"max_tokens":50,"name":"x"}'));
      expect(d.body.rawText, contains('"pin": "{{pin}}"'));
      expect(d.body.rawText, contains('"max_tokens": 50'));
    });

    test('a body without secrets is kept exactly as it was sent', () {
      const body = '{"a":  1,\n "b": [1,2]}';
      final d = map(exchange(method: 'POST', requestHeaders: const [_json], requestBody: body));
      expect(d.body.rawText, body);
    });

    test('the resend form keeps the real address and the real ids', () {
      final d = RecordedRequestMapper.map(
        exchange(path: '/users/42?x=1', requestHeaders: const [_auth]),
        baseUrl: 'https://api.example.com/v2/',
        useBaseUrlVariable: false,
        templatePath: false,
      );
      expect(d.url, 'https://api.example.com/v2/users/42?x=1');
      expect(d.name, 'GET /users/42');
      expect(d.headers.single.value, 'Bearer {{token}}');
      expect(d.pathVariables, isEmpty);
    });

    test('variable names are made from header and field names', () {
      expect(RecordedRequestMapper.variableNameFor('Authorization'), 'token');
      expect(RecordedRequestMapper.variableNameFor('X-Api-Key'), 'apiKey');
      expect(RecordedRequestMapper.variableNameFor('access_token'), 'accessToken');
      expect(RecordedRequestMapper.variableNameFor('clientSecret'), 'clientSecret');
      expect(RecordedRequestMapper.variableNameFor('123'), 'secret123');
    });
  });

  group('CreateCollectionFromRecordingUseCase', () {
    late InMemoryDb db;
    late CreateCollectionFromRecordingUseCase useCase;
    final savedAt = DateTime.utc(2026, 10, 7, 13);

    setUp(() {
      db = InMemoryDb();
      useCase = CreateCollectionFromRecordingUseCase(db.writer, db.environmentRepository, db.exampleRepository, db.scriptsRepository, now: () => savedAt);
    });

    test('writes the collection through the importer\'s writer: folders and requests in the planned order, with their variables', () async {
      final result = await useCase(plan(session()));

      expect(db.collections.single.name, 'Recorded from api.example.com');
      expect(result.collectionName, 'Recorded from api.example.com');
      expect(result.requests, 6);
      expect(result.folders, 4);
      expect([for (final f in db.folders) f.name], ['users', 'auth', 'health', 'orders']);
      expect([for (final r in db.requests) r.name], [
        'GET /users',
        'GET /users/{userId}',
        'POST /users',
        'POST /auth/login',
        'GET /health',
        'GET /api/v1/orders/{orderUuid}',
      ]);
      final folderOf = {for (final f in db.folders) f.id: f.name};
      expect([for (final r in db.requests) folderOf[r.folderId]], ['users', 'users', 'users', 'auth', 'health', 'orders']);
      expect(db.requests[1].url, '{{baseUrl}}/users/{{userId}}');
      expect({for (final v in db.variables) v.key: v.value}, {
        'baseUrl': _base,
        'userId': '42',
        'orderUuid': '123e4567-e89b-12d3-a456-426614174000',
      });
    });

    test('keeps the answers as examples of the right request, with the time they were saved', () async {
      await useCase(plan(session()));

      expect(db.examples, hasLength(9));
      final byRequest = <String, List<String>>{};
      for (final e in db.examples) {
        final request = db.requests.firstWhere((r) => r.id == e.requestId);
        (byRequest[request.name] ??= []).add(e.name);
      }
      expect(byRequest['GET /users/{userId}'], ['200 OK', '200 OK (2)', '404 Not Found']);
      expect(db.examples.every((e) => e.savedAt == savedAt), isTrue);
      expect(db.examples.any((e) => e.body.contains('eyJ')), isFalse);
      expect(db.examples.first.headers.containsKey(ResponseExampleEntity.truncatedHeader), isFalse);
    });

    test('creates an environment with baseUrl and the secret variables empty, and does not activate it', () async {
      final result = await useCase(plan(session()));

      final environment = db.environments.single;
      expect(environment.name, 'Recorded from api.example.com');
      expect(environment.isActive, isFalse);
      expect([for (final v in db.environmentVariables) (v.key, v.value, v.isSecret, v.enabled)], [
        ('baseUrl', _base, false, true),
        ('token', '', true, true),
        ('password', '', true, true),
      ]);
      expect(result.environmentId, environment.id);
      expect(result.notes.last, contains('"Recorded from api.example.com"'));
      expect(result.notes.last, contains('token, password'));
      expect(result.notes.last, contains('no credential was saved'));
    });

    test('a second recording does not clash with the first one\'s environment', () async {
      await useCase(plan(session()));
      final second = await useCase(plan(session()));

      expect(second.environmentName, 'Recorded from api.example.com (recorded)');
      expect(db.environments.map((e) => e.name), ['Recorded from api.example.com', 'Recorded from api.example.com (recorded)']);
    });

    test('status checks are saved when asked for', () async {
      await useCase(plan(session(), const RecordingOptions(addStatusAssertions: true)));

      expect(db.scripts, hasLength(6));
      final created = db.requests.firstWhere((r) => r.name == 'POST /users');
      final checks = ScriptsJsonCodec.decodeAssertions(db.scripts[created.id]!.assertionsJson);
      expect([for (final c in checks) (c.type, c.expected)], [(AssertionType.statusEquals, '201')]);
    });

    test('no credential value ends up anywhere that was saved', () async {
      await useCase(plan(session()));

      final saved = StringBuffer()
        ..writeAll([for (final r in db.requests) '${r.url} ${r.headers.map((h) => '${h.key}=${h.value}')} ${r.body.rawText}'])
        ..writeAll([for (final e in db.examples) '${e.headers} ${e.body}'])
        ..writeAll([for (final v in db.environmentVariables) v.value])
        ..writeAll([for (final v in db.variables) v.value]);
      for (final secret in ['tokenvalue1234567890', 'hunter2', 'pw1', 'eyJhbGci']) {
        expect(saved.toString(), isNot(contains(secret)), reason: secret);
      }
    });

    test('a failure part-way removes the collection, its examples and the environment', () async {
      db.failSaveRequestOnCall = 3;

      await expectLater(useCase(plan(session())), throwsA(isA<StateError>()));

      expect(db.collections, isEmpty);
      expect(db.requests, isEmpty);
      expect(db.examples, isEmpty);
      expect(db.environments, isEmpty);
      expect(db.environmentVariables, isEmpty);
    });

    test('an environment that cannot be created leaves nothing behind either', () async {
      db.failCreateEnvironmentOnCall = 1;

      await expectLater(useCase(plan(session())), throwsA(isA<StateError>()));

      expect(db.collections, isEmpty);
      expect(db.environments, isEmpty);
    });

    test('an empty plan is refused with a sentence', () async {
      await expectLater(
        useCase(plan([exchange(path: '/a.png')])),
        throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('no call that can be turned into a request'))),
      );
      expect(db.collections, isEmpty);
    });
  });
}
