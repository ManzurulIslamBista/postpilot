import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_http_response.dart';
import '../../../core/utils/variable_resolver.dart';
import '../../documentation/domain/services/secret_masker.dart';
import '../data/realtime_session.dart';
import '../domain/services/realtime_url.dart';

enum RealtimeMode { webSocket, sse }

enum RealtimeStatus { disconnected, connecting, connected }

/// Backs the realtime tester: the connection settings, the live state and the message log.
final class RealtimeViewModel with ChangeNotifier {
  static const _logLimit = 2000;

  final RealtimeConnector _connector;

  /// Resolves `{{variables}}` (the active environment, globals) in the URL and headers.
  final Future<VariableResolver> Function() _resolver;

  /// How long a connection may take to open before it is given up on.
  final Duration connectTimeout;

  RealtimeViewModel(this._connector, this._resolver, {this.connectTimeout = const Duration(seconds: 30)});

  RealtimeMode mode = RealtimeMode.webSocket;
  String url = '';
  String headersText = '';
  String protocolsText = '';

  RealtimeStatus status = RealtimeStatus.disconnected;
  String? error;
  final List<RealtimeMessage> messages = [];
  int sent = 0;
  int received = 0;

  RealtimeSession? _session;
  StreamSubscription<RealtimeMessage>? _sub;
  bool _disposed = false;

  /// The attempt in progress; replaced or cleared when it ends or is cancelled, so
  /// a late answer from an old attempt can tell it is no longer wanted.
  ApiCancelToken? _attempt;

  bool get isConnected => status == RealtimeStatus.connected;
  bool get isConnecting => status == RealtimeStatus.connecting;
  bool get canSend => isConnected && mode == RealtimeMode.webSocket;

  /// False in a browser, where an event stream cannot be read as it arrives.
  bool get sseSupported => _connector.supportsLiveSse;

  void setMode(RealtimeMode value) {
    if (isConnected || isConnecting) return;
    if (value == RealtimeMode.sse && !sseSupported) {
      error = RealtimeConnector.sseUnsupportedMessage;
      notifyListeners();
      return;
    }
    mode = value;
    notifyListeners();
  }

  Future<void> connect() async {
    if (status != RealtimeStatus.disconnected) return;
    if (mode == RealtimeMode.sse && !sseSupported) {
      error = RealtimeConnector.sseUnsupportedMessage;
      notifyListeners();
      return;
    }
    // Claimed before anything is awaited: a second click (or Enter) while the variables
    // load would otherwise open a second socket.
    status = RealtimeStatus.connecting;
    error = null;
    final attempt = _attempt = ApiCancelToken();
    notifyListeners();
    // Cancelled, replaced by a newer attempt, or the view model is gone.
    bool abandoned() => _disposed || !identical(_attempt, attempt);
    try {
      final resolver = await _resolver();
      if (abandoned()) return;
      final resolvedUrl = resolver.resolve(url);
      final uri = mode == RealtimeMode.webSocket ? RealtimeUrl.forWebSocket(resolvedUrl) : RealtimeUrl.forSse(resolvedUrl);
      if (uri == null) {
        status = RealtimeStatus.disconnected;
        _attempt = null;
        error = mode == RealtimeMode.webSocket
            ? 'Enter a WebSocket URL such as wss://example.com/socket'
            : 'Enter an event stream URL such as https://example.com/events';
        notifyListeners();
        return;
      }
      // A token in the query (`?token=...`) must not end up in a log that gets pasted into a bug report.
      _log(RealtimeDirection.system, 'Connecting to ${SecretMasker.maskUrl('$uri')} …');
      notifyListeners();
      final headers = resolver.resolveMap(RealtimeUrl.parseHeaders(headersText));
      final pending = mode == RealtimeMode.webSocket
          ? _connector.connectWebSocket(
              uri,
              headers: headers,
              protocols: RealtimeUrl.parseProtocols(resolver.resolve(protocolsText)),
              cancel: attempt,
            )
          : _connector.connectSse(uri, headers: headers, cancel: attempt);
      final RealtimeSession session;
      try {
        session = await Future.any<RealtimeSession>([
          pending,
          attempt.whenCancelled.then<RealtimeSession>((_) => throw const _AttemptCancelled()),
        ]).timeout(connectTimeout);
      } on TimeoutException {
        attempt.cancel();
        unawaited(pending.then((opened) => opened.close(), onError: (Object _) {}));
        final seconds = connectTimeout.inSeconds;
        throw StateError(
          'The server did not answer within ${seconds == 1 ? '1 second' : '$seconds seconds'}. '
          'Check the address and that the server is running.',
        );
      } catch (_) {
        // Cancelled or failed: whatever the attempt still manages to open is closed, not left running.
        unawaited(pending.then((opened) => opened.close(), onError: (Object _) {}));
        rethrow;
      }
      if (abandoned()) {
        await session.close();
        return;
      }
      _attempt = null;
      _session = session;
      status = RealtimeStatus.connected;
      _log(RealtimeDirection.system, 'Connected');
      _sub = session.messages.listen((m) {
        _add(m);
        if (m.direction == RealtimeDirection.incoming) received++;
        notifyListeners();
      });
      unawaited(session.done.then((_) {
        if (_disposed || !identical(_session, session)) return;
        status = RealtimeStatus.disconnected;
        _session = null;
        _sub?.cancel();
        notifyListeners();
      }));
    } catch (e) {
      // A cancelled attempt was already reported by disconnect().
      if (abandoned()) return;
      _attempt = null;
      status = RealtimeStatus.disconnected;
      error = _describe(e);
      _log(RealtimeDirection.system, 'Failed: $error');
    }
    notifyListeners();
  }

