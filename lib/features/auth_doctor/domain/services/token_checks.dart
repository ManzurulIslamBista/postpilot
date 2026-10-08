// Pure Dart (no Flutter, no database).
import '../../../response_tools/domain/services/quick_decoder.dart';
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'environment_words.dart';
import 'server_words.dart';
import 'token_evidence.dart';

/// What the token itself says, read with the app's JWT decoder (see [JwtDecoder]; the signature is never verified): that
/// it has expired, is not valid yet, was issued in the future, is unsigned, was meant for another audience or issuer, is
/// an ID token where an access token is needed, or lacks the scope or role the server asks for. A token that is not a
/// JWT (an opaque string) cannot be read this way, and the doctor says so.
abstract final class TokenChecks {
  /// A clock that is a minute off is normal; more than that is worth a word.
  static const _tolerance = Duration(seconds: 60);
  static const _bearerLike = {'bearer', 'token', 'jwt', ''};

  /// The JWTs the request carried, with the credential each came in.
  static List<(SentCredential, JwtInfo)> jwtsOf(AuthContext ctx) => [
        for (final c in _candidates(ctx))
          if (JwtDecoder.tryDecode(c.secret) case final jwt?) (c, jwt),
      ];

  static List<SentCredential> _candidates(AuthContext ctx) => [
        for (final c in ctx.tokens)
          if (c.secret.isNotEmpty && (!c.isAuthorization || _bearerLike.contains(c.scheme.toLowerCase()))) c,
      ];

  static List<AuthFinding> run(AuthContext ctx) {
    if (!ctx.input.requestKnown) return const [];
    final out = <AuthFinding>[];
    for (final (credential, jwt) in jwtsOf(ctx)) {
      out.addAll(_forToken(ctx, credential, jwt));
    }
    return out;
  }

  /// The token is not a JWT, so its expiry and audience cannot be checked here. Only worth saying when nothing else was
  /// found, which is why the doctor asks for it separately.
  static AuthFinding? opaque(AuthContext ctx) {
    if (!ctx.input.requestKnown || ctx.status == 403) return null;
    for (final c in _candidates(ctx)) {
      if (!c.isAuthorization || c.secret.contains(' ')) continue;
      if (JwtDecoder.tryDecode(c.secret) != null) continue;
      return AuthFinding(
        id: 'token.opaque',
        confidence: FindingConfidence.possible,
        title: 'The token cannot be inspected',
        explanation: 'The token is not a JWT (it is an opaque string), so its expiry, audience and scopes cannot be read here. '
            'Only the server that issued it can say whether it is still valid.',
        fix: 'Get a fresh token from the login or token request and send again. If that works, the old one had expired or been revoked.',
        evidence: ['${_cap(c.label)}: ${TokenEvidence.ofHeader(c.value)}', ...ServerWords.evidence(ctx)],
      );
    }
    return null;
  }

