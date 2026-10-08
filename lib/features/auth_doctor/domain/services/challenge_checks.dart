// Pure Dart (no Flutter, no database).
import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/services/digest_auth_challenge.dart';
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'server_words.dart';
import 'token_checks.dart';

/// What the server's own challenge (`WWW-Authenticate`, `Proxy-Authenticate`) and the words of its error body say: a Bearer
/// error code, a scheme the request did not use, a Digest challenge, an API key sent to the wrong place.
abstract final class ChallengeChecks {
  /// [soFar] are the findings the other checks made: the server's error code is only worth a card of its own when they did
  /// not already explain it.
  static List<AuthFinding> run(AuthContext ctx, List<AuthFinding> soFar) {
    final out = <AuthFinding>[];
    final bearer = _bearerError(ctx, soFar);
    if (bearer != null) out.add(bearer);
    final scheme = _scheme(ctx);
    if (scheme != null) out.add(scheme);
    final digest = _digest(ctx);
    if (digest != null) out.add(digest);
    final proxy = _proxy(ctx);
    if (proxy != null) out.add(proxy);
    out.addAll(_apiKeyPlace(ctx));
    return out;
  }

  static String _challengeLine(AuthContext ctx) {
    final header = ctx.responseHeader(ctx.status == 407 ? 'proxy-authenticate' : 'www-authenticate') ?? '';
    return '${ctx.status == 407 ? 'Proxy-Authenticate' : 'WWW-Authenticate'}: ${ctx.quote(header, max: 200)}';
  }

  // --- RFC 6750 error codes -------------------------------------------------------------------------------------

