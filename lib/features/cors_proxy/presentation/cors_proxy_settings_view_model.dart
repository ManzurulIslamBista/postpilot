import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/cors_proxy_settings_store.dart';
import '../data/cors_proxy_tester.dart';
import '../data/cors_reachability.dart';
import '../domain/cors_proxy_diagnosis.dart';
import '../domain/cors_proxy_protocol.dart';
import '../domain/cors_proxy_settings.dart';

/// The web app's side of the CORS proxy: whether it is on, where it is, its token, and a connection test. One for the whole
/// session: the HTTP client asks it for the route of every call.
final class CorsProxySettingsViewModel extends ChangeNotifier {
  final CorsProxySettingsStore _store;
  final CorsProxyTester _tester;

  /// Where the app runs (`https://app.example.com`), in a browser; null elsewhere.
  final String? pageOrigin;

  CorsProxySettingsViewModel(this._store, {CorsProxyTester? tester, String? pageOrigin})
      : pageOrigin = pageOrigin ?? currentPageOrigin(),
        _tester = tester ?? CorsProxyTester(pageOrigin: pageOrigin ?? currentPageOrigin());

  CorsProxySettings settings = const CorsProxySettings();
  CorsProxyTestResult? testResult;
  bool testing = false;
  bool _disposed = false;
  Future<void>? _loading;

  /// Loads the saved choices once; later calls return the same future.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    settings = await _store.load();
    if (!_disposed) notifyListeners();
  }

  /// The route the next call takes: null while the proxy is off. Waits for the saved choices, so the first call after a
  /// start does not go out before they are known.
  Future<CorsProxyRoute?> route() async {
    await load();
    return settings.route;
  }

  void setEnabled(bool enabled) {
    if (settings.enabled == enabled) return;
    settings = settings.copyWith(enabled: enabled);
    unawaited(_store.saveEnabled(enabled));
    _changed();
  }

  void setUrl(String url) {
    if (settings.url == url) return;
    settings = settings.copyWith(url: url);
    unawaited(_store.saveUrl(url));
    _changed();
  }

  void setToken(String token) {
    if (settings.token == token) return;
    settings = settings.copyWith(token: token);
    unawaited(_store.saveToken(token));
    _changed();
  }

  /// A new random token, to start the proxy with (`--token`) so there is nothing to copy back from the terminal.
  void generateToken() => setToken(CorsProxyToken.generate());

  /// What to type to start the proxy for this page: it allows this page's own address when that is not on this computer.
  String command({bool withToken = false}) {
    final origin = pageOrigin;
    final needsOrigin = origin != null && !CorsProxyOrigins.isLoopback(origin);
    final token = settings.token.trim();
    return [
      CorsProxyProtocol.command,
      if (needsOrigin) '--allow-origin $origin',
      // Typed into a shell as it is, so a token with a `;` or `$(` in it is not put into the command.
      if (withToken && token.isNotEmpty && CorsProxyToken.isShellSafe(token) && CorsProxyToken.problem(token) == null) '--token $token',
    ].join(' ');
  }

  Future<void> test() async {
    if (testing) return;
    testing = true;
    testResult = null;
    notifyListeners();
    final tested = settings;
    try {
      final result = await _tester.run(tested);
      // The choices were edited while the test ran: its result is about the old ones.
      if (identical(tested, settings)) testResult = result;
    } finally {
      testing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _changed() {
    // A result belongs to the choices it was made with.
    testResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
