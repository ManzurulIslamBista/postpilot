// Pure Dart (no Flutter): the app, the command line and the MCP server renew tokens with this same class.
import 'dart:async';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/services/oauth2_token_service.dart';
import '../entities/auth_owner.dart';
import '../repositories/oauth2_token_store.dart';
import 'token_status.dart';

/// Why a token could not be obtained. [message] says what happened and what to do, with server text
/// masked; it is safe to show as it is. A request that needed the token is never sent after this.
final class OAuth2RenewalException implements Exception {
  final String message;

  /// The cause in a few words (`the client credentials were rejected`), for a line that already says what
  /// was being done.
  final String summary;

  /// The only way out is a person signing in (Authorization Code without a usable refresh token).
  final bool needsSignIn;

  const OAuth2RenewalException(this.message, {required this.summary, this.needsSignIn = false});

  @override
  String toString() => message;
}

enum TokenRenewalKind {
  /// Nothing to do: the token is valid, there is none to renew, or Auto-renew is off.
  none,

  /// A new token from the refresh token.
  refreshed,

  /// A new token from the configured grant (client credentials or password).
  fetched,

  /// The refresh token was rejected, so the configured grant got a new token.
  fetchedAfterRefreshRejected,

  /// Another caller had just renewed it: this one used (or waited for) that token.
  reused,

  /// The renewal failed, but the token in hand is still valid, so it is used as it is.
  keptCurrent,
}

/// What [OAuth2TokenManager.ensureFresh] decided for one send.
final class TokenRenewal {
  /// The auth to send with: the one given, or the same with the renewed token in it.
  final RequestAuth auth;
  final TokenRenewalKind kind;

  /// One line for the response and the run result (`Refreshed the OAuth 2.0 token before sending.`);
  /// null when nothing happened. Never holds a token.
  final String? note;

  /// The server issued a new refresh token in place of the old one. A run that cannot save it (the
  /// command line) says so, because the old one is dead from now on.
  final bool refreshTokenRotated;

  const TokenRenewal(this.auth, this.kind, {this.note, this.refreshTokenRotated = false});

  factory TokenRenewal.none(RequestAuth auth) => TokenRenewal(auth, TokenRenewalKind.none);

  /// The token in [auth] is not the one that was passed in.
  bool get replacesAuth => switch (kind) {
        TokenRenewalKind.refreshed ||
        TokenRenewalKind.fetched ||
        TokenRenewalKind.fetchedAfterRefreshRejected ||
        TokenRenewalKind.reused =>
          true,
        TokenRenewalKind.none || TokenRenewalKind.keptCurrent => false,
      };
}

class _Obtained {
  final OAuth2Token token;
  final TokenRenewalKind kind;
  final bool rotated;
  const _Obtained(this.token, this.kind, this.rotated);
}

class _Recent {
  final OAuth2Token token;

  /// Every access and refresh token this one replaced. A caller whose auth still holds one of them read it
  /// before the renewal was written back, so it is stale; a token that is not on this list was set by hand
  /// since, and is newer.
  final Set<String> superseded;

  const _Recent(this.token, this.superseded);
}

/// Keeps the OAuth 2.0 token of an auth valid, so a developer never has to click "Get token" again.
///
/// [ensureFresh] is called right before a request is sent. When the token is missing or expires within
/// [margin] it obtains a new one: the refresh grant when there is a refresh token, else the configured
/// grant (client credentials, password). Authorization Code without a refresh token cannot be
/// automated; that is said, once, and never retried. The new token (and a rotated refresh token) is
/// written back through the [OAuth2TokenStore].
///
/// One renewal runs per token configuration: requests that start together (a run, parallel sends) wait
/// for the first one instead of each spending a refresh token, which a server that rotates them would
/// refuse the second time. Whatever the last renewal delivered stays in memory, so a caller that read the
/// stored auth just before it was written back does not start another, and a run that cannot write
/// tokens anywhere (the command line in CI) keeps using the one it got.
final class OAuth2TokenManager {
  final OAuth2TokenService _service;
  final OAuth2TokenStore _store;
  final DateTime Function() _now;
  final Duration margin;

  final Map<String, Future<_Obtained>> _flights = {};
  final Map<String, _Recent> _recent = {};

  OAuth2TokenManager(this._service, this._store, {DateTime Function()? now, this.margin = defaultRenewalMargin})
      : _now = now ?? DateTime.now;