  static List<AuthFinding> _forToken(AuthContext ctx, SentCredential c, JwtInfo jwt) {
    final out = <AuthFinding>[];
    final now = ctx.now.toUtc();
    final token = '${_cap(c.label)}: ${TokenEvidence.ofHeader(c.value)}';
    final alg = '${jwt.header['alg'] ?? '?'}';
    final said = ServerWords.evidence(ctx);
    final variable = c.variables.isEmpty ? '' : ' in {{${c.variables.first}}}';

    final exp = jwt.expiresAt;
    if (exp != null && jwt.isExpired(now)) {
      final lifetime = jwt.issuedAt == null ? null : exp.difference(jwt.issuedAt!);
      out.add(AuthFinding(
        id: 'jwt.expired',
        confidence: FindingConfidence.certain,
        title: 'The token has expired',
        explanation: 'The token ($alg) says it expired at ${AuthText.stamp(exp)}, ${AuthText.span(now.difference(exp))} before this '
            'response. A server refuses an expired token with 401 as soon as exp has passed.',
        fix: 'Get a new token: run your login request (or renew the OAuth 2.0 token in the Auth tab), save it$variable, and send again.',
        evidence: [
          token,
          'exp: ${AuthText.stamp(exp)} (${AuthText.span(now.difference(exp))} ago)',
          if (lifetime != null) 'Lifetime of the token: ${AuthText.span(lifetime)}.',
          ...said,
        ],
      ));
    }

    final nbf = jwt.notBefore;
    if (nbf != null && nbf.isAfter(now)) {
      out.add(AuthFinding(
        id: 'jwt.not-yet-valid',
        confidence: FindingConfidence.certain,
        title: 'The token is not valid yet',
        explanation: 'The token says it is valid from ${AuthText.stamp(nbf)} (nbf), which is ${AuthText.span(nbf.difference(now))} '
            'after this response. Either it was issued for later, or the clocks of this computer and the server disagree.',
        fix: 'Wait until it is valid, or check the clock of this computer (and of the server that issued the token) and get a new token.',
        evidence: [token, 'nbf: ${AuthText.stamp(nbf)} (in ${AuthText.span(nbf.difference(now))})', ..._skew(ctx), ...said],
      ));
    }

    final iat = jwt.issuedAt;
    if (iat != null && iat.isAfter(now.add(_tolerance))) {
      out.add(AuthFinding(
        id: 'jwt.issued-in-future',
        confidence: FindingConfidence.likely,
        title: 'The token was issued in the future',
        explanation: 'The token says it was issued at ${AuthText.stamp(iat)} (iat), ${AuthText.span(iat.difference(now))} after this '
            'response. That means a clock is wrong: this computer\'s is behind, or the issuing server\'s is ahead. A strict server '
            'rejects such a token.',
        fix: 'Set the clock of this computer by network time, then get a new token.',
        evidence: [token, 'iat: ${AuthText.stamp(iat)} (in ${AuthText.span(iat.difference(now))})', ..._skew(ctx), ...said],
      ));
    }

    if (alg.toLowerCase() == 'none') {
      out.add(AuthFinding(
        id: 'jwt.alg-none',
        confidence: FindingConfidence.likely,
        title: 'The token is not signed',
        explanation: 'Its header says alg "none", which means no signature. Servers refuse such a token, because anyone could have written it.',
        fix: 'Use a token the identity provider signed. If you made the token yourself, sign it (the JWT Bearer type in the Auth tab does).',
        evidence: [token, 'header alg: none', ...said],
      ));
    }

    out.addAll(_audience(ctx, jwt, token, said));
    out.addAll(_issuer(ctx, jwt, token));
    out.addAll(_kind(jwt, token, said));
    out.addAll(_scope(ctx, jwt, token));
    return out;
  }

  // --- aud and iss ---------------------------------------------------------------------------------------------

  static List<String> _audiences(JwtInfo jwt) {
    final aud = jwt.payload['aud'];
    if (aud is String) return [aud];
    if (aud is List) return [for (final a in aud) if (a is String) a];
    return const [];
  }

  static String? _hostOf(String value) {
    final v = value.trim();
    if (v.isEmpty || v.contains(' ')) return null;
    final withScheme = v.contains('://') ? v : 'https://$v';
    final host = Uri.tryParse(withScheme)?.host.toLowerCase() ?? '';
    // A name such as "my-api" or "orders" is an identifier, not an address: it says nothing about the host.
    return host.contains('.') || host == 'localhost' ? host : null;
  }

  static bool _sameHost(String a, String b) => a == b || a.endsWith('.$b') || b.endsWith('.$a');