  static AuthFinding? _bearerError(AuthContext ctx, List<AuthFinding> soFar) {
    final challenge = ctx.challenge('bearer');
    final error = challenge?.error;
    if (challenge == null || error == null) return null;
    final description = challenge.errorDescription ?? '';
    final lower = description.toLowerCase();
    final explained = soFar.any((f) => f.confidence == FindingConfidence.certain);
    final evidence = [_challengeLine(ctx), if (challenge.realm != null) 'Realm: ${challenge.realm}'];

    switch (error) {
      case 'invalid_token':
        if (explained) return null;
        final (why, fix) = lower.contains('expire')
            ? (
                'The server says the token has expired.',
                'Get a new token (run the login request, or renew the OAuth 2.0 token in the Auth tab) and send again.',
              )
            : lower.contains('signature')
                ? (
                    'The server could not verify the token\'s signature: it was signed with another key or by another issuer, '
                        'often the identity provider of a different environment, or it was altered.',
                    'Check that the active environment is the one the token was issued for, then get a new token.',
                  )
                : lower.contains('revoked')
                    ? ('The server says the token was revoked.', 'Log in again to get a new token.')
                    : lower.contains('audience') || lower.contains('aud')
                        ? (
                            'The server says the token was issued for another audience.',
                            'Ask for a token with the audience of this API (the Audience field of the OAuth 2.0 settings).',
                          )
                        : lower.contains('malformed') || lower.contains('format') || lower.contains('parse')
                            ? (
                                'The server could not read the token: it is cut off, has extra characters or quotes, or is not a token at all.',
                                'Paste the token again, whole and without quotes or spaces.',
                              )
                            : (
                                'The server refused the token without saying why. It may be expired, revoked, signed by another issuer, '
                                    'or meant for another environment.',
                                'Get a new token and check that the active environment is the one it was issued for.',
                              );
        return AuthFinding(
          id: 'challenge.invalid-token',
          confidence: FindingConfidence.certain,
          title: 'The server says the token is invalid',
          explanation: why,
          fix: fix,
          evidence: [...evidence, if (description.isNotEmpty) 'error_description: "${ctx.quote(description)}"'],
        );
      case 'insufficient_scope':
        if (soFar.any((f) => f.id == 'token.missing-scope')) return null;
        final wanted = challenge.scopes;
        final readable = TokenChecks.jwtsOf(ctx);
        if (readable.isNotEmpty) {
          // The token was read and does list what is asked for, so the server must be looking somewhere else.
          final (granted, _) = TokenChecks.grantedBy(readable.first.$2);
          return AuthFinding(
            id: 'challenge.insufficient-scope',
            confidence: FindingConfidence.certain,
            title: 'The server says the scope is insufficient',
            explanation: 'The server asks for ${wanted.isEmpty ? 'a scope' : AuthText.list(wanted.map((s) => '"$s"'))} and says the token is not enough, '
                'although the token lists ${granted.isEmpty ? 'no scope' : AuthText.list(granted.take(8).map((g) => '"$g"'))}. '
                'The server may read another claim (roles, groups, permissions) or call the scope by another name.',
            fix: 'Compare the names the API documents with the scope and role claims of the token, and request the scope under the name the API uses.',
            evidence: evidence,
          );
        }
        return AuthFinding(
          id: 'challenge.insufficient-scope',
          confidence: FindingConfidence.certain,
          title: 'The token does not have the scope this endpoint needs',
          explanation: wanted.isEmpty
              ? 'The server accepted the token but says it lacks a scope this endpoint needs.'
              : 'The server accepted the token but says it needs ${AuthText.list(wanted.map((s) => '"$s"'))}. The token cannot be read here '
                  '(it is not a JWT), so which scopes it has is unknown.',
          fix: 'Request a token with ${wanted.isEmpty ? 'the scope the endpoint documents' : 'that scope'} (the Scope field of the OAuth 2.0 settings) and send again.',
          evidence: evidence,
        );
      case 'invalid_request':
        final twice = ctx.authorization != null && ctx.credentials.any((c) => c.place == CredentialPlace.query && c.name.toLowerCase().contains('token'));
        return AuthFinding(
          id: 'challenge.invalid-request',
          confidence: FindingConfidence.certain,
          title: 'The server could not understand how the token was sent',
          explanation: twice
              ? 'The token travels twice, in the Authorization header and in the query string. RFC 6750 allows one place only, '
                  'and the server answers invalid_request.'
              : 'The server says the request is malformed as far as authentication goes: a missing or repeated token parameter, '
                  'an unsupported way of sending it, or a duplicated header.',
          fix: twice
              ? 'Remove the token from the query string and keep the Authorization header.'
              : 'Send the token once, in the Authorization header as "Bearer <token>".',
          evidence: [...evidence, if (description.isNotEmpty) 'error_description: "${ctx.quote(description)}"'],
        );
    }
    return null;
  }

  // --- a scheme the server did not ask for -----------------------------------------------------------------------

