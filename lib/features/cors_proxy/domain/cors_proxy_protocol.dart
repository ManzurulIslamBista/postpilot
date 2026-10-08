// Pure Dart: the wire protocol of the CORS proxy, shared by the proxy engine, the web client that talks to it and the
// settings pane that explains it.
import 'dart:convert';
import 'dart:math';

/// Header names and paths of the protocol. A web page cannot read a server that sends no CORS headers, so the web app sends
/// its real request to a small proxy on the developer's computer, names the real address in [urlHeader] and proves it may
/// use the proxy with [tokenHeader]. The proxy forwards the call and answers with CORS headers.
abstract final class CorsProxyProtocol {
  /// The real target of the call: an absolute http(s) URL.
  static const urlHeader = 'X-PostPilot-Url';

  /// The secret printed when the proxy starts; without it every call but a preflight is refused.
  static const tokenHeader = 'X-PostPilot-Token';

  /// `manual` asks the proxy to hide a redirect from the browser. A browser follows a 3xx answer by itself and never shows it
  /// to the page, so the proxy answers 200 and names the real status in [statusHeader].
  static const redirectsHeader = 'X-PostPilot-Redirects';
  static const redirectsManual = 'manual';

  /// The upstream's real status and reason, when [redirectsHeader] hid a redirect behind a 200.
  static const statusHeader = 'X-PostPilot-Status';
  static const statusTextHeader = 'X-PostPilot-Status-Text';

  /// The upstream's `Set-Cookie` lines, which a browser hides from a page: one header holding a JSON array.
  static const setCookieHeader = 'X-PostPilot-Set-Cookie';

  /// Set on an answer the proxy made itself (a wrong token, an upstream that could not be reached), never on one it passed
  /// on; its value is the error code. The upstream cannot send it: every `X-PostPilot-*` header is dropped from its answer.
  static const errorHeader = 'X-PostPilot-Proxy-Error';

  static const healthPath = '/__postpilot/health';
  static const defaultPort = 8787;
  static const defaultUrl = 'http://localhost:$defaultPort';

  /// What a person types to start it (from the PostPilot folder).
  static const command = 'dart run bin/postpilot.dart proxy';

  /// The version the health check reports, so a web app can tell an older proxy from a newer one.
  static const version = '1';

  /// The statuses a browser follows by itself.
  static const redirectStatuses = {301, 302, 303, 307, 308};

  static bool isOwnHeader(String lowerName) => lowerName.startsWith('x-postpilot-');

  /// [cookies] as the value of [setCookieHeader]: a JSON array in ASCII only (a header value cannot hold anything else),
  /// because the lines cannot simply be joined: a cookie's `Expires` holds a comma of its own.
  static String encodeSetCookies(List<String> cookies) {
    final json = jsonEncode(cookies);
    final out = StringBuffer();
    for (final unit in json.codeUnits) {
      if (unit < 0x7f) {
        out.writeCharCode(unit);
      } else {
        out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return out.toString();
  }

  /// The cookie lines of a [setCookieHeader] value; a value that is not a JSON array of text is taken as one cookie.
  static List<String> decodeSetCookies(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List && decoded.every((e) => e is String)) return List<String>.from(decoded);
    } on FormatException {
      // Not ours: handled below.
    }
    return value.trim().isEmpty ? const [] : [value];
  }
}

/// The secret that lets a page use the proxy.
abstract final class CorsProxyToken {
  /// A token of 192 random bits, as URL-safe text.
  static String generate({Random? random}) {
    final rng = random ?? Random.secure();
    return base64Url.encode([for (var i = 0; i < 24; i++) rng.nextInt(256)]).replaceAll('=', '');
  }

  /// What is wrong with a token a person chose, null when it is usable: it travels in a header, so it is printable ASCII
  /// without spaces, and it is long enough not to be guessed.
  static String? problem(String token) {
    if (token.length < 8) return 'The token must be at least 8 characters long.';
    if (token.length > 256) return 'The token must be at most 256 characters long.';
    if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(token)) return 'The token may only contain visible ASCII characters, without spaces.';
    return null;
  }

  /// The shortest token a proxy that other devices can reach accepts: anyone on the network may keep guessing.
  static const lanMinLength = 16;

  /// What is wrong with [token] for a proxy that listens on the network, null when it is usable there.
  static String? lanProblem(String token) =>
      token.length < lanMinLength
          ? 'A proxy that other devices can reach needs a token of at least $lanMinLength characters (leave --token out to get a random one).'
          : null;

  /// Whether [token] can be typed into a shell command as it is: letters, digits and `. _ ~ -` only.
  static bool isShellSafe(String token) => RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token);

  /// Whether [given] is [expected], compared in a time that does not depend on how many leading characters match.
  static bool matches(String? given, String expected) {
    if (given == null) return false;
    final a = utf8.encode(given);
    final b = utf8.encode(expected);
    var diff = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      diff |= (i < a.length ? a[i] : 0) ^ b[i];
    }
    return diff == 0;
  }
}

/// Which web pages may use the proxy.
final class CorsProxyOrigins {
  final Set<String> _extra;

  /// [extra] are origins as [normalize] writes them (the ones given with `--allow-origin`).
  CorsProxyOrigins([Iterable<String> extra = const []]) : _extra = {...extra};