  static List<AuthFinding> _audience(AuthContext ctx, JwtInfo jwt, String token, List<String> said) {
    final host = ctx.host;
    if (host.isEmpty) return const [];
    final audiences = _audiences(jwt);
    final addresses = {for (final a in audiences) a: _hostOf(a)};
    final hosts = addresses.values.whereType<String>().toList();
    if (hosts.isEmpty || hosts.any((h) => _sameHost(h, host))) return const [];
    return [
      AuthFinding(
        id: 'jwt.audience',
        confidence: FindingConfidence.likely,
        title: 'The token was issued for another audience',
        explanation: 'The token\'s aud claim names ${AuthText.list(audiences.map((a) => '"$a"'))}, and this request goes to "$host". '
            'A server that checks the audience rejects a token that was meant for another API.',
        fix: 'Ask the identity provider for a token with the audience of this API (the Audience field of the OAuth 2.0 settings), or '
            'send the request to the API the token was issued for.',
        evidence: [token, 'aud: ${audiences.join(', ')}', 'Request host: $host', ...said],
      ),
    ];
  }

  static List<AuthFinding> _issuer(AuthContext ctx, JwtInfo jwt, String token) {
    final iss = jwt.payload['iss'];
    final host = ctx.host;
    if (iss is! String || host.isEmpty) return const [];
    final issHost = _hostOf(iss);
    if (issHost == null || EnvironmentWords.baseDomain(issHost) == EnvironmentWords.baseDomain(host)) return const [];
    final issuerKind = EnvironmentWords.kindOfHost(issHost) ?? EnvironmentWords.kindOf(issHost);
    final hostKind = EnvironmentWords.kindOfHost(host);
    final issuerName = issuerKind?.name;
    final hostName = hostKind?.name;
    final crossed = issuerName != null && hostName != null && issuerName != hostName;
    // Many APIs are fronted by an identity provider on another domain: that alone is not a fault.
    return [
      AuthFinding(
        id: 'jwt.issuer',
        confidence: crossed ? FindingConfidence.likely : FindingConfidence.possible,
        title: crossed ? 'The token comes from a $issuerName login, the API is $hostName' : 'The token was issued by another host',
        explanation: crossed
            ? 'The token was issued by "$issHost", which looks like a $issuerName identity provider, but the request goes to "$host", '
                'which looks like $hostName. The two environments do not trust each other\'s tokens.'
            : 'The token was issued by "$issHost" and the request goes to "$host". That is normal when a separate identity provider '
                'signs the tokens, and wrong when the token came from the identity provider of another environment.',
        fix: crossed
            ? 'Log in against the $hostName identity provider and use that token (check which environment is active).'
            : 'Check that the token comes from the identity provider this API trusts (the token URL of the OAuth 2.0 settings).',
        evidence: [token, 'iss: $iss', 'Request host: $host'],
      ),
    ];
  }

  /// An ID token or a refresh token sent where an access token is wanted.
  static List<AuthFinding> _kind(JwtInfo jwt, String token, List<String> said) {
    final use = '${jwt.payload['token_use'] ?? ''}'.toLowerCase();
    final typ = '${jwt.payload['typ'] ?? ''}'.toLowerCase();
    final wrong = use == 'id' ? 'an ID token' : (typ == 'id' ? 'an ID token' : (typ == 'refresh' ? 'a refresh token' : null));
    if (wrong == null) return const [];
    return [
      AuthFinding(
        id: 'jwt.wrong-kind',
        confidence: FindingConfidence.likely,
        title: 'This is $wrong, not an access token',
        explanation: 'The token\'s own claims say it is $wrong. APIs expect the access token; an ID token or a refresh token is refused.',
        fix: 'Use the access_token of the token response, not the ${wrong.contains('ID') ? 'id_token' : 'refresh_token'}.',
        evidence: [token, if (use.isNotEmpty) 'token_use: $use', if (typ.isNotEmpty) 'typ: $typ', ...said],
      ),
    ];
  }

  // --- scope and role ------------------------------------------------------------------------------------------

  static const _scopeClaims = ['scope', 'scp', 'scopes', 'permissions', 'roles', 'groups', 'authorities', 'entitlements'];

