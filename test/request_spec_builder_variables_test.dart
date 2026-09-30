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

ApiRequestEntity _request({
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> params = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(type: AuthType.none),
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
      auth: auth,
    );

ResolvedRequestSpec _build(
  ApiRequestEntity request, {
  Map<String, String> variables = const {},
  bool trim = false,
  bool noCache = false,
  RequestAuth? inheritedAuth,
}) =>
    const RequestSpecBuilder().build(
      request,
      VariableResolver(variables),
      inheritedAuth: inheritedAuth,
      trimKeysAndValues: trim,
      sendNoCache: noCache,
    );

KeyValueItem _kv(String key, String value, {bool enabled = true}) =>
    KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  group('{{variables}} in keys, as in values', () {
    const variables = {'tenant': 'acme', 'param': 'limit', 'field': 'name'};

    test('header keys', () {
      final spec = _build(_request(headers: [_kv('X-{{tenant}}', 'v-{{tenant}}')]), variables: variables);

      expect(spec.headers, {'X-acme': 'v-acme'});
    });

    test('query keys', () {
      final spec = _build(_request(params: [_kv('{{param}}', '5')]), variables: variables);

      expect(spec.url, 'https://api.example.com/items?limit=5');
    });

    test('urlencoded and form-data keys', () {
      final urlEncoded = _build(
        _request(body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [_kv('{{field}}', 'Ann')])),
        variables: variables,
      );
      final formData = _build(
        _request(body: RequestBody(type: BodyType.formData, formFields: [_kv('{{field}}', 'Ann')])),
        variables: variables,
      );

      expect(utf8.decode(urlEncoded.bodyBytes!), 'name=Ann');
      expect(utf8.decode(formData.bodyBytes!), contains('name="name"\r\n\r\nAnn\r\n'));
    });

    test('the API key name, in the header and in the query', () {
      const auth = RequestAuth(type: AuthType.apiKey, apiKeyName: '{{tenant}}-key', apiKeyValue: 'secret');

      final inHeader = _build(_request(auth: auth), variables: variables);
      final inQuery = _build(
        _request(auth: auth.copyWith(apiKeyLocation: ApiKeyLocation.query)),
        variables: variables,
      );

      expect(inHeader.headers, {'acme-key': 'secret'});
      expect(inQuery.url, 'https://api.example.com/items?acme-key=secret');
    });

    test('the API key name of an inherited collection auth', () {
      const collectionAuth = RequestAuth(type: AuthType.apiKey, apiKeyName: '{{tenant}}-key', apiKeyValue: 'secret');

      final spec = _build(_request(auth: const RequestAuth()), variables: variables, inheritedAuth: collectionAuth);

      expect(spec.headers, {'acme-key': 'secret'});
    });

    test('the JWT prefix', () {
      final spec = _build(
        _request(
          auth: const RequestAuth(
            type: AuthType.jwtBearer,
            jwtSecret: 'secret',
            jwtPayload: '{"a":1}',
            jwtHeaderPrefix: '{{prefix}}',
          ),
        ),
        variables: {'prefix': 'JWT'},
      );

      expect(spec.headers['Authorization'], startsWith('JWT '));
    });

    test('a token no variable defines is left as written, keys included', () {
      final spec = _build(_request(headers: [_kv('X-{{unknown}}', 'v')]));

      expect(spec.headers, {'X-{{unknown}}': 'v'});
    });

    test('a key that resolves to nothing drops its row, like an empty key', () {
      final spec = _build(
        _request(headers: [_kv('{{blank}}', 'v'), _kv('Real', 'v')], params: [_kv('{{blank}}', 'v')]),
        variables: {'blank': ''},
      );

      expect(spec.headers, {'Real': 'v'});
      expect(spec.url, 'https://api.example.com/items');
    });

    test('a key is trimmed after its variables resolve', () {
      final spec = _build(
        _request(headers: [_kv('{{name}}', 'v')]),
        variables: {'name': '  X-Trace '},
        trim: true,
      );

      expect(spec.headers, {'X-Trace': 'v'});
    });

    test('a disabled row is skipped whatever its key resolves to', () {
      final spec = _build(_request(headers: [_kv('X-{{tenant}}', 'v', enabled: false)]), variables: variables);

      expect(spec.headers, isEmpty);
    });
  });

  group('the no-cache header', () {
    test('is added when asked for, and only then', () {
      final request = _request(headers: [_kv('X-Trace', 'abc')]);

      expect(_build(request, noCache: true).headers, {'X-Trace': 'abc', 'Cache-Control': 'no-cache'});
      expect(_build(request).headers, {'X-Trace': 'abc'});
    });

    test('leaves a Cache-Control the request sets itself alone, whatever its case', () {
      for (final name in ['Cache-Control', 'cache-control', 'CACHE-CONTROL']) {
        final spec = _build(_request(headers: [_kv(name, 'max-age=60')]), noCache: true);

        expect(spec.headers, {name: 'max-age=60'}, reason: name);
      }
    });

    test('does not count a disabled Cache-Control row', () {
      final spec = _build(_request(headers: [_kv('Cache-Control', 'max-age=60', enabled: false)]), noCache: true);

      expect(spec.headers, {'Cache-Control': 'no-cache'});
    });

    test('goes on top of an auth header without touching it', () {
      final spec = _build(
        _request(auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'tok')),
        noCache: true,
      );

      expect(spec.headers, {'Authorization': 'Bearer tok', 'Cache-Control': 'no-cache'});
    });
  });
}
