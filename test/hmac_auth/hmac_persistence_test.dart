// The HMAC auth is kept in the existing JSON of an auth (the `authConfigJson` column, a collection's and a folder's
// auth text, a backup, a Git document): no schema change. These tests prove it reads back whole and that nothing
// else's JSON changed.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_codec.dart';
import 'package:postpilot/features/request_builder/data/models/request_json_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_presets.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

const _custom = RequestAuth(
  type: AuthType.hmac,
  hmacPreset: HmacPreset.generic,
  hmacSecret: 'whsec_abc123',
  hmacAlgorithm: HmacAlgorithm.sha512,
  hmacEncoding: HmacEncoding.base64,
  hmacPayloadTemplate: '{method}\n{path}\n{timestamp}\n{body}',
  hmacHeaderName: 'X-Signature',
  hmacHeaderTemplate: 'v1={signature}',
  hmacTimestampHeader: 'X-Timestamp',
  hmacTimestampSource: HmacTimestampSource.fixed,
  hmacTimestampValue: '1700000000',
);

void _expectSameFields(RequestAuth actual, RequestAuth expected) {
  expect(actual.type, expected.type);
  expect(actual.hmacPreset, expected.hmacPreset);
  expect(actual.hmacSecret, expected.hmacSecret);
  expect(actual.hmacAlgorithm, expected.hmacAlgorithm);
  expect(actual.hmacEncoding, expected.hmacEncoding);
  expect(actual.hmacPayloadTemplate, expected.hmacPayloadTemplate);
  expect(actual.hmacHeaderName, expected.hmacHeaderName);
  expect(actual.hmacHeaderTemplate, expected.hmacHeaderTemplate);
  expect(actual.hmacTimestampHeader, expected.hmacTimestampHeader);
  expect(actual.hmacTimestampSource, expected.hmacTimestampSource);
  expect(actual.hmacTimestampValue, expected.hmacTimestampValue);
}

