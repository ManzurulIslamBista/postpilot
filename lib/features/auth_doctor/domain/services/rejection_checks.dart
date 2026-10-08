// Pure Dart (no Flutter, no database).
import '../../../../core/enums/auth_type.dart';
import '../../../odoo/domain/services/odoo_diagnosis.dart';
import '../../../odoo/domain/services/odoo_error_parser.dart';
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'server_words.dart';

/// The causes that are not about the credential at all: Odoo's access rights, a firewall or CDN in front of the API, an
/// IP allow-list, a missing CSRF token, a method the URL does not allow, a rate limit, a signature or a clock that is
/// off, and credentials lost in a redirect.
abstract final class RejectionChecks {
  static List<AuthFinding> run(AuthContext ctx) => [
        ?_odoo(ctx),
        ..._waf(ctx),
        ..._ipAllowList(ctx),
        ..._csrf(ctx),
        ?_method(ctx),
        ?_rateLimit(ctx),
        ..._signature(ctx),
        ..._redirect(ctx),
      ];

  // --- Odoo ----------------------------------------------------------------------------------------------------

  static const _odooNames = {'AccessError', 'AccessDenied', 'Forbidden', 'Unauthorized', 'SessionExpiredException'};
  static final _notAllowed = RegExp(r'you are not allowed to (?:access|modify|create|delete|read|write)', caseSensitive: false);

  /// Odoo's own words for a rejection, read with the app's Odoo error parser (the same one the Odoo error banner uses).
  /// The live part of the Odoo error doctor needs a server connection and stays in that banner.
  static AuthFinding? _odoo(AuthContext ctx) {
    if (ctx.status != 401 && ctx.status != 403) return null;
    final body = ctx.body.trim();
    OdooErrorInfo? info;
    if (body.startsWith('{')) info = OdooErrorParser.parse(body, statusCode: ctx.status);
    String exception;
    String message;
    OdooDiagnosis? diagnosis;
    String title;
    String? hint;
    if (info != null) {
      final short = info.exception.split('.').last;
      diagnosis = info.diagnosis;
      final kind = diagnosis?.kind;
      final access = kind == OdooErrorKind.accessModel || kind == OdooErrorKind.accessRule || _odooNames.contains(short);
      if (!access) return null;
      exception = info.exception;
      message = info.message;
      title = info.title;
      hint = info.hint;
    } else {
      final match = _notAllowed.firstMatch(body);
      if (match == null) return null;
      exception = 'odoo.exceptions.AccessError';
      message = body.split(RegExp(r'[\r\n]+')).firstWhere((l) => _notAllowed.hasMatch(l), orElse: () => match[0]!);
      diagnosis = OdooDiagnoser.diagnose(exception, message);
      title = 'Access denied';
      hint = diagnosis == null ? null : OdooErrorParser.hintOf(diagnosis);
    }
    final live = diagnosis != null &&
        (diagnosis.kind == OdooErrorKind.accessModel || diagnosis.kind == OdooErrorKind.accessRule);
    final steps = diagnosis?.steps ?? const <String>[];
    return AuthFinding(
      id: 'forbidden.odoo',
      confidence: FindingConfidence.certain,
      title: 'Odoo: $title',
      explanation: diagnosis?.explanation ?? 'Odoo answered "$title"${message.isEmpty ? '' : ': ${ctx.quote(message, max: 200)}'}.',
      fix: [
        if (steps.isNotEmpty) steps.join(' ') else hint ?? 'Check the groups of the API user and the access rules of the model.',
        if (live) 'The Odoo error banner on the response can look the groups and record rules up on the live server ("Look it up on the server").',
      ].join(' '),
      evidence: [
        'Odoo exception: $exception',
        if (message.isNotEmpty) 'Odoo said: "${ctx.quote(message)}"',
      ],
    );
  }

  // --- a firewall or CDN answered, not the API --------------------------------------------------------------------

