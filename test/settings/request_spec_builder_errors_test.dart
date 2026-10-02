import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

ApiRequestEntity _request({
  List<KeyValueItem> headers = const [],
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
      queryParams: const [],
      body: body,
      auth: auth,
    );

ResolvedRequestSpec _build(ApiRequestEntity request) =>
    const RequestSpecBuilder().build(request, VariableResolver(const {}));

void main() {
  group('the Content-Type default', () {
    const rawJson = RequestBody(type: BodyType.raw, rawText: '{"a":1}');

    test('is added when the request sets none', () {
      expect(_build(_request(body: rawJson)).headers, {'Content-Type': 'application/json'});
    });

    test('yields to a Content-Type the user typed, whatever its case', () {
      for (final name in ['Content-Type', 'content-type', 'CONTENT-TYPE']) {
        final spec = _build(
          _request(body: rawJson, headers: [KeyValueItem(key: name, value: 'application/vnd.api+json')]),
        );

        expect(spec.headers, {name: 'application/vnd.api+json'}, reason: name);
      }
    });

    test('is added when the user only has a disabled Content-Type row', () {
      final spec = _build(
        _request(body: rawJson, headers: [KeyValueItem(key: 'content-type', value: 'text/plain', enabled: false)]),
      );

      expect(spec.headers, {'Content-Type': 'application/json'});
    });
  });

  group('invalid JSON in the request itself', () {
    test('GraphQL variables surface as an InvalidRequestException that names them', () {
      final request = _request(
        body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ a }', graphqlVariables: '{"a": 1,}'),
      );

      expect(
        () => _build(request),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('GraphQL variables'))),
      );
    });

    test('valid GraphQL variables still go out', () {
      final spec = _build(
        _request(body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ a }', graphqlVariables: '{"a": 1}')),
      );

      expect(String.fromCharCodes(spec.bodyBytes!), contains('"variables":{"a":1}'));
    });

    test('a malformed JWT payload surfaces as an InvalidRequestException that names it', () {
      final request = _request(
        auth: const RequestAuth(type: AuthType.jwtBearer, jwtSecret: 's', jwtPayload: '{"a":'),
      );

      expect(
        () => _build(request),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('JWT payload'))),
      );
    });

    test('a JWT payload that is not an object is reported, not thrown as a TypeError', () {
      final request = _request(
        auth: const RequestAuth(type: AuthType.jwtBearer, jwtSecret: 's', jwtPayload: '[1,2]'),
      );

      expect(
        () => _build(request),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('JSON object'))),
      );
    });
  });
}
