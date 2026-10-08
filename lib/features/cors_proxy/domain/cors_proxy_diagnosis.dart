// Pure Dart: what "Test connection" tells the person, for every way the proxy can fail to be usable.
import 'cors_proxy_protocol.dart';

enum CorsProxyTestKind {
  connected,
  invalidUrl,
  notRunning,
  blocked,
  mixedContent,
  tokenMissing,
  tokenWrong,
  originNotAllowed,
  hostNotAllowed,
  notAProxy,
  timeout,
}

/// The outcome of a connection test: a short title and a sentence that says what is wrong and what to do.
final class CorsProxyTestResult {
  final CorsProxyTestKind kind;
  final String title;
  final String message;

  const CorsProxyTestResult(this.kind, this.title, this.message);

  bool get ok => kind == CorsProxyTestKind.connected;
}

abstract final class CorsProxyDiagnosis {
  static String _authority(Uri base) => base.hasPort ? '${base.host}:${base.port}' : base.host;

  static bool _isLoopbackHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '::1' || h.startsWith('127.');
  }

  static CorsProxyTestResult invalidUrl(String problem) => CorsProxyTestResult(CorsProxyTestKind.invalidUrl, 'The address is not valid', problem);

  static CorsProxyTestResult connected(Uri base, {String? version, String? allowedOrigin}) => CorsProxyTestResult(
        CorsProxyTestKind.connected,
        'Connected',
        'The CORS proxy at ${_authority(base)} answered'
            '${version == null ? '' : ' (protocol $version)'}'
            '${allowedOrigin == null ? '' : ' and allows this page ($allowedOrigin)'}. '
            'Switch it on and your calls go through it.',
      );

  /// What a server that answered the health check says, when it is not a working answer: [status] of the answer and, when it
  /// came from the proxy, its error [code].
  static CorsProxyTestResult refused(Uri base, int status, String? code, {String? pageOrigin}) {
    final where = _authority(base);
    switch (code) {
      case 'token_required':
        return CorsProxyTestResult(
          CorsProxyTestKind.tokenMissing,
          'The token is missing',
          'The proxy at $where is running but wants a token. Paste the one it printed when it started into the Token field.',
        );
      case 'token_invalid':
        return CorsProxyTestResult(
          CorsProxyTestKind.tokenWrong,
          'The token is wrong',
          'The proxy at $where is running but this token is not the one it printed when it started. A restarted proxy makes a '
              'new token unless you start it with --token. Paste the current one.',
        );
      case 'origin_not_allowed':
        final page = pageOrigin ?? 'this page';
        return CorsProxyTestResult(
          CorsProxyTestKind.originNotAllowed,
          'This page is not allowed',
          'The proxy at $where does not allow $page. Restart it with --allow-origin ${pageOrigin ?? '<this page\'s address>'}.',
        );
      case 'host_not_allowed':
        return CorsProxyTestResult(
          CorsProxyTestKind.hostNotAllowed,
          'The proxy does not answer to this address',
          'The proxy at $where only answers calls addressed to localhost or 127.0.0.1. Use one of those in the URL, or start it with --allow-lan.',
        );
    }
    return CorsProxyTestResult(
      CorsProxyTestKind.notAProxy,
      'That is not the PostPilot CORS proxy',
      'Something answered at $where with status $status, but not the way the CORS proxy does. Check the address and the port, '
          'then start the proxy with "${CorsProxyProtocol.command}".',
    );
  }

  static CorsProxyTestResult timedOut(Uri base) => CorsProxyTestResult(
        CorsProxyTestKind.timeout,
        'No answer in time',
        'The proxy at ${_authority(base)} did not answer within a few seconds. Check the address, and that no firewall or VPN '
            'sits between the browser and the proxy.',
      );

  /// The check failed without an answer. [reachable] says whether anything listens at the address (a browser can find out
  /// with a `no-cors` request; null when this platform cannot tell). [pageOrigin] is where the app runs, in a browser.
  static CorsProxyTestResult unreachable(Uri base, {bool? reachable, String? pageOrigin}) {
    final where = _authority(base);
    final pageIsSecure = pageOrigin != null && pageOrigin.startsWith('https://');
    // `http://localhost` is exempt from the mixed-content rule in the browsers that matter; any other http address is not.
    if (pageIsSecure && base.scheme == 'http' && !_isLoopbackHost(base.host)) {
      return CorsProxyTestResult(
        CorsProxyTestKind.mixedContent,
        'The browser blocks an http:// proxy from an https:// page',
        'This page is served over https, so the browser refuses to call the proxy at $where over plain http. Open PostPilot '
            'from http://localhost instead, or put the proxy behind https.',
      );
    }
    if (reachable == true) {
      final page = pageOrigin ?? 'this page';
      return CorsProxyTestResult(
        CorsProxyTestKind.blocked,
        'The proxy is there, but the browser blocked its answer',
        'Something answers at $where, but the browser did not let the page read it. Most often the proxy does not allow $page: '
            'restart it with --allow-origin ${pageOrigin ?? '<this page\'s address>'}. Other causes: ${pageIsSecure ? 'an https page '
            'reaching an http proxy (Safari blocks that even for localhost), ' : ''}or a public page reaching a proxy on this '
            'computer, which Chrome only allows after you accept its "local network access" prompt.',
      );
    }
    return CorsProxyTestResult(
      CorsProxyTestKind.notRunning,
      'Nothing answers at that address',
      'Nothing is listening at $where. Start the proxy in a terminal with "${CorsProxyProtocol.command}", then press Test '
          'connection again. If it runs on another port, change the URL.',
    );
  }
}
