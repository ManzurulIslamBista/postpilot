import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/request_auth.dart';

/// How long before its expiry a token counts as due for renewal: a request that starts with 20 seconds
/// left would otherwise be rejected by the time it arrives.
const defaultRenewalMargin = Duration(seconds: 30);

enum TokenHealth { missing, valid, expiring, expired, noExpiry }

/// What the Auth tab says about the OAuth 2.0 token of an auth: whether there is one, when it expires and
/// whether the app keeps it valid by itself. Pure, so the editor, the inherited-auth line and the tests
/// read the same words.
final class TokenStatus {
  final TokenHealth health;

  /// Time until expiry; null when there is no token, or the server reported no expiry.
  final Duration? remaining;
  final bool autoRenew;

  /// Whether a renewal can run without a person: any grant with a refresh token, and client credentials
  /// or password grants even without one. Authorization Code with no refresh token needs a browser.
  final bool selfRenewing;

  const TokenStatus({
    required this.health,
    required this.remaining,
    required this.autoRenew,
    required this.selfRenewing,
  });

  factory TokenStatus.of(RequestAuth auth, DateTime now, {Duration margin = defaultRenewalMargin}) {
    final expiry = auth.oauth2TokenExpiry;
    final remaining = auth.hasOAuth2Token && expiry != null ? expiry.difference(now) : null;
    final health = !auth.hasOAuth2Token
        ? TokenHealth.missing
        : expiry == null
            ? TokenHealth.noExpiry
            : !now.isBefore(expiry)
                ? TokenHealth.expired
                : !now.add(margin).isBefore(expiry)
                    ? TokenHealth.expiring
                    : TokenHealth.valid;
    return TokenStatus(
      health: health,
      remaining: remaining,
      autoRenew: auth.oauth2AutoRenew,
      selfRenewing: OAuth2Readiness.canRenewAlone(auth),
    );
  }

  /// A token that is missing or expired cannot authenticate a request.
  bool get isUsable => health == TokenHealth.valid || health == TokenHealth.expiring || health == TokenHealth.noExpiry;

  /// `Token valid for 12m`, `Token expires in 20s`, `Token expired`, `No token yet`.
  String get headline => switch (health) {
        TokenHealth.missing => 'No token yet',
        TokenHealth.noExpiry => 'Token present (no expiry reported)',
        TokenHealth.expired => 'Token expired',
        TokenHealth.expiring => 'Token expires in ${describeDuration(remaining!)}',
        TokenHealth.valid => 'Token valid for ${describeDuration(remaining!)}',
      };

  /// One sentence about the renewal, shown under [headline].
  String get renewalLine {
    if (!autoRenew) {
      return 'Auto-renew is off: a token that is missing or expired is sent as it is.';
    }
    if (!selfRenewing) {
      return 'Auto-renew is on, but Authorization Code needs a browser: sign in once and the refresh token '
          '(if the server issues one) keeps the token valid. Without one, sign in again when it expires.';
    }
    final margin = defaultRenewalMargin.inSeconds;
    return 'Auto-renew is on: before a send the token is renewed when it is missing or expires within $margin s.';
  }

  /// `1h 5m`, `12m`, `40s`.
  static String describeDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds < 0 ? 0 : d.inSeconds}s';
  }
}

/// Whether an OAuth 2.0 auth can supply a token without a person, judged without any network call.
abstract final class OAuth2Readiness {
  /// True when a renewal can run unattended: a refresh token (any grant), or a grant that completes in
  /// one POST (client credentials, password) with a token URL to send it to.
  static bool canRenewAlone(RequestAuth auth) {
    if (auth.type != AuthType.oauth2) return false;
    if (auth.hasOAuth2RefreshToken) return true;
    return auth.oauth2GrantType != OAuth2GrantType.authorizationCodePkce;
  }

  /// Whether the token is missing or due within [margin]; a token with no reported expiry never is.
  static bool needsRenewal(RequestAuth auth, DateTime now, {Duration margin = defaultRenewalMargin}) {
    if (!auth.hasOAuth2Token) return true;
    final expiry = auth.oauth2TokenExpiry;
    return expiry != null && !now.add(margin).isBefore(expiry);
  }

  /// Why [auth] cannot be used for a request that nobody is around to sign in for (the command line, a CI
  /// job, the MCP server); null when it can. It judges before anything is sent, so a run can leave such a
  /// request out instead of failing it halfway.
  static String? whyNotUnattended(RequestAuth auth, DateTime now, {Duration margin = defaultRenewalMargin}) {
    if (!needsRenewal(auth, now, margin: margin)) return null;
    final expired = auth.hasOAuth2Token && auth.isOAuth2TokenExpiredAt(now);
    if (auth.hasOAuth2Token && !expired) return null; // within the margin, still valid: send it as it is
    // With Auto-renew off an expired token is sent as it is (the request then fails loudly with its 401); with
    // nothing to send there is nothing to run.
    if (!auth.oauth2AutoRenew) return auth.hasOAuth2Token ? null : 'there is no token and Auto-renew is off';
    if (auth.hasOAuth2RefreshToken) return null; // the refresh grant needs no browser
    if (auth.oauth2GrantType == OAuth2GrantType.authorizationCodePkce) {
      return 'Authorization Code sign-in is a browser step: open the Auth tab, sign in once, and the workspace '
          'will carry the token (with its refresh token, if the server issues one)';
    }
    if (auth.oauth2AccessTokenUrl.trim().isEmpty) {
      return 'the Auth tab has no Access Token URL to get a token from';
    }
    return null;
  }
}