  /// Every scope, role or permission the token lists, and whether it lists any at all.
  static (Set<String>, bool) grantedBy(JwtInfo jwt) {
    final granted = <String>{};
    var any = false;
    void add(Object? value) {
      if (value is String) {
        any = true;
        granted.addAll(value.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty));
      } else if (value is List) {
        any = true;
        for (final item in value) {
          if (item is String) granted.add(item);
        }
      }
    }

    for (final claim in _scopeClaims) {
      add(jwt.payload[claim]);
    }
    final realm = jwt.payload['realm_access'];
    if (realm is Map) add(realm['roles']);
    final resource = jwt.payload['resource_access'];
    if (resource is Map) {
      for (final client in resource.values) {
        if (client is Map) add(client['roles']);
      }
    }
    return (granted, any);
  }

  static final _stopwords = {'and', 'or', 'the', 'to', 'access', 'is', 'are', 'of', 'for', 'this', 'a', 'an', 'missing', 'required'};
  static final _requiredPhrases = [
    RegExp(r'''(?:required|requires|missing|needs?|insufficient)\s+(?:the\s+)?(?:scope|role|permission)s?\s*[:=]?\s*["'\[]?([\w:./\-]+)''', caseSensitive: false),
    RegExp(r'''(?:scope|role|permission)\s+["']([\w:./\-]+)["']\s+(?:is\s+)?(?:required|missing|needed)''', caseSensitive: false),
  ];

  /// The scopes or roles the server says it needs, and whether it said so in a challenge (certain) or only in words.
  static (List<String>, bool) requiredBy(AuthContext ctx) {
    final bearer = ctx.challenge('bearer');
    if (bearer != null && bearer.scopes.isNotEmpty && (bearer.error == 'insufficient_scope' || ctx.status == 403)) {
      return (bearer.scopes, bearer.error == 'insufficient_scope');
    }
    for (final pattern in _requiredPhrases) {
      final name = pattern.firstMatch(ctx.body)?[1];
      if (name != null && !_stopwords.contains(name.toLowerCase())) return ([name], false);
    }
    return (const [], false);
  }

  static List<AuthFinding> _scope(AuthContext ctx, JwtInfo jwt, String token) {
    final (required, certain) = requiredBy(ctx);
    if (required.isEmpty) return const [];
    final (granted, any) = grantedBy(jwt);
    final lower = {for (final g in granted) g.toLowerCase()};
    final missing = [
      for (final r in required)
        if (!lower.contains(r.toLowerCase())) r,
    ];
    if (missing.isEmpty) return const [];
    return [
      AuthFinding(
        id: 'token.missing-scope',
        confidence: certain ? FindingConfidence.certain : FindingConfidence.likely,
        title: 'The token lacks ${missing.length == 1 ? 'a scope or role' : 'scopes or roles'} the API asks for',
        explanation: 'The server asks for ${AuthText.list(required.map((r) => '"$r"'))}, and the token '
            '${any ? 'lists ${granted.isEmpty ? 'none' : AuthText.list(granted.take(8).map((g) => '"$g"'))}' : 'has no scope or role claim at all'}. '
            'Missing: ${AuthText.list(missing.map((m) => '"$m"'))}.',
        fix: 'Request a token with ${missing.length == 1 ? 'that scope' : 'those scopes'} (the Scope field of the OAuth 2.0 settings), '
            'or give the user the role in the identity provider, then get a new token.',
        evidence: [
          token,
          'Required: ${required.join(' ')}',
          'In the token: ${granted.isEmpty ? '(nothing)' : granted.take(12).join(' ')}',
        ],
      ),
    ];
  }

  /// The server's clock against this computer's, from the `Date` header; nothing when they agree or it is missing.
  static List<String> _skew(AuthContext ctx) {
    final server = AuthText.httpDate(ctx.responseHeader('date'));
    if (server == null) return const [];
    final difference = server.difference(ctx.now.toUtc());
    if (difference.abs() < const Duration(minutes: 2)) return const [];
    return ['The server\'s Date header is ${AuthText.span(difference)} ${difference.isNegative ? 'behind' : 'ahead of'} this computer.'];
  }

  static String _cap(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}
