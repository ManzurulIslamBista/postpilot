import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

ResolvedRequestSpec _build(
  ApiRequestEntity request, {
  bool trim = false,
  Map<String, String> variables = const {},
}) =>
    const RequestSpecBuilder().build(request, VariableResolver(variables), trimKeysAndValues: trim);

ApiRequestEntity _request({
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> params = const [],
  RequestBody body = RequestBody.empty,
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'r',
      method: HttpMethod.post,
      url: 'https://api.example.com/items',
      headers: headers,
      queryParams: params,
      body: body,
      auth: const RequestAuth(type: AuthType.none),
    );

KeyValueItem _kv(String key, String value, {bool enabled = true}) =>
    KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  group('with trimming off (the default)', () {
    test('keys and values keep their whitespace', () {
      final spec = _build(_request(
        headers: [_kv(' X-Trace ', ' abc ')],
        params: [_kv(' page ', ' 2 ')],
      ));

      expect(spec.headers[' X-Trace '], ' abc ');
      expect(Uri.parse(spec.url).queryParameters, {' page ': ' 2 '});
    });
  });

  group('with trimming on', () {
    test('header keys and values are trimmed', () {
      final spec = _build(_request(headers: [_kv('  X-Trace\t', '\n abc  '), _kv('Accept', 'application/json')]), trim: true);

      expect(spec.headers, {'X-Trace': 'abc', 'Accept': 'application/json'});
    });

    test('query keys and values are trimmed and encoded after trimming', () {
      final spec = _build(_request(params: [_kv(' q ', ' a b ')]), trim: true);

      expect(spec.url, 'https://api.example.com/items?q=a+b');
    });

    test('a value is trimmed after its variables resolve', () {
      final spec = _build(
        _request(headers: [_kv('X-Token', '{{token}}')], params: [_kv('id', '{{id}}')]),
        trim: true,
        variables: {'token': '  secret  ', 'id': ' 7 '},
      );

      expect(spec.headers['X-Token'], 'secret');
      expect(spec.url, 'https://api.example.com/items?id=7');
    });

    test('a row whose key is only whitespace is dropped', () {
      final spec = _build(_request(headers: [_kv('   ', 'v'), _kv('Real', 'v')], params: [_kv('  ', 'v')]), trim: true);

      expect(spec.headers, {'Real': 'v'});
      expect(spec.url, 'https://api.example.com/items');
    });

    test('a disabled row stays out either way', () {
      final spec = _build(_request(headers: [_kv(' A ', 'v', enabled: false)]), trim: true);

      expect(spec.headers, isEmpty);
    });

    test('urlencoded body fields are trimmed', () {
      final spec = _build(
        _request(
          body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [_kv(' name ', ' Ann '), _kv(' ', 'dropped')]),
        ),
        trim: true,
      );

      expect(utf8.decode(spec.bodyBytes!), 'name=Ann');
    });

    test('form-data fields are trimmed', () {
      final spec = _build(
        _request(body: RequestBody(type: BodyType.formData, formFields: [_kv(' file ', ' x '), _kv('', 'dropped')])),
        trim: true,
      );

      final text = utf8.decode(spec.bodyBytes!);
      expect(text, contains('name="file"\r\n\r\nx\r\n'));
      expect(text, isNot(contains('dropped')));
    });

    test('a raw body is never touched', () {
      const raw = '  {"a": 1}  ';
      final spec = _build(_request(body: const RequestBody(type: BodyType.raw, rawText: raw)), trim: true);

      expect(utf8.decode(spec.bodyBytes!), raw);
    });

    test('a request with nothing to trim builds the same spec either way', () {
      final request = _request(headers: [_kv('A', 'b')], params: [_kv('q', '1')]);

      final trimmed = _build(request, trim: true);
      final untouched = _build(request);

      expect(trimmed.headers, untouched.headers);
      expect(trimmed.url, untouched.url);
    });
  });
}
