import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/cors_proxy_engine.dart';

/// The desktop side of the CORS proxy: starts and stops the same engine `postpilot proxy` runs, so a person with the app needs
/// no terminal. One for the whole session: the proxy keeps answering after its dialog is closed.
final class CorsProxyServerViewModel extends ChangeNotifier {
  /// How many finished calls are kept for the list in the dialog.
  static const maxEvents = 200;

  final CorsProxyEngine Function() _engineFactory;
  final bool _supported;

  /// [engineFactory] and [supported] replace the real engine, for a test.
  CorsProxyServerViewModel({CorsProxyEngine Function()? engineFactory, bool? supported})
      : _engineFactory = engineFactory ?? CorsProxyEngine.create,
        _supported = supported ?? CorsProxyEngine.isSupported;

  /// False in a browser, which cannot listen on a port.
  bool get isSupported => _supported;

  String portText = '${CorsProxyProtocol.defaultPort}';
  String originsText = '';
  bool allowLan = false;
  bool insecure = false;

  /// The secret of this session's proxy; kept when it is stopped and started again, so what the web app holds stays right.
  String token = CorsProxyToken.generate();

  CorsProxyEngine? _engine;
  StreamSubscription<CorsProxyEvent>? _events;
  CorsProxyConfig? _running;
  bool _busy = false;
  bool _disposed = false;

  /// What kept the proxy from starting, null when nothing did.
  String? error;

  /// The newest call first.
  final List<CorsProxyEvent> events = [];

  bool get isRunning => _running != null;
  bool get isBusy => _busy;
  int? get port => _engine?.port;
  CorsProxyConfig? get runningConfig => _running;

  /// What to paste into the web app's Proxy URL field.
  String get url => 'http://localhost:${port ?? portText}';

  void update({String? port, String? origins, bool? allowLan, bool? insecure}) {
    if (isRunning) return;
    portText = port ?? portText;
    originsText = origins ?? originsText;
    this.allowLan = allowLan ?? this.allowLan;
    this.insecure = insecure ?? this.insecure;
    error = null;
    notifyListeners();
  }

  /// A new token for the next start; the web app needs it pasted again.
  void newToken() {
    if (isRunning) return;
    token = CorsProxyToken.generate();
    notifyListeners();
  }

  Future<void> start() async {
    if (isRunning || _busy || !_supported) return;
    final port = int.tryParse(portText.trim());
    if (port == null || port < 0 || port > 65535) {
      error = 'The port must be a whole number from 0 to 65535 (0 picks a free one).';
      notifyListeners();
      return;
    }
    final origins = CorsProxyOrigins.parseList(originsText);
    if (origins.error != null) {
      error = origins.error;
      notifyListeners();
      return;
    }
    final config = CorsProxyConfig(
      token: token,
      host: allowLan ? CorsProxyConfig.allInterfaces : CorsProxyConfig.loopbackHost,
      port: port,
      allowedOrigins: origins.origins,
      insecure: insecure,
    );
    _busy = true;
    error = null;
    notifyListeners();
    final engine = _engine ??= _engineFactory();
    try {
      await engine.start(config);
      _running = config;
      events.clear();
      // Cancelling a subscription to a broadcast stream finishes at once; there is nothing to wait for.
      unawaited(_events?.cancel());
      _events = engine.events.listen(_onEvent);
    } on StateError catch (e) {
      error = e.message;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!isRunning || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      unawaited(_events?.cancel());
      _events = null;
      await _engine?.stop();
      _running = null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _onEvent(CorsProxyEvent event) {
    events.insert(0, event);
    if (events.length > maxEvents) events.removeRange(maxEvents, events.length);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    unawaited(_engine?.dispose());
    super.dispose();
  }
}
