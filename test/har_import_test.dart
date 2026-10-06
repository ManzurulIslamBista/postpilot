import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/imported_collection.dart';
import 'package:postpilot/features/import_export/domain/services/har_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'support/in_memory_import_export_fakes.dart';

List<Map<String, String>> _headers(Map<String, String> headers) => [
      for (final e in headers.entries) {'name': e.key, 'value': e.value},
    ];

Map<String, dynamic> _entry(
  String method,
  String url, {
  List<Map<String, String>>? headers,
  Map<String, dynamic>? postData,
  List<Map<String, String>>? cookies,
}) =>
    {
      'startedDateTime': '2026-01-01T10:00:00.000Z',
      'time': 42,
      'request': {
        'method': method,
        'url': url,
        'httpVersion': 'h2',
        'headers': headers ?? const [],
        'queryString': const [],
        'cookies': cookies ?? const [],
        'headersSize': -1,
        'bodySize': 0,
        'postData': ?postData,
      },
      'response': {'status': 200, 'statusText': '', 'headers': const [], 'content': {'size': 0, 'mimeType': 'application/json'}},
    };

String _har(List<Object?> entries) => jsonEncode({
      'log': {
        'version': '1.2',
        'creator': {'name': 'WebInspector', 'version': '537.36'},
        'pages': [
          {'id': 'page_1', 'title': 'https://shop.example.com/'},
        ],
        'entries': entries,
      },
    });

ImportedRequest _parseOne(Map<String, dynamic> entry) => HarParser.parse(_har([entry])).requests.single;

