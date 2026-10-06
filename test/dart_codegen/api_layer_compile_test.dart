// The generated API layer for a collection full of awkward requests: written to
// a real folder, read back, and every file parsed with the Dart analyzer. A
// missing quote, an unescaped `$`, a duplicate parameter or a use case that
// overwrote another all show up here instead of in the user's project.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/generated_files_writer.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';

const _secretKey = 'abcdef1234567890SECRETkey';
const _secretQuery = 'sk_live_abcdefghijklmnopqrstuv';
const _basicCredential = 'dXNlcjpwYXNzd29yZA==';

List<ApiSpecRequest> _tricky() => const [
      // The same title in two folders: same method name in each, but one use case class per collection.
      ApiSpecRequest(
        name: 'Get all',
        method: 'GET',
        url: '{{baseUrl}}/users',
        folders: ['Users'],
        exampleResponse: '[{"id":1,"name":"Ann","address":{"city":"Oslo"}}]',
      ),
      ApiSpecRequest(
        name: 'Get all',
        method: 'GET',
        url: '{{baseUrl}}/orders',
        folders: ['Orders'],
        exampleResponse: '[{"id":1,"total":9.5,"items":[{"sku":"a"}]}]',
      ),
      ApiSpecRequest(name: 'Get all', method: 'GET', url: '{{baseUrl}}/orders/archived', folders: ['Orders']),
      ApiSpecRequest(name: 'Metadata', method: 'GET', url: r'{{baseUrl}}/odata/$metadata'),
      ApiSpecRequest(name: "It's a \\ path", method: 'GET', url: r"{{baseUrl}}/it's/a\path/$value"),
      ApiSpecRequest(
        name: 'Names clash',
        method: 'POST',
        url: '{{baseUrl}}/x/{{body}}/{{response}}/:name/{{body}}',
        bodyKind: ApiBodyKind.json,
        bodyText: '{"a":1}',
      ),
      ApiSpecRequest(
        name: 'Headers',
        method: 'GET',
        url: '{{baseUrl}}/h',
        query: [('q', '{{term}}*'), ('api_key', _secretQuery), ('page', '{{page}}'), ('limit', '20')],
        headers: [
          ('X-Api-Version', '2'),
          ('Content-Type', 'application/json'),
          ('Accept', "text/plain; it's"),
          ('X-Api-Key', _secretKey),
          ('X-Trace', r'req-{{trace}}-$x'),
          ('Host', 'example.test'),
          ('Authorization', 'Basic $_basicCredential'),
          ('Authorization', 'Bearer {{token}}'),
        ],
        unsupportedAuth: 'Basic Auth',
      ),
      ApiSpecRequest(
        name: 'Awkward keys',
        method: 'GET',
        url: '{{baseUrl}}/keys',
        exampleResponse: '{"string":{"a":1},"list":{"b":2},"options":{"c":3},"response":{"d":4},"int":{"e":5},'
            '"dateTime":{"f":"2026-01-01T00:00:00Z"},"object":{"g":1},"map":{"h":2},"bool":{"i":true}}',
      ),
      ApiSpecRequest(name: 'List body', method: 'PUT', url: '{{baseUrl}}/list', bodyKind: ApiBodyKind.json, bodyText: '[1,2,3]'),
      ApiSpecRequest(name: 'Text body', method: 'POST', url: '{{baseUrl}}/t', bodyKind: ApiBodyKind.text, bodyText: 'hello'),
      ApiSpecRequest(
        name: 'Form',
        method: 'POST',
        url: '{{baseUrl}}/f',
        bodyKind: ApiBodyKind.form,
        headers: [('Content-Type', 'multipart/form-data')],
      ),
      ApiSpecRequest(name: 'Url encoded', method: 'POST', url: '{{baseUrl}}/u', bodyKind: ApiBodyKind.urlEncoded),
      ApiSpecRequest(
        name: 'Graph',
        method: 'POST',
        url: '{{baseUrl}}/graphql',
        bodyKind: ApiBodyKind.graphql,
        bodyText: "query { a(x: \"'''\") { id } }",
      ),
      ApiSpecRequest(name: 'Options', method: 'OPTIONS', url: '{{baseUrl}}/o'),
      ApiSpecRequest(name: 'Class', method: 'GET', url: '{{baseUrl}}/class'),
      ApiSpecRequest(name: 'To Json', method: 'GET', url: '{{baseUrl}}/tojson'),
    ];

