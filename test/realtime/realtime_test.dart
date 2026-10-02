import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/realtime/data/realtime_session.dart';
import 'package:postpilot/features/realtime/domain/services/realtime_url.dart';
import 'package:postpilot/features/realtime/domain/services/sse_parser.dart';
import 'package:postpilot/features/realtime/presentation/realtime_view_model.dart';

void main() {
  group('SseParser', () {
    test('parses events split across arbitrary chunks, with all four fields and comments', () {
      final p = SseParser();
      final events = <SseEvent>[];
      for (final chunk in [': hello\n', 'event: tick\nda', 'ta: 1\nid: 7\nretry: 3000\n\n', 'data: a\ndata: b\n', '\n', 'data: no newline yet']) {
        events.addAll(p.add(chunk));
      }
      expect(events, hasLength(2));
      expect(events[0].event, 'tick');
      expect(events[0].data, '1');
      expect(events[0].id, '7');
      expect(events[0].retryMs, 3000);
      expect(events[1].event, 'message');
      expect(events[1].data, 'a\nb');
    });

    test('handles CRLF and lone CR line ends, and a CRLF split across chunks', () {
      final p = SseParser();
      expect(p.add('data: x\r\n\r\n').single.data, 'x');
      expect(p.add('data: y\r\r').single.data, 'y');
      expect(p.add('data: z\r'), isEmpty);
      expect(p.add('\n\r\n').single.data, 'z', reason: 'the LF opening the next chunk belongs to the CR before it');
      expect(p.add('data: w\n\n').single.data, 'w');
    });

    test('a blank line without data sends nothing and resets the event name', () {
      final p = SseParser();
      expect(p.add('event: lonely\n\n'), isEmpty);
      expect(p.add('data: d\n\n').single.event, 'message');
    });

    test('field without a value and a value with a leading space', () {
      final p = SseParser();
      expect(p.add('data\n\n').single.data, '');
      expect(p.add('data:  two spaces\n\n').single.data, ' two spaces');
    });
  });

  group('RealtimeUrl', () {
    test('web socket URLs are normalised', () {
      expect(RealtimeUrl.forWebSocket('https://a.test/x')!.toString(), 'wss://a.test/x');
      expect(RealtimeUrl.forWebSocket('http://a.test')!.scheme, 'ws');
      expect(RealtimeUrl.forWebSocket('localhost:3000/ws')!.toString(), 'ws://localhost:3000/ws');
      expect(RealtimeUrl.forWebSocket('echo.websocket.org')!.scheme, 'wss');
      expect(RealtimeUrl.forWebSocket('192.168.1.5:8069/websocket')!.scheme, 'ws');
      expect(RealtimeUrl.forWebSocket(''), isNull);
      expect(RealtimeUrl.forWebSocket('ftp://a.test'), isNull);
    });

    test('SSE URLs are normalised', () {
      expect(RealtimeUrl.forSse('wss://a.test/e')!.toString(), 'https://a.test/e');
      expect(RealtimeUrl.forSse('localhost:3000/events')!.scheme, 'http');
      expect(RealtimeUrl.forSse('api.test/events')!.scheme, 'https');
    });

    test('headers and protocols', () {
      expect(RealtimeUrl.parseHeaders('Authorization: Bearer a:b\n# comment\n\nX-Id:1\nbroken'), {'Authorization': 'Bearer a:b', 'X-Id': '1'});
      expect(RealtimeUrl.parseProtocols('a, b  c'), ['a', 'b', 'c']);
    });
  });

  group('RealtimeViewModel against real servers', () {
    late HttpServer server;
    late RealtimeViewModel vm;

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(condition(), isTrue, reason: 'timed out waiting');
    }

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      vm = RealtimeViewModel(const RealtimeConnector(), () async => VariableResolver({'host': '127.0.0.1:${server.port}'}));
    });
    tearDown(() async {
      vm.dispose();
      await server.close(force: true);
    });

    test('WebSocket: connects, sends, receives, sees the server close', () async {
      final seenHeaders = <String?>[];
      server.listen((req) async {
        seenHeaders.add(req.headers.value('x-token'));
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((m) {
          socket.add('echo:$m');
          if (m == 'bye') socket.close(1000, 'done');
        });
      });
      vm
        ..url = '{{host}}/socket'
        ..headersText = 'X-Token: {{host}}';
      await vm.connect();
      expect(vm.isConnected, isTrue, reason: vm.error);
      vm.send('hello');
      await until(() => vm.received == 1);
      expect(vm.messages.any((m) => m.direction == RealtimeDirection.outgoing && m.text == 'hello'), isTrue);
      expect(vm.messages.any((m) => m.direction == RealtimeDirection.incoming && m.text == 'echo:hello'), isTrue);
      expect(seenHeaders.single, '127.0.0.1:${server.port}', reason: 'headers are sent with {{variables}} resolved');
      vm.send('bye');
      await until(() => vm.status == RealtimeStatus.disconnected);
      expect(vm.messages.last.text, contains('Connection closed (code 1000: done)'));
      expect(vm.exportLog(), contains('-> hello'));
    });

    test('WebSocket: a server that is not a socket gives a readable error', () async {
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..write('plain http')
          ..close();
      });
      vm.url = '{{host}}';
      await vm.connect();
      expect(vm.isConnected, isFalse);
      expect(vm.error, isNotNull);
      expect(vm.status, RealtimeStatus.disconnected);
    });

    test('SSE: streams events as they are written, then ends', () async {
      server.listen((req) async {
        req.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..bufferOutput = false;
        req.response.write('event: greet\ndata: {"n":1}\n\n');
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        req.response.write('data: two\nid: 9\n\n');
        await req.response.flush();
        await req.response.close();
      });
      vm
        ..setMode(RealtimeMode.sse)
        ..url = 'http://{{host}}/events';
      await vm.connect();
      await until(() => vm.received == 2);
      final labels = vm.messages.where((m) => m.direction == RealtimeDirection.incoming).map((m) => '${m.label}|${m.text}').toList();
      expect(labels, ['greet|{"n":1}', 'message #9|two']);
      await until(() => vm.status == RealtimeStatus.disconnected);
      expect(vm.messages.last.text, 'Stream ended');
    });

    test('SSE: a non-2xx answer is an error, not a connection', () async {
      server.listen((req) => req.response
        ..statusCode = 403
        ..close());
      vm
        ..setMode(RealtimeMode.sse)
        ..url = 'http://{{host}}/x';
      await vm.connect();
      expect(vm.isConnected, isFalse);
      expect(vm.error, contains('403'));
    });

    test('an empty URL is reported without connecting; sending when disconnected is ignored', () async {
      await vm.connect();
      expect(vm.error, contains('WebSocket URL'));
      vm.send('x');
      expect(vm.sent, 0);
    });
  });
}
