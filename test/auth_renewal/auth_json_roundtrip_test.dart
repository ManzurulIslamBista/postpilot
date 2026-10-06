// The settings of self-renewing auth (Auto-renew, the re-login request) live inside the auth JSON, so they must
// read back from every place an auth is stored or shared: the database column, a backup, a workspace file, Git.
// Old data without them must read as before, and no token may leak into what is shared.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/git_sync/data/mappers/collection_doc_mapper.dart';
import 'package:postpilot/features/git_sync/data/mappers/doc_values.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/data/models/request_json_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';
import 'auth_harness.dart';

const _relogin = ReloginConfig(request: 'Auth/Login');
const _accessToken = 'live-access-token-0123456789';
const _refreshToken = 'live-refresh-token-9876543210';

RequestAuth _collectionAuth() => oauthAuth(
      secret: 'client-secret-xyz',
      token: _accessToken,
      expiry: DateTime.utc(2026, 10, 6, 13),
      refresh: _refreshToken,
    ).withRelogin(_relogin);

void main() {
  group('RequestAuth JSON', () {
    test('auth saved before these settings existed reads back with Auto-renew on and no re-login', () {
      final old = RequestAuth.fromJson({
        'type': 'oauth2',
        'oauth2GrantType': 'clientCredentials',
        'oauth2AccessTokenUrl': 'https://auth.test/token',
        'oauth2ClientId': 'cid',
        'oauth2AccessToken': 'tok',
      });

      expect(old.oauth2AutoRenew, isTrue);
      expect(old.relogin, isNull);
      expect(old.oauth2AccessToken, 'tok');
    });

    test('the defaults add no key, so existing JSON, diffs and Git files stay exactly as they were', () {
      final json = const RequestAuth(type: AuthType.oauth2).toJson();

      expect(json.containsKey('oauth2AutoRenew'), isFalse);
      expect(json.containsKey('relogin'), isFalse);
      expect(RequestAuth.fromJson(json).toJson(), json);
    });

    test('Auto-renew off and the re-login request round-trip through JSON and the request column codec', () {
      final auth = _collectionAuth().copyWith(oauth2AutoRenew: false);

      final viaString = RequestAuth.fromJsonString(auth.toJsonString())!;
      final viaColumn = RequestJsonCodec.decodeAuth('oauth2', RequestJsonCodec.encodeAuth(auth));

      for (final restored in [viaString, viaColumn]) {
        expect(restored.oauth2AutoRenew, isFalse);
        expect(restored.relogin, _relogin);
        expect(restored.oauth2AccessToken, _accessToken);
      }
      expect(auth.toJson()['relogin'], {'request': 'Auth/Login'});
    });

    test('editing one part keeps the others: a token keeps the re-login, a re-login keeps the token and Auto-renew', () {
      final auth = _collectionAuth().copyWith(oauth2AutoRenew: false);

      final retoken = auth.withOAuth2Token('new', null, refreshToken: 'r2');
      expect(retoken.relogin, _relogin);
      expect(retoken.oauth2AutoRenew, isFalse);
      final recopied = auth.copyWith(oauth2Scope: 'read');
      expect(recopied.relogin, _relogin);
      expect(recopied.oauth2AccessToken, _accessToken);
      final cleared = auth.withRelogin(null);
      expect(cleared.relogin, isNull);
      expect(cleared.oauth2AccessToken, _accessToken);
      expect(cleared.oauth2AutoRenew, isFalse);
      expect(auth.clearOAuth2Token().relogin, _relogin);
    });

    test('takeNewerOAuth2Token merges a token renewed behind an open request\'s back without touching its other edits', () {
      final mine = oauthAuth(token: 'old', expiry: DateTime.utc(2026, 10, 6, 12)).copyWith(oauth2Scope: 'edited-scope');
      final theirs = oauthAuth(token: 'renewed', expiry: DateTime.utc(2026, 10, 6, 13), refresh: 'r1');

      final merged = mine.takeNewerOAuth2Token(theirs)!;

      expect((merged.oauth2AccessToken, merged.oauth2RefreshToken, merged.oauth2Scope), ('renewed', 'r1', 'edited-scope'));
      expect(mine.takeNewerOAuth2Token(mine), isNull);
      expect(theirs.takeNewerOAuth2Token(mine), isNull, reason: 'an older token is not newer');
      expect(mine.takeNewerOAuth2Token(const RequestAuth(type: AuthType.bearer)), isNull);
      expect(oauthAuth().takeNewerOAuth2Token(theirs)!.oauth2AccessToken, 'renewed', reason: 'a cleared token takes the new one');
    });
  });

  group('ReloginConfig JSON', () {
    test('writes the default statuses as nothing and others sorted; reads garbage as no config', () {
      expect(const ReloginConfig(request: 'Login').toJson(), {'request': 'Login'});
      expect(const ReloginConfig(request: 'Login', statuses: {403}).toJson(), {'request': 'Login', 'statuses': [403]});
      expect(const ReloginConfig(request: 'Login', statuses: {403, 401, 419}).toJson()['statuses'], [401, 403, 419]);

      expect(ReloginConfig.fromJson({'request': 'Auth/Login'}), _relogin);
      expect(ReloginConfig.fromJson({'request': 'Login', 'statuses': [403, 'x', 99, 700]}), const ReloginConfig(request: 'Login', statuses: {403}));
      expect(ReloginConfig.fromJson({'request': 'Login', 'statuses': <int>[]})!.isActive, isFalse);
      for (final bad in [null, 'Login', 42, <String, Object?>{}, {'request': ''}, {'request': 7}]) {
        expect(ReloginConfig.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('triggers only on its statuses', () {
      const config = ReloginConfig(request: 'Login');

      expect([for (final s in [200, 400, 401, 403, 404, 500]) config.triggersOn(s)], [false, false, true, true, false, false]);
      expect(const ReloginConfig(request: '').triggersOn(401), isFalse);
    });
  });

  group('a backup', () {
    BackupSnapshot snapshot() => BackupSnapshot(
          exportedAt: DateTime.utc(2026),
          collections: [
            BackupCollection(
              name: 'API',
              auth: _collectionAuth(),
              folders: const [
                FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Admin'),
              ],
              folderDefaults: {
                1: LevelDefaults(
                  auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{adminToken}}')
                      .withRelogin(const ReloginConfig(request: 'Admin/AdminLogin', statuses: {401})),
                ),
              },
            ),
          ],
        );

    test('carries the collection\'s and a folder\'s re-login and Auto-renew through encode and decode', () {
      final decoded = BackupCodec.decode(BackupCodec.encode(snapshot()));

      final collection = decoded.collections.single;
      expect(collection.auth!.relogin, _relogin);
      expect(collection.auth!.oauth2AutoRenew, isTrue);
      expect(collection.folderDefaults[1]!.auth!.relogin, const ReloginConfig(request: 'Admin/AdminLogin', statuses: {401}));
      expect(collection.defaultsTree.chainFor(1).scopes.last.defaults.auth!.relogin!.request, 'Admin/AdminLogin');
    });

    test('a collection with no auth of its own can still carry a re-login', () {
      final withNone = BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [BackupCollection(name: 'API', auth: const RequestAuth(type: AuthType.none).withRelogin(_relogin))],
      );

      final restored = BackupCodec.decode(BackupCodec.encode(withNone)).collections.single.auth!;

      expect(restored.type, AuthType.none);
      expect(restored.relogin, _relogin);
    });

    test('a backup from before has no re-login and reads as it always did', () {
      final json = jsonDecode(BackupCodec.encode(snapshot())) as Map<String, dynamic>;
      ((json['collections'] as List).single['auth'] as Map).remove('relogin');

      expect(BackupCodec.decode(jsonEncode(json)).collections.single.auth!.relogin, isNull);
    });
  });

  group('Git', () {
    SyncDoc collectionDoc(Map<String, Object?> auth) => SyncDoc(
          uid: 'c-1',
          kind: SyncKind.collection,
          parentUid: null,
          name: 'API',
          data: {'auth': auth},
        );

    test('keeps the re-login in the shared doc and drops every token from it', () {
      final canonical = CollectionDocMapper.canonical(collectionDoc(_collectionAuth().toJson()));
      final shared = SecretFields.stripDoc(canonical);
      final text = jsonEncode(shared.data);

      expect((shared.data['auth'] as Map)['relogin'], {'request': 'Auth/Login'});
      for (final secret in [_accessToken, _refreshToken, 'client-secret-xyz']) {
        expect(text, isNot(contains(secret)));
      }
      expect((shared.data['auth'] as Map)['oauth2AccessTokenUrl'], 'https://auth.test/oauth/token');
    });

    test('pulling a doc back keeps what is local: the tokens stay, the re-login comes from the doc', () {
      final local = CollectionDocMapper.canonical(collectionDoc(_collectionAuth().toJson()));
      final remote = SecretFields.stripDoc(local).data['auth'] as Map<String, Object?>;
      remote['relogin'] = {'request': 'Other/Login'};

      final merged = CollectionDocMapper.canonical(collectionDoc(remote), local: local);

      final auth = RequestAuth.fromJson(Map<String, dynamic>.from(merged.data['auth'] as Map));
      expect(auth.oauth2AccessToken, _accessToken);
      expect(auth.oauth2RefreshToken, _refreshToken);
      expect(auth.relogin!.request, 'Other/Login');
    });

    test('the collection_auth row written from a doc has the re-login; a No Auth collection keeps one that is set', () {
      final doc = CollectionDocMapper.canonical(collectionDoc(_collectionAuth().toJson()));
      expect(RequestAuth.fromJsonString(CollectionDocMapper.authJson(doc))!.relogin, _relogin);

      final none = const RequestAuth(type: AuthType.none);
      expect(DocValues.collectionAuth(none.toJson()), isNull, reason: 'No Auth alone is no row, as before');
      expect(DocValues.collectionAuth(none.withRelogin(_relogin).toJson())!['relogin'], {'request': 'Auth/Login'});
    });

    test('a folder\'s auth carries its re-login through the doc mapper', () {
      final folderAuth = const RequestAuth(type: AuthType.bearer, bearerToken: '{{t}}').withRelogin(_relogin);

      final mapped = DocValues.folderAuth(folderAuth.toJson())!;

      expect(mapped['relogin'], {'request': 'Auth/Login'});
      expect(DocValues.folderAuth(const RequestAuth(type: AuthType.inherit).withRelogin(_relogin).toJson()), isNull,
          reason: 'a folder that only inherits sets no auth, so it holds no re-login either');
    });
  });

  group('a workspace file and its local secrets', () {
    Map<String, dynamic> workspace() => {
          'format': 'postpilot-backup',
          'version': 2,
          'collections': [
            {
              'name': 'API',
              'auth': _collectionAuth().toJson(),
              'folders': <Object>[],
              'requests': <Object>[],
            },
          ],
        };

    test('the shared file keeps the re-login and the token URL; tokens and secrets move to the local file and come back', () {
      final doc = workspace();

      final split = SecretSplitter.split(doc);

      final publicText = jsonEncode(split.publicDoc);
      for (final secret in [_accessToken, _refreshToken, 'client-secret-xyz']) {
        expect(publicText, isNot(contains(secret)));
        expect(split.secrets.values, contains(secret));
      }
      final publicAuth = (split.publicDoc['collections'] as List).single['auth'] as Map;
      expect(publicAuth['relogin'], {'request': 'Auth/Login'});
      expect(publicAuth['oauth2AccessTokenUrl'], 'https://auth.test/oauth/token');

      final merged = SecretSplitter.merge(split.publicDoc, split.secrets);
      final restored = RequestAuth.fromJson(Map<String, dynamic>.from((merged['collections'] as List).single['auth'] as Map));
      expect(restored.oauth2AccessToken, _accessToken);
      expect(restored.oauth2RefreshToken, _refreshToken);
      expect(restored.oauth2ClientSecret, 'client-secret-xyz');
      expect(restored.relogin, _relogin);
    });
  });
}
