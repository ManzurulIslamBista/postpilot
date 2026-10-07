// Pure Dart: shared by the engine, the dialog and the command line entry.

/// How a recorder listens and where it forwards to.
final class RecorderConfig {
  /// The server the app really talks to (`https://api.example.com`, a path prefix such as `/v2` is kept).
  final Uri upstream;

  /// The address to listen on: `127.0.0.1` (this computer only) or `0.0.0.0` (every network interface, so a phone on the
  /// same Wi-Fi or an emulator can reach it).
  final String host;

  /// 0 picks a free port.
  final int port;

  /// Accept the upstream's TLS certificate even when it is self-signed or expired. Only for the upstream host.
  final bool allowSelfSigned;

  /// Send the upstream's own address in `Host`, and swap the recorder's address for the upstream's in `Origin` and
  /// `Referer`, so a server that checks them accepts the call.
  final bool rewriteHostHeaders;

  /// Ask the upstream for gzip or no compression instead of brotli, which the recorder cannot inflate for its recording.
  /// What the upstream answers is still passed on untouched.
  final bool keepResponsesReadable;

  /// Reach the upstream through the proxy named by `HTTP_PROXY` / `HTTPS_PROXY` instead of directly.
  final bool useSystemProxy;

  /// How long to wait for the upstream to connect, and how long it may stay silent while answering.
  final Duration connectTimeout;
  final Duration timeout;

  /// How much of each body is kept for the recording; the app and the upstream always get the whole body.
  final int maxBodyBytes;

  const RecorderConfig({
    required this.upstream,
    this.host = loopbackHost,
    this.port = 0,
    this.allowSelfSigned = false,
    this.rewriteHostHeaders = true,
    this.keepResponsesReadable = true,
    this.useSystemProxy = false,
    this.connectTimeout = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 60),
    this.maxBodyBytes = defaultMaxBodyBytes,
  });

  static const loopbackHost = '127.0.0.1';
  static const allInterfaces = '0.0.0.0';
  static const defaultMaxBodyBytes = 512 * 1024;

  /// Listens on every network interface (a device other than this computer can connect).
  bool get listensOnAllInterfaces => host == allInterfaces || host == '::';

  /// A reason this configuration cannot be started, null when it can.
  String? get problem {
    final bad = upstreamProblem(upstream.toString());
    if (bad != null) return bad;
    if (port < 0 || port > 65535) return 'The port must be between 1 and 65535 (0 picks a free one).';
    return null;
  }

  /// The upstream [text] as typed (`api.example.com`, `https://api.example.com/v2/`) as a base address; null when it is
  /// not one. A missing scheme means https. A query, a fragment and a `user:password@` part are dropped: none can be
  /// part of a base address (the app sends its own credentials).
  static Uri? parseUpstream(String text) {
    var t = text.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    if (!t.contains('://')) t = 'https://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceAll(RegExp(r'/+$'), ''),
    );
  }

  /// What is wrong with the upstream [text], null when it is usable.
  static String? upstreamProblem(String text) {
    if (text.trim().isEmpty) return 'Enter the address of the server your app talks to, for example https://api.example.com.';
    if (text.trim().contains('{{')) return 'The upstream must be a real address, not a {{variable}}. Paste the resolved URL.';
    if (parseUpstream(text) == null) {
      return 'That is not an http:// or https:// address. Use something like https://api.example.com.';
    }
    return null;
  }
}
