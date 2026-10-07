// Pure Dart (shared by the dart:io engine and its tests).

/// The header rules of a reverse proxy: what is dropped on each hop, what is rewritten so the upstream accepts a call that
/// was addressed to the recorder.
abstract final class RecorderHeaders {
  /// RFC 9110 section 7.6.1: meaningful for one connection only, so never passed on.
  static const hopByHop = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'proxy-connection',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };

  /// A request header the recorder does not copy: hop-by-hop ones, `Host` (set from the upstream address or rewritten),
  /// `Content-Length` (set from the body that is streamed) and `Expect` (the recorder already answered the `100`).
  static bool dropFromRequest(String lowerName) =>
      hopByHop.contains(lowerName) || lowerName == 'host' || lowerName == 'content-length' || lowerName == 'expect';

  /// A response header the recorder does not copy; the framing (`Content-Length` / chunked) is rebuilt from the body it
  /// streams.
  static bool dropFromResponse(String lowerName) => hopByHop.contains(lowerName) || lowerName == 'content-length';

  /// [value] of `Accept-Encoding` without the codings the recorder cannot inflate for its recording (brotli, zstd, the `*`
  /// wildcard that lets the server pick one of them). Nothing left means only `identity`. The compressed answer the app
  /// receives is unchanged; this only decides what the upstream is asked for.
  static String readableAcceptEncoding(String value) {
    final kept = <String>[];
    for (final part in value.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final coding = token.split(';').first.trim().toLowerCase();
      if (coding == 'gzip' || coding == 'x-gzip' || coding == 'deflate' || coding == 'identity') kept.add(token);
    }
    return kept.isEmpty ? 'identity' : kept.join(', ');
  }

  /// `host[:port]` as a `Host` header writes it (the port is left out when it is the scheme's default).
  static String authorityOf(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    return uri.hasPort && uri.port != defaultPort ? '$host:${uri.port}' : host;
  }

  /// `scheme://host[:port]` of [uri].
  static String originOf(Uri uri) => '${uri.scheme}://${authorityOf(uri)}';

  /// The address a request for [target] (`/users?page=2`, as the app wrote it) is forwarded to: the upstream's origin and
  /// path prefix, then the target. Throws a [FormatException] for a target that cannot be an address.
  static Uri upstreamUri(Uri upstream, String target) {
    final prefix = upstream.path.replaceAll(RegExp(r'/+$'), '');
    final path = target.startsWith('/') ? target : '/$target';
    return Uri.parse('${originOf(upstream)}$prefix$path');
  }

  /// A hostname or address that names this computer or a device on a private network: what an app writes when it talks
  /// to a server on the developer's machine (`localhost`, `10.0.2.2` of the Android emulator, `192.168.x.x`).
  static bool isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h.endsWith('.local') || h.endsWith('.localhost')) return true;
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final n = [for (final p in parts) int.tryParse(p)];
    if (n.any((p) => p == null || p < 0 || p > 255)) return false;
    final a = n[0]!, b = n[1]!;
    return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Whether [address] (`http://10.0.2.2:8099`, from an `Origin` or `Referer` header) is the recorder itself: the address
  /// the app used in its `Host` header, or this computer or a private-network address on the recorder's [localPort].
  static bool isRecorderAddress(Uri address, {String? hostHeader, required int localPort}) {
    if (address.host.isEmpty) return false;
    if (hostHeader != null && address.hasAuthority && authorityOf(address).toLowerCase() == hostHeader.toLowerCase()) return true;
    final port = address.hasPort ? address.port : (address.scheme == 'https' ? 443 : 80);
    return port == localPort && isLocalHost(address.host);
  }

  /// The `Origin` or `Referer` [value] the upstream should see: the recorder's own address becomes the upstream's. Any
  /// other value (a web app's real origin, `null`) is left alone, so CORS checks that name that origin still pass.
  static String rewriteOriginLike(String value, {required Uri upstream, String? hostHeader, required int localPort}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !isRecorderAddress(uri, hostHeader: hostHeader, localPort: localPort)) return value;
    final rest = value.trim().substring('${uri.scheme}://${uri.authority}'.length);
    return '${originOf(upstream)}$rest';
  }
}
