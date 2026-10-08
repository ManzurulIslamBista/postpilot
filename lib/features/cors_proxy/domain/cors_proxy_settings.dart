// Pure Dart: what the web app remembers about the CORS proxy, and the route a request takes when it is switched on.
import 'cors_proxy_protocol.dart';

/// Where the web app sends its calls instead of straight to the server.
final class CorsProxyRoute {
  /// `scheme://host[:port]` of the proxy.
  final Uri base;

  /// Sent in `X-PostPilot-Token`; empty sends none (the proxy then answers 401 and says so).
  final String token;

  const CorsProxyRoute(this.base, this.token);

  /// `host[:port]` of the proxy, for messages.
  String get authority => base.hasPort ? '${base.host.contains(':') ? '[${base.host}]' : base.host}:${base.port}' : base.host;

  /// Whether a call to [target] goes through the proxy: any http(s) address except the proxy itself (which the person may
  /// call directly, for example its health check).
  bool proxies(Uri target) {
    if (target.scheme != 'http' && target.scheme != 'https') return false;
    final samePort = (target.hasPort ? target.port : (target.scheme == 'https' ? 443 : 80)) == _portOf(base);
    return !(samePort && target.host.toLowerCase() == base.host.toLowerCase() && target.scheme == base.scheme);
  }

  /// The address the browser requests: the proxy with the path of [target], which the proxy ignores (the real address is in
  /// `X-PostPilot-Url`) but which makes the call readable in the browser's network tab.
  Uri endpointFor(Uri target) {
    final path = target.path.isEmpty ? '/' : target.path;
    return Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null, path: path);
  }

  static int _portOf(Uri uri) => uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

  @override
  bool operator ==(Object other) => other is CorsProxyRoute && other.base == base && other.token == token;

  @override
  int get hashCode => Object.hash(base, token);
}

/// The web app's CORS proxy choices: on or off, its address and its token. The token is a secret: it is kept in the secure
/// storage of the browser, never in the workspace file or in Git.
final class CorsProxySettings {
  final bool enabled;
  final String url;
  final String token;

  const CorsProxySettings({this.enabled = false, this.url = CorsProxyProtocol.defaultUrl, this.token = ''});

  CorsProxySettings copyWith({bool? enabled, String? url, String? token}) =>
      CorsProxySettings(enabled: enabled ?? this.enabled, url: url ?? this.url, token: token ?? this.token);

  /// [text] as the base address of a proxy (`localhost:8787` means `http://localhost:8787`); null when it is not one. A path,
  /// a query and a `user:password@` part are dropped.
  static Uri? parseUrl(String text) {
    var t = text.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    if (!t.contains('://')) t = 'http://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  Uri? get baseUri => parseUrl(url);

  /// What is wrong with the address, null when it is usable.
  String? get urlProblem => baseUri == null ? 'Enter the address the proxy printed, for example ${CorsProxyProtocol.defaultUrl}.' : null;

  /// What is wrong with the token, null when it is usable. It travels in a header, which holds visible ASCII only: anything
  /// else would make the browser refuse the call, and that is reported as "the proxy did not answer".
  String? get tokenProblem {
    final t = token.trim();
    if (t.isEmpty || RegExp(r'^[\x21-\x7e]+$').hasMatch(t)) return null;
    return 'The token may only contain visible ASCII characters, without spaces. Paste it exactly as the proxy printed it.';
  }

  /// The route requests take, null while the proxy is off or its address cannot be used.
  CorsProxyRoute? get route {
    final base = baseUri;
    return enabled && base != null ? CorsProxyRoute(base, token.trim()) : null;
  }

  @override
  bool operator ==(Object other) => other is CorsProxySettings && other.enabled == enabled && other.url == url && other.token == token;

  @override
  int get hashCode => Object.hash(enabled, url, token);
}