void main() {
  group('the auth JSON', () {
    test('every field of a customised HMAC auth reads back', () {
      final back = RequestAuth.fromJson(jsonDecode(jsonEncode(_custom.toJson())) as Map<String, dynamic>);

      _expectSameFields(back, _custom);
      expect(back.toJson(), _custom.toJson());
    });

    test('the string form a collection stores reads back too', () {
      _expectSameFields(RequestAuth.fromJsonString(_custom.toJsonString())!, _custom);
    });

    test('an HMAC auth left at its defaults writes none of its fields, and reads back as the GitHub preset', () {
      const plain = RequestAuth(type: AuthType.hmac);

      final json = plain.toJson();

      expect(json.keys.where((k) => k.startsWith('hmac')), isEmpty);
      final back = RequestAuth.fromJson(json);
      expect(back.type, AuthType.hmac);
      expect(back.hmacPreset, HmacPreset.github);
      expect(back.hmacHeaderName, 'X-Hub-Signature-256');
      expect(back.hmacHeaderTemplate, 'sha256={signature}');
      expect(back.hmacPayloadTemplate, '{body}');
      expect(back.hmacAlgorithm, HmacAlgorithm.sha256);
      expect(back.hmacEncoding, HmacEncoding.hex);
    });

    test('the auth of any other type has the same JSON as before the HMAC type existed', () {
      for (final auth in const [
        RequestAuth(),
        RequestAuth.none,
        RequestAuth(type: AuthType.bearer, bearerToken: 't'),
        RequestAuth(type: AuthType.awsSignatureV4, awsAccessKey: 'a', awsSecretKey: 's'),
        RequestAuth(type: AuthType.jwtBearer, jwtSecret: 's'),
      ]) {
        expect(auth.toJson().keys.where((k) => k.startsWith('hmac')), isEmpty, reason: auth.type.name);
      }
    });

    test('a text written before the HMAC type existed reads with the defaults', () {
      final back = RequestAuth.fromJson({'type': 'bearer', 'bearerToken': 'abc'});

      expect(back.type, AuthType.bearer);
      expect(back.hmacSecret, isEmpty);
      expect(back.hmacPreset, HmacPreset.github);
    });

    test('an unknown enum name falls back to the default instead of failing', () {
      final back = RequestAuth.fromJson({
        'type': 'hmac',
        'hmacAlgorithm': 'md5',
        'hmacEncoding': 'rot13',
        'hmacTimestampSource': 'yesterday',
        'hmacPreset': 'paypal',
        'hmacHeaderName': 'X-Sig',
      });

      expect(back.hmacAlgorithm, HmacAlgorithm.sha256);
      expect(back.hmacEncoding, HmacEncoding.hex);
      expect(back.hmacTimestampSource, HmacTimestampSource.now);
      expect(back.hmacPreset, HmacPreset.github);
      expect(back.hmacHeaderName, 'X-Sig');
    });

    test('copyWith, withRelogin and the OAuth 2.0 token helpers keep the HMAC fields', () {
      _expectSameFields(_custom.copyWith(bearerToken: 'x'), _custom);
      _expectSameFields(_custom.withRelogin(null), _custom);
      _expectSameFields(_custom.withOAuth2Token('at', DateTime.utc(2030)), _custom);
      _expectSameFields(_custom.clearOAuth2Token(), _custom);
      _expectSameFields(_custom.resolveInherited(const RequestAuth(type: AuthType.bearer)), _custom);
    });

    test('HMAC auth is a type of its own in the type list and is labelled', () {
      expect(AuthType.values, contains(AuthType.hmac));
      expect(AuthType.hmac.label, 'HMAC signature');
      expect(AuthType.values.map((t) => t.name).toSet(), hasLength(AuthType.values.length));
    });
  });

  group('the request row and the other stores', () {
    test('the codec of the authType and authConfigJson columns', () {
      final text = RequestJsonCodec.encodeAuth(_custom);

      final back = RequestJsonCodec.decodeAuth(AuthType.hmac.name, text);

      _expectSameFields(back, _custom);
    });

    test('a request saved to the database comes back with its HMAC auth, through the existing columns', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repos = DriftRepos(db);
      final shop = await repos.collectionRepository.createCollection('Shop');

      final id = await addRequest(repos, shop, 'Webhook', auth: _custom);
      final loaded = (await repos.requestRepository.findById(id))!;

      _expectSameFields(loaded.auth, _custom);
      final row = await db.select(db.requests).getSingle();
      expect(row.authType, 'hmac');
      expect(jsonDecode(row.authConfigJson), containsPair('hmacHeaderName', 'X-Signature'));
    });

    test('a collection\'s auth is stored as text and reads back', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repos = DriftRepos(db);
      final shop = await repos.collectionRepository.createCollection('Shop');

      await repos.collectionAuthRepository.setAuthJson(shop, _custom.toJsonString());

      _expectSameFields(RequestAuth.fromJsonString(await repos.collectionAuthRepository.getAuthJson(shop))!, _custom);
    });

    test('what a folder or a collection passes down keeps it', () {
      final json = DefaultsCodec.authToJson(_custom);

      _expectSameFields(DefaultsCodec.authFromJson(json)!, _custom);
      expect(DefaultsCodec.authFromJson(DefaultsCodec.authToJson(const RequestAuth(type: AuthType.hmac)))?.type, AuthType.hmac);
    });
  });

  group('the presets', () {
    test('a new HMAC auth is the GitHub preset', () {
      expect(HmacPresets.matches(HmacPreset.github, const RequestAuth(type: AuthType.hmac)), isTrue);
    });

    test('each preset fills in the documented scheme and keeps the secret and the timestamp source', () {
      const mine = RequestAuth(
        type: AuthType.hmac,
        hmacSecret: 'keep-me',
        hmacTimestampSource: HmacTimestampSource.fixed,
        hmacTimestampValue: '1700000000',
      );

      final stripe = HmacPresets.apply(mine, HmacPreset.stripe);
      expect(stripe.hmacPreset, HmacPreset.stripe);
      expect(stripe.hmacHeaderName, 'Stripe-Signature');
      expect(stripe.hmacHeaderTemplate, 't={timestamp},v1={signature}');
      expect(stripe.hmacPayloadTemplate, '{timestamp}.{body}');
      expect(stripe.hmacSecret, 'keep-me');
      expect(stripe.hmacTimestampSource, HmacTimestampSource.fixed);
      expect(stripe.hmacTimestampValue, '1700000000');

      final shopify = HmacPresets.apply(mine, HmacPreset.shopify);
      expect(shopify.hmacHeaderName, 'X-Shopify-Hmac-Sha256');
      expect(shopify.hmacEncoding, HmacEncoding.base64);
      expect(shopify.hmacHeaderTemplate, '{signature}');

      final slack = HmacPresets.apply(mine, HmacPreset.slack);
      expect(slack.hmacHeaderName, 'X-Slack-Signature');
      expect(slack.hmacHeaderTemplate, 'v0={signature}');
      expect(slack.hmacPayloadTemplate, 'v0:{timestamp}:{body}');
      expect(slack.hmacTimestampHeader, 'X-Slack-Request-Timestamp');

      // Back to GitHub: the Slack timestamp header and the base64 are gone again.
      final github = HmacPresets.apply(slack, HmacPreset.github);
      expect(github.hmacTimestampHeader, isEmpty);
      expect(github.hmacEncoding, HmacEncoding.hex);
      expect(github.hmacHeaderName, 'X-Hub-Signature-256');
    });

    test('Generic keeps every value and only changes the name', () {
      final slack = HmacPresets.apply(const RequestAuth(type: AuthType.hmac, hmacSecret: 's'), HmacPreset.slack);

      final generic = HmacPresets.apply(slack, HmacPreset.generic);

      expect(generic.hmacPreset, HmacPreset.generic);
      _expectSameFields(generic.copyWith(hmacPreset: HmacPreset.slack), slack);
    });

    test('an edit that leaves the preset makes the auth generic; one that does not, does not', () {
      final stripe = HmacPresets.apply(const RequestAuth(type: AuthType.hmac), HmacPreset.stripe);

      expect(HmacPresets.settled(stripe.copyWith(hmacSecret: 'typed')).hmacPreset, HmacPreset.stripe);
      expect(HmacPresets.settled(stripe.copyWith(hmacTimestampSource: HmacTimestampSource.fixed)).hmacPreset, HmacPreset.stripe);
      expect(HmacPresets.settled(stripe.copyWith(hmacHeaderName: 'Stripe-Signature-2')).hmacPreset, HmacPreset.generic);
      expect(HmacPresets.settled(stripe.copyWith(hmacAlgorithm: HmacAlgorithm.sha512)).hmacPreset, HmacPreset.generic);
    });
  });
}
