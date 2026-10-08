import 'dart:convert';

/// A JWT-shaped bearer token and a session cookie: both must stay out of everything a clean-up saves.
const harToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiIsImV4cCI6MTg5MzQ1NjAwMH0.dGhpcy1pcy1ub3QtYS1yZWFsLXNpZ25hdHVyZQ';
const harCookie = 'abc123def456ghi789';

Map<String, dynamic> _entry(
  int index,
  String method,
  String url, {
  List<(String, String)> headers = const [],
  String? body,
  String? bodyMime,
  int status = 200,
  String statusText = 'OK',
  List<(String, String)> responseHeaders = const [],
  String? responseMime,
  String? responseText,
  String? responseEncoding,
  String? resourceType,
  bool noResponse = false,
}) =>
    {
      'startedDateTime': DateTime.utc(2026, 10, 8, 10, 0, 0, index * 100).toIso8601String(),
      'time': 40 + index,
      'request': {
        'method': method,
        'url': url,
        'httpVersion': 'h2',
        'headers': [for (final h in headers) {'name': h.$1, 'value': h.$2}],
        'queryString': const [],
        'cookies': const [],
        'headersSize': -1,
        'bodySize': body?.length ?? 0,
        if (body != null) 'postData': {'mimeType': bodyMime ?? 'application/json', 'text': body},
      },
      'response': {
        'status': noResponse ? 0 : status,
        'statusText': noResponse ? '' : statusText,
        'httpVersion': 'h2',
        'headers': [for (final h in responseHeaders) {'name': h.$1, 'value': h.$2}],
        'cookies': const [],
        'content': {
          'size': responseText?.length ?? 0,
          'mimeType': responseMime ?? 'application/json',
          'text': ?responseText,
          'encoding': ?responseEncoding,
        },
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': responseText?.length ?? 0,
      },
      'cache': const {},
      'timings': {'send': 1, 'wait': 30, 'receive': 9},
      '_resourceType': ?resourceType,
    };

/// What a person gets from "Save all as HAR" after using a web shop for a minute. Twelve entries:
///
///  0. a font Chrome labels `font`                        (static file)
///  1. a stylesheet with no extension, labelled `stylesheet`  (static file)
///  2. `icons.woff2` served as octet-stream, no label      (static file, by its extension)
///  3. a Google Analytics collect call                      (analytics)
///  4. the CORS preflight of the call below                  (preflight)
///  5. `GET /api/users/12`, a bearer token and a session cookie
///  6. `GET /api/users/98?expand=roles`, the same credentials and one more header: the more complete call of the two
///  7. `POST /api/orders` with a JSON body and the token
///  8. `GET /api/orders?page=2`
///  9. `GET https://api.other.test/v1/ping`                  (another host)
/// 10. a `data:` URL                                          (not an http call)
/// 11. `GET /api/health` that got no answer                   (status 0)
Map<String, dynamic> shopHar() {
  final auth = ('authorization', 'Bearer $harToken');
  final cookie = ('cookie', 'session=$harCookie; theme=dark');
  return {
    'log': {
      'version': '1.2',
      'creator': {'name': 'WebInspector', 'version': '537.36'},
      'pages': [
        {'id': 'page_1', 'title': 'https://app.shop.test/'},
      ],
      'entries': [
        _entry(0, 'GET', 'https://fonts.gstatic.com/s/inter/v13/inter.woff2', headers: [('accept', '*/*')], responseMime: 'font/woff2', responseText: 'd09GMgABAAAAAAy8AA4AAAA', responseEncoding: 'base64', resourceType: 'font'),
        _entry(1, 'GET', 'https://app.shop.test/css/app?v=3', headers: [('accept', 'text/css,*/*;q=0.1')], responseMime: 'text/css', responseText: 'body{margin:0}', resourceType: 'stylesheet'),
        _entry(2, 'GET', 'https://app.shop.test/assets/icons.woff2', headers: [('accept', '*/*')], responseMime: 'application/octet-stream', responseText: 'd09GMgABAAAAAAy8AA4AAAA', responseEncoding: 'base64'),
        _entry(3, 'POST', 'https://www.google-analytics.com/g/collect?v=2&tid=G-ABC123&cid=1234.5678', headers: [('content-type', 'text/plain;charset=UTF-8')], body: 'en=page_view', bodyMime: 'text/plain', status: 204, statusText: 'No Content', responseMime: 'text/plain'),
        _entry(4, 'OPTIONS', 'https://app.shop.test/api/users/12', headers: [('access-control-request-method', 'GET'), ('access-control-request-headers', 'authorization'), ('origin', 'https://app.shop.test')], status: 204, statusText: 'No Content', responseMime: 'text/plain'),
        _entry(
          5,
          'GET',
          'https://app.shop.test/api/users/12',
          headers: [('host', 'app.shop.test'), ('accept', 'application/json'), ('accept-encoding', 'gzip, deflate, br'), auth, cookie],
          responseHeaders: [('content-type', 'application/json; charset=utf-8'), ('x-request-id', 'srv-1')],
          responseText: '{"id":12,"name":"Ann Lee"}',
        ),
        _entry(
          6,
          'GET',
          'https://app.shop.test/api/users/98?expand=roles',
          headers: [('host', 'app.shop.test'), ('accept', 'application/json'), ('accept-encoding', 'gzip, deflate, br'), auth, cookie, ('x-request-id', 'req-7f3a')],
          responseHeaders: [('content-type', 'application/json; charset=utf-8')],
          responseText: '{"id":98,"name":"Bob Ray","roles":["admin"]}',
        ),
        _entry(
          7,
          'POST',
          'https://app.shop.test/api/orders',
          headers: [('content-type', 'application/json'), ('content-length', '22'), auth],
          body: '{"sku":"A1","qty":2}',
          status: 201,
          statusText: 'Created',
          responseText: '{"id":501,"sku":"A1"}',
        ),
        _entry(8, 'GET', 'https://app.shop.test/api/orders?page=2', headers: [('accept', 'application/json'), auth], responseText: '{"items":[],"page":2}'),
        _entry(9, 'GET', 'https://api.other.test/v1/ping', headers: [('accept', 'application/json')], responseText: '{"pong":true}'),
        _entry(10, 'GET', 'data:image/png;base64,iVBORw0KGgo='),
        _entry(11, 'GET', 'https://app.shop.test/api/health', noResponse: true),
      ],
    },
  };
}

String shopHarText() => jsonEncode(shopHar());

/// A recording with nothing in it that is an API: a font, a script, a beacon.
String staticOnlyHarText() => jsonEncode({
      'log': {
        'version': '1.2',
        'entries': [
          _entry(0, 'GET', 'https://app.shop.test/static/js/main.4f2a1b.js', responseMime: 'text/plain', responseText: 'console.log(1)'),
          _entry(1, 'GET', 'https://app.shop.test/static/css/main.css', responseMime: 'text/plain', responseText: 'a{}'),
          _entry(2, 'POST', 'https://www.google-analytics.com/g/collect?v=2', body: 'en=page_view', bodyMime: 'text/plain', status: 204),
        ],
      },
    });