  static AuthFinding? _scheme(AuthContext ctx) {
    if (ctx.status != 401 && ctx.status != 407) return null;
    if (ctx.challenges.isEmpty || !ctx.input.requestKnown) return null;
    final asked = {for (final c in ctx.challenges) c.scheme.toLowerCase()};
    final wants = AuthText.list(ctx.challenges.map((c) => c.scheme).toSet());
    final sentScheme = ctx.input.authType == AuthType.digest ? 'digest' : (ctx.authorization?.scheme.toLowerCase() ?? '');

    if ((asked.contains('negotiate') || asked.contains('ntlm')) && !asked.contains('bearer') && !asked.contains('basic') && !asked.contains('digest')) {
      return AuthFinding(
        id: 'challenge.windows-auth',
        confidence: FindingConfidence.likely,
        title: 'The server wants Windows integrated authentication',
        explanation: 'The server asks for $wants (Kerberos or NTLM), a login handshake that PostPilot does not perform.',
        fix: 'Send the call from a tool that supports it (curl --negotiate or --ntlm), or ask for a Basic, Bearer or API-key access for scripts.',
        evidence: [_challengeLine(ctx)],
      );
    }
    if (sentScheme.isNotEmpty && !asked.contains(sentScheme)) {
      const known = {'bearer', 'basic', 'digest'};
      if (!known.contains(sentScheme) || !asked.any(known.contains)) return null;
      final label = sentScheme[0].toUpperCase() + sentScheme.substring(1);
      return AuthFinding(
        id: 'challenge.scheme-mismatch',
        confidence: FindingConfidence.certain,
        title: 'The server wants $wants, the request used $label',
        explanation: 'The server\'s challenge lists $wants, and the request authenticated with $label, which it did not offer.',
        fix: 'Open the Auth tab and choose ${asked.contains('basic') ? 'Basic Auth' : asked.contains('digest') ? 'Digest Auth' : 'Bearer Token'} '
            'and fill in what that type needs.',
        evidence: [_challengeLine(ctx), 'The request sent: $label'],
      );
    }
    if (sentScheme.isEmpty && ctx.authorization == null && ctx.tokens.isNotEmpty && asked.any(const {'bearer', 'basic', 'digest'}.contains)) {
      final names = AuthText.list(ctx.tokens.map((c) => '"${c.name}"'));
      return AuthFinding(
        id: 'challenge.scheme-mismatch',
        confidence: FindingConfidence.likely,
        title: 'The server wants $wants in the Authorization header',
        explanation: 'The request sent its credential as $names, but the server\'s challenge asks for $wants in the Authorization header.',
        fix: 'Open the Auth tab and choose ${asked.contains('basic') ? 'Basic Auth' : asked.contains('digest') ? 'Digest Auth' : 'Bearer Token'} instead of a custom header.',
        evidence: [_challengeLine(ctx)],
      );
    }
    return null;
  }

  // --- Digest --------------------------------------------------------------------------------------------------

  static AuthFinding? _digest(AuthContext ctx) {
    final challenge = ctx.challenge('digest');
    if (challenge == null || ctx.status != 401) return null;
    final header = ctx.responseHeader('www-authenticate');
    final answerable = DigestAuthChallenge.parse(header);
    final evidence = [
      _challengeLine(ctx),
      if (challenge.params['algorithm'] != null) 'algorithm: ${challenge.params['algorithm']}',
      if (challenge.params['qop'] != null) 'qop: ${challenge.params['qop']}',
    ];
    if (answerable == null) {
      return AuthFinding(
        id: 'challenge.digest-unsupported',
        confidence: FindingConfidence.likely,
        title: 'PostPilot cannot answer this Digest challenge',
        explanation: 'The Digest challenge has no nonce, or asks for an algorithm or quality of protection that is not supported '
            '(MD5, SHA-256 and SHA-512-256 with auth or auth-int are).',
        fix: 'Ask the server to offer MD5 or SHA-256 with qop "auth", or use Basic over https if the server allows it.',
        evidence: evidence,
      );
    }
    if ((challenge.params['stale'] ?? '').toLowerCase() == 'true') {
      return AuthFinding(
        id: 'challenge.digest-stale',
        confidence: FindingConfidence.certain,
        title: 'The Digest nonce was stale',
        explanation: 'The server says stale=true: the user name and password were right, but the nonce it had issued had expired.',
        fix: 'Send the request again; the client answers the new challenge.',
        evidence: evidence,
      );
    }
    if (ctx.input.authType == AuthType.digest) {
      return AuthFinding(
        id: 'challenge.digest-refused',
        confidence: FindingConfidence.likely,
        title: 'The Digest user name or password was refused',
        explanation: 'The client answered the Digest challenge${answerable.realm.isEmpty ? '' : ' for the realm "${answerable.realm}"'} '
            'and the server still answered 401, which means the user name or password is wrong for that realm.',
        fix: 'Check the user name and password in the Auth tab (and the variables they use).',
        evidence: evidence,
      );
    }
    return null;
  }

  // --- 407 -----------------------------------------------------------------------------------------------------