void main() {
  group('a browser recording', () {
    final chromeEntries = <Object?>[
      _entry(
        'GET',
        'https://shop.example.com/api/products?page=2&sort=price',
        headers: [
          {'name': ':authority', 'value': 'shop.example.com'},
          {'name': ':method', 'value': 'GET'},
          {'name': ':path', 'value': '/api/products?page=2&sort=price'},
          {'name': ':scheme', 'value': 'https'},
          {'name': 'accept', 'value': 'application/json'},
          {'name': 'accept-encoding', 'value': 'gzip, deflate, br'},
          {'name': 'cookie', 'value': 'session=abc'},
          {'name': 'cookie', 'value': 'theme=dark'},
          {'name': 'user-agent', 'value': 'Mozilla/5.0'},
        ],
        cookies: [
          {'name': 'session', 'value': 'abc'},
          {'name': 'theme', 'value': 'dark'},
        ],
      ),
      _entry(
        'POST',
        'https://shop.example.com/api/cart',
        headers: _headers({'content-type': 'application/json', 'content-length': '22', 'host': 'shop.example.com'}),
        postData: {'mimeType': 'application/json', 'text': '{"sku":"A1","qty":2}'},
      ),
      _entry(
        'OPTIONS',
        'https://shop.example.com/api/cart',
        headers: _headers({'access-control-request-method': 'POST', 'origin': 'https://shop.example.com'}),
      ),
      _entry('GET', 'data:image/png;base64,iVBORw0KGgo='),
      _entry('GET', 'wss://shop.example.com/socket'),
      _entry('CONNECT', 'https://shop.example.com:443'),
      {'startedDateTime': 'x'},
    ];

    late ParsedHar parsed;

    setUp(() => parsed = HarParser.parse(_har(chromeEntries)));

    test('every replayable entry becomes a request named "METHOD /path"', () {
      expect(parsed.requests.map((r) => r.name), ['GET /api/products', 'POST /api/cart']);
      expect(parsed.requests.map((r) => r.method), [HttpMethod.get, HttpMethod.post]);
    });

    test('entries that cannot be replayed are counted, not imported', () {
      // The CORS preflight, a data: URL, a websocket, CONNECT and an entry with no request.
      expect(parsed.skipped, 5);
    });

    test('the collection is named after the first host', () {
      expect(parsed.name, 'HAR import - shop.example.com');
    });

    test('the URL is kept exactly as recorded, query string included', () {
      expect(parsed.requests.first.url, 'https://shop.example.com/api/products?page=2&sort=price');
    });

    test('pseudo-headers and headers the HTTP client sets itself are dropped', () {
      final products = parsed.requests.first;

      expect(products.headers.map((h) => h.key), ['accept', 'Cookie', 'user-agent']);
      final cart = parsed.requests.last;
      expect(cart.headers.map((h) => h.key), ['content-type']);
    });

    test('HTTP/2 cookie headers merge into one, and the cookies array is not added on top', () {
      final cookies = parsed.requests.first.headers.where((h) => h.key.toLowerCase() == 'cookie').toList();

      expect(cookies, hasLength(1));
      expect(cookies.single.value, 'session=abc; theme=dark');
    });

    test('the cookies array is used only when there is no Cookie header', () {
      final request = _parseOne(_entry('GET', 'https://a.test/x', cookies: [
        {'name': 'sid', 'value': '1'},
        {'name': 'lang', 'value': 'en'},
      ]));

      expect(request.headers.single.key, 'Cookie');
      expect(request.headers.single.value, 'sid=1; lang=en');
    });

    test('a JSON body is kept as raw JSON', () {
      final cart = parsed.requests.last;

      expect(cart.body.type, BodyType.raw);
      expect(cart.body.rawContentType, RawContentType.json);
      expect(cart.body.rawText, '{"sku":"A1","qty":2}');
    });

    test('auth is left to the Authorization header the request already carries', () {
      expect(parsed.requests.every((r) => r.auth.type == AuthType.inherit), isTrue);
      final withToken = _parseOne(_entry('GET', 'https://a.test/x', headers: _headers({'authorization': 'Bearer t'})));
      expect(withToken.headers.single.value, 'Bearer t');
    });
  });

  group('bodies', () {
    test('a form with params keeps them as fields', () {
      final request = _parseOne(_entry('POST', 'https://a.test/login',
          headers: _headers({'content-type': 'application/x-www-form-urlencoded'}),
          postData: {
            'mimeType': 'application/x-www-form-urlencoded',
            'text': 'user=ann%40example.com&pass=s3cret',
            'params': [
              {'name': 'user', 'value': 'ann@example.com'},
              {'name': 'pass', 'value': 's3cret'},
            ],
          }));

      expect(request.body.type, BodyType.urlEncoded);
      expect(request.body.urlEncodedFields.map((f) => (f.key, f.value)), [('user', 'ann@example.com'), ('pass', 's3cret')]);
    });

    test('a form recorded only as text is split and decoded', () {
      final request = _parseOne(_entry('POST', 'https://a.test/login',
          postData: {'mimeType': 'application/x-www-form-urlencoded', 'text': 'q=hello%20world&flag&empty='}));

      expect(request.body.urlEncodedFields.map((f) => (f.key, f.value)), [('q', 'hello world'), ('flag', ''), ('empty', '')]);
    });

    test('multipart with params keeps text fields and imports file parts as file rows named by the HAR', () {
      final request = _parseOne(_entry('POST', 'https://a.test/upload', postData: {
        'mimeType': 'multipart/form-data; boundary=----X',
        'params': [
          {'name': 'title', 'value': 'Cat'},
          {'name': 'photo', 'fileName': 'cat.png', 'contentType': 'image/png'},
        ],
      }));

      expect(request.body.type, BodyType.formData);
      expect(request.body.formFields.map((f) => (f.key, f.value, f.isFile, f.contentType)), [
        ('title', 'Cat', false, ''),
        ('photo', 'cat.png', true, 'image/png'),
      ]);
    });

    test('multipart recorded only as text replays as a raw body under its own boundary', () {
      const text = '------X\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n------X--\r\n';
      final request = _parseOne(_entry('POST', 'https://a.test/upload',
          headers: _headers({'content-type': 'multipart/form-data; boundary=----X'}),
          postData: {'mimeType': 'multipart/form-data; boundary=----X', 'text': text}));

      expect(request.body.type, BodyType.raw);
      expect(request.body.rawText, text);
      expect(request.headers.single.value, 'multipart/form-data; boundary=----X');
    });

    test('a media type the raw types cannot express becomes an explicit Content-Type header', () {
      final request = _parseOne(_entry('POST', 'https://a.test/events', postData: {'mimeType': 'application/x-ndjson', 'text': '{"a":1}\n{"a":2}'}));

      expect(request.headers.single.key, 'Content-Type');
      expect(request.headers.single.value, 'application/x-ndjson');
    });

    test('plain text needs no extra header', () {
      final request = _parseOne(_entry('PUT', 'https://a.test/note', postData: {'mimeType': 'text/plain', 'text': 'hi'}));

      expect(request.body.rawContentType, RawContentType.text);
      expect(request.headers, isEmpty);
    });

    test('a request with no postData has no body', () {
      expect(_parseOne(_entry('DELETE', 'https://a.test/x/1')).body.type, BodyType.none);
    });
  });

  group('names', () {
    test('a URL without a path is named "METHOD /"', () {
      expect(_parseOne(_entry('GET', 'https://a.test')).name, 'GET /');
    });

    test('an unresolvable first host falls back to a plain collection name', () {
      expect(HarParser.parse(_har([])).name, 'HAR import');
    });
  });

  group('errors', () {
    test('JSON that is not a HAR file is rejected', () {
      expect(() => HarParser.parse('{"hello": "world"}'), throwsA(isA<ImportException>()));
      expect(() => HarParser.parse('{"log": {"entries": "nope"}}'), throwsA(isA<ImportException>()));
      expect(() => HarParser.parse('[]'), throwsA(isA<ImportException>()));
    });

    test('text that is not JSON surfaces as a FormatException', () {
      expect(() => HarParser.parse('not json'), throwsFormatException);
    });
  });

  group('import into the database', () {
    late InMemoryDb db;
    late ImportHarUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportHarUseCase(db.writer);
    });

    test('creates one flat collection and reports what was skipped', () async {
      final summary = await useCase(_har([
        _entry('GET', 'https://shop.example.com/api/products?page=2'),
        _entry('POST', 'https://shop.example.com/api/cart',
            headers: _headers({'content-type': 'application/json'}), postData: {'mimeType': 'application/json', 'text': '{}'}),
        _entry('GET', 'data:text/plain,hello'),
      ]));

      expect(summary.format, ImportFormat.har);
      expect(summary.requests, 2);
      expect(summary.skipped, 1);
      expect(summary.collectionName, 'HAR import - shop.example.com');
      expect(summary.description, 'Imported "HAR import - shop.example.com": 2 requests (1 skipped)');

      final requests = db.requestsOf(summary.collectionIds.single);
      expect(requests.map((r) => r.name), ['GET /api/products', 'POST /api/cart']);
      expect(requests.every((r) => r.folderId == null), isTrue);
      expect(requests.last.body.rawText, '{}');
      expect(db.folders, isEmpty);
    });

    test('a recording without replayable requests is an error and creates nothing', () async {
      await expectLater(useCase(_har([_entry('GET', 'data:text/plain,hello')])), throwsA(isA<ImportException>()));

      expect(db.collections, isEmpty);
    });

    test('a failing write removes the half-built collection', () async {
      db.failSaveRequestOnCall = 2;

      await expectLater(
        useCase(_har([_entry('GET', 'https://a.test/1'), _entry('GET', 'https://a.test/2'), _entry('GET', 'https://a.test/3')])),
        throwsA(isA<StateError>()),
      );

      expect(db.collections, isEmpty);
      expect(db.requests, isEmpty);
    });
  });
}
