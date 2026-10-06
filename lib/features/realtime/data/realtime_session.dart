import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/network/api_http_response.dart';
import '../domain/services/sse_parser.dart';
import 'ws_connect_stub.dart' if (dart.library.io) 'ws_connect_io.dart' as ws;

enum RealtimeDirection { incoming, outgoing, system }

/// One line of the message log.
final class RealtimeMessage {
  final DateTime at;
  final RealtimeDirection direction;
  final String text;

  /// The event name of a Server-Sent Event, empty for WebSocket frames.
  final String label;
  const RealtimeMessage(this.at, this.direction, this.text, {this.label = ''});
}

/// A live connection: a stream of what arrives, and a way to send and close.
abstract interface class RealtimeSession {
  Stream<RealtimeMessage> get messages;

  /// Completes when the connection ends, by either side.
  Future<void> get done;
  void send(String text);
  Future<void> close();
}

/// Opens connections. WebSocket frames go through `web_socket_channel`
/// (custom headers only where the platform allows them: not in a browser);
/// Server-Sent Events are read as a streamed HTTP response.
final class RealtimeConnector {
  /// Whether a Server-Sent Events stream can be read as it arrives. In a browser
  /// the request layer (XMLHttpRequest through Dio) only hands over a response
  /// when it has ended, and an event stream never does, so no event would show up.
  final bool supportsLiveSse;

  const RealtimeConnector({this.supportsLiveSse = !kIsWeb});

  static const sseUnsupportedMessage = 'Server-Sent Events cannot be streamed live in the browser build: the browser only hands '
      'over a response once it has ended, and an event stream does not end. Use the desktop or mobile app for SSE.';

  /// [cancel] abandons the attempt while it is still connecting.
  Future<RealtimeSession> connectWebSocket(
    Uri uri, {
    Map<String, String> headers = const {},
    List<String> protocols = const [],
    ApiCancelToken? cancel,
  }) async {
    final (:channel, :abort) = ws.connect(uri, headers: headers, protocols: protocols);
    unawaited(cancel?.whenCancelled.then((_) async {
      abort();
      try {
        await channel.sink.close();
      } catch (_) {
        // Nothing to close if the attempt had already failed.
      }
    }));
    await channel.ready;
    return _WebSocketSession(channel);
  }

  Future<RealtimeSession> connectSse(
    Uri uri, {
    Map<String, String> headers = const {},
    String method = 'GET',
    String? body,
    Dio? dio,
    ApiCancelToken? cancel,
  }) async {
    if (!supportsLiveSse) throw UnsupportedError(sseUnsupportedMessage);
    final dioCancel = CancelToken();
    unawaited(cancel?.whenCancelled.then((_) => dioCancel.cancel('cancelled by the user')));
    final client = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: null, validateStatus: (_) => true));
    final response = await client.request<ResponseBody>(
      uri.toString(),
      data: body,
      cancelToken: dioCancel,
      options: Options(
        method: method,
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache', ...headers},
        validateStatus: (_) => true,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      dioCancel.cancel();
      throw StateError('The server answered $status ${response.statusMessage ?? ''}'.trim());
    }
    return _SseSession(response.data!, dioCancel, response.headers.value('content-type'));
  }
}

final class _WebSocketSession implements RealtimeSession {
  final WebSocketChannel _channel;
  final _controller = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();

  _WebSocketSession(this._channel) {
    _channel.stream.listen(
      (data) => _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.incoming, data is String ? data : 'binary frame, ${(data as List<int>).length} bytes: ${_preview(data)}')),
      onError: (Object e) => _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.system, 'Error: $e')),
      onDone: () {
        final code = _channel.closeCode;
        _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.system, 'Connection closed${code == null ? '' : ' (code $code${_channel.closeReason == null || _channel.closeReason!.isEmpty ? '' : ': ${_channel.closeReason}'})'}'));
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  static String _preview(List<int> bytes) => bytes.take(24).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  Stream<RealtimeMessage> get messages => _controller.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void send(String text) {
    _channel.sink.add(text);
    _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.outgoing, text));
  }

  @override
  Future<void> close() async {
    await _channel.sink.close(1000);
    if (!_done.isCompleted) _done.complete();
  }
}

final class _SseSession implements RealtimeSession {
  final CancelToken _cancel;
  final _controller = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();
  final _parser = SseParser();

  _SseSession(ResponseBody body, this._cancel, String? contentType) {
    if (contentType != null && !contentType.contains('text/event-stream')) {
      // A broadcast stream drops events nobody listens to yet; the owner subscribes right after construction.
      Timer(Duration.zero, () {
        if (!_controller.isClosed) {
          _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.system, 'Warning: the server sent "$contentType", not text/event-stream.'));
        }
      });
    }
    body.stream.cast<List<int>>().transform(utf8.decoder).listen(
      (chunk) {
        for (final e in _parser.add(chunk)) {
          _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.incoming, e.data, label: '${e.event}${e.id == null ? '' : ' #${e.id}'}'));
        }
      },
      onError: (Object e) {
        if (!_cancel.isCancelled) _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.system, 'Error: $e'));
        if (!_done.isCompleted) _done.complete();
      },
      onDone: () {
        _controller.add(RealtimeMessage(DateTime.now(), RealtimeDirection.system, 'Stream ended'));
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  @override
  Stream<RealtimeMessage> get messages => _controller.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void send(String text) => throw UnsupportedError('Server-Sent Events are one-way: the server sends, the client listens.');

  @override
  Future<void> close() async {
    _cancel.cancel('closed by the user');
    if (!_done.isCompleted) _done.complete();
  }
}