  /// What is shown to the user. A socket error quotes the URL, query token included, so it is masked.
  String _describe(Object e) {
    final text = SecretMasker.maskMessage(e.toString());
    if (text.contains('was not upgraded to websocket')) {
      return 'The server did not accept the WebSocket upgrade. Check the path and that it is a WebSocket endpoint.';
    }
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('Connection refused')) {
      return "Can't reach the server. Check the address and that it is running.";
    }
    return text.replaceFirst(RegExp(r'^(Bad state|StateError|Exception|Unsupported operation): '), '');
  }

  /// Closes the connection, or gives up on one that is still being opened.
  Future<void> disconnect() async {
    if (isConnecting) {
      _attempt?.cancel();
      _attempt = null;
      status = RealtimeStatus.disconnected;
      _log(RealtimeDirection.system, 'Connection attempt cancelled');
      notifyListeners();
      return;
    }
    final session = _session;
    if (session == null) return;
    await session.close();
    status = RealtimeStatus.disconnected;
    _session = null;
    await _sub?.cancel();
    _log(RealtimeDirection.system, 'Disconnected');
    notifyListeners();
  }

  void send(String text) {
    final session = _session;
    if (session == null || !canSend || text.isEmpty) return;
    try {
      session.send(text);
      sent++;
    } catch (e) {
      error = _describe(e);
    }
    notifyListeners();
  }

  void clear() {
    messages.clear();
    sent = 0;
    received = 0;
    notifyListeners();
  }

  /// The log as plain text, for pasting into a bug report. Credentials are masked, in
  /// URLs and in the text of the messages, whatever the screen shows.
  String exportLog() {
    String two(int n) => n.toString().padLeft(2, '0');
    return messages.map((m) {
      final t = m.at;
      final arrow = switch (m.direction) {
        RealtimeDirection.incoming => '<-',
        RealtimeDirection.outgoing => '->',
        RealtimeDirection.system => '--',
      };
      final text = m.direction == RealtimeDirection.system ? SecretMasker.maskMessage(m.text) : SecretMasker.maskBody(m.text);
      return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} $arrow ${m.label.isEmpty ? '' : '[${m.label}] '}$text';
    }).join('\n');
  }

  void _log(RealtimeDirection direction, String text) => _add(RealtimeMessage(DateTime.now(), direction, text));

  void _add(RealtimeMessage m) {
    // What a session reports about itself can quote the URL ("Error: ... wss://host/ws?token=...").
    if (m.direction == RealtimeDirection.system) {
      m = RealtimeMessage(m.at, m.direction, SecretMasker.maskMessage(m.text), label: m.label);
    }
    messages.add(m);
    if (messages.length > _logLimit) messages.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _attempt?.cancel();
    _sub?.cancel();
    _session?.close();
    super.dispose();
  }
}

/// Thrown into a connection attempt that the user cancelled.
final class _AttemptCancelled implements Exception {
  const _AttemptCancelled();
}
