// Self-renewing OAuth 2.0: when a token is renewed, which grant is used, that parallel callers share one
// renewal, and what is said (and what is never said) when it fails. The token endpoint is an in-memory fake.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/auth_owner.dart';
import 'package:postpilot/features/auth_renewal/domain/repositories/oauth2_token_store.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import 'package:postpilot/features/auth_renewal/domain/services/token_status.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'auth_harness.dart';

final class _RecordingStore implements OAuth2TokenStore {
  final List<({AuthOwner owner, RequestAuth source, OAuth2Token token})> saved = [];
  Object? failWith;

  @override
  Future<void> save(AuthOwner owner, RequestAuth source, OAuth2Token token) async {
    if (failWith case final failure?) throw failure;
    saved.add((owner: owner, source: source, token: token));
  }
}

void main() {
  late FakeAuthServer server;
  late _RecordingStore store;
  late DateTime now;
  late OAuth2TokenManager manager;
  final owner = AuthOwner.collection(1, 'API');
  final resolver = VariableResolver(const {});

  DateTime clock() => now;

  setUp(() {
    server = FakeAuthServer();
    store = _RecordingStore();
    now = DateTime.utc(2026, 10, 6, 12);
    manager = OAuth2TokenManager(OAuth2TokenService(server, now: clock), store, now: clock);
  });

  Future<TokenRenewal> ensure(RequestAuth auth, {AuthOwner? as, bool force = false, VariableResolver? vars}) =>
      manager.ensureFresh(auth, owner: as ?? owner, resolver: vars ?? resolver, force: force);

  group('when a token is due', () {
    test('a token valid for more than the 30 s margin is left alone: nothing is requested', () async {
      final auth = oauthAuth(token: 'old', expiry: now.add(const Duration(seconds: 31)));

      final result = await ensure(auth);

      expect(result.kind, TokenRenewalKind.none);
      expect(result.auth, same(auth));
      expect(result.note, isNull);
      expect(server.tokenCalls, isEmpty);
    });

    test('a token that expires within the margin is renewed before the send, at exactly 30 s too', () async {
      final result = await ensure(oauthAuth(token: 'old', expiry: now.add(const Duration(seconds: 30))));

      expect(server.tokenCalls.map((c) => c.grant), ['client_credentials']);
      expect(result.kind, TokenRenewalKind.fetched);
      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(result.auth.oauth2TokenExpiry, now.add(const Duration(seconds: 3600)));
      expect(result.note, 'Fetched a new OAuth 2.0 token (Client Credentials) before sending.');
      expect(result.replacesAuth, isTrue);
    });

    test('an expired token and a missing token are fetched; a token with no reported expiry is never renewed', () async {
      expect((await ensure(oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 1))))).auth.oauth2AccessToken, 'at-1');
      expect((await ensure(oauthAuth(), as: AuthOwner.folder(2, 'Other'))).auth.oauth2AccessToken, 'at-2');
      server.tokenCalls.clear();

      final result = await ensure(oauthAuth(token: 'forever'));

      expect(result.kind, TokenRenewalKind.none);
      expect(result.auth.oauth2AccessToken, 'forever');
      expect(server.tokenCalls, isEmpty);
    });

    test('the password grant is used for a password configuration', () async {
      final result = await ensure(oauthAuth(grant: OAuth2GrantType.password));

      expect(server.tokenCalls.single.grant, 'password');
      expect(server.tokenCalls.single.form['username'], 'ann');
      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(result.note, 'Fetched a new OAuth 2.0 token (Password Credentials) before sending.');
    });

    test('with Auto-renew off an expired token is sent as it is, and only Renew now (force) fetches', () async {
      final auth = oauthAuth(autoRenew: false, token: 'old', expiry: now.subtract(const Duration(hours: 1)));

      final left = await ensure(auth);
      expect(left.kind, TokenRenewalKind.none);
      expect(left.auth.oauth2AccessToken, 'old');
      expect(server.tokenCalls, isEmpty);

      final forced = await ensure(auth, force: true);
      expect(forced.auth.oauth2AccessToken, 'at-1');
    });

    test('an auth that is not OAuth 2.0 is none of its business', () async {
      const bearer = RequestAuth(type: AuthType.bearer, bearerToken: 'x');

      expect((await ensure(bearer)).kind, TokenRenewalKind.none);
      expect(server.tokenCalls, isEmpty);
    });

    test('{{variables}} in the OAuth fields are resolved for the token request, and the stored auth keeps them unresolved', () async {
      final auth = oauthAuth(tokenEndpoint: '{{authBase}}/oauth/token', secret: '{{secretVar}}', clientIdValue: '{{cid}}');
      final vars = VariableResolver(const {'authBase': 'https://auth.test', 'secretVar': 'csecret', 'cid': 'cid'});

      final result = await ensure(auth, vars: vars);

      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(store.saved.single.source.oauth2AccessTokenUrl, '{{authBase}}/oauth/token');
      expect(store.saved.single.source.oauth2ClientSecret, '{{secretVar}}');
    });
  });

  group('the refresh token', () {
    test('is used when there is one, and a rotated refresh token is the one that gets saved', () async {
      server
        ..rotateRefresh = true
        ..validRefresh.add('rt-old');
      final auth = oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 5)), refresh: 'rt-old');

      final result = await ensure(auth);

      expect(server.tokenCalls.map((c) => c.grant), ['refresh_token']);
      expect(server.tokenCalls.single.form['refresh_token'], 'rt-old');
      expect(result.kind, TokenRenewalKind.refreshed);
      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(result.auth.oauth2RefreshToken, 'rt-1');
      expect(result.refreshTokenRotated, isTrue);
      expect(result.note, 'Renewed the OAuth 2.0 token with the refresh token before sending.');
      expect(store.saved.single.token.refreshToken, 'rt-1');
      expect(store.saved.single.owner, owner);
    });

    test('is kept when the server does not rotate it', () async {
      server.validRefresh.add('rt-old');

      final result = await ensure(oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 5)), refresh: 'rt-old'));

      expect(result.auth.oauth2RefreshToken, 'rt-old');
      expect(result.refreshTokenRotated, isFalse);
    });

    test('a refused refresh token falls back to the configured grant, and says so', () async {
      final result = await ensure(oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 5)), refresh: 'rt-dead'));

      expect(server.tokenCalls.map((c) => c.grant), ['refresh_token', 'client_credentials']);
      expect(result.kind, TokenRenewalKind.fetchedAfterRefreshRejected);
      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(result.note, startsWith('The refresh token was rejected, so a new OAuth 2.0 token was fetched'));
    });
  });

  group('Authorization Code cannot be automated', () {
    final pkce = OAuth2GrantType.authorizationCodePkce;

    test('no token: it says to sign in once, sends nothing to the server, and never loops', () async {
      for (var i = 0; i < 3; i++) {
        await expectLater(
          ensure(oauthAuth(grant: pkce)),
          throwsA(isA<OAuth2RenewalException>()
              .having((e) => e.needsSignIn, 'needsSignIn', isTrue)
              .having((e) => e.message, 'message', allOf(contains('Open the Auth tab and sign in once'), contains('Authorization Code')))),
        );
      }
      expect(server.tokenCalls, isEmpty);
    });

    test('an expired token without a refresh token says so; a token still valid for a few seconds is used as it is', () async {
      await expectLater(
        ensure(oauthAuth(grant: pkce, token: 'old', expiry: now.subtract(const Duration(seconds: 1)))),
        throwsA(isA<OAuth2RenewalException>().having((e) => e.message, 'message', contains('has expired'))),
      );

      final almost = oauthAuth(grant: pkce, token: 'old', expiry: now.add(const Duration(seconds: 10)));
      final result = await ensure(almost);
      expect(result.kind, TokenRenewalKind.none);
      expect(result.auth.oauth2AccessToken, 'old');
      expect(server.tokenCalls, isEmpty);
    });

    test('with a refresh token it renews by itself; a refresh token the server refuses asks for a new sign-in, without echoing it', () async {
      server.validRefresh.add('rt-good');
      final fine = await ensure(oauthAuth(grant: pkce, token: 'old', expiry: now.subtract(const Duration(minutes: 1)), refresh: 'rt-good'));
      expect(fine.kind, TokenRenewalKind.refreshed);

      server.tokenCalls.clear();
      await expectLater(
        ensure(oauthAuth(grant: pkce, token: 'old-2', expiry: now.subtract(const Duration(minutes: 1)), refresh: 'rt-revoked-value')),
        throwsA(isA<OAuth2RenewalException>().having(
          (e) => e.message,
          'message',
          allOf(contains('refresh token was rejected'), contains('sign in once'), isNot(contains('rt-revoked-value'))),
        )),
      );
      expect(server.tokenCalls.map((c) => c.grant), ['refresh_token'], reason: 'one try, no fallback to a grant that needs a browser');
    });
  });

  group('one renewal at a time', () {
    test('five requests that start together wait for one token request and share its token', () async {
      final gate = Completer<void>();
      server.tokenGate = gate.future;
      final auth = oauthAuth();

      final all = [for (var i = 0; i < 5; i++) ensure(auth)];
      await pumpEventQueue();
      gate.complete();
      final results = await Future.wait(all);

      expect(server.tokenCalls, hasLength(1));
      expect(results.map((r) => r.auth.oauth2AccessToken).toSet(), {'at-1'});
      expect(results.where((r) => r.kind == TokenRenewalKind.fetched), hasLength(1));
      expect(results.where((r) => r.kind == TokenRenewalKind.reused), hasLength(4));
      expect(store.saved, hasLength(1));
    });

    test('a server that rotates refresh tokens is asked once: a late caller holding the old auth does not spend the old token again', () async {
      server
        ..rotateRefresh = true
        ..validRefresh.add('rt-old');
      final stale = oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 5)), refresh: 'rt-old');
      final gate = Completer<void>();
      server.tokenGate = gate.future;

      final together = [for (var i = 0; i < 3; i++) ensure(stale)];
      await pumpEventQueue();
      gate.complete();
      await Future.wait(together);
      final late = await ensure(stale);

      expect(server.refreshes, 1, reason: 'a second refresh with rt-old would be invalid_grant');
      expect(late.kind, TokenRenewalKind.reused);
      expect(late.auth.oauth2AccessToken, 'at-1');
      expect(late.auth.oauth2RefreshToken, 'rt-1');
    });

    test('the next renewal, an hour later, uses the rotated refresh token although the caller still holds the old auth', () async {
      server
        ..rotateRefresh = true
        ..validRefresh.add('rt-old');
      final stale = oauthAuth(token: 'old', expiry: now.subtract(const Duration(minutes: 5)), refresh: 'rt-old');
      await ensure(stale);

      now = now.add(const Duration(hours: 1, minutes: 1));
      final second = await ensure(stale);

      expect(server.tokenCalls.map((c) => c.form['refresh_token']), ['rt-old', 'rt-1']);
      expect(second.auth.oauth2AccessToken, 'at-2');
      expect(second.auth.oauth2RefreshToken, 'rt-2');
    });

    test('a renewal that failed is shared by everyone waiting for it, then tried afresh by the next request', () async {
      final gate = Completer<void>();
      server
        ..tokenGate = gate.future
        ..tokenFailure = const NetworkException('refused', kind: NetworkErrorKind.connectionError);
      final auth = oauthAuth();

      final all = [for (var i = 0; i < 3; i++) ensure(auth).then<Object?>((_) => null, onError: (Object e) => e)];
      await pumpEventQueue();
      gate.complete();
      final outcomes = await Future.wait(all);

      expect(outcomes, everyElement(isA<OAuth2RenewalException>()));
      expect(server.tokenCalls, hasLength(1));

      server
        ..tokenFailure = null
        ..tokenGate = null;
      expect((await ensure(auth)).auth.oauth2AccessToken, 'at-1');
      expect(server.tokenCalls, hasLength(2));
    });

    test('different owners do not share a renewal: each has its own token', () async {
      final a = await ensure(oauthAuth(), as: AuthOwner.collection(1, 'A'));
      final b = await ensure(oauthAuth(), as: AuthOwner.folder(7, 'Admin'));

      expect(server.tokenCalls, hasLength(2));
      expect({a.auth.oauth2AccessToken, b.auth.oauth2AccessToken}, {'at-1', 'at-2'});
    });

    test('forget() drops what was renewed in memory, so a cleared token is not quietly brought back', () async {
      await ensure(oauthAuth());
      final brought = await ensure(oauthAuth());
      expect(brought.kind, TokenRenewalKind.reused);
      expect(server.tokenCalls, hasLength(1));

      manager.forget(owner);
      final fresh = await ensure(oauthAuth());

      expect(fresh.kind, TokenRenewalKind.fetched);
      expect(server.tokenCalls, hasLength(2));
    });

    test('forgetAll() does the same for every owner', () async {
      await ensure(oauthAuth());
      await ensure(oauthAuth(), as: AuthOwner.folder(7, 'Admin'));
      expect(server.tokenCalls, hasLength(2));

      manager.forgetAll();

      expect((await ensure(oauthAuth())).kind, TokenRenewalKind.fetched);
      expect((await ensure(oauthAuth(), as: AuthOwner.folder(7, 'Admin'))).kind, TokenRenewalKind.fetched);
      expect(server.tokenCalls, hasLength(4));
    });

    test('a token pasted by hand after a renewal is newer than the memory and is used as it is', () async {
      await ensure(oauthAuth());

      final result = await ensure(oauthAuth(token: 'typed-by-hand', expiry: now.add(const Duration(hours: 2))));

      expect(result.kind, TokenRenewalKind.none);
      expect(result.auth.oauth2AccessToken, 'typed-by-hand');
      expect(server.tokenCalls, hasLength(1));
    });
  });

  group('failures say what is wrong, and never repeat a secret', () {
    Future<OAuth2RenewalException> failure(RequestAuth auth) async {
      try {
        await ensure(auth);
      } on OAuth2RenewalException catch (e) {
        return e;
      }
      fail('expected the renewal to fail');
    }

    test('wrong client credentials: invalid_client, with what to check', () async {
      final e = await failure(oauthAuth(secret: 'wrong-secret-9'));

      expect(e.message, allOf(contains('rejected the client credentials'), contains('Client authentication failed'), contains('Client ID and Client Secret')));
      expect(e.message, isNot(contains('wrong-secret-9')));
      expect(e.summary, 'the client credentials were rejected');
    });

    test('a {{variable}} nothing defines is named, instead of being sent to the server as a wrong secret', () async {
      final e = await failure(oauthAuth(secret: '{{clientSecret}}'));

      expect(e.message, allOf(contains('Client Secret'), contains('{{clientSecret}}'), contains('POSTPILOT_VAR_clientSecret')));
      expect(e.summary, '{{clientSecret}} is not defined');
      expect(server.tokenCalls, isEmpty);

      final url = await failure(oauthAuth(tokenEndpoint: '{{authBase}}/token'));
      expect(url.message, allOf(contains('Access Token URL'), contains('{{authBase}}')));
    });

    test('a refused password is invalid_grant for the user name and password', () async {
      final e = await failure(oauthAuth(grant: OAuth2GrantType.password).copyWith(oauth2Password: 'not-the-password'));

      expect(e.message, allOf(contains('rejected the grant'), contains('Invalid user credentials'), contains('user name and password')));
      expect(e.message, isNot(contains('not-the-password')));
    });

    test('a server that echoes the secret in its error text gets it masked', () async {
      server.tokenOverride = (call) => server.reply(400, {
            'error': 'invalid_request',
            'error_description': 'bad request for client_secret=sup3r-secret-value and password hunter2xyz',
          });

      final e = await failure(
        oauthAuth(secret: 'sup3r-secret-value', grant: OAuth2GrantType.password).copyWith(oauth2Password: 'hunter2xyz'),
      );

      expect(e.message, isNot(contains('sup3r-secret-value')));
      expect(e.message, isNot(contains('hunter2xyz')));
      expect(e.message, contains('••••••'));
    });

    test('a network failure names the host, not the whole URL, and the server text is masked', () async {
      server.tokenFailure = const NetworkException('connect failed', kind: NetworkErrorKind.connectionError, summary: "Couldn't reach auth.test.");

      final e = await failure(oauthAuth(tokenEndpoint: 'https://auth.test/oauth/token?api_key=abc123secret456'));

      expect(e.message, contains('Could not reach the token endpoint at auth.test'));
      expect(e.message, isNot(contains('abc123secret456')));
      expect(e.summary, 'the token endpoint could not be reached');
    });

    test('a URL that is not a token endpoint (an HTML 404) is said to be one', () async {
      server.tokenOverride = (call) => server.reply(404, '<html>Not found</html>');

      final e = await failure(oauthAuth());

      expect(e.message, allOf(contains('did not answer like a token endpoint'), contains('Access Token URL')));
    });

    test('an auth with no token URL says so instead of sending anything', () async {
      final e = await failure(oauthAuth(tokenEndpoint: ''));

      expect(e.message, contains('no Access Token URL'));
      expect(server.tokenCalls, isEmpty);
    });

    test('a token that is still valid is used when the renewal fails, with a note; an expired one is not', () async {
      server.tokenFailure = const NetworkException('refused', kind: NetworkErrorKind.connectionError);

      final kept = await ensure(oauthAuth(token: 'still-good', expiry: now.add(const Duration(seconds: 20))));
      expect(kept.kind, TokenRenewalKind.keptCurrent);
      expect(kept.auth.oauth2AccessToken, 'still-good');
      expect(kept.note, allOf(contains('Could not renew the OAuth 2.0 token'), contains('expires in 20s')));
      expect(kept.replacesAuth, isFalse);

      await expectLater(ensure(oauthAuth(token: 'dead', expiry: now.subtract(const Duration(seconds: 1)))), throwsA(isA<OAuth2RenewalException>()));
    });
  });

  group('writing the token back', () {
    test('goes to the store with the owner and the auth it was fetched for; a store that fails does not fail the send', () async {
      store.failWith = StateError('disk full');

      final result = await ensure(oauthAuth());

      expect(result.auth.oauth2AccessToken, 'at-1');
      expect(store.saved, isEmpty);
      store.failWith = null;

      await ensure(oauthAuth(), as: AuthOwner.folder(3, 'Admin'));
      expect(store.saved.single.owner.kind, AuthOwnerKind.folder);
      expect(store.saved.single.owner.id, 3);
    });

    test('obtainNow (the Renew now button) takes a token without caching or writing anything back', () async {
      server
        ..rotateRefresh = true
        ..validRefresh.add('rt-old');

      final token = await manager.obtainNow(oauthAuth(token: 'old', refresh: 'rt-old'), resolver);

      expect(token.accessToken, 'at-1');
      expect(token.refreshToken, 'rt-1');
      expect(store.saved, isEmpty);
    });
  });

  group('the status the Auth tab shows', () {
    final auth = oauthAuth();
    test('says whether there is a token, when it ends and whether it renews itself', () {
      String headline(RequestAuth a) => TokenStatus.of(a, now).headline;

      expect(headline(auth), 'No token yet');
      expect(headline(auth.withOAuth2Token('t', null)), 'Token present (no expiry reported)');
      expect(headline(auth.withOAuth2Token('t', now.add(const Duration(minutes: 12, seconds: 40)))), 'Token valid for 12m');
      expect(headline(auth.withOAuth2Token('t', now.add(const Duration(hours: 1, minutes: 5)))), 'Token valid for 1h 5m');
      expect(headline(auth.withOAuth2Token('t', now.add(const Duration(seconds: 20)))), 'Token expires in 20s');
      expect(headline(auth.withOAuth2Token('t', now.subtract(const Duration(seconds: 1)))), 'Token expired');
    });

    test('flags Authorization Code without a refresh token as needing a person, and Auto-renew off', () {
      final pkce = auth.copyWith(oauth2GrantType: OAuth2GrantType.authorizationCodePkce);

      expect(TokenStatus.of(auth, now).selfRenewing, isTrue);
      expect(TokenStatus.of(pkce, now).selfRenewing, isFalse);
      expect(TokenStatus.of(pkce.withOAuth2Token('t', now, refreshToken: 'r'), now).selfRenewing, isTrue);
      expect(TokenStatus.of(pkce, now).renewalLine, contains('needs a browser'));
      expect(TokenStatus.of(auth.copyWith(oauth2AutoRenew: false), now).renewalLine, contains('Auto-renew is off'));
      expect(TokenStatus.of(auth, now).renewalLine, contains('Auto-renew is on'));
    });

    test('Readiness: what a process nobody signs in for can and cannot run', () {
      String? why(RequestAuth a) => OAuth2Readiness.whyNotUnattended(a, now);
      final pkce = auth.copyWith(oauth2GrantType: OAuth2GrantType.authorizationCodePkce);

      expect(why(auth), isNull);
      expect(why(auth.copyWith(oauth2AccessTokenUrl: '')), contains('no Access Token URL'));
      expect(why(pkce), contains('browser'));
      expect(why(pkce.withOAuth2Token('t', now.add(const Duration(hours: 1)))), isNull);
      expect(why(pkce.withOAuth2Token('t', now.subtract(const Duration(hours: 1)), refreshToken: 'r')), isNull);
      expect(why(auth.copyWith(oauth2AutoRenew: false)), contains('Auto-renew is off'));
      expect(
        why(auth.copyWith(oauth2AutoRenew: false).withOAuth2Token('t', now.subtract(const Duration(hours: 1)))),
        isNull,
        reason: 'with Auto-renew off an expired token is sent as it is, and fails loudly with its 401',
      );
    });
  });
}
