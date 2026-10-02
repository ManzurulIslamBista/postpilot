import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/services/curl_script_parser.dart';
import 'package:postpilot/features/import_export/domain/services/curl_script_writer.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'support/in_memory_import_export_fakes.dart';

void main() {
  group('script layout', () {
    test('a shebang, a header, a banner per folder and each name right above its command', () {
      final script = CurlScriptWriter.write(collectionName: 'My API', entries: const [
        CurlScriptEntry.generated(name: 'Get user', folder: 'Users', command: "curl --location --request GET 'https://a.test/u'"),
        CurlScriptEntry.generated(name: 'List users', folder: 'Users', command: "curl --location --request GET 'https://a.test/users'"),
        CurlScriptEntry.generated(name: 'Ping', folder: null, command: "curl --location --request GET 'https://a.test/ping'"),
      ]);

      expect(script, '''
#!/usr/bin/env bash
# PostPilot collection: My API
# Variables and secrets are written with the values they have right now, in plain text.

# --- Users ---

# Get user
curl --location --request GET 'https://a.test/u'

# List users
curl --location --request GET 'https://a.test/users'

# --- Collection root ---

# Ping
curl --location --request GET 'https://a.test/ping'
''');
    });

    test('a collection without folders gets no banner', () {
      final script = CurlScriptWriter.write(
        collectionName: 'Flat',
        entries: const [CurlScriptEntry.generated(name: 'A', folder: null, command: 'curl https://a.test')],
      );

      expect(script, isNot(contains('---')));
    });

    test('a name with line breaks stays one comment line', () {
      final script = CurlScriptWriter.write(
        collectionName: 'C',
        entries: const [CurlScriptEntry.generated(name: 'First\nSecond\r\n  Third', folder: null, command: 'curl https://a.test')],
      );

      expect(script, contains('# First Second Third\ncurl https://a.test'));
    });

    test('a folder name with line breaks cannot start an executable line', () {
      final script = CurlScriptWriter.write(
        collectionName: 'C',
        entries: const [
          CurlScriptEntry.generated(name: 'A', folder: 'x\nrm -rf ~ #', command: 'curl https://a.test'),
          CurlScriptEntry.generated(name: 'B', folder: 'y\r\nrm -rf /  touch z', command: 'curl https://b.test'),
        ],
      );

      expect(script, contains('\n# --- x rm -rf ~ # ---\n'));
      for (final line in script.split('\n')) {
        expect(line.isEmpty || line.startsWith('#') || line.startsWith('curl '), isTrue, reason: 'unexpected executable line: $line');
      }
    });

    test('a request that could not be rendered is explained in a comment', () {
      final script = CurlScriptWriter.write(
        collectionName: 'C',
        entries: const [CurlScriptEntry.failed(name: 'Broken', folder: null, failure: 'Bad JWT\npayload')],
      );

      expect(script, contains('# Broken\n# Could not generate a command for this request: Bad JWT payload\n'));
    });
  });

  group('export use case', () {
    late InMemoryDb db;
    late ExportCurlScriptUseCase useCase;
    late int collectionId;

    setUp(() async {
      db = InMemoryDb();
      useCase = ExportCurlScriptUseCase(
        db.loader,
        GenerateCodeSnippetUseCase(
          BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository),
          db.collectionAuthRepository,
        ),
      );
      collectionId = await db.collectionRepository.createCollection('API');
      await db.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: collectionId, key: 'baseUrl', value: 'https://api.test', enabled: true));
      await db.collectionAuthRepository.setAuthJson(collectionId, const RequestAuth(type: AuthType.bearer, bearerToken: 'tok').toJsonString());
      final users = await db.collectionRepository.createFolder(collectionId: collectionId, name: 'Users');

      Future<void> add(String name, {int? folderId, HttpMethod method = HttpMethod.get, required String url, List<KeyValueItem> headers = const [], RequestBody body = RequestBody.empty, RequestAuth auth = const RequestAuth()}) async {
        final id = await db.requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: name);
        await db.requestRepository.saveRequest(ApiRequestEntity(
          id: id,
          collectionId: collectionId,
          folderId: folderId,
          name: name,
          method: method,
          url: url,
          headers: headers,
          queryParams: const [],
          body: body,
          auth: auth,
        ));
      }

      await add('Get user', folderId: users, url: '{{baseUrl}}/users/1');
      await add('Create user',
          method: HttpMethod.post,
          url: '{{baseUrl}}/users',
          headers: [KeyValueItem(key: 'Content-Type', value: 'application/json')],
          body: const RequestBody(type: BodyType.raw, rawText: '{"name":"O\'Neil"}'),
          auth: RequestAuth.none);
      await add('Bad JWT', url: '{{baseUrl}}/jwt', auth: const RequestAuth(type: AuthType.jwtBearer, jwtPayload: 'not json'));
    });

    test('writes one resolved command per request, with variables and inherited auth applied', () async {
      final result = await useCase(collectionId);

      expect(result.collectionName, 'API');
      expect(result.itemCount, 2);
      expect(result.skipped, 1);
      expect(result.text, startsWith('#!/usr/bin/env bash\n# PostPilot collection: API\n'));
      expect(result.text, contains("# --- Users ---\n\n# Get user\ncurl --location --request GET 'https://api.test/users/1' \\\n--header 'Authorization: Bearer tok'"));
      expect(result.text, contains("# Create user\ncurl --location --request POST 'https://api.test/users' \\\n--header 'Content-Type: application/json' \\\n--data-raw '{\"name\":\"O'\\''Neil\"}'"));
    });

    test('a request the generator rejects is skipped with a comment, the rest is still written', () async {
      final result = await useCase(collectionId);

      expect(result.text, contains('# Bad JWT\n# Could not generate a command for this request:'));
      expect(result.text, isNot(contains('/jwt')));
    });

    test('an unknown collection is a not-found error', () async {
      await expectLater(useCase(999), throwsA(isA<NotFoundException>()));
    });

    test('the script imports back into the same requests', () async {
      final script = (await useCase(collectionId)).text;

      final parsed = CurlScriptParser.parse(script);

      expect(parsed.skipped, 0);
      expect(parsed.requests.map((r) => r.name), ['Get user', 'Create user']);
      final create = parsed.requests.last;
      expect(create.method, HttpMethod.post);
      expect(create.url, 'https://api.test/users');
      expect(create.body.rawText, '{"name":"O\'Neil"}');
      expect(create.body.rawContentType, RawContentType.json);
      expect(create.headers.single.key, 'Content-Type');
      final get = parsed.requests.first;
      expect(get.headers.single.value, 'Bearer tok');
    });
  });

  group('parsing a script', () {
    test('a single command becomes one request named "METHOD /path"', () {
      final parsed = CurlScriptParser.parse("curl -X DELETE 'https://api.test/pets/7?force=1'");

      expect(parsed.requests.single.name, 'DELETE /pets/7');
      expect(parsed.requests.single.method, HttpMethod.delete);
      expect(parsed.requests.single.url, 'https://api.test/pets/7?force=1');
    });

    test('a URL without a path is named after "/"', () {
      expect(CurlScriptParser.parse('curl https://api.test').requests.single.name, 'GET /');
    });

    test('several commands, each named by the comment above it', () {
      final parsed = CurlScriptParser.parse('''
#!/bin/sh
set -e
# PostPilot collection: Pets

# --- Pets ---

# List pets
curl --location --request GET 'https://api.test/pets' \\
--header 'Accept: application/json'

echo done
# Create pet
curl --location --request POST 'https://api.test/pets' \\
--header 'Content-Type: application/json' \\
--data-raw '{"name":"Rex"}'
curl https://api.test/unnamed
''');

      expect(parsed.requests.map((r) => r.name), ['List pets', 'Create pet', 'GET /unnamed']);
      expect(parsed.requests.map((r) => r.method), [HttpMethod.get, HttpMethod.post, HttpMethod.get]);
      expect(parsed.requests[0].headers.single.value, 'application/json');
      expect(parsed.requests[1].body.rawText, '{"name":"Rex"}');
    });

    test('a quoted body may span lines without continuation backslashes', () {
      final parsed = CurlScriptParser.parse('''
# Multi-line body
curl -X POST https://api.test/x -H 'Content-Type: application/json' --data-raw '{
  "a": 1,
  "b": [1, 2]
}'
curl https://api.test/next
''');

      expect(parsed.requests, hasLength(2));
      expect(parsed.requests.first.body.rawText, '{\n  "a": 1,\n  "b": [1, 2]\n}');
      expect(parsed.requests.last.url, 'https://api.test/next');
    });

    test('a shell prompt, curl.exe and Windows line endings', () {
      final parsed = CurlScriptParser.parse('\$ curl.exe https://api.test/a\r\n# Named\r\ncurl https://api.test/b \\\r\n  -H "X-Team: blue"\r\n');

      expect(parsed.requests.map((r) => r.name), ['GET /a', 'Named']);
      expect(parsed.requests.last.headers.single.key, 'X-Team');
    });

    test('basic auth and cookies from the usual flags', () {
      final request = CurlScriptParser.parse("curl -u ann:secret -b 'sid=1' https://api.test/me").requests.single;

      expect(request.auth.type, AuthType.basic);
      expect(request.auth.basicUsername, 'ann');
      expect(request.auth.basicPassword, 'secret');
      expect(request.headers.single.key, 'Cookie');
    });

    test('data without a Content-Type is sniffed: JSON stays JSON, anything else is sent as a form like curl does', () {
      final json = CurlScriptParser.parse("curl -d '{\"a\":1}' https://api.test/j").requests.single;
      expect(json.body.rawContentType, RawContentType.json);
      expect(json.headers, isEmpty);

      final form = CurlScriptParser.parse("curl -d 'a=1&b=2' https://api.test/f").requests.single;
      expect(form.method, HttpMethod.post);
      expect(form.body.rawText, 'a=1&b=2');
      expect(form.headers.single.key, 'Content-Type');
      expect(form.headers.single.value, 'application/x-www-form-urlencoded');
    });

    test('a declared Content-Type decides the raw type and is not repeated', () {
      final request = CurlScriptParser.parse("curl -H 'content-type: application/xml' -d '<a/>' https://api.test/x").requests.single;

      expect(request.body.rawContentType, RawContentType.xml);
      expect(request.headers, hasLength(1));
    });

    test('commands that cannot be read are counted and skipped', () {
      final parsed = CurlScriptParser.parse('curl -X GET\ncurl https://api.test/ok -H\ncurl https://api.test/fine');

      expect(parsed.requests.single.url, 'https://api.test/fine');
      expect(parsed.skipped, 2);
    });

    test('text with no curl command gives nothing', () {
      final parsed = CurlScriptParser.parse('echo hello\n# just a comment\nls -la');

      expect(parsed.requests, isEmpty);
      expect(parsed.skipped, 0);
    });
  });

  group('import use case', () {
    late InMemoryDb db;
    late ImportCurlScriptUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportCurlScriptUseCase(db.writer);
    });

    test('creates a new collection for the commands by default', () async {
      final summary = await useCase(const ImportCurlScriptParams(script: '# One\ncurl https://a.test/1\n# Two\ncurl -X POST https://a.test/2 -d \'{}\''));

      expect(summary.format, ImportFormat.curl);
      expect(summary.collectionName, 'Imported cURL');
      expect(summary.requests, 2);
      expect(db.collections.single.name, 'Imported cURL');
      final requests = db.requestsOf(summary.collectionIds.single);
      expect(requests.map((r) => r.name), ['One', 'Two']);
      expect(requests.last.body.rawText, '{}');
      expect(summary.description, 'Imported "Imported cURL": 2 requests');
    });

    test('adds to an existing collection and folder when given one', () async {
      final collectionId = await db.collectionRepository.createCollection('Mine');
      final folderId = await db.collectionRepository.createFolder(collectionId: collectionId, name: 'Inbox');

      final summary = await useCase(ImportCurlScriptParams(script: 'curl https://a.test/1', collectionId: collectionId, folderId: folderId));

      expect(db.collections, hasLength(1));
      expect(summary.collectionIds, [collectionId]);
      expect(summary.collectionName, isNull);
      expect(db.requestsOf(collectionId).single.folderId, folderId);
      expect(summary.description, 'Imported: 1 request');
    });

    test('reports commands it had to skip', () async {
      final summary = await useCase(const ImportCurlScriptParams(script: 'curl https://a.test/ok\ncurl -X GET'));

      expect(summary.requests, 1);
      expect(summary.skipped, 1);
    });

    test('text without a usable command is an error and creates nothing', () async {
      await expectLater(useCase(const ImportCurlScriptParams(script: 'echo hi')), throwsA(isA<ImportException>()));

      expect(db.collections, isEmpty);
    });
  });
}
