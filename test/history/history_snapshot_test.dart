// The request snapshot History stores: what is masked, what stays a template, and that it reads back.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/services/history_masker.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

const _mask = '••••••';

ApiRequestEntity _request({
  String url = 'https://api.test/users',
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> queryParams = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(type: AuthType.none),
  HttpMethod method = HttpMethod.post,
}) =>
    ApiRequestEntity(
      id: 7,
      collectionId: 3,
      folderId: null,
      name: 'Create user',
      method: method,
      url: url,
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: auth,
    );

HistoryRequestSnapshot _capture(ApiRequestEntity request, {int maxBodyBytes = 256 * 1024, List<String> secrets = const []}) =>
    HistoryRequestSnapshot.capture(
      request,
      meta: const HistoryEntryMeta(requestId: 7, requestName: 'Create user', collectionId: 3, collectionName: 'Shop'),
      maxBodyBytes: maxBodyBytes,
      secretValues: secrets,
    );

void main() {
  group('masking a request before it is stored', () {
    test('a literal credential in a header, the URL, a query row and a JSON body is masked; a template is kept', () {
      final snapshot = _capture(_request(
        url: 'https://alice:hunter2pass@api.test/x?api_key=abc123secretvalue&page=2&token={{t}}',
        headers: [
          KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}'),
          KeyValueItem(key: 'X-Api-Key', value: 'plain-literal-key-value'),
          KeyValueItem(key: 'Cookie', value: 'session=abcdef123456'),
          // Not secret by its name, but a GitHub token by its shape.
          KeyValueItem(key: 'X-Customer-Ref', value: 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'),
          KeyValueItem(key: 'Accept', value: 'application/json'),
        ],
        queryParams: [
          KeyValueItem(key: 'access_token', value: 'literal-token-123'),
          KeyValueItem(key: 'limit', value: '10'),
        ],
        body: const RequestBody(
          type: BodyType.raw,
          rawText: '{"user":"ann","password":"p4ssw0rd!","pin":1234,"note":"hi"}',
        ),
      ));

      expect(snapshot.url, 'https://alice:$_mask@api.test/x?api_key=$_mask&page=2&token={{t}}');
      final headers = {for (final h in snapshot.headers) h.key: h.value};
      expect(headers['Authorization'], 'Bearer {{token}}');
      expect(headers['X-Api-Key'], _mask);
      expect(headers['Cookie'], _mask);
      expect(headers['X-Customer-Ref'], _mask);
      expect(headers['Accept'], 'application/json');
      final query = {for (final p in snapshot.queryParams) p.key: p.value};
      expect(query, {'access_token': _mask, 'limit': '10'});
      expect(snapshot.body.rawText, '{"user":"ann","password":"$_mask","pin":"$_mask","note":"hi"}');
      expect(snapshot.hasMaskedValues, isTrue);
    });

    test('form fields are masked by their name, and so are the values of the auth fields', () {
      final snapshot = _capture(_request(
        body: RequestBody(
          type: BodyType.urlEncoded,
          urlEncodedFields: [
            KeyValueItem(key: 'username', value: 'ann'),
            KeyValueItem(key: 'client_secret', value: 'shh-its-a-secret'),
          ],
        ),
        auth: const RequestAuth(
          type: AuthType.basic,
          basicUsername: 'ann',
          basicPassword: 'hunter2pass',
          bearerToken: '{{token}}',
          awsSecretKey: 'wJalrXUtnFEMI/K7MDENG',
          oauth2AccessToken: 'live-cached-access-token',
          oauth2RefreshToken: 'live-cached-refresh-token',
        ),
      ));

      expect({for (final f in snapshot.body.urlEncodedFields) f.key: f.value}, {'username': 'ann', 'client_secret': _mask});
      expect(snapshot.auth.type, AuthType.basic);
      expect(snapshot.auth.basicUsername, 'ann');
      expect(snapshot.auth.basicPassword, _mask);
      expect(snapshot.auth.bearerToken, '{{token}}', reason: 'a variable reference holds no credential');
      expect(snapshot.auth.awsSecretKey, _mask);
      expect(snapshot.auth.oauth2AccessToken, '', reason: 'cached tokens are blanked, not masked: there is nothing to type back');
      expect(snapshot.auth.oauth2RefreshToken, '');
      expect(snapshot.auth.oauth2TokenExpiry, isNull);
    });

    test('a request without a literal credential has nothing masked', () {
      final snapshot = _capture(_request(
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
      ));

      expect(snapshot.hasMaskedValues, isFalse);
      expect(snapshot.body.rawText, '{"name":"{{name}}"}');
    });

    test('toRequest puts the request back with masked values empty, never as the mask', () {
      final snapshot = _capture(_request(
        url: 'https://api.test/x?api_key=abc123secretvalue',
        headers: [KeyValueItem(key: 'X-Api-Key', value: 'plain-literal-key-value'), KeyValueItem(key: 'Accept', value: '*/*')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"password":"p4ssw0rd!"}'),
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'literal-bearer-token'),
      ));

      final request = snapshot.toRequest(id: 99, collectionId: 5, name: 'Copy');

      expect(request.id, 99);
      expect(request.collectionId, 5);
      expect(request.name, 'Copy');
      expect(request.url, 'https://api.test/x?api_key=');
      expect({for (final h in request.headers) h.key: h.value}, {'X-Api-Key': '', 'Accept': '*/*'});
      expect(request.body.rawText, '{"password":""}');
      expect(request.auth.bearerToken, '');
      expect(request.method, HttpMethod.post);
    });

    test('a body longer than the limit is cut after masking, and a credential at the cut is not stored in part', () {
      // 100 bytes, then a password whose value runs past the limit of 120 bytes.
      final body = '${'a' * 100}{"password":"${'S' * 50}"}';

      final capped = HistoryMasker.cappedText(body, 120);

      // The masked text is 100 + 13 bytes, then the 3-byte bullets; two fit in the 120.
      expect(capped.text, '${'a' * 100}{"password":"••');
      expect(capped.truncated, isTrue);
      expect(capped.text, isNot(contains('SS')));
    });

    test('a resolved secret that sits in a body under an innocent name is hidden too', () {
      final capped = HistoryMasker.cappedText('{"ref":"tok-9f8e7d6c5b"}', 1000, secretValues: ['tok-9f8e7d6c5b']);

      expect(capped.text, '{"ref":"$_mask"}');
      expect(capped.truncated, isFalse);
    });

    test('a long body is flagged on the snapshot', () {
      final snapshot = _capture(
        _request(body: RequestBody(type: BodyType.raw, rawText: 'x' * 5000)),
        maxBodyBytes: 1000,
      );

      expect(snapshot.bodyTruncated, isTrue);
      expect(snapshot.body.rawText.length, 1000);
    });
  });

  group('storage format', () {
    test('what is encoded reads back: request, body, auth and the facts about its origin', () {
      final original = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(
          requestId: 7,
          requestName: 'Create user',
          collectionId: 3,
          collectionName: 'Shop',
          environmentName: 'Staging',
          responseBytes: 1234,
          responseTruncated: true,
          hasResponseBody: true,
          statusMessage: 'Created',
          error: 'oops',
        ),
        method: HttpMethod.put,
        url: '{{baseUrl}}/users/1',
        headers: [KeyValueItem(key: 'X-One', value: '1'), KeyValueItem(key: 'X-Off', value: '2', enabled: false)],
        queryParams: [KeyValueItem(key: 'a', value: 'b')],
        body: RequestBody(
          type: BodyType.graphql,
          rawContentType: RawContentType.xml,
          rawText: 'raw',
          formFields: [KeyValueItem(key: 'f', value: 'v')],
          urlEncodedFields: [KeyValueItem(key: 'u', value: 'w')],
          graphqlQuery: '{ me { id } }',
          graphqlVariables: '{"a":1}',
        ),
        auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-Key', apiKeyValue: '{{key}}'),
        bodyTruncated: true,
      );

      final decoded = HistoryRequestSnapshot.decode(original.encode())!;

      expect(decoded.method, HttpMethod.put);
      expect(decoded.url, '{{baseUrl}}/users/1');
      expect([for (final h in decoded.headers) (h.key, h.value, h.enabled)], [('X-One', '1', true), ('X-Off', '2', false)]);
      expect([for (final p in decoded.queryParams) (p.key, p.value)], [('a', 'b')]);
      expect(decoded.body.type, BodyType.graphql);
      expect(decoded.body.rawContentType, RawContentType.xml);
      expect(decoded.body.rawText, 'raw');
      expect(decoded.body.formFields.single.key, 'f');
      expect(decoded.body.urlEncodedFields.single.value, 'w');
      expect(decoded.body.graphqlQuery, '{ me { id } }');
      expect(decoded.body.graphqlVariables, '{"a":1}');
      expect(decoded.auth.type, AuthType.apiKey);
      expect(decoded.auth.apiKeyValue, '{{key}}');
      expect(decoded.bodyTruncated, isTrue);
      final meta = decoded.meta;
      expect(
        (meta.requestId, meta.requestName, meta.collectionId, meta.collectionName, meta.environmentName),
        (7, 'Create user', 3, 'Shop', 'Staging'),
      );
      expect((meta.responseBytes, meta.responseTruncated, meta.hasResponseBody, meta.statusMessage, meta.error), (1234, true, true, 'Created', 'oops'));
    });

    test('an empty or damaged payload reads as no snapshot', () {
      expect(HistoryRequestSnapshot.decode('{}'), isNull);
      expect(HistoryRequestSnapshot.decode('not json'), isNull);
      expect(HistoryRequestSnapshot.decodeMetaOf('{}'), isNull);
    });

    test('the URL shown with an entry is the stored URL plus its enabled query rows', () {
      final snapshot = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.get,
        url: 'https://api.test/a?x=1',
        queryParams: [KeyValueItem(key: 'y', value: '2'), KeyValueItem(key: 'z', value: '3', enabled: false), KeyValueItem(key: '', value: 'q')],
      );

      expect(snapshot.fullUrl, 'https://api.test/a?x=1&y=2');
      expect(HistoryRequestSnapshot.bare('delete', 'https://api.test/b').fullUrl, 'https://api.test/b');
      expect(HistoryRequestSnapshot.bare('delete', 'https://api.test/b').name, 'DELETE https://api.test/b');
    });
  });
}
