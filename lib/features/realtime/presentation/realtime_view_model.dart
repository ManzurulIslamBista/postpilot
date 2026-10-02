import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/utils/variable_resolver.dart';
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

  RealtimeViewModel(this._connector, this._resolver);

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

  bool get isConnected => status == RealtimeStatus.connected;
  bool get canSend => isConnected && mode == RealtimeMode.webSocket;

  void setMode(RealtimeMode value) {
    if (isConnected || status == RealtimeStatus.connecting) return;
    mode = value;
    notifyListeners();
  }

  Future<void> connect() async {
    if (status != RealtimeStatus.disconnected) return;
    final resolver = await _resolver();
    final resolvedUrl = resolver.resolve(url);
    final uri = mode == RealtimeMode.webSocket ? RealtimeUrl.forWebSocket(resolvedUrl) : RealtimeUrl.forSse(resolvedUrl);
    if (uri == null) {
      error = mode == RealtimeMode.webSocket
          ? 'Enter a WebSocket URL such as wss://example.com/socket'
          : 'Enter an event stream URL such as https://example.com/events';
      notifyListeners();
      return;
    }
    status = RealtimeStatus.connecting;
    error = null;
    _log(RealtimeDirection.system, 'Connecting to $uri …');
    notifyListeners();
    try {
      final headers = resolver.resolveMap(RealtimeUrl.parseHeaders(headersText));
      final session = mode == RealtimeMode.webSocket
          ? await _connector.connectWebSocket(uri, headers: headers, protocols: RealtimeUrl.parseProtocols(resolver.resolve(protocolsText)))
          : await _connector.connectSse(uri, headers: headers);
      if (_disposed) {
        await session.close();
        return;
      }
      _session = session;
      status = RealtimeStatus.connected;
      _log(RealtimeDirection.system, 'Connected');
      _sub = session.messages.listen((m) {
        _add(m);
        if (m.direction == RealtimeDirection.incoming) received++;
        notifyListeners();
      });
      unawaited(session.done.then((_) {
        if (_disposed) return;
        status = RealtimeStatus.disconnected;
        _session = null;
        _sub?.cancel();
        notifyListeners();
      }));
    } catch (e) {
      status = RealtimeStatus.disconnected;
      error = _describe(e);
      _log(RealtimeDirection.system, 'Failed: $error');
    }
    notifyListeners();
  }

  String _describe(Object e) {
    final text = e.toString();
    if (text.contains('was not upgraded to websocket')) {
      return 'The server did not accept the WebSocket upgrade. Check the path and that it is a WebSocket endpoint.';
    }
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('Connection refused')) {
      return "Can't reach the server. Check the address and that it is running.";
    }
    return text.replaceFirst(RegExp(r'^(Bad state|StateError|Exception): '), '');
  }

  Future<void> disconnect() async {
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

  /// The log as plain text, for pasting into a bug report.
  String exportLog() {
    String two(int n) => n.toString().padLeft(2, '0');
    return messages.map((m) {
      final t = m.at;
      final arrow = switch (m.direction) {
        RealtimeDirection.incoming => '<-',
        RealtimeDirection.outgoing => '->',
        RealtimeDirection.system => '--',
      };
      return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} $arrow ${m.label.isEmpty ? '' : '[${m.label}] '}${m.text}';
    }).join('\n');
  }

  void _log(RealtimeDirection direction, String text) => _add(RealtimeMessage(DateTime.now(), direction, text));

  void _add(RealtimeMessage m) {
    messages.add(m);
    if (messages.length > _logLimit) messages.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _session?.close();
    super.dispose();
  }
}
