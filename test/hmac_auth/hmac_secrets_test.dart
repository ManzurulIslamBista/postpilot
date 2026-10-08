// The HMAC secret is a credential like the AWS secret key or the JWT secret: it is moved out of the shared
// workspace file by SecretSplitter, stripped from Git documents, masked in History and in exports.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/documentation/domain/services/secret_masker.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/services/history_curl.dart';
import 'package:postpilot/features/history/domain/services/history_har.dart';
import 'package:postpilot/features/history/domain/services/history_masker.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/hmac_presets.dart';
import 'package:postpilot/features/workplace/domain/services/credential_keeper.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

const _liveSecret = 'whsec_live_9f8e7d6c5b4a3928';

const _hmac = RequestAuth(type: AuthType.hmac, hmacSecret: _liveSecret);
const _byVariable = RequestAuth(type: AuthType.hmac, hmacSecret: '{{webhookSecret}}');

ApiRequestEntity _request(String name, RequestAuth auth) => ApiRequestEntity(
      id: 0,
      collectionId: 0,
      folderId: null,
      name: name,
      method: HttpMethod.post,
      url: 'https://api.example.com/hooks/in',
      headers: const [],
      queryParams: const [],
      body: const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
      auth: auth,
    );

Map<String, dynamic> _doc() {
  final snapshot = BackupSnapshot(
    exportedAt: DateTime.utc(2026),
    collections: [
      BackupCollection(
        name: 'Hooks',
        auth: _hmac,
        folders: const [FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Stripe')],
        folderDefaults: const {
          1: LevelDefaults(auth: RequestAuth(type: AuthType.hmac, hmacSecret: 'folder-signing-secret-4455')),
        },
        requests: [
          BackupRequest(request: _request('Own secret', HmacPresets.apply(_hmac, HmacPreset.slack))),
          BackupRequest(request: _request('By variable', _byVariable)),
        ],
      ),
    ],
  );
  return jsonDecode(BackupCodec.encode(snapshot)) as Map<String, dynamic>;
}

Map<String, dynamic> _collection(Map<String, dynamic> doc) => (doc['collections'] as List).single as Map<String, dynamic>;

Map<String, dynamic> _requestNamed(Map<String, dynamic> doc, String name) =>
    (_collection(doc)['requests'] as List).cast<Map<String, dynamic>>().firstWhere((r) => r['name'] == name);

void main() {
  group('SecretSplitter', () {
    test('the secret of a collection, a folder and a request is split out like any other auth secret', () {
      final split = SecretSplitter.split(_doc());
      final shop = _collection(split.publicDoc);

      expect(shop['auth']['hmacSecret'], '');
      expect(shop['auth']['type'], 'hmac', reason: 'what kind of auth it is stays readable');
      expect((shop['folders'] as List).single['auth']['hmacSecret'], '');
      expect(_requestNamed(split.publicDoc, 'Own secret')['auth']['hmacSecret'], '');

      expect(split.secrets['cauth/Hooks/hmacSecret'], _liveSecret);
      expect(split.secrets['fauth/Hooks/Stripe/hmacSecret'], 'folder-signing-secret-4455');
      expect(split.secrets['rauth/Hooks/Own secret/hmacSecret'], _liveSecret);
      expect(jsonEncode(split.publicDoc), isNot(contains(_liveSecret)));
      expect(jsonEncode(split.publicDoc), isNot(contains('folder-signing-secret-4455')));
    });

    test('the fields that are no secret stay in the shared file: header names, templates, preset', () {
      final split = SecretSplitter.split(_doc());
      final auth = _requestNamed(split.publicDoc, 'Own secret')['auth'] as Map;

      expect(auth['hmacPreset'], 'slack');
      expect(auth['hmacHeaderName'], 'X-Slack-Signature');
      expect(auth['hmacHeaderTemplate'], 'v0={signature}');
      expect(auth['hmacPayloadTemplate'], 'v0:{timestamp}:{body}');
      expect(auth['hmacTimestampHeader'], 'X-Slack-Request-Timestamp');
    });

    test('a secret that only references a variable is not a secret', () {
      final split = SecretSplitter.split(_doc());

      expect(_requestNamed(split.publicDoc, 'By variable')['auth']['hmacSecret'], '{{webhookSecret}}');
      expect(split.secrets.keys.where((k) => k.contains('By variable')), isEmpty);
    });

    test('merging the secrets back restores the document', () {
      final doc = _doc();
      final split = SecretSplitter.split(doc);

      final merged = SecretSplitter.merge(split.publicDoc, split.secrets);

      expect(merged, doc);
    });

    test('nothing HMAC is left that a push would publish', () {
      expect(SecretSplitter.exposed(_doc(), keepLocal: true), isEmpty);
    });
  });

  group('Git documents and pulls', () {
    test('stripAuth removes the secret and keeps a variable reference', () {
      expect(SecretFields.authKeys, contains('hmacSecret'));
      expect(SecretFields.stripAuth(_hmac.toJson()), isNot(contains('hmacSecret')));
      expect(SecretFields.stripAuth(_hmac.toJson())['hmacHeaderName'], 'X-Hub-Signature-256');
      expect(SecretFields.stripAuth(_byVariable.toJson())['hmacSecret'], '{{webhookSecret}}');
    });

    test('a pull that left the secret blank keeps the one this device has', () {
      final current = SecretSplitter.merge(SecretSplitter.split(_doc()).publicDoc, SecretSplitter.split(_doc()).secrets);
      final incoming = SecretSplitter.split(_doc()).publicDoc;

      final kept = CredentialKeeper.keep(incoming, current);

      expect(_collection(kept)['auth']['hmacSecret'], _liveSecret);
      expect(_requestNamed(kept, 'Own secret')['auth']['hmacSecret'], _liveSecret);
    });
  });

  group('History and exports', () {
    test('History masks a literal secret and keeps a variable reference', () {
      expect(HistoryMasker.auth(_hmac).hmacSecret, SecretMasker.mask);
      expect(HistoryMasker.auth(_byVariable).hmacSecret, '{{webhookSecret}}');
      expect(HistoryMasker.auth(_hmac).hmacHeaderName, 'X-Hub-Signature-256');
    });

    test('History keeps the templates of every preset as they are written', () {
      for (final preset in HmacPreset.values.where((p) => p != HmacPreset.generic)) {
        final auth = HmacPresets.apply(_hmac, preset);

        final masked = HistoryMasker.auth(auth);

        expect(masked.hmacPayloadTemplate, auth.hmacPayloadTemplate, reason: preset.name);
        expect(masked.hmacHeaderTemplate, auth.hmacHeaderTemplate, reason: preset.name);
        expect(masked.hmacHeaderName, auth.hmacHeaderName, reason: preset.name);
        expect(masked.hmacTimestampHeader, auth.hmacTimestampHeader, reason: preset.name);
        expect(masked.hmacSecret, SecretMasker.mask, reason: preset.name);
      }
    });

    test('a request captured for History does not hold the secret', () {
      final snapshot = HistoryRequestSnapshot.capture(
        _request('Hook', _hmac),
        meta: const HistoryEntryMeta(),
        maxBodyBytes: 1000,
      );

      expect(jsonEncode(snapshot.auth.toJson()), isNot(contains(_liveSecret)));
      expect(snapshot.auth.type, AuthType.hmac);
    });

    test('the HAR and cURL of a History entry name the signature header with a masked value', () {
      final auth = HistoryMasker.auth(_hmac);

      final header = HistoryHar.authorizationHeader(auth, (text) => text)!;
      final curl = HistoryCurl.template(HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.post,
        url: 'https://api.example.com/hooks/in',
        body: const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
        auth: auth,
      ));

      expect(header.name, 'X-Hub-Signature-256');
      expect(header.value, SecretMasker.mask);
      expect(curl, contains("--header 'X-Hub-Signature-256: ${SecretMasker.mask}'"));
      expect(curl, contains('HMAC signature credentials are not part of History'));
      expect(curl, isNot(contains(_liveSecret)));
    });

    test('an HMAC auth without a header name adds no header to a HAR', () {
      expect(HistoryHar.authorizationHeader(_hmac.copyWith(hmacHeaderName: ''), (text) => text), isNull);
    });
  });
}