  /// [auth] as stored (its `{{variables}}` unresolved); [resolver] fills them in for the token request.
  /// With [force] a new token is obtained even when the current one is valid ("Renew now").
  Future<TokenRenewal> ensureFresh(
    RequestAuth auth, {
    required AuthOwner owner,
    required VariableResolver resolver,
    bool force = false,
  }) async {
    if (auth.type != AuthType.oauth2 || (!force && !auth.oauth2AutoRenew)) return TokenRenewal.none(auth);

    final resolved = OAuth2TokenService.resolveFields(auth, resolver);
    final key = _keyOf(owner, resolved);
    final current = _overlay(key, auth);
    final overlaid = !identical(current, auth);
    final now = _now();

    if (!force && !OAuth2Readiness.needsRenewal(current, now, margin: margin)) {
      return overlaid ? _reused(current) : TokenRenewal.none(current);
    }
    final expired = !current.hasOAuth2Token || current.isOAuth2TokenExpiredAt(now);
    if (!force && !OAuth2Readiness.canRenewAlone(current)) {
      // Nothing can renew it without a person. A token that still has a few seconds is as good as it will get.
      if (!expired) return TokenRenewal.none(current);
      throw _signInOnce(current);
    }

    final _Obtained obtained;
    var joined = false;
    try {
      final running = _flights[key];
      joined = running != null;
      obtained = await _joinOrStart(key, () => _obtain(key, owner, current, resolveWith: resolver));
    } on OAuth2RenewalException catch (e) {
      if (!force && !expired) {
        final left = TokenStatus.describeDuration(current.oauth2TokenExpiry!.difference(now));
        return TokenRenewal(
          current,
          TokenRenewalKind.keptCurrent,
          note: 'Could not renew the OAuth 2.0 token (${e.summary}); '
              'sent with the current one, which expires in $left.',
        );
      }
      rethrow;
    }

    final renewed = current.withOAuth2Token(
      obtained.token.accessToken,
      obtained.token.expiresAt,
      refreshToken: obtained.token.refreshToken ?? '',
    );
    final kind = joined ? TokenRenewalKind.reused : obtained.kind;
    return TokenRenewal(
      renewed,
      kind,
      note: _noteFor(kind, current.oauth2GrantType),
      refreshTokenRotated: obtained.rotated,
    );
  }

  /// A token from [auth]'s settings, nothing else: no cache, no write-back. The Auth tab's "Renew now"
  /// and "Get new access token" use it and hand the token to the editor, which saves it the way it saves
  /// any edit. Throws [OAuth2RenewalException] with a message ready to show.
  Future<OAuth2Token> obtainNow(RequestAuth auth, VariableResolver resolver) async {
    final resolved = OAuth2TokenService.resolveFields(auth, resolver);
    return (await _acquire(resolved)).token;
  }

