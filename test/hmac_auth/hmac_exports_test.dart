// What the exporters do with an HMAC auth: Postman has no HMAC type (the block is read back by PostPilot, and the
// secret is redacted on request), OpenAPI gets an API key in the signature header.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_exporter.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_presets.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

const _secret = 'whsec_export_secret_77';

final _stripe = HmacPresets.apply(
  const RequestAuth(
    type: AuthType.hmac,
    hmacSecret: _secret,
    hmacTimestampSource: HmacTimestampSource.fixed,
    hmacTimestampValue: '1700000000',
  ),
  HmacPreset.stripe,
);

ApiRequestEntity _request(String name, RequestAuth auth) => ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: name,
      method: HttpMethod.post,
      url: 'https://api.example.com/hooks/in',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: auth,
    );

void main() {
  group('Postman', () {
    test('export then import keeps every field of the HMAC auth', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'Hooks',
        folders: const [],
        requests: [_request('Stripe', _stripe)],
        collectionAuth: _stripe,
      );

      final collection = PostmanCollectionParser.parse(json);
      final back = (collection.items.single as PostmanRequestItem).auth;

      expect(back.type, AuthType.hmac);
      expect(back.hmacPreset, HmacPreset.stripe);
      expect(back.hmacSecret, _secret);
      expect(back.hmacAlgorithm, HmacAlgorithm.sha256);
      expect(back.hmacEncoding, HmacEncoding.hex);
      expect(back.hmacPayloadTemplate, '{timestamp}.{body}');
      expect(back.hmacHeaderName, 'Stripe-Signature');
      expect(back.hmacHeaderTemplate, 't={timestamp},v1={signature}');
      expect(back.hmacTimestampSource, HmacTimestampSource.fixed);
      expect(back.hmacTimestampValue, '1700000000');
      expect(collection.auth?.type, AuthType.hmac, reason: 'the collection\'s own auth as well');
    });

    test('a Shopify request keeps base64 and the Slack timestamp header survives too', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'Hooks',
        folders: const [],
        requests: [
          _request('Shopify', HmacPresets.apply(const RequestAuth(type: AuthType.hmac), HmacPreset.shopify)),
          _request('Slack', HmacPresets.apply(const RequestAuth(type: AuthType.hmac), HmacPreset.slack)),
        ],
      );

      final items = PostmanCollectionParser.parse(json).items.cast<PostmanRequestItem>();

      expect(items[0].auth.hmacEncoding, HmacEncoding.base64);
      expect(items[1].auth.hmacTimestampHeader, 'X-Slack-Request-Timestamp');
      expect(items[1].auth.hmacPreset, HmacPreset.slack);
    });

    test('redacting replaces the secret with a variable that is declared, and keeps the rest', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'Hooks',
        folders: const [],
        requests: [_request('Stripe', _stripe)],
        redactSecrets: true,
      );

      expect(json, isNot(contains(_secret)));
      final collection = PostmanCollectionParser.parse(json);
      final back = (collection.items.single as PostmanRequestItem).auth;
      expect(back.hmacSecret, '{{hmacSecret}}');
      expect(back.hmacHeaderName, 'Stripe-Signature');
      expect(collection.variables.map((v) => v.key), contains('hmacSecret'));
    });
  });

  group('OpenAPI', () {
    Map<String, dynamic> export(List<ApiRequestEntity> requests) =>
        jsonDecode(OpenApiExporter.export(collectionName: 'Hooks', folders: const [], requests: requests).text) as Map<String, dynamic>;

    test('the signature header is an API key scheme, shared by requests with the same header', () {
      final doc = export([_request('One', _stripe), _request('Two', _stripe)]);

      final schemes = (doc['components'] as Map<String, dynamic>)['securitySchemes'] as Map<String, dynamic>;
      expect(schemes.keys, ['hmacAuth']);
      final scheme = schemes['hmacAuth'] as Map;
      expect(scheme['type'], 'apiKey');
      expect(scheme['name'], 'Stripe-Signature');
      expect(scheme['in'], 'header');
      expect(scheme['description'], contains('HMAC-SHA256'));
      expect(jsonEncode(doc), isNot(contains(_secret)));
    });

    test('a signature without a header name has no scheme', () {
      final doc = export([_request('One', _stripe.copyWith(hmacHeaderName: ''))]);

      expect((doc['components'] as Map?)?['securitySchemes'], anyOf(isNull, isEmpty));
    });
  });
}