  List<String> get extra => List.unmodifiable(_extra);

  /// `scheme://host[:port]` for [text] (lowercase, a default port and a trailing slash dropped); null when it is not an
  /// origin: no http(s) scheme, no host, a path, a query or a wildcard.
  static String? normalize(String text) {
    final t = text.trim();
    if (t.isEmpty || t.contains('*') || t.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) return null;
    final host = uri.host.toLowerCase();
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    final shownHost = host.contains(':') ? '[$host]' : host;
    return uri.hasPort && uri.port != defaultPort ? '${uri.scheme}://$shownHost:${uri.port}' : '${uri.scheme}://$shownHost';
  }

  /// The origins in [text] (separated by commas, spaces or new lines), or what is wrong with one of them.
  static ({List<String> origins, String? error}) parseList(String text) {
    final origins = <String>[];
    for (final part in text.split(RegExp(r'[,\s]+'))) {
      if (part.isEmpty) continue;
      final origin = normalize(part);
      if (origin == null) {
        return (
          origins: const [],
          error: part.contains('*')
              ? 'A wildcard origin would let every website use the proxy. Name each origin, for example https://app.example.com.'
              : '"$part" is not an origin. Use scheme, host and port only, for example https://app.example.com or http://localhost:5000.',
        );
      }
      if (!origins.contains(origin)) origins.add(origin);
    }
    return (origins: origins, error: null);
  }

  /// A page on this computer: `http(s)://localhost`, `127.x.x.x` or `[::1]` on any port.
  static bool isLoopback(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '::1' || RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }

  /// Whether a call carrying [origin] in its `Origin` header may be answered: a page on this computer, or one that was named.
  bool allows(String origin) {
    final normalized = normalize(origin);
    return normalized != null && (isLoopback(normalized) || _extra.contains(normalized));
  }

  /// The origins in words, for the start message.
  String describe() => ['http(s)://localhost:*', 'http(s)://127.0.0.1:*', ..._extra].join(', ');
}

/// A refused call: the status, a code a program can read and a sentence that says what to do.
final class CorsProxyRefusal {
  final int status;
  final String code;
  final String message;
  const CorsProxyRefusal(this.status, this.code, this.message);
}

/// Counts the wrong tokens each caller sent in the last minute, so that a proxy other devices can reach cannot be guessed at
/// as fast as the network allows. A caller that sent [maxFailures] of them is refused until the oldest has aged out.
final class CorsProxyAttempts {
  static const maxFailures = 10;
  static const window = Duration(minutes: 1);
  static const _maxCallers = 1000;

  final _failures = <String, List<DateTime>>{};

  bool isLocked(String caller, DateTime now) {
    final failures = _failures[caller];
    if (failures == null) return false;
    failures.removeWhere((at) => now.difference(at) >= window);
    if (failures.isEmpty) {
      _failures.remove(caller);
      return false;
    }
    return failures.length >= maxFailures;
  }

  void recordFailure(String caller, DateTime now) {
    if (_failures.length >= _maxCallers && !_failures.containsKey(caller)) {
      _failures.removeWhere((_, list) => list.every((at) => now.difference(at) >= window));
      if (_failures.length >= _maxCallers) return;
    }
    (_failures[caller] ??= []).add(now);
  }

  void clear(String caller) => _failures.remove(caller);
}

/// The address a call is meant for.
abstract final class CorsProxyTargets {
  /// The URL in [header] (the value of [CorsProxyProtocol.urlHeader]) as a [Uri], or why it cannot be used. [ownPort] and
  /// [ownHosts] name the proxy itself: a call to it would loop forever.
  static ({Uri? uri, CorsProxyRefusal? refusal}) parse(String? header, {required int ownPort, Set<String> ownHosts = const {}}) {
    CorsProxyRefusal refuse(int status, String code, String message) => CorsProxyRefusal(status, code, message);
    final text = header?.trim() ?? '';
    if (text.isEmpty) {
      return (
        uri: null,
        refusal: refuse(400, 'missing_target', 'The ${CorsProxyProtocol.urlHeader} header is missing. It names the address the call is for.'),
      );
    }
    final uri = Uri.tryParse(text);
    if (uri == null || text.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) {
      return (uri: null, refusal: refuse(400, 'invalid_target', 'The address in ${CorsProxyProtocol.urlHeader} is not a valid URL.'));
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return (
        uri: null,
        refusal: refuse(400, 'unsupported_scheme', 'Only http:// and https:// addresses can be forwarded, not "${uri.scheme.isEmpty ? 'no scheme' : uri.scheme}".'),
      );
    }
    if (uri.host.isEmpty) {
      return (uri: null, refusal: refuse(400, 'invalid_target', 'The address in ${CorsProxyProtocol.urlHeader} has no host.'));
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final host = uri.host.toLowerCase();
    final isSelf = port == ownPort &&
        (host == 'localhost' || host == '::1' || host == '0.0.0.0' || host == '::' || host.startsWith('127.') || ownHosts.contains(host));
    if (isSelf) {
      return (
        uri: null,
        refusal: refuse(508, 'proxy_loop', 'That address is this proxy itself, so forwarding it would loop forever. Use the address of the real server.'),
      );
    }
    return (uri: uri, refusal: null);
  }
}