  /// Forgets what was renewed in memory for [owner]; the next send reads the stored auth as it is. Called
  /// when the token is cleared by hand, so a cleared token is not quietly brought back.
  void forget(AuthOwner owner) {
    final prefix = '${owner.key}|';
    _recent.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// [forget] for every owner: for an editor that clears a token and cannot tell which owner's it was.
  void forgetAll() => _recent.clear();

  // --------------------------------------------------------------------------------------------

  Future<_Obtained> _joinOrStart(String key, Future<_Obtained> Function() start) {
    final running = _flights[key];
    if (running != null) return running;
    final flight = () async {
      try {
        return await start();
      } finally {
        _flights.remove(key);
      }
    }();
    _flights[key] = flight;
    return flight;
  }

  Future<_Obtained> _obtain(String key, AuthOwner owner, RequestAuth source, {required VariableResolver resolveWith}) async {
    final resolved = OAuth2TokenService.resolveFields(source, resolveWith);
    final obtained = await _acquire(resolved);
    final superseded = {
      ...?_recent[key]?.superseded,
      if (source.hasOAuth2Token) source.oauth2AccessToken,
      if (source.hasOAuth2RefreshToken) source.oauth2RefreshToken,
    };
    _recent[key] = _Recent(obtained.token, superseded);
    try {
      await _store.save(owner, source, obtained.token);
    } catch (_) {
      // The token works whether or not it could be saved; the next send uses the copy kept in memory.
    }
    return obtained;
  }

  /// The grant choice: the refresh token when there is one, the configured grant otherwise (also when
  /// the refresh token was refused as expired or revoked), and for Authorization Code nothing else.
  Future<_Obtained> _acquire(RequestAuth resolved) async {
    if (_undefinedVariable(resolved) case final problem?) throw problem;
    final previousRefresh = resolved.oauth2RefreshToken;
    var rejectedRefresh = false;
    if (resolved.hasOAuth2RefreshToken) {
      try {
        final token = await _service.refreshToken(resolved);
        return _Obtained(token, TokenRenewalKind.refreshed, _rotated(previousRefresh, token));
      } on OAuth2TokenException catch (e) {
        final canFallBack = e.kind == OAuth2FailureKind.invalidGrant &&
            resolved.oauth2GrantType != OAuth2GrantType.authorizationCodePkce;
        if (!canFallBack) throw _explain(e, resolved, refreshing: true);
        rejectedRefresh = true;
      }
    }
    if (resolved.oauth2GrantType == OAuth2GrantType.authorizationCodePkce) throw _signInOnce(resolved);
    try {
      final token = await _service.fetchToken(resolved);
      return _Obtained(
        token,
        rejectedRefresh ? TokenRenewalKind.fetchedAfterRefreshRejected : TokenRenewalKind.fetched,
        false,
      );
    } on OAuth2TokenException catch (e) {
      throw _explain(e, resolved, refreshing: false);
    }
  }

  /// A `{{variable}}` in the OAuth fields that nothing defined stays in the text, and would be sent to the token endpoint
  /// as it is: the server would answer "invalid client" for a secret that is really just missing. Say so instead.
  static OAuth2RenewalException? _undefinedVariable(RequestAuth resolved) {
    final password = resolved.oauth2GrantType == OAuth2GrantType.password;
    final fields = {
      'Access Token URL': resolved.oauth2AccessTokenUrl,
      'Client ID': resolved.oauth2ClientId,
      'Client Secret': resolved.oauth2ClientSecret,
      'Scope': resolved.oauth2Scope,
      'Audience': resolved.oauth2Audience,
      if (password) 'Username': resolved.oauth2Username,
      if (password) 'Password': resolved.oauth2Password,
    };
    for (final MapEntry(key: label, value: text) in fields.entries) {
      final name = AppConstants.variablePattern.firstMatch(text)?[1];
      if (name == null) continue;
      return OAuth2RenewalException(
        'The $label on the Auth tab uses {{$name}}, but no variable of that name is defined. Define it in the active '
        'environment, the collection or the globals; on the command line pass --var $name=... or set POSTPILOT_VAR_$name.',
        summary: '{{$name}} is not defined',
      );
    }
    return null;
  }

  static bool _rotated(String previous, OAuth2Token token) =>
      previous.isNotEmpty && token.refreshToken != null && token.refreshToken != previous;

  /// [auth] with what the last renewal for [key] delivered, when [auth] still holds a token that renewal
  /// replaced (or none at all). A token that was set by hand since is newer than the cache, so the cache is dropped.
  RequestAuth _overlay(String key, RequestAuth auth) {
    final recent = _recent[key];
    if (recent == null) return auth;
    final token = recent.token;
    if (auth.oauth2AccessToken == token.accessToken) return auth;
    final stale = !auth.hasOAuth2Token ||
        recent.superseded.contains(auth.oauth2AccessToken) ||
        (auth.hasOAuth2RefreshToken && recent.superseded.contains(auth.oauth2RefreshToken));
    if (!stale) {
      _recent.remove(key);
      return auth;
    }
    return auth.withOAuth2Token(token.accessToken, token.expiresAt, refreshToken: token.refreshToken ?? '');
  }

  /// The token an earlier request renewed, handed to a caller that still held the old one. That request already
  /// said so, so this one adds no note: a process that keeps tokens in memory only would repeat it on every request.
  TokenRenewal _reused(RequestAuth auth) => TokenRenewal(auth, TokenRenewalKind.reused);

  /// One renewal serves every request that shares the token endpoint, client, grant, scope and user.
  static String _keyOf(AuthOwner owner, RequestAuth resolved) => [
        owner.key,
        resolved.oauth2AccessTokenUrl,
        resolved.oauth2GrantType.name,
        resolved.oauth2ClientId,
        resolved.oauth2Scope,
        resolved.oauth2Audience,
        resolved.oauth2Username,
      ].join('|');

  /// Whether [stored] still describes the token endpoint, client and grant [source] was fetched for.
  /// A token must not be written onto a configuration it was not issued for.
  static bool sameConfig(RequestAuth stored, RequestAuth source) =>
      stored.type == AuthType.oauth2 &&
      source.type == AuthType.oauth2 &&
      stored.oauth2GrantType == source.oauth2GrantType &&
      stored.oauth2AccessTokenUrl == source.oauth2AccessTokenUrl &&
      stored.oauth2ClientId == source.oauth2ClientId &&
      stored.oauth2Scope == source.oauth2Scope &&
      stored.oauth2Audience == source.oauth2Audience &&
      stored.oauth2Username == source.oauth2Username;

  // --- words ----------------------------------------------------------------------------------

  static String? _noteFor(TokenRenewalKind kind, OAuth2GrantType grant) => switch (kind) {
        TokenRenewalKind.refreshed => 'Renewed the OAuth 2.0 token with the refresh token before sending.',
        TokenRenewalKind.fetched => 'Fetched a new OAuth 2.0 token (${grant.label}) before sending.',
        TokenRenewalKind.fetchedAfterRefreshRejected =>
          'The refresh token was rejected, so a new OAuth 2.0 token was fetched (${grant.label}) before sending.',
        TokenRenewalKind.reused => 'Waited for the OAuth 2.0 token another request was renewing.',
        TokenRenewalKind.none || TokenRenewalKind.keptCurrent => null,
      };

  static OAuth2RenewalException _signInOnce(RequestAuth auth) => OAuth2RenewalException(
        auth.hasOAuth2Token
            ? 'The OAuth 2.0 token has expired, and Authorization Code sign-in needs a browser, so it cannot be renewed '
                'automatically. Open the Auth tab and sign in once; after that the refresh token (if the server issues '
                'one) keeps it valid.'
            : 'There is no OAuth 2.0 token yet, and Authorization Code sign-in needs a browser, so it cannot be fetched '
                'automatically. Open the Auth tab and sign in once.',
        summary: 'Authorization Code needs a sign-in',
        needsSignIn: true,
      );

  /// A failed token request, in words that say which part to check. Server text is masked: an
  /// `error_description` can echo what was sent.
  static OAuth2RenewalException _explain(OAuth2TokenException e, RequestAuth auth, {required bool refreshing}) {
    final detail = _scrub(e.message, auth);
    final (text, summary) = switch (e.kind) {
      OAuth2FailureKind.invalidClient => (
          'The token endpoint rejected the client credentials (${_bare(detail)}). Check the Client ID and Client Secret '
              'on the Auth tab, and whether the client authenticates with the Basic header or the request body.',
          'the client credentials were rejected',
        ),
      OAuth2FailureKind.invalidGrant when refreshing => (
          'The refresh token was rejected (${_bare(detail)}): it expired or was revoked. Open the Auth tab and sign '
              'in once to get a new one.',
          'the refresh token was rejected',
        ),
      OAuth2FailureKind.invalidGrant => (
          'The token endpoint rejected the grant (${_bare(detail)}). '
              '${auth.oauth2GrantType == OAuth2GrantType.password ? 'Check the user name and password on the Auth tab.' : 'Check the settings on the Auth tab.'}',
          'the grant was rejected',
        ),
      OAuth2FailureKind.network => (_end(detail), 'the token endpoint could not be reached'),
      OAuth2FailureKind.badEndpoint => (
          'The Access Token URL did not answer like a token endpoint (${_bare(detail)}). Check it on the Auth tab.',
          'the Access Token URL is not a token endpoint',
        ),
      OAuth2FailureKind.other => ('Could not get an OAuth 2.0 token: ${_end(detail)}', 'the token endpoint refused the request'),
    };
    return OAuth2RenewalException(text, summary: summary);
  }

  /// [text] from a server, with the credentials of [auth] that it may echo (a refresh token it refuses, the client
  /// secret, a password) and anything that looks like a credential masked.
  static String _scrub(String text, RequestAuth auth) {
    var clean = text;
    for (final secret in [
      auth.oauth2ClientSecret,
      auth.oauth2Password,
      auth.oauth2RefreshToken,
      auth.oauth2AccessToken,
    ]) {
      if (secret.length >= 3) clean = clean.replaceAll(secret, SecretMasker.mask);
    }
    return SecretMasker.maskBody(SecretMasker.maskMessage(clean)).trim();
  }

  /// [text] without a closing full stop, to sit inside brackets.
  static String _bare(String text) => text.endsWith('.') ? text.substring(0, text.length - 1) : text;

  /// [text] as a sentence.
  static String _end(String text) => RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}