/// Top-level `class X` / `enum X` / `mixin X` names declared in [source].
Set<String> _declared(String source) => {
      for (final m in RegExp(r'^(?:(?:abstract|final|base|sealed|interface|mixin)\s+)*(?:class|enum)\s+(\w+)', multiLine: true).allMatches(source))
        m[1]!,
    };

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('postpilot_api_layer_'));
  tearDown(() => dir.deleteSync(recursive: true));

  for (final style in DartModelStyle.values) {
    for (final domain in [true, false]) {
      test('writes a parseable, self-consistent project (${style.name}, domain layer: $domain)', () async {
        final result = const ApiLayerGenerator().generate(
          'Tricky API',
          _tricky(),
          options: ApiLayerOptions(packageName: 'tricky_app', modelStyle: style, domainLayer: domain),
        );
        final written = await writeFilesToFolder(dir.path, {for (final f in result.files) f.path: f.content});
        expect(written.skipped, isEmpty);
        expect(written.written, hasLength(result.files.length));
        expect(result.files.map((f) => f.path).toSet(), hasLength(result.files.length), reason: 'no file is generated twice');

        final onDisk = <String, String>{};
        for (final f in result.files) {
          onDisk[f.path] = File('${dir.path}/${f.path}').readAsStringSync();
          expect(onDisk[f.path], f.content);
        }

        // 1. Every file is valid Dart syntax.
        for (final entry in onDisk.entries) {
          final parsed = parseString(content: entry.value, path: entry.key, throwIfDiagnostics: false);
          expect(parsed.errors, isEmpty, reason: '${entry.key}: ${parsed.errors.map((e) => e.message).join('; ')}\n${entry.value}');
        }

        // 2. Every import of the generated package points at a generated file.
        final importPattern = RegExp(r"import 'package:tricky_app/([^']+)';");
        final byPath = {for (final path in onDisk.keys) path: path};
        final imports = <String, List<String>>{};
        for (final entry in onDisk.entries) {
          imports[entry.key] = [
            for (final m in importPattern.allMatches(entry.value)) 'lib/${m[1]}',
          ];
          for (final target in imports[entry.key]!) {
            expect(byPath.containsKey(target), isTrue, reason: '${entry.key} imports $target, which was not generated');
          }
        }

        // 3. Every generated type a file mentions is declared in it or in a file it imports.
        final declared = {for (final e in onDisk.entries) e.key: _declared(e.value)};
        final mention = RegExp(r'\b([A-Z]\w*(?:UseCase|Repository|RepositoryImpl|RemoteDataSource|Params|Request\d*|Response\d*))\b');
        for (final entry in onDisk.entries) {
          final visible = {...declared[entry.key]!, for (final i in imports[entry.key]!) ...?declared[i]};
          for (final m in mention.allMatches(entry.value)) {
            final name = m[1]!;
            if (name == 'RequestOptions' || name == 'BaseOptions') continue;
            expect(visible, contains(name), reason: '${entry.key} uses $name without declaring or importing it');
          }
        }

        // 4. No class is declared twice among the files that are not DTOs (use cases, repositories, data sources).
        final seen = <String, String>{};
        for (final entry in onDisk.entries) {
          if (entry.key.contains('/models/')) continue;
          for (final name in declared[entry.key]!) {
            expect(seen.containsKey(name), isFalse, reason: '$name is declared in ${entry.key} and in ${seen[name]}');
            seen[name] = entry.key;
          }
        }
      });
    }
  }

  test('use cases of two folders with the same title do not overwrite each other', () {
    final r = const ApiLayerGenerator().generate('Tricky API', _tricky(), options: const ApiLayerOptions(packageName: 'tricky_app'));
    final paths = r.files.map((f) => f.path).toList();
    expect(paths, containsAll([
      'lib/features/tricky_api/domain/usecases/users_get_all_usecase.dart',
      'lib/features/tricky_api/domain/usecases/orders_get_all_usecase.dart',
      // The second "Get all" in Orders is getAll2 in its group, which no other group has: no prefix needed.
      'lib/features/tricky_api/domain/usecases/get_all2_usecase.dart',
    ]));
    expect(paths.where((p) => p.endsWith('/get_all_usecase.dart')), isEmpty);
    String content(String path) => r.files.firstWhere((f) => f.path == path).content;
    final users = content('lib/features/tricky_api/domain/usecases/users_get_all_usecase.dart');
    expect(users, contains('final class UsersGetAllUseCase implements UseCase<List<GetAllResponse>, NoParams>'));
    expect(users, contains('_repository.getAll()'));
    final orders = content('lib/features/tricky_api/domain/usecases/orders_get_all_usecase.dart');
    expect(orders, contains('final class OrdersGetAllUseCase'));
    expect(orders, contains('OrdersRepository'));
    final injection = content('lib/features/tricky_api/tricky_api_injection.dart');
    expect(injection, contains('registerLazySingleton<UsersGetAllUseCase>'));
    expect(injection, contains('registerLazySingleton<OrdersGetAllUseCase>'));
    expect(injection, contains("usecases/users_get_all_usecase.dart'"));
  });

  test('a path keeps its literal characters: \$ and quotes are escaped, arguments are URL-encoded', () {
    final r = const ApiLayerGenerator().generate('Tricky API', _tricky(), options: const ApiLayerOptions(domainLayer: false));
    final ds = r.files.firstWhere((f) => f.path.endsWith('tricky_api_remote_data_source.dart')).content;
    expect(ds, contains(r"_dio.get<dynamic>('/odata/\$metadata')"));
    expect(ds, contains(r"`GET /odata/$metadata`"));
    expect(ds, contains(r"_dio.get<dynamic>('/it\'s/a\\path/\$value')"));
    // `body` and `response` are taken by the method itself, and the repeated variable is one argument.
    expect(ds, contains('required String body, required String response2, required String name, required NamesClashRequest body2'));
    expect(ds, contains(r"'/x/${Uri.encodeComponent(body)}/${Uri.encodeComponent(response2)}/${Uri.encodeComponent(name)}/${Uri.encodeComponent(body)}'"));
    expect(ds, contains('data: body2.toJson()'));
  });

  test('static headers are written out, credentials never are, and what is left out is said so', () {
    final r = const ApiLayerGenerator().generate('Tricky API', _tricky(), options: const ApiLayerOptions(domainLayer: false));
    final ds = r.files.firstWhere((f) => f.path.endsWith('tricky_api_remote_data_source.dart')).content;
    final all = r.files.map((f) => f.content).join('\n');
    expect(ds, contains("'X-Api-Version': '2'"));
    expect(ds, contains("'Content-Type': 'application/json'"));
    expect(ds, contains(r"'Accept': 'text/plain; it\'s'"));
    expect(ds, contains(r"'X-Trace': 'req-${trace}-\$x'"));
    expect(ds, contains("'X-Api-Key': xApiKey"));
    expect(ds, contains("'Authorization': authorization"));
    expect(ds, contains(r"'q': '${term}*'"));
    expect(ds, contains("if (page != null) 'page': page"));
    expect(ds, contains("'limit': limit"));
    expect(ds, contains("if (apiKey != null) 'api_key': apiKey"));
    // The credentials of the saved request stay out of the generated source.
    for (final secret in [_secretKey, _secretQuery, _basicCredential]) {
      expect(all, isNot(contains(secret)));
    }
    // The bearer header is the interceptor's job.
    expect(ds, isNot(contains('token')));
    // Dropped on purpose, and written down.
    expect(ds, contains('NOT TRANSLATED: the header "Host" is set by the HTTP client itself.'));
    expect(ds, contains('NOT TRANSLATED: Basic Auth authentication: add it to createApiClient'));
    expect(ds, contains('NOT TRANSLATED: the Content-Type of a form body'));
    expect(r.notes.any((n) => n.contains('Basic Auth authentication')), isTrue);
    expect(r.notes.any((n) => n.contains('"Host"')), isTrue);
  });

  test('DTO classes do not take the names of core types or of Dio', () {
    final r = const ApiLayerGenerator().generate('Tricky API', _tricky(), options: const ApiLayerOptions(domainLayer: false));
    final model = r.files.firstWhere((f) => f.path.endsWith('awkward_keys_response.dart')).content;
    for (final taken in ['String', 'List', 'Map', 'DateTime', 'Object', 'Options', 'Response']) {
      expect(model, isNot(contains('class $taken ')), reason: taken);
    }
    for (final renamed in ['StringModel', 'ListModel', 'MapModel', 'DateTimeModel', 'ObjectModel', 'OptionsModel', 'ResponseModel']) {
      expect(model, contains('class $renamed '), reason: renamed);
    }
    expect(model, contains('final Int intValue;'));
    expect(model, contains('final Bool boolValue;'));
  });

  test('shared files are flagged, the rest is not', () {
    final r = const ApiLayerGenerator().generate('Tricky API', _tricky());
    expect([for (final f in r.files) if (f.shared) f.path]..sort(), ['lib/core/network/api_client.dart', 'lib/core/usecases/usecase.dart']);
    final noDomain = const ApiLayerGenerator().generate('Tricky API', _tricky(), options: const ApiLayerOptions(domainLayer: false));
    expect([for (final f in noDomain.files) if (f.shared) f.path], ['lib/core/network/api_client.dart']);
  });

  test('a base URL with a variable in the host is not written as a default', () {
    final r = const ApiLayerGenerator().generate('X', const [ApiSpecRequest(name: 'Ping', method: 'GET', url: 'https://{{host}}/ping')]);
    expect(r.files.firstWhere((f) => f.path.endsWith('api_client.dart')).content, contains("defaultValue: ''"));
    expect(r.notes.any((n) => n.contains('contains variables')), isTrue);
  });

  test('a package name with spaces or capitals cannot break the imports', () {
    final r = const ApiLayerGenerator().generate('X', const [ApiSpecRequest(name: 'Ping', method: 'GET', url: 'https://a.test/ping')],
        options: const ApiLayerOptions(packageName: "My App's"));
    final injection = r.files.firstWhere((f) => f.path.endsWith('_injection.dart')).content;
    expect(injection, contains("import 'package:my_app_s/features/x/"));
  });
}
