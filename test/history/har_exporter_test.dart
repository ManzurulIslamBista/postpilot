// The HAR file History exports: valid against the HAR 1.2 structure, free of credentials, and readable by
// PostPilot's own HAR importer.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/services/har_exporter.dart';
import 'package:postpilot/features/history/domain/services/history_har.dart';
import 'package:postpilot/features/history/domain/services/history_template_expander.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/import_export/domain/services/har_parser.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

/// HAR 1.2 (softwareishard.com/blog/har-12-spec) checked field by field, written from the spec and not from the
/// exporter: every required field is present with the right type, the date is ISO 8601, `time` is the sum of the
/// timings that are known, and `-1` appears only where the spec allows it.
void expectValidHar12(Map<String, dynamic> har) {
  final log = har['log'] as Map<String, dynamic>;
  expect(log['version'], '1.2');
  final creator = log['creator'] as Map<String, dynamic>;
  expect(creator['name'], 'PostPilot');
  expect(creator['version'], isA<String>());
  final entries = log['entries'] as List;
  final iso = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$');

  for (final raw in entries) {
    final entry = raw as Map<String, dynamic>;
    expect(entry['startedDateTime'], matches(iso));
    expect(entry['time'], isA<num>());
    expect(entry['time'], greaterThanOrEqualTo(0));

    final request = entry['request'] as Map<String, dynamic>;
    expect(request['method'], isA<String>());
    expect(request['url'], isA<String>());
    expect(request['httpVersion'], isA<String>());
    expect(request['cookies'], isA<List>());
    expect(request['headers'], isA<List>());
    expect(request['queryString'], isA<List>());
    for (final pair in [...request['headers'] as List, ...request['queryString'] as List]) {
      expect((pair as Map).keys.toSet(), {'name', 'value'});
      expect(pair['name'], isA<String>());
      expect(pair['value'], isA<String>());
    }
    expect(request['headersSize'], isA<int>());
    expect(request['headersSize'], greaterThanOrEqualTo(-1));
    expect(request['bodySize'], greaterThanOrEqualTo(-1));
    final postData = request['postData'];
    if (postData != null) {
      postData as Map<String, dynamic>;
      expect(postData['mimeType'], isA<String>());
      // The spec: `text` and `params` are mutually exclusive.
      expect(postData.containsKey('text') != postData.containsKey('params'), isTrue);
    }

    final response = entry['response'] as Map<String, dynamic>;
    expect(response['status'], isA<int>());
    expect(response['statusText'], isA<String>());
    expect(response['httpVersion'], isA<String>());
    expect(response['cookies'], isA<List>());
    expect(response['headers'], isA<List>());
    final content = response['content'] as Map<String, dynamic>;
    expect(content['size'], isA<int>());
    expect(content['size'], greaterThanOrEqualTo(-1));
    expect(content['mimeType'], isA<String>());
    expect(response['redirectURL'], isA<String>());
    expect(response['headersSize'], greaterThanOrEqualTo(-1));
    expect(response['bodySize'], greaterThanOrEqualTo(-1));

    expect(entry['cache'], isA<Map>());
    final timings = entry['timings'] as Map<String, dynamic>;
    for (final required in ['send', 'wait', 'receive']) {
      expect(timings[required], isA<num>(), reason: required);
      expect(timings[required], greaterThanOrEqualTo(0), reason: '$required may not be -1');
    }
    for (final optional in ['blocked', 'dns', 'connect', 'ssl']) {
      if (timings.containsKey(optional)) expect(timings[optional], greaterThanOrEqualTo(-1), reason: optional);
    }
    final known = [for (final v in timings.values) if ((v as num) != -1) v];
    expect(entry['time'], known.fold<num>(0, (sum, v) => sum + v), reason: 'time is the sum of the timings that are not -1');
  }
}

