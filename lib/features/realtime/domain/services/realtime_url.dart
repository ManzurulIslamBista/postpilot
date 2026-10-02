/// Turns what the user typed into a URL the connection can use, and reads
/// headers typed one per line.
abstract final class RealtimeUrl {
  /// WebSocket: `http(s)` becomes `ws(s)`, and a bare host gets `ws://`
  /// (`wss://` for anything that is not local). Returns null for an empty or unreadable URL.
  static Uri? forWebSocket(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    var url = text;
    if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (!url.contains('://')) {
      url = '${_isLocal(url) ? 'ws' : 'wss'}://$url';
    }
    return _valid(Uri.tryParse(url), const {'ws', 'wss'});
  }

  /// SSE: a bare host gets `http://` when local and `https://` otherwise.
  static Uri? forSse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    var url = text;
    if (url.startsWith('ws://')) {
      url = 'http://${url.substring(5)}';
    } else if (url.startsWith('wss://')) {
      url = 'https://${url.substring(6)}';
    } else if (!url.contains('://')) {
      url = '${_isLocal(url) ? 'http' : 'https'}://$url';
    }
    return _valid(Uri.tryParse(url), const {'http', 'https'});
  }

  static bool _isLocal(String hostAndPath) => RegExp(r'^(localhost|127\.0\.0\.1|10\.|192\.168\.|\[::1\])', caseSensitive: false).hasMatch(hostAndPath);

  static Uri? _valid(Uri? uri, Set<String> schemes) =>
      uri != null && schemes.contains(uri.scheme) && uri.host.isNotEmpty ? uri : null;

  /// `Name: value` per line; blank lines and `#` comments are skipped.
  static Map<String, String> parseHeaders(String text) {
    final headers = <String, String>{};
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
    }
    return headers;
  }

  /// Sub-protocols typed with commas or spaces.
  static List<String> parseProtocols(String text) => text.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
}