  static AuthFinding? _proxy(AuthContext ctx) {
    if (ctx.status != 407 || ctx.authorization == null) return null;
    final realm = ctx.challenges.isEmpty ? null : ctx.challenges.first.realm;
    return AuthFinding(
      id: 'challenge.proxy-refused',
      confidence: FindingConfidence.likely,
      title: 'The proxy refused the credentials',
      explanation: 'A Proxy-Authorization header was sent and the proxy still answered 407${realm == null ? '' : ' for the realm "$realm"'}: '
          'the user name or password is wrong, or the proxy wants another scheme.',
      fix: 'Check the proxy user name and password in Settings, and the scheme the proxy asks for.',
      evidence: [_challengeLine(ctx)],
    );
  }

  // --- an API key in the wrong place -----------------------------------------------------------------------------

  static final _keyWords = RegExp(r'api[\s_-]?key|apikey|api[\s_-]?token|access[\s_-]?token|auth[\s_-]?token|\bkey\b');
  static final _queryWords = RegExp(r'query[\s_-]*(?:string|param)|url param|\bquery\b|\?[a-z_]+=');
  static final _headerName = RegExp(r'\b(x-[a-z0-9-]*(?:key|token|auth)[a-z0-9-]*)\b', caseSensitive: false);

  static List<AuthFinding> _apiKeyPlace(AuthContext ctx) {
    if (ctx.status != 401 && ctx.status != 403) return const [];
    if (!ctx.input.requestKnown || ctx.isHtml || ctx.bodyLower.isEmpty) return const [];
    final out = <AuthFinding>[];
    final inHeader = [for (final c in ctx.tokens) if (c.place == CredentialPlace.header) c];
    final inQuery = [for (final c in ctx.tokens) if (c.place == CredentialPlace.query) c];
    final mentionsKey = _keyWords.hasMatch(ctx.bodyLower);
    final mentionsQuery = _queryWords.hasMatch(ctx.bodyLower);
    final mentionsHeader = ctx.bodyLower.contains('header');
    final said = ServerWords.evidence(ctx);

    if (mentionsKey && mentionsQuery && !mentionsHeader && inHeader.isNotEmpty && inQuery.isEmpty) {
      out.add(AuthFinding(
        id: 'apikey.wrong-place-query',
        confidence: FindingConfidence.likely,
        title: 'The server looks for the key in the query string',
        explanation: 'The key was sent in a header (${AuthText.list(inHeader.map((c) => '"${c.name}"'))}), but the server\'s message talks about '
            'a query parameter.',
        fix: 'In the Auth tab choose API Key and set "Add to" to Query Params, with the parameter name the API documents.',
        evidence: [...said, 'The key travelled in the header ${inHeader.first.name}.'],
      ));
    } else if (mentionsKey && mentionsHeader && !mentionsQuery && inQuery.isNotEmpty && inHeader.isEmpty) {
      out.add(AuthFinding(
        id: 'apikey.wrong-place-header',
        confidence: FindingConfidence.likely,
        title: 'The server looks for the key in a header',
        explanation: 'The key was sent in the query string (${AuthText.list(inQuery.map((c) => '"${c.name}"'))}), but the server\'s message talks '
            'about a header.',
        fix: 'In the Auth tab choose API Key and set "Add to" to Header, with the header name the API documents.',
        evidence: [...said, 'The key travelled in the query parameter ${inQuery.first.name}.'],
      ));
    }

    final named = _headerName.firstMatch(ctx.body)?[1];
    if (named != null && inHeader.isNotEmpty && !inHeader.any((c) => c.name.toLowerCase() == named.toLowerCase())) {
      out.add(AuthFinding(
        id: 'apikey.header-name',
        confidence: FindingConfidence.likely,
        title: 'The server names the header $named',
        explanation: 'The error text mentions the header "$named", and the request sent its credential as ${AuthText.list(inHeader.map((c) => '"${c.name}"'))}.',
        fix: 'Use "$named" as the header name of the API key.',
        evidence: [...said, 'Header named by the server: $named', 'Credential headers sent: ${inHeader.map((c) => c.name).join(', ')}'],
      ));
    }
    return out;
  }
}
