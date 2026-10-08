// "Clean up (recommended)" for a HAR recording: the traffic recorder's own noise filter, path normaliser, collection builder and masking applied to
// what a browser saved. The fixture is a hand-written recording of twelve entries (see har_fixtures.dart); every number below is counted from it by hand.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/entities/imported_collection.dart';
import 'package:postpilot/features/import_export/domain/services/har_cleanup.dart';
import 'package:postpilot/features/import_export/domain/services/har_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/noise_filter.dart';
import 'package:postpilot/features/traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'har_fixtures.dart';

List<ImportedRequest> _requestsOf(List<ImportedItem> items) {
  final found = <ImportedRequest>[];
  for (final item in items) {
    switch (item) {
      case ImportedFolder():
        found.addAll(_requestsOf(item.children));
      case ImportedRequest():
        found.add(item);
    }
  }
  return found;
}

/// Every string a plan would put on disk: addresses, header and body text, variables, saved examples.
String _everythingIn(HarCleanup cleanup) {
  final out = StringBuffer();
  for (final request in _requestsOf(cleanup.plan.collection.items)) {
    out
      ..writeln(request.url)
      ..writeln(request.body.rawText);
    for (final h in [...request.headers, ...request.queryParams]) {
      out.writeln('${h.key}: ${h.value}');
    }
  }
  for (final v in cleanup.plan.collection.variables) {
    out.writeln('${v.key}=${v.value}');
  }
  for (final v in cleanup.plan.environmentVariables) {
    out.writeln('${v.key}=${v.value}');
  }
  for (final planned in cleanup.plan.requests) {
    for (final e in planned.examples) {
      out
        ..writeln(e.body)
        ..writeln(e.headers);
    }
  }
  return out.toString();
}

