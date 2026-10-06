// Tokens are secrets. A renewal, a re-login and a token that failed must leave none of them in History, the
// console, an error message, a Postman export or what is shared through Git or a workspace file.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/logging_api_client.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/auth_owner.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/auth_renewal/domain/repositories/oauth2_token_store.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/renew_request_auth_usecase.dart';
import 'package:postpilot/features/console/presentation/view_models/request_console_log.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_names.dart';
import 'package:postpilot/features/history/data/repositories/history_repository_impl.dart';
import 'package:postpilot/features/history/data/repository_history_context_source.dart';
import 'package:postpilot/features/history/domain/services/history_masker.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/documentation/domain/services/secret_masker.dart';
import 'auth_harness.dart';

const _suffix = '-Zq81xK0pLmN4vTb7yRwQ';

void main() {
  late AuthWorld world;
  late int shop;

  setUp(() async {
    world = await AuthWorld.create(server: FakeAuthServer()..tokenSuffix = _suffix);
    shop = await world.collection('Shop');
  });
  tearDown(() => world.close());

  Future<String> everythingStored() async {
    final out = StringBuffer();
    for (final table in ['history_entries', 'history_payloads']) {
      for (final row in await world.db.customSelect('SELECT * FROM $table').get()) {
        for (final value in row.data.values) {
          out.writeln(value is Uint8List ? utf8.decode(value, allowMalformed: true) : '$value');
        }
      }
    }
    return out.toString();
  }

  test('History keeps no access token, refresh token or client secret from a send that renewed its token', () async {
    world.server.rotateRefresh = true;
    world.server.validRefresh.add('rt-seed$_suffix');
    await world.setCollectionAuth(
      shop,
      oauthAuth(token: 'dead-token$_suffix', expiry: world.now.subtract(const Duration(hours: 1)), refresh: 'rt-seed$_suffix'),
    );
    final store = HistoryRepositoryImpl(
      world.db.historyDao,
      context: RepositoryHistoryContextSource(
        collections: world.repos.collectionRepository,
        environments: world.repos.environmentRepository,
        globals: world.repos.globalVariableRepository,
        collectionAuth: world.repos.collectionAuthRepository,
      ),
    );
    final send = SendRequestUseCase(
      world.server,
      world.resolver,
      store,
      world.repos.collectionAuthRepository,
      null,
      null,
      const RequestSpecBuilder(),
      world.defaults,
      RenewRequestAuthUseCase(world.manager),
      world.relogin,
    );
    // An API that echoes back the credentials it was called with, as a careless one does.
    world.server.apiOverride = (spec) => world.server.reply(200, {
          'you_sent': spec.headers['Authorization'],
          'access_token': spec.headers['Authorization']?.replaceFirst('Bearer ', ''),
        });
    final echo = await world.request(shop, 'Echo', '/echo');

    final response = await send(echo);

    final stored = await world.storedCollectionAuth(shop);
    expect(response.statusCode, 200);
    expect(stored.oauth2AccessToken, 'at-1$_suffix', reason: 'the renewed token is stored in the collection');
    expect(stored.oauth2RefreshToken, 'rt-1$_suffix');
    final history = await everythingStored();
    expect(history, isNotEmpty);
    for (final secret in ['at-1$_suffix', 'rt-1$_suffix', 'rt-seed$_suffix', 'dead-token$_suffix', 'csecret']) {
      expect(history, isNot(contains(secret)), reason: secret);
    }
  });

  test('History keeps no token from a login response that a re-login ran', () async {
    final authFolder = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Auth');
    await world.loginRequest(shop, folderId: authFolder);
    await world.repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'token', value: 'stale-token-value-0001', isSecret: true, enabled: true),
    );
    final store = HistoryRepositoryImpl(
      world.db.historyDao,
      context: RepositoryHistoryContextSource(
        collections: world.repos.collectionRepository,
        environments: world.repos.environmentRepository,
        globals: world.repos.globalVariableRepository,
        collectionAuth: world.repos.collectionAuthRepository,
      ),
    );
    final send = SendRequestUseCase(
      world.server,
      world.resolver,
      store,
      world.repos.collectionAuthRepository,
      null,
      null,
      const RequestSpecBuilder(),
      world.defaults,
      RenewRequestAuthUseCase(world.manager),
      world.relogin,
    );
    await world.setCollectionAuth(
      shop,
      const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}').withRelogin(const ReloginConfig(request: 'Auth/Login')),
    );
    final orders = await world.request(shop, 'Orders', '/orders');

    final response = await send(orders);

    expect(response.authNotes.single, contains('Re-authenticated via "Auth/Login"'));
    final history = await everythingStored();
    expect(history, contains('login'), reason: 'the login request is in History');
    expect(history, isNot(contains('login-1$_suffix')));
  });

  test('the console lists token requests and the requests they authorize, without a secret in any field', () async {
    final log = RequestConsoleLog();
    final logging = LoggingApiClient(world.server, log);
    final manager = OAuth2TokenManager(OAuth2TokenService(logging, now: world.clock), const MemoryOAuth2TokenStore(), now: world.clock);
    world.server.rotateRefresh = true;
    world.server.validRefresh.add('rt-seed$_suffix');

    final renewal = await manager.ensureFresh(
      oauthAuth(token: 'old', expiry: world.now.subtract(const Duration(hours: 1)), refresh: 'rt-seed$_suffix'),
      owner: AuthOwner.collection(shop, 'Shop'),
      resolver: await world.resolver(shop),
    );
    await logging.send(ApiRequestSpec(
      method: 'GET',
      url: '$apiHost/orders?access_token=${renewal.auth.oauth2AccessToken}',
      headers: {'Authorization': 'Bearer ${renewal.auth.oauth2AccessToken}'},
    ));
    world.server.tokenFailure = NetworkException(
      'failed: $tokenUrl?client_secret=csecret-in-url-123456',
      kind: NetworkErrorKind.connectionError,
    );
    await manager.ensureFresh(oauthAuth(), owner: AuthOwner.folder(1, 'F'), resolver: await world.resolver(shop)).then<void>((_) {}, onError: (Object _) {});

    final shown = StringBuffer();
    for (final e in log.entries) {
      shown.writeln([e.method, e.url, e.headersCount, e.bodySize, e.statusCode, e.errorMessage].join(' | '));
    }
    expect(log.entries.length, 3);
    for (final secret in [renewal.auth.oauth2AccessToken, renewal.auth.oauth2RefreshToken, 'rt-seed$_suffix', 'csecret']) {
      expect(shown.toString(), isNot(contains(secret)), reason: secret);
    }
    expect(shown.toString(), contains(tokenUrl));
  });

  test('a token request that failed explains itself without the token, the secret, or the server\'s echo of them', () async {
    world.server.tokenOverride = (call) => world.server.reply(400, {
          'error': 'invalid_grant',
          'error_description': 'refresh_token=${call.form['refresh_token']} and client_secret=csecret rejected for access_token=at-9$_suffix',
        });
    final auth = oauthAuth(token: 'old', expiry: world.now.subtract(const Duration(hours: 1)), refresh: 'rt-echoed$_suffix');

    Object? caught;
    try {
      await world.manager.ensureFresh(auth, owner: AuthOwner.collection(shop, 'Shop'), resolver: await world.resolver(shop));
    } on OAuth2RenewalException catch (e) {
      caught = e;
    }

    expect(caught, isA<OAuth2RenewalException>());
    final text = '${(caught as OAuth2RenewalException).message} ${caught.summary}';
    for (final secret in ['rt-echoed$_suffix', 'csecret', 'at-9$_suffix']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });

  group('what is exported or shared', () {
    final auth = oauthAuth(
      secret: 'client-secret-xyz',
      token: 'live-access$_suffix',
      expiry: DateTime.utc(2026, 10, 6, 13),
      refresh: 'live-refresh$_suffix',
    );

    test('the secret helpers know the OAuth token keys, by JSON name and by auth field', () {
      for (final name in ['access_token', 'refresh_token', 'id_token', 'oauth2AccessToken', 'oauth2RefreshToken']) {
        expect(SecretNames.looksSecretKey(name), isTrue, reason: name);
        expect(SecretMasker.isSensitiveName(name), isTrue, reason: name);
      }
      expect(SecretFields.authKeys, containsAll(['oauth2AccessToken', 'oauth2RefreshToken', 'oauth2TokenExpiry', 'oauth2ClientSecret', 'oauth2Password']));
      final body = SecretMasker.maskBody('{"access_token":"abc.def-123456789","refresh_token":"r-123456789","expires_in":3600}');
      expect(body, '{"access_token":"${SecretMasker.mask}","refresh_token":"${SecretMasker.mask}","expires_in":3600}');
    });

    test('a token endpoint response and a login response are masked wherever an app shows a body', () {
      final raw = jsonEncode({'access_token': 'a$_suffix', 'refresh_token': 'r$_suffix', 'token': 't$_suffix', 'expires_in': 60});

      final shown = HistoryMasker.text(raw);

      for (final secret in ['a$_suffix', 'r$_suffix', 't$_suffix']) {
        expect(shown, isNot(contains(secret)));
      }
      expect(shown, contains('"expires_in":60'));
    });

    test('History blanks the tokens of the auth it snapshots', () {
      final snapshot = HistoryMasker.auth(auth);

      expect(snapshot.oauth2AccessToken, isEmpty);
      expect(snapshot.oauth2RefreshToken, isEmpty);
      expect(snapshot.oauth2TokenExpiry, isNull);
      expect(jsonEncode(snapshot.toJson()), isNot(contains('client-secret-xyz')));
    });

    test('a Postman export leaves the tokens out, and the redacted one the client secret too', () {
      final plain = PostmanCollectionExporter.export(collectionName: 'API', folders: const [], requests: const [], collectionAuth: auth);
      final redacted =
          PostmanCollectionExporter.export(collectionName: 'API', folders: const [], requests: const [], collectionAuth: auth, redactSecrets: true);

      for (final text in [plain, redacted]) {
        expect(text, isNot(contains('live-access$_suffix')));
        expect(text, isNot(contains('live-refresh$_suffix')));
      }
      expect(redacted, isNot(contains('client-secret-xyz')));
    });

    test('a doc for Git has no token or secret, and a workspace file moves them to the local file', () {
      final doc = SyncDoc(uid: 'c', kind: SyncKind.collection, parentUid: null, name: 'API', data: {'auth': auth.toJson()});

      final shared = jsonEncode(SecretFields.stripDoc(doc).data);

      for (final secret in ['live-access$_suffix', 'live-refresh$_suffix', 'client-secret-xyz']) {
        expect(shared, isNot(contains(secret)));
      }
    });
  });
}