  static List<AuthFinding> _waf(AuthContext ctx) {
    if (ctx.status != 403 && ctx.status != 401) return const [];
    final server = (ctx.responseHeader('server') ?? '').toLowerCase();
    // Block pages write their punctuation as numeric entities (`Reference&#32;&#35;18...`).
    final page = _plain(ctx.body);
    final body = page.toLowerCase();
    bool has(String header) => ctx.responseHeaders.containsKey(header);

    String? vendor;
    String? advice;
    final reference = <String>[];
    if ((server == 'cloudflare' || has('cf-ray') || has('cf-mitigated')) && (ctx.isHtml || has('cf-mitigated'))) {
      vendor = 'Cloudflare';
      final ray = ctx.responseHeader('cf-ray');
      if (ray != null) reference.add('cf-ray: $ray');
      advice = 'Ask the owner of the site to allow your address or to add a firewall rule that skips bot protection for API calls, '
          'send a normal User-Agent, or use an origin address that is not behind Cloudflare. Give them the Ray ID.';
    } else if (server.contains('akamai') || (body.contains('reference #') && body.contains('access denied'))) {
      vendor = 'Akamai';
      final ref = RegExp(r'reference\s*#\s*([\w.\-]+)', caseSensitive: false).firstMatch(page)?[1];
      if (ref != null) reference.add('Reference #$ref');
      advice = 'The request was stopped by Akamai\'s bot or WAF rules. Ask the site owner to allow your address, and give them the reference number.';
    } else if (has('x-amzn-waf-action') || (server.contains('cloudfront') && (body.contains('request blocked') || body.contains('could not be satisfied')))) {
      vendor = 'AWS WAF or CloudFront';
      advice = 'A web application firewall rule blocked the request before it reached the API. Ask the owner to check the WAF rules and the allow-list.';
    } else if (has('x-iinfo') || body.contains('_incapsula_resource') || body.contains('incapsula incident')) {
      vendor = 'Imperva (Incapsula)';
      advice = 'Imperva\'s firewall blocked the request. Ask the site owner to allow your address and give them the incident id from the page.';
    } else if (server.contains('sucuri') || body.contains('sucuri website firewall')) {
      vendor = 'Sucuri';
      advice = 'Sucuri\'s firewall blocked the request. Ask the site owner to allow your address.';
    } else if (body.contains('modsecurity') || body.contains('not acceptable! an appropriate representation')) {
      vendor = 'ModSecurity';
      advice = 'A ModSecurity rule rejected the request, often because of its User-Agent, headers or body. Ask the owner which rule fired.';
    } else if (body.contains('the requested url was rejected') && body.contains('support id')) {
      vendor = 'an F5 BIG-IP firewall';
      advice = 'The firewall rejected the request. Ask the owner to look up the support id shown on the page.';
    }
    if (vendor != null) {
      return [
        AuthFinding(
          id: 'forbidden.waf',
          confidence: FindingConfidence.likely,
          title: '$vendor blocked the request',
          explanation: 'The answer is a block page from $vendor, not a response of the API: the request was stopped before it reached the '
              'application, so the token was never looked at.',
          fix: advice!,
          evidence: [
            if (server.isNotEmpty) 'server: ${ctx.responseHeader('server')}',
            ...reference,
            if (ctx.isHtml) 'The body is an HTML page, not the API\'s JSON.',
          ],
        ),
      ];
    }
    if (ctx.status == 403 && ctx.isHtml && RegExp(r'access denied|request blocked|403 forbidden|<title>forbidden|you don.t have permission to access').hasMatch(body)) {
      return [
        AuthFinding(
          id: 'forbidden.web-server',
          confidence: FindingConfidence.possible,
          title: 'A web server or proxy refused, not the API',
          explanation: 'The answer is an HTML error page. A web server or proxy in front of the API (nginx, Apache, IIS, a gateway) refused the '
              'path itself, before any token check: a deny rule, a directory without an index, a file permission, or an address restriction.',
          fix: 'Check the URL (path, trailing slash, version), and ask whoever runs the server whether this path or your address is restricted.',
          evidence: [
            if (server.isNotEmpty) 'server: ${ctx.responseHeader('server')}',
            'The body is an HTML page, not the API\'s JSON.',
          ],
        ),
      ];
    }
    return const [];
  }