void main() {
  group('what is kept and what is left out', () {
    late HarCleanup cleanup;

    setUp(() => cleanup = HarCleanup.build(shopHarText()));

    test('the host with most calls of the app\'s own is the API, and every other call to another host is counted', () {
      expect(cleanup.baseUrl, 'https://app.shop.test');
      expect(cleanup.host, 'app.shop.test');
      expect(cleanup.plan.collection.name, 'HAR import - app.shop.test');
      expect(cleanup.otherHosts, {'api.other.test': 1});
      expect(cleanup.entries, 12);
    });

    test('fonts, stylesheets and static files are dropped, by the browser\'s own label and by the file extension', () {
      // 0 (label font), 1 (label stylesheet), 2 (icons.woff2 served as octet-stream).
      expect(cleanup.dropped[NoiseReason.staticAsset], 3);
    });

    test('analytics hosts and CORS preflights are dropped, one each', () {
      expect(cleanup.dropped[NoiseReason.analytics], 1);
      expect(cleanup.dropped[NoiseReason.preflight], 1);
      expect(cleanup.droppedTotal, 5);
    });

    test('a data: URL is not a call, and a call that got no answer is left out apart from the noise', () {
      expect(cleanup.unreadable, 1);
      expect(cleanup.unanswered, 1);
    });

    test('everything that is not a request adds up: 12 entries, 4 calls kept', () {
      // 1 not a call + 1 no answer + 5 noise + 1 other host.
      expect(cleanup.skipped, 8);
      expect(cleanup.entries - cleanup.skipped, 4);
    });

    test('four calls make three requests: the two users calls are one', () {
      expect(_requestsOf(cleanup.plan.collection.items).map((r) => r.name), ['GET /api/users/{userId}', 'POST /api/orders', 'GET /api/orders']);
      expect(cleanup.plan.counts.requests, 3);
      expect(cleanup.plan.counts.merged, 1);
    });

    test('requests are grouped into folders by the first path segment after api', () {
      final folders = cleanup.plan.collection.items.whereType<ImportedFolder>().toList();

      expect(folders.map((f) => f.name), ['users', 'orders']);
      expect(folders.first.children.map((c) => c.name), ['GET /api/users/{userId}']);
      expect(folders.last.children.map((c) => c.name), ['POST /api/orders', 'GET /api/orders']);
      expect(cleanup.plan.counts.folders, 2);
    });

    test('of the two repeated calls the more complete one is the request: its query, its extra header, its id', () {
      final users = _requestsOf(cleanup.plan.collection.items).first;

      expect(users.method, HttpMethod.get);
      expect(users.url, '{{baseUrl}}/api/users/{{userId}}?expand=roles');
      expect(users.headers.map((h) => h.key), containsAll(['Accept', 'Authorization', 'Cookie', 'X-Request-Id']));
      final variables = {for (final v in cleanup.plan.collection.variables) v.key: v.value};
      expect(variables, {'baseUrl': 'https://app.shop.test', 'userId': '98'});
    });

    test('the other call is not lost: both answers are saved as examples of the one request', () {
      final users = cleanup.plan.requests.first;

      expect(users.calls, 2);
      expect(users.examples.map((e) => e.name), ['200 OK', '200 OK (2)']);
      expect(users.examples.map((e) => jsonDecode(e.body)['id']), [98, 12]);
    });

    test('the transport headers of the browser are gone, and Host in particular', () {
      for (final request in _requestsOf(cleanup.plan.collection.items)) {
        final names = request.headers.map((h) => h.key.toLowerCase()).toSet();
        expect(names.intersection({'host', 'accept-encoding', 'content-length', ':authority'}), isEmpty, reason: request.name);
      }
    });

    test('a JSON body is kept as it was sent', () {
      final order = _requestsOf(cleanup.plan.collection.items)[1];

      expect(order.body.rawText, '{"sku":"A1","qty":2}');
    });
  });

  group('credentials', () {
    late HarCleanup cleanup;

    setUp(() => cleanup = HarCleanup.build(shopHarText()));

    test('a bearer token and a session cookie become secret variables, as the recorder makes them', () {
      final users = _requestsOf(cleanup.plan.collection.items).first;
      final header = {for (final h in users.headers) h.key: h.value};

      expect(header['Authorization'], 'Bearer {{token}}');
      expect(header['Cookie'], '{{cookie}}');
      expect(cleanup.plan.secretVariables.toSet(), {'token', 'cookie'});
      expect({for (final v in cleanup.plan.environmentVariables) v.key: v.value}, {'baseUrl': 'https://app.shop.test', 'token': '', 'cookie': ''});
    });

    test('neither the token nor the cookie value is in anything that would be saved', () {
      final everything = _everythingIn(cleanup);

      expect(everything, isNot(contains(harToken)));
      expect(everything, isNot(contains('eyJhbGci')));
      expect(everything, isNot(contains(harCookie)));
      expect(everything, contains('Bearer {{token}}'));
    });
  });

  group('the notes say what happened', () {
    test('what was left out, by kind, and why the other host is not here', () {
      final notes = HarCleanup.build(shopHarText()).notes;

      expect(notes, contains('Left out 5 calls that are not calls of the app\'s API: 3 static files, 1 analytics or tracker call, 1 CORS preflight.'));
      expect(notes, contains('1 call got no answer in the browser (blocked, cancelled or failed) and was left out.'));
      expect(notes, contains('1 entry was not an http(s) call (a data: URL, a WebSocket) and was left out.'));
      expect(notes.any((n) => n.startsWith('1 call to other hosts (api.other.test) was left out: this collection works against https://app.shop.test')), isTrue);
      expect(notes.any((n) => n.startsWith('Repeated calls became one request each: 1 call was merged.')), isTrue);
      expect(notes.last, '4 responses saved as examples, with credentials in them masked.');
    });

    test('a recording that is all noise has an empty plan', () {
      final cleanup = HarCleanup.build(staticOnlyHarText());

      expect(cleanup.plan.isEmpty, isTrue);
      expect(cleanup.droppedTotal, 3);
      expect(cleanup.notes.first, 'Left out 3 calls that are not calls of the app\'s API: 2 static files, 1 analytics or tracker call.');
    });
  });

  group('the file', () {
    test('text that is not a HAR file is refused the way the plain import refuses it', () {
      expect(() => HarCleanup.build('{"hello":"world"}'), throwsA(isA<ImportException>()));
      expect(() => HarCleanup.build('not json'), throwsFormatException);
    });

    test('Firefox writes no resource type: the type of the answer says what a call is', () {
      final har = jsonEncode({
        'log': {
          'entries': [
            for (final (url, mime) in [
              ('https://app.shop.test/a/script', 'application/javascript'),
              ('https://app.shop.test/a/picture', 'image/webp'),
              ('https://app.shop.test/a/sheet', 'text/css; charset=utf-8'),
              ('https://app.shop.test/api/items', 'application/json'),
            ])
              {
                'startedDateTime': '2026-10-08T10:00:00.000Z',
                'request': {'method': 'GET', 'url': url, 'headers': const []},
                'response': {'status': 200, 'statusText': 'OK', 'headers': const [], 'content': {'mimeType': mime, 'text': 'x'}},
              },
          ],
        },
      });

      final cleanup = HarCleanup.build(har);

      expect(cleanup.dropped[NoiseReason.staticAsset], 3);
      expect(_requestsOf(cleanup.plan.collection.items).map((r) => r.name), ['GET /api/items']);
    });

    test('a body Chrome wrote as base64 is decoded, and form fields without text are rebuilt from their params', () {
      final har = jsonEncode({
        'log': {
          'entries': [
            {
              'startedDateTime': '2026-10-08T10:00:00.000Z',
              'request': {
                'method': 'POST',
                'url': 'https://app.shop.test/api/login',
                'headers': [
                  {'name': 'content-type', 'value': 'application/x-www-form-urlencoded'},
                ],
                'postData': {
                  'mimeType': 'application/x-www-form-urlencoded',
                  'params': [
                    {'name': 'login', 'value': 'ann@shop.test'},
                    {'name': 'password', 'value': 'correct horse'},
                  ],
                },
              },
              'response': {
                'status': 200,
                'statusText': 'OK',
                'headers': const [],
                'content': {'mimeType': 'application/json', 'encoding': 'base64', 'text': base64.encode(utf8.encode('{"ok":true}'))},
              },
            },
          ],
        },
      });

      final cleanup = HarCleanup.build(har);

      final login = _requestsOf(cleanup.plan.collection.items).single;
      expect({for (final f in login.body.urlEncodedFields) f.key: f.value}, {'login': 'ann@shop.test', 'password': '{{password}}'});
      expect(cleanup.plan.requests.single.examples.single.body, '{"ok":true}');
      expect(cleanup.plan.secretVariables, contains('password'));
    });
  });

  group('off is today\'s behaviour', () {
    test('the plain import still reads every http call of the same file, in order, with no folders and nothing merged', () {
      final parsed = HarParser.parse(shopHarText());

      expect(parsed.requests.map((r) => r.name), [
        'GET /s/inter/v13/inter.woff2',
        'GET /css/app',
        'GET /assets/icons.woff2',
        'POST /g/collect',
        'GET /api/users/12',
        'GET /api/users/98',
        'POST /api/orders',
        'GET /api/orders',
        'GET /v1/ping',
        'GET /api/health',
      ]);
      // The preflight and the data: URL are the two it has always skipped.
      expect(parsed.skipped, 2);
      expect(parsed.name, 'HAR import - fonts.gstatic.com');
      expect(parsed.requests[4].headers.firstWhere((h) => h.key == 'authorization').value, 'Bearer $harToken');
    });
  });

  group('ImportHarUseCase', () {
    late InMemoryDb db;
    late ImportHarUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportHarUseCase(
        db.writer,
        recorded: CreateCollectionFromRecordingUseCase(db.writer, db.environmentRepository, db.exampleRepository, db.scriptsRepository),
      );
    });

    test('importCleaned writes the collection, its folders, its examples and an environment for the secrets', () async {
      final summary = await useCase.importCleaned(shopHarText());

      expect(summary.format, ImportFormat.har);
      expect(summary.collectionName, 'HAR import - app.shop.test');
      expect((summary.folders, summary.requests, summary.environments, summary.skipped), (2, 3, 1, 8));
      expect(summary.description, 'Imported "HAR import - app.shop.test": 2 folders, 3 requests, 1 environment (8 skipped)');
      expect(db.collections.single.name, 'HAR import - app.shop.test');
      expect(db.folders.map((f) => f.name), ['users', 'orders']);
      expect(db.requests.map((r) => r.name), ['GET /api/users/{userId}', 'POST /api/orders', 'GET /api/orders']);
      expect({for (final v in db.variables) v.key: v.value}, {'baseUrl': 'https://app.shop.test', 'userId': '98'});
      expect(db.examples, hasLength(4));
    });

    test('the environment holds baseUrl and the secrets, empty, and is not switched on', () async {
      final summary = await useCase.importCleaned(shopHarText());

      final environment = db.environments.single;
      expect(environment.name, 'HAR import - app.shop.test');
      expect(environment.isActive, isFalse);
      expect(summary.environmentName, 'HAR import - app.shop.test');
      expect([for (final v in db.environmentVariables) (v.key, v.value, v.isSecret)], [
        ('baseUrl', 'https://app.shop.test', false),
        ('token', '', true),
        ('cookie', '', true),
      ]);
    });

    test('the notes say what was left out, then what the person has to do with the secrets', () async {
      final summary = await useCase.importCleaned(shopHarText());

      expect(summary.notes.first, startsWith('Left out 5 calls'));
      expect(summary.notes.last, contains('Created the environment "HAR import - app.shop.test"'));
      expect(summary.notes.last, contains('token, cookie'));
      expect(summary.notes.last, contains('no credential was saved'));
      expect(summary.notesHeading, 'Imported with 8 skipped items');
    });

    test('no credential is stored anywhere', () async {
      await useCase.importCleaned(shopHarText());

      final stored = [
        for (final r in db.requests) '${r.url} ${r.headers.map((h) => h.value).join(' ')} ${r.body.rawText}',
        for (final e in db.examples) '${e.body} ${e.headers}',
        for (final v in db.environmentVariables) v.value,
        for (final v in db.variables) v.value,
      ].join('\n');
      expect(stored, isNot(contains(harToken)));
      expect(stored, isNot(contains(harCookie)));
    });

    test('a recording with no API call in it is an error that says how to import it anyway, and creates nothing', () async {
      await expectLater(
        useCase.importCleaned(staticOnlyHarText()),
        throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('Untick "Clean up"'))),
      );

      expect(db.collections, isEmpty);
      expect(db.environments, isEmpty);
    });

    test('a second import does not clash with the first one\'s environment', () async {
      await useCase.importCleaned(shopHarText());
      final second = await useCase.importCleaned(shopHarText());

      expect(second.environmentName, 'HAR import - app.shop.test (recorded)');
    });

    test('without the recorder\'s writer the clean-up is unavailable, and the plain import is untouched', () async {
      final plain = ImportHarUseCase(db.writer);

      await expectLater(plain.importCleaned(shopHarText()), throwsA(isA<ImportException>()));
      final summary = await plain(shopHarText());
      expect(summary.requests, 10);
      expect(db.folders, isEmpty);
    });
  });

  group('the one import entry point', () {
    final log = <String>[];
    late ImportAnyUseCase any;

    setUp(() {
      log.clear();
      any = ImportAnyUseCase(
        _Unused<int, String>(),
        _Unused<int, String>(),
        _Unused<ImportSummary, String>(),
        _Har(log),
        _Unused<ImportSummary, ImportCurlScriptParams>(),
        _Unused<ImportSummary, String>(),
        InMemoryDb().collectionRepository,
        InMemoryDb().requestRepository,
        importPostmanEnvironment: _Unused<ImportSummary, String>(),
      );
    });

    test('the plain import is the default, so nothing that called it before changes', () async {
      await any(ImportAnyParams(text: shopHarText()));

      expect(log, ['plain']);
    });

    test('cleanHar sends a HAR file to the clean-up', () async {
      await any(ImportAnyParams(text: shopHarText(), cleanHar: true));

      expect(log, ['cleaned']);
    });

    test('the option means nothing for any other format', () async {
      await expectLater(any(const ImportAnyParams(text: 'curl https://a.test', cleanHar: true)), throwsA(isA<UnimplementedError>()));
      expect(log, isEmpty);
    });
  });
}

final class _Unused<O, P> implements UseCase<O, P> {
  @override
  Future<O> call(P params) => throw UnimplementedError('not used here');
}

final class _Har implements UseCase<ImportSummary, String>, CleanableHarImporter {
  final List<String> log;
  _Har(this.log);

  @override
  Future<ImportSummary> call(String params) async {
    log.add('plain');
    return const ImportSummary(format: ImportFormat.har);
  }

  @override
  Future<ImportSummary> importCleaned(String text) async {
    log.add('cleaned');
    return const ImportSummary(format: ImportFormat.har);
  }
}