HarEntryInput _getJson({int? durationMs = 120}) => HarEntryInput(
      startedAt: DateTime.utc(2026, 10, 6, 14, 3, 22),
      durationMs: durationMs,
      method: 'GET',
      url: 'https://api.test/search?q=a+b&page=2&flag',
      requestHeaders: const [HarHeader('Accept', 'application/json')],
      statusCode: 200,
      statusText: 'OK',
      responseHeaders: const [HarHeader('Content-Type', 'application/json; charset=utf-8')],
      responseMimeType: 'application/json',
      responseText: '{"items":[1,2]}',
      responseBytes: 15,
    );

void main() {
  group('the file', () {
    test('a send with everything known is a valid HAR 1.2 entry with the times it was given', () {
      final har = jsonDecode(HarExporter.export([_getJson()], creatorVersion: '2.3')) as Map<String, dynamic>;

      expectValidHar12(har);
      final log = har['log'] as Map<String, dynamic>;
      expect((log['creator'] as Map)['version'], '2.3');
      final entry = (log['entries'] as List).single as Map<String, dynamic>;
      expect(entry['startedDateTime'], '2026-10-06T14:03:22.000Z');
      expect(entry['time'], 120);
      expect(entry['timings'], {'blocked': -1, 'dns': -1, 'connect': -1, 'ssl': -1, 'send': 0, 'wait': 120, 'receive': 0});
      final request = entry['request'] as Map<String, dynamic>;
      expect(request['queryString'], [
        {'name': 'q', 'value': 'a b'},
        {'name': 'page', 'value': '2'},
        {'name': 'flag', 'value': ''},
      ]);
      final response = entry['response'] as Map<String, dynamic>;
      expect(response['status'], 200);
      expect(response['content'], {'size': 15, 'mimeType': 'application/json', 'text': '{"items":[1,2]}'});
      expect(response['headers'], [
        {'name': 'Content-Type', 'value': 'application/json; charset=utf-8'},
      ]);
    });

    test('what is not known is -1: header and wire sizes, the parts of the time, and an unknown body size', () {
      final entry = ((HarExporter.build([_getJson()])['log'] as Map)['entries'] as List).single as Map<String, dynamic>;
      final request = entry['request'] as Map<String, dynamic>;
      final response = entry['response'] as Map<String, dynamic>;

      expect(request['headersSize'], -1);
      expect(response['headersSize'], -1);
      expect(response['bodySize'], -1);
      expect(request['bodySize'], 0, reason: 'a request without a body has none: that is known, not -1');

      final unknownSize = HarEntryInput(
        startedAt: DateTime.utc(2026, 1, 1),
        method: 'GET',
        url: 'https://api.test/',
        statusCode: 200,
      );
      final content = (((HarExporter.build([unknownSize])['log'] as Map)['entries'] as List).single as Map)['response']['content'];
      expect(content['size'], -1);
    });

    test('a send that got no response is status 0 with the reason, and a send with no recorded time has zero timings', () {
      final failed = HarEntryInput(
        startedAt: DateTime.utc(2026, 1, 1),
        method: 'POST',
        url: 'https://api.test/x',
        error: "Couldn't find the server api.test.",
      );

      final har = HarExporter.build([failed, _getJson(durationMs: null)]);

      expectValidHar12(jsonDecode(jsonEncode(har)) as Map<String, dynamic>);
      final entries = (har['log'] as Map)['entries'] as List;
      final response = (entries[0] as Map)['response'] as Map;
      expect(response['status'], 0);
      expect(response['_error'], "Couldn't find the server api.test.");
      expect((entries[1] as Map)['time'], 0);
      expect(((entries[1] as Map)['timings'] as Map)['wait'], 0);
    });

    test('a multipart form is written as params and the others as text, never both', () {
      final form = HarEntryInput(
        startedAt: DateTime.utc(2026, 1, 1),
        method: 'POST',
        url: 'https://api.test/upload',
        requestMimeType: 'multipart/form-data',
        requestParams: const [HarHeader('title', 'Hello'), HarHeader('password', 'p4ssw0rd!')],
        statusCode: 201,
      );
      final json = HarEntryInput(
        startedAt: DateTime.utc(2026, 1, 1),
        method: 'POST',
        url: 'https://api.test/json',
        requestMimeType: 'application/json',
        requestBody: '{"a":1}',
        statusCode: 201,
      );

      final text = HarExporter.export([form, json]);
      final har = jsonDecode(text) as Map<String, dynamic>;

      expectValidHar12(har);
      final entries = (har['log'] as Map)['entries'] as List;
      expect(((entries[0] as Map)['request'] as Map)['postData'], {
        'mimeType': 'multipart/form-data',
        'params': [
          {'name': 'title', 'value': 'Hello'},
          {'name': 'password', 'value': '••••••'},
        ],
      });
      expect(((entries[1] as Map)['request'] as Map)['postData'], {'mimeType': 'application/json', 'text': '{"a":1}'});
      expect(((entries[1] as Map)['request'] as Map)['bodySize'], 7);
    });
  });

  group('credentials', () {
    test('are masked in the URL, the request headers, both bodies and a failure text, whatever the input holds', () {
      const secrets = ['hunter2pass', 'abc123secretvalue', 'Sup3rS3cretBearer', 'p4ssw0rd!', 'respSecret99', 'sk_live_ABCDEFGHIJKLMNOP'];
      final input = HarEntryInput(
        startedAt: DateTime.utc(2026, 1, 1),
        method: 'POST',
        url: 'https://alice:hunter2pass@api.test/x?api_key=abc123secretvalue&page=1',
        requestHeaders: const [HarHeader('Authorization', 'Bearer Sup3rS3cretBearer'), HarHeader('Accept', '*/*')],
        requestMimeType: 'application/json',
        requestBody: '{"user":"ann","password":"p4ssw0rd!"}',
        statusCode: 200,
        responseText: '{"token":"respSecret99","name":"ann"}',
        error: 'Could not reach https://api.test/x?key=sk_live_ABCDEFGHIJKLMNOP',
      );

      final text = HarExporter.export([input]);

      for (final secret in secrets) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      final entry = (((jsonDecode(text) as Map)['log'] as Map)['entries'] as List).single as Map;
      expect(entry['request']['url'], 'https://alice:••••••@api.test/x?api_key=••••••&page=1');
      expect(entry['request']['headers'], [
        {'name': 'Authorization', 'value': 'Bearer ••••••'},
        {'name': 'Accept', 'value': '*/*'},
      ]);
      expect(entry['request']['postData']['text'], '{"user":"ann","password":"••••••"}');
      expect(entry['response']['content']['text'], '{"token":"••••••","name":"ann"}');
    });

    test('a variable is filled in only when it is not secret, so the URL is absolute and no token is written', () {
      final expander = HistoryTemplateExpander.safe(
        const VariableResolver.layered([
          {'baseUrl': 'https://api.test', 'apiToken': 'tok-live-123456', 'region': 'eu', 'greeting': 'Hello {{apiToken}}'},
          {'region': 'us'},
        ]),
        secretKeys: {'customerCode'},
      );

      expect(expander('{{baseUrl}}/v1/{{region}}'), 'https://api.test/v1/eu', reason: 'the first scope wins');
      expect(expander('Bearer {{apiToken}}'), 'Bearer {{apiToken}}');
      expect(expander('{{greeting}}'), 'Hello {{apiToken}}', reason: 'a value that points at a secret does not give it away');
      expect(expander('{{customerCode}} {{\$guid}} {{unknown}}'), '{{customerCode}} {{\$guid}} {{unknown}}');
    });
  });

  group('from History entries', () {
    final sentAt = DateTime.utc(2026, 10, 6, 9, 30);

    HistoryEntryEntity entry({String method = 'POST', String url = '{{baseUrl}}/users', int? status = 201, HistoryEntryMeta? meta}) =>
        HistoryEntryEntity(id: 1, method: method, url: url, statusCode: status, durationMs: 80, sentAt: sentAt, meta: meta);

    test('the request as saved becomes an absolute request: variables filled in, auth as a masked header, body and type', () {
      final snapshot = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(requestName: 'Create user', collectionName: 'Shop', environmentName: 'Staging', responseBytes: 9, statusMessage: 'Created'),
        method: HttpMethod.post,
        url: '{{baseUrl}}/users',
        headers: [KeyValueItem(key: 'X-Trace', value: 'abc'), KeyValueItem(key: 'X-Off', value: 'no', enabled: false)],
        queryParams: [KeyValueItem(key: 'dry', value: 'true')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
      );
      final expander = HistoryTemplateExpander.safe(const VariableResolver.layered([
        {'baseUrl': 'https://api.test', 'name': 'Ann', 'token': 'tok-live-123456'},
      ]));

      final input = HistoryHar.inputFor(
        entry(meta: snapshot.meta),
        HistoryDetail(request: snapshot, responseText: '{"id":1}', responseContentType: 'application/json'),
        expand: expander.call,
      );
      final har = jsonDecode(HarExporter.export([input])) as Map<String, dynamic>;
      final e = ((har['log'] as Map)['entries'] as List).single as Map<String, dynamic>;

      expectValidHar12(har);
      expect(e['request']['url'], 'https://api.test/users?dry=true');
      expect(e['request']['headers'], [
        {'name': 'X-Trace', 'value': 'abc'},
        {'name': 'Authorization', 'value': 'Bearer {{token}}'},
        {'name': 'Content-Type', 'value': 'application/json'},
      ]);
      expect(e['request']['postData'], {'mimeType': 'application/json', 'text': '{"name":"Ann"}'});
      expect(e['response']['statusText'], 'Created');
      expect(e['response']['content']['text'], '{"id":1}');
      expect(e['comment'], 'Shop > Create user (Staging)');
      expect(jsonEncode(har), isNot(contains('tok-live-123456')));
    });

    test('an entry that kept no details is still an entry: method, URL, status and time', () {
      final input = HistoryHar.inputFor(entry(method: 'GET', url: 'https://api.test/ping', status: 204), null);
      final har = jsonDecode(HarExporter.export([input])) as Map<String, dynamic>;
      final e = ((har['log'] as Map)['entries'] as List).single as Map<String, dynamic>;

      expectValidHar12(har);
      expect(e['request']['method'], 'GET');
      expect(e['request']['url'], 'https://api.test/ping');
      expect(e['response']['status'], 204);
      expect(e['response']['statusText'], 'No Content');
      expect(e['response']['content']['size'], -1);
    });
  });

  group('PostPilot reads its own file back', () {
    test('the method, URL, headers and body of every entry come back as requests', () {
      final snapshot = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(requestName: 'Create user'),
        method: HttpMethod.post,
        url: 'https://api.test/users',
        headers: [KeyValueItem(key: 'X-Trace', value: 'abc')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"Ann"}'),
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
      );
      final inputs = [
        HistoryHar.inputFor(
          HistoryEntryEntity(id: 1, method: 'POST', url: 'https://api.test/users', statusCode: 201, durationMs: 80, sentAt: DateTime.utc(2026, 10, 6)),
          HistoryDetail(request: snapshot),
        ),
        HistoryHar.inputFor(
          HistoryEntryEntity(id: 2, method: 'GET', url: 'https://api.test/users?page=2', statusCode: 200, durationMs: 40, sentAt: DateTime.utc(2026, 10, 7)),
          null,
        ),
      ];

      final parsed = HarParser.parse(HarExporter.export(inputs));

      expect(parsed.skipped, 0);
      expect(parsed.requests, hasLength(2));
      final post = parsed.requests[0];
      expect(post.method, HttpMethod.post);
      expect(post.url, 'https://api.test/users');
      expect({for (final h in post.headers) h.key: h.value}, {
        'X-Trace': 'abc',
        'Authorization': 'Bearer {{token}}',
        'Content-Type': 'application/json',
      });
      expect(post.body.type, BodyType.raw);
      expect(post.body.rawText, '{"name":"Ann"}');
      final get = parsed.requests[1];
      expect(get.method, HttpMethod.get);
      expect(get.url, 'https://api.test/users?page=2');
      expect(get.headers, isEmpty);
    });
  });
}
