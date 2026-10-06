import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_template.dart';

MockRequest _request({Map<String, List<String>> query = const {}, Map<String, String> headers = const {}, String body = ''}) =>
    MockRequest(method: 'POST', path: '/x', query: query, headers: headers, body: body);

String _render(String text, {MockRequest? request, Map<String, String> path = const {}, DateTime? now, String Function()? guid}) =>
    MockTemplate.render(text, request ?? _request(), pathParams: path, now: now, newGuid: guid, random: Random(1));

void main() {
  final noon = DateTime.utc(2026, 10, 6, 12);

  group('path, query and header', () {
    test('an unquoted path parameter that is a number stays a number', () {
      expect(_render('{"id": {{path.id}}}', path: {'id': '42'}), '{"id": 42}');
    });

    test('an unquoted value that is not a number is quoted', () {
      expect(_render('{"id": {{path.id}}}', path: {'id': 'abc'}), '{"id": "abc"}');
      // A leading zero is an identifier, not a number.
      expect(_render('{"zip": {{query.zip}}}', request: _request(query: {'zip': ['007']})), '{"zip": "007"}');
      expect(_render('{"n": {{query.n}}}', request: _request(query: {'n': ['-3.5']})), '{"n": -3.5}');
    });

    test('inside a JSON string the value is escaped, so the body stays valid JSON', () {
      const awkward = 'A "quoted" \\ back\nslash';
      final out = _render('{"name": "{{query.name}}"}', request: _request(query: {'name': [awkward]}));
      expect(jsonDecode(out), {'name': awkward});
    });

    test('a header and a query parameter by name, with spaces allowed inside the braces', () {
      final request = _request(query: {'page': ['3']}, headers: {'X-Tenant': 'acme'});
      expect(_render('t={{ header.x-tenant }} p={{ query.page }}', request: request), 't=acme p=3');
    });

    test('a missing value is empty inside a string and null outside one', () {
      expect(_render('{"a": "{{query.nope}}", "b": {{query.nope}}}'), '{"a": "", "b": null}');
    });
  });

  group('body', () {
    final request = _request(body: '{"user": {"name": "Ann", "age": 31, "vip": true}, "items": [{"id": 7}, {"id": 8}], "note": null}');

    test('a field of the JSON body, nested and by list index', () {
      expect(_render('{"who": "{{body.user.name}}", "second": {{body.items.1.id}}}', request: request), '{"who": "Ann", "second": 8}');
    });

    test('outside a string a body value is written as JSON', () {
      expect(_render('{"name": {{body.user.name}}, "age": {{body.user.age}}, "vip": {{body.user.vip}}, "user": {{body.user}}}', request: request),
          '{"name": "Ann", "age": 31, "vip": true, "user": {"name":"Ann","age":31,"vip":true}}');
    });

    test('inside a string a body value is its text', () {
      expect(_render('{"hello": "Hi {{body.user.name}}, {{body.user.age}}"}', request: request), '{"hello": "Hi Ann, 31"}');
    });

    test('a null or absent body field is null / empty', () {
      expect(_render('{"x": {{body.note}}, "y": {{body.missing.deep}}}', request: request), '{"x": null, "y": null}');
      expect(_render('{"x": {{body.a}}}'), '{"x": null}', reason: 'no body at all');
    });

    test('the whole body', () {
      expect(_render('{"echo": {{body}}}', request: _request(body: '{"a":1}')), '{"echo": {"a":1}}');
    });
  });

  group('dynamic values', () {
    test(r'$guid is a fresh value each time it is written', () {
      var n = 0;
      expect(_render('{"a": "{{\$guid}}", "b": {{\$guid}}}', guid: () => 'g-${++n}'), '{"a": "g-1", "b": "g-2"}');
    });

    test(r'$timestamp is Unix seconds and $isoTimestamp an ISO-8601 instant', () {
      // 2026-10-06T12:00:00Z is 1791288000 seconds after the epoch.
      expect(_render('{"t": {{\$timestamp}}}', now: noon), '{"t": 1791288000}');
      expect(_render('{"t": "{{\$isoTimestamp}}"}', now: noon), '{"t": "2026-10-06T12:00:00.000Z"}');
    });

    test(r'a real $guid is a v4 UUID', () {
      final out = MockTemplate.render('{{\$guid}}', _request(), random: Random(5));
      expect(out, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('leaving things alone', () {
    test('text in double braces that is none of these stays as it is', () {
      expect(_render('{"token": "{{token}}", "x": "{{\$unknown}}", "y": "{{path}}"}'), '{"token": "{{token}}", "x": "{{\$unknown}}", "y": "{{path}}"}');
    });

    test('a body without placeholders is returned untouched', () {
      const body = '{"a": 1}';
      expect(identical(_render(body), body), isTrue);
      expect(MockTemplate.hasPlaceholders(body), isFalse);
      expect(MockTemplate.hasPlaceholders('{{query.x}}'), isTrue);
    });

    test('text that is not JSON gets the plain text of the value', () {
      expect(_render('Hello {{query.name}}!', request: _request(query: {'name': ['Ann "A"']})), 'Hello Ann "A"!');
    });
  });
}