  /// [text] with its numeric character references (`&#46;`) turned into the characters.
  static String _plain(String text) => text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m[1]!);
        return code == null || code > 0x10FFFF ? m[0]! : String.fromCharCode(code);
      });

  // --- IP allow-list -------------------------------------------------------------------------------------------

  static final _ipWords = [
    RegExp(r'\bip(?: address)?\b[^\n]{0,50}?\b(?:not (?:allowed|permitted|whitelisted|allow-?listed|authori[sz]ed)|blocked|denied|restricted|forbidden|banned)\b'),
    RegExp(r"\b(?:not|isn't|is not) (?:in|on) the (?:ip )?(?:white|allow)-?list\b"),
    RegExp(r'\bip (?:restriction|filter|allow-?list|white-?list)\b'),
    RegExp(r'\b(?:access|request)s? from (?:your|this) (?:ip|network|location|address)\b'),
    RegExp(r'\b(?:white|allow)-?list(?:ed)?\b'),
  ];

  static List<AuthFinding> _ipAllowList(AuthContext ctx) {
    if (ctx.status != 403 && ctx.status != 401) return const [];
    if (ctx.bodyLower.isEmpty) return const [];
    for (final pattern in _ipWords) {
      final match = pattern.firstMatch(ctx.bodyLower);
      if (match == null) continue;
      // The server's own message when it has one, else the words around the match.
      final length = ctx.body.length;
      final around = ctx.body.substring((match.start - 30).clamp(0, length), (match.end + 40).clamp(0, length));
      final said = ServerWords.evidence(ctx);
      return [
        AuthFinding(
          id: 'forbidden.ip-allowlist',
          confidence: FindingConfidence.likely,
          title: 'This address may not be on the allow-list',
          explanation: 'The server\'s message talks about an IP address restriction. A request from an address that is not on the allow-list '
              'is refused whatever the token says.',
          fix: 'Call from a network that is on the list (the office, or its VPN), or ask the owner to add the public address of this '
              'computer. PostPilot never looks that address up for you.',
          evidence: said.isNotEmpty ? said : ['The server said: "${ctx.quote(around)}"'],
        ),
      ];
    }
    return const [];
  }

  // --- CSRF, Origin, Referer, X-Requested-With --------------------------------------------------------------------

  static final _csrfWords = RegExp(r'csrf|xsrf|cross[- ]site request forgery|authenticity token|page expired');
  static const _unsafe = {'POST', 'PUT', 'PATCH', 'DELETE'};

  static List<AuthFinding> _csrf(AuthContext ctx) {
    if (ctx.status != 403 && ctx.status != 419 && ctx.status != 400) return const [];
    final headerNames = ctx.requestHeaders.keys.toList();
    final hasCsrfHeader = headerNames.any((h) => h.contains('csrf') || h.contains('xsrf'));
    final body = ctx.bodyLower;
    final said = ServerWords.evidence(ctx);
    final out = <AuthFinding>[];

    if (_csrfWords.hasMatch(body) && !hasCsrfHeader) {
      out.add(AuthFinding(
        id: 'forbidden.csrf',
        confidence: FindingConfidence.likely,
        title: 'A CSRF token is missing',
        explanation: 'The server\'s message is about a CSRF (cross-site request forgery) token, and the request has no CSRF header '
            '(X-CSRF-Token, X-XSRF-TOKEN). Servers that use cookie sessions require it on every request that changes data.',
        fix: 'Read the token the server gives you (a cookie such as XSRF-TOKEN, a /csrf endpoint, a meta tag) and send it as the header the '
            'framework expects, or as the form field. An API called with a Bearer token usually does not need CSRF: check that the server is '
            'not treating the call as a browser session.',
        evidence: [...said, 'The request has no header with "csrf" or "xsrf" in its name.'],
      ));
    }
    final needsOrigin = RegExp(r'\borigin\b').hasMatch(body.replaceAll('origin server', '')) && ctx.requestHeader('origin') == null;
    final needsReferer = RegExp(r'\breferr?er\b').hasMatch(body) && ctx.requestHeader('referer') == null;
    if (needsOrigin || needsReferer) {
      final names = [if (needsOrigin) 'Origin', if (needsReferer) 'Referer'];
      out.add(AuthFinding(
        id: 'forbidden.origin',
        confidence: FindingConfidence.likely,
        title: 'The server wants an ${names.join(' / ')} header',
        explanation: 'The server\'s message talks about the ${names.join(' or ')} of the request, and the request sent none. '
            'A server that guards against cross-site calls refuses a request whose origin it cannot see.',
        fix: 'Add the header ${names.map((n) => '$n: https://<the site>').join(' and ')} with the address your web app runs on.',
        evidence: [...said, for (final n in names) 'The request has no $n header.'],
      ));
    }
    if (body.contains('x-requested-with') && ctx.requestHeader('x-requested-with') == null) {
      out.add(AuthFinding(
        id: 'forbidden.xhr',
        confidence: FindingConfidence.likely,
        title: 'The server wants X-Requested-With',
        explanation: 'The server\'s message mentions X-Requested-With, the header a browser script adds to an AJAX call, and the request has none.',
        fix: 'Add the header X-Requested-With: XMLHttpRequest.',
        evidence: [...said, 'The request has no X-Requested-With header.'],
      ));
    }
    final cookieOnly = ctx.credentials.isNotEmpty && ctx.credentials.every((c) => c.isCookie);
    if (out.isEmpty && ctx.status == 403 && _unsafe.contains(ctx.input.method.toUpperCase()) && cookieOnly && !hasCsrfHeader) {
      out.add(AuthFinding(
        id: 'forbidden.csrf-maybe',
        confidence: FindingConfidence.possible,
        title: 'A cookie session without a CSRF token',
        explanation: 'The request changes data (${ctx.input.method.toUpperCase()}), authenticates with a cookie only, and sent no CSRF header. '
            'Frameworks such as Django, Rails, Laravel and Spring answer exactly this with 403.',
        fix: 'Send the CSRF token the server issued in the header it expects (X-CSRF-Token, X-XSRF-TOKEN), or use token authentication.',
        evidence: [...said, 'Credentials sent: cookie only.'],
      ));
    }
    return out;
  }

  // --- the method is not allowed -------------------------------------------------------------------------------

  static AuthFinding? _method(AuthContext ctx) {
    final allow = ctx.responseHeader('allow');
    if (allow == null || allow.trim().isEmpty) return null;
    final allowed = {for (final m in allow.split(',')) m.trim().toUpperCase()}..remove('');
    final method = ctx.input.method.toUpperCase();
    if (allowed.isEmpty || allowed.contains(method)) return null;
    return AuthFinding(
      id: 'forbidden.method',
      confidence: FindingConfidence.certain,
      title: 'This URL does not allow $method',
      explanation: 'The response carries an Allow header listing ${allowed.join(', ')}, and the request used $method. A server may answer '
          'a method it does not offer with ${ctx.status} instead of 405.',
      fix: 'Use one of ${allowed.join(', ')}, or check that the path and the API version are the right ones for $method.',
      evidence: ['Allow: ${allowed.join(', ')}', 'The request method: $method'],
    );
  }

  // --- a rate limit ----------------------------------------------------------------------------------------------

  static AuthFinding? _rateLimit(AuthContext ctx) {
    String? header(List<String> names) {
      for (final name in names) {
        final value = ctx.responseHeader(name);
        if (value != null && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    final remaining = header(['x-ratelimit-remaining', 'ratelimit-remaining', 'x-rate-limit-remaining', 'x-ratelimit-requests-remaining']);
    final retryAfter = header(['retry-after']);
    final reset = header(['x-ratelimit-reset', 'ratelimit-reset', 'x-rate-limit-reset']);
    final limit = header(['x-ratelimit-limit', 'ratelimit-limit', 'x-rate-limit-limit']);
    final exhausted = remaining != null && int.tryParse(remaining) == 0;
    final worded = RegExp(r'rate.?limit|too many requests|quota (?:exceeded|exhausted)|throttl').hasMatch(ctx.bodyLower);
    if (!exhausted && retryAfter == null && !worded) return null;

    var wait = '';
    final resetNumber = int.tryParse(reset ?? '');
    if (resetNumber != null) {
      // A Unix time (GitHub, Twitter) or a number of seconds (the IETF header).
      final seconds = resetNumber > 1000000000 ? resetNumber - ctx.now.toUtc().millisecondsSinceEpoch ~/ 1000 : resetNumber;
      if (seconds > 0) wait = ' It resets in ${AuthText.span(Duration(seconds: seconds))}.';
    } else if (int.tryParse(retryAfter ?? '') case final seconds? when seconds > 0) {
      wait = ' The server asks you to retry after ${AuthText.span(Duration(seconds: seconds))}.';
    } else if (AuthText.httpDate(retryAfter) case final date?) {
      final seconds = date.difference(ctx.now.toUtc()).inSeconds;
      if (seconds > 0) wait = ' The server asks you to retry in ${AuthText.span(Duration(seconds: seconds))}.';
    }
    return AuthFinding(
      id: 'forbidden.rate-limit',
      confidence: exhausted ? FindingConfidence.certain : FindingConfidence.likely,
      title: 'The rate limit may be used up',
      explanation: 'The response ${exhausted ? 'says no requests are left in the current window' : 'carries rate-limit information'}, and some servers '
          'refuse with ${ctx.status} instead of 429 when a client is over its limit.$wait',
      fix: 'Wait for the window to reset and send fewer requests (add a delay between requests in the runner), or ask for a higher limit.',
      evidence: [
        if (remaining != null) 'Remaining: $remaining',
        if (limit != null) 'Limit: $limit',
        if (reset != null) 'Reset: $reset',
        if (retryAfter != null) 'Retry-After: $retryAfter',
        if (remaining == null && retryAfter == null && worded) ...ServerWords.evidence(ctx),
      ],
    );
  }

  // --- signatures and clocks -------------------------------------------------------------------------------------

  static final _skewWords = RegExp(
    r'requesttimetooskewed|time too skewed|difference between the request time and the current time|clock skew|request (?:has )?expired|signature expired|'
    r'timestamp[^.\n]{0,50}(?:expired|too old|too far|invalid|out of range|skew|window|drift)|'
    r'(?:expired|invalid|old) timestamp|nonce[^.\n]{0,30}(?:used|reuse|old|expired)',
  );
  static final _mismatchWords = RegExp(
    r'signaturedoesnotmatch|signature (?:we calculated )?does not match|the request signature we calculated|invalid ?signature|signature (?:mismatch|verification failed|is invalid)|hmac',
  );

  static List<AuthFinding> _signature(AuthContext ctx) {
    final body = ctx.bodyLower;
    final sigv4 = ctx.input.authType == AuthType.awsSignatureV4;
    final hmac = ctx.input.authType == AuthType.hmac;
    final said = ServerWords.evidence(ctx);
    final out = <AuthFinding>[];

    final server = AuthText.httpDate(ctx.responseHeader('date'));
    final offset = server?.difference(ctx.now.toUtc());
    final skewed = offset != null && offset.abs() > const Duration(minutes: 5);
    final clock = offset == null
        ? <String>[]
        : ['The server\'s Date header is ${AuthText.span(offset)} ${offset.isNegative ? 'behind' : 'ahead of'} this computer.'];

    if (_skewWords.hasMatch(body) || (sigv4 && skewed)) {
      out.add(AuthFinding(
        id: 'signature.clock-skew',
        confidence: _skewWords.hasMatch(body) ? FindingConfidence.certain : FindingConfidence.likely,
        title: 'The request\'s timestamp is too far from the server\'s clock',
        explanation: 'Signed requests carry the time they were made at, and the server refuses one that is more than a few minutes off '
            '(AWS allows 5 minutes). ${skewed ? 'This computer\'s clock and the server\'s differ by ${AuthText.span(offset)}.' : 'The server\'s message points at the timestamp.'}',
        fix: 'Set the clock of this computer automatically (network time) and send again. For a signature you build yourself, generate the timestamp at send time.',
        evidence: [...said, ...clock],
      ));
    }
    if (_mismatchWords.hasMatch(body)) {
      out.add(AuthFinding(
        id: 'signature.mismatch',
        confidence: FindingConfidence.likely,
        title: 'The signature does not match',
        explanation: sigv4
            ? 'The server computed another AWS Signature v4 than the one sent: the secret key, region or service differs, or something changed '
                'in the request after it was signed.'
            : 'The server computed another signature than the one sent, so it was made from different bytes or with another secret.',
        fix: sigv4
            ? 'Check the region and the service in the Auth tab (they are part of the signature), the access and secret keys, and that no proxy '
                'rewrites the Host header or the path. Send the exact body that was signed.'
            : hmac
                ? 'Check the HMAC settings in the Auth tab against the API documentation: the secret, the algorithm (SHA-256 or SHA-1), the encoding '
                    '(hex or base64), the signed payload (usually the body, some APIs sign the timestamp and the body together) and the format of the header. '
                    'The body must be the exact bytes that are sent.'
                : 'Check the secret, the exact bytes that are signed (body, key order, encoding of the URL), and the timestamp format.',
        evidence: [...said, if (sigv4) 'Auth type: AWS Signature v4', if (hmac) 'Auth type: HMAC signature'],
      ));
    }
    return out;
  }

  // --- credentials lost in a redirect -------------------------------------------------------------------------

  static bool _keepsCredentials(Uri from, Uri to) =>
      to.scheme == from.scheme && to.port == from.port && (to.host == from.host || to.host.endsWith('.${from.host}'));

  static bool _local(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1' || host.endsWith('.localhost') || host.startsWith('10.') || host.startsWith('192.168.');

  static List<AuthFinding> _redirect(AuthContext ctx) {
    if (ctx.status != 401 && ctx.status != 403) return const [];
    final sent = ctx.tokens.where((c) => !c.isCookie).isNotEmpty || ctx.input.authType == AuthType.digest;
    if (!sent) return const [];
    for (final hop in ctx.input.redirects) {
      final from = Uri.tryParse(hop.from);
      final to = Uri.tryParse(hop.to);
      if (from == null || to == null || _keepsCredentials(from, to)) continue;
      return [
        AuthFinding(
          id: 'redirect.credentials-dropped',
          confidence: FindingConfidence.certain,
          title: 'The credential was dropped at a redirect',
          explanation: 'The server answered ${hop.status} and sent the client from ${from.host} to ${to.host}. Clients (PostPilot, browsers, curl) do not '
              'forward an Authorization header or a cookie to another host or to another scheme, so the final server received none.',
          fix: 'Call the final address directly (${to.scheme}://${to.host}${to.hasPort ? ':${to.port}' : ''}), for example by putting it in the base URL.',
          evidence: ['Redirect ${hop.status}: ${from.scheme}://${from.host} to ${to.scheme}://${to.host}', 'The request had a credential.'],
        ),
      ];
    }
    final uri = ctx.uri;
    if (ctx.status == 401 && ctx.input.redirects.isEmpty && uri != null && uri.scheme == 'http' && !_local(ctx.host)) {
      return [
        AuthFinding(
          id: 'redirect.http',
          confidence: FindingConfidence.possible,
          title: 'The URL uses http, not https',
          explanation: 'Servers usually answer http with a redirect to https, and a client drops the credential when the scheme changes, '
              'so the call arrives on https without it.',
          fix: 'Use the https:// address.',
          evidence: ['Request URL scheme: http', 'The request had a credential.'],
        ),
      ];
    }
    return const [];
  }
}
