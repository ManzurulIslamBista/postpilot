import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/realtime/data/realtime_session.dart';
import 'package:postpilot/features/realtime/presentation/realtime_view_model.dart';

const _secret = 'SECRETtoken123abc';
const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlc2lnbmF0dXJl';

void main() {
  late HttpServer server;
  late RealtimeViewModel vm;
  final held = <HttpRequest>[];

  Future<void> until(bool Function() condition, {String reason = 'timed out waiting'}) async {
    for (var i = 0; i < 150 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: reason);
  }

  VariableResolver resolver() => VariableResolver({'host': '127.0.0.1:${server.port}'});

  setUp(() async {
    held.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    vm = RealtimeViewModel(const RealtimeConnector(), () async => resolver());
  });
  tearDown(() async {
    vm.dispose();
    await server.close(force: true);
  });

  group('connecting', () {
    test('a second click while the first is still starting opens no second socket', () async {
      var upgrades = 0;
      server.listen((req) async {
        upgrades++;
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((_) {});
      });
      final gate = Completer<void>();
      vm.dispose();
      // The variables take a moment to load: the window in which a second click used to get through.
      vm = RealtimeViewModel(const RealtimeConnector(), () async {
        await gate.future;
        return resolver();
      })
        ..url = '{{host}}/socket';

      final first = vm.connect();
      expect(vm.status, RealtimeStatus.connecting, reason: 'claimed before anything is awaited');
      final second = vm.connect();
      vm.connect().ignore();
      gate.complete();
      await Future.wait([first, second]);
      expect(vm.isConnected, isTrue, reason: vm.error);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(upgrades, 1);
    });

    test('Cancel works while connecting: the state is reset at once and the connection is dropped', () async {
      // A bare socket, so the test can see the moment the client lets go of the connection.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final accepted = <Socket>[];
      final dropped = Completer<void>();
      void gone() {
        if (!dropped.isCompleted) dropped.complete();
      }

      raw.listen((socket) {
        accepted.add(socket);
        socket.listen((_) {}, onDone: gone, onError: (Object _) => gone());
      });
      vm.dispose();
      vm = RealtimeViewModel(const RealtimeConnector(), () async => VariableResolver({'raw': '127.0.0.1:${raw.port}'}))..url = '{{raw}}/socket';
      final attempt = vm.connect();
      await until(() => accepted.isNotEmpty, reason: 'the handshake reached the server');
      expect(vm.status, RealtimeStatus.connecting);

      await vm.disconnect();
      expect(vm.status, RealtimeStatus.disconnected);
      expect(vm.messages.last.text, 'Connection attempt cancelled');
      await attempt.timeout(const Duration(seconds: 5));
      expect(vm.error, isNull, reason: 'cancelling is not a failure');
      expect(vm.status, RealtimeStatus.disconnected);
      await dropped.future.timeout(const Duration(seconds: 5), onTimeout: () => fail('the client never closed the connection'));
      for (final socket in accepted) {
        socket.destroy();
      }
    });

    test('Cancel also aborts an event-stream request that has no answer yet', () async {
      // A bare socket, so the test can see the moment the client lets go of the connection.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final accepted = <Socket>[];
      final dropped = Completer<void>();
      void gone() {
        if (!dropped.isCompleted) dropped.complete();
      }

      raw.listen((socket) {
        accepted.add(socket);
        socket.listen((_) {}, onDone: gone, onError: (Object _) => gone());
      });
      vm.dispose();
      vm = RealtimeViewModel(const RealtimeConnector(), () async => VariableResolver({'raw': '127.0.0.1:${raw.port}'}))
        ..mode = RealtimeMode.sse
        ..url = 'http://{{raw}}/events';
      final attempt = vm.connect();
      await until(() => accepted.isNotEmpty, reason: 'the request reached the server');
      await vm.disconnect();
      await attempt.timeout(const Duration(seconds: 5));
      expect(vm.status, RealtimeStatus.disconnected);
      expect(vm.error, isNull);
      await dropped.future.timeout(const Duration(seconds: 5), onTimeout: () => fail('the client never closed the connection'));
      for (final socket in accepted) {
        socket.destroy();
      }
    });

    test('a new attempt right after a cancel is not confused with the old one', () async {
      server.listen((req) async {
        if (req.uri.path == '/slow') {
          held.add(req);
          return;
        }
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((_) {});
      });
      vm.url = '{{host}}/slow';
      final old = vm.connect();
      await until(() => held.isNotEmpty);
      await vm.disconnect();
      vm.url = '{{host}}/fast';
      await vm.connect();
      expect(vm.isConnected, isTrue, reason: vm.error);
      await old.timeout(const Duration(seconds: 5));
      expect(vm.isConnected, isTrue, reason: 'the old attempt ending must not undo the new connection');
      expect(vm.error, isNull);
    });

    test('a server that never answers is given up on after the timeout', () async {
      server.listen(held.add);
      vm.dispose();
      vm = RealtimeViewModel(const RealtimeConnector(), () async => resolver(), connectTimeout: const Duration(seconds: 1))..url = '{{host}}/socket';
      final started = DateTime.now();
      await vm.connect();
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 10)));
      expect(vm.status, RealtimeStatus.disconnected);
      expect(vm.error, contains('did not answer within 1 second'));
      expect(vm.messages.last.text, startsWith('Failed: The server did not answer'));
    });

    test('a failing variable lookup ends the attempt instead of leaving it "connecting"', () async {
      vm.dispose();
      vm = RealtimeViewModel(const RealtimeConnector(), () async => throw StateError('no environment'))..url = 'a.test/socket';
      await vm.connect();
      expect(vm.status, RealtimeStatus.disconnected);
      expect(vm.error, 'no environment');
    });
  });

  group('secrets', () {
    test('the log, the error and the exported text never carry the token of the URL or of a message', () async {
      server.listen((req) async {
        final socket = await WebSocketTransformer.upgrade(req);
        socket.add('{"token":"$_jwt","note":"hello"}');
        socket.listen((m) => socket.add(m));
      });
      vm.url = '{{host}}/socket?token=$_secret&room=7';
      await vm.connect();
      expect(vm.isConnected, isTrue, reason: vm.error);
      await until(() => vm.received == 1);
      vm.send('{"password":"hunter2hunter2","msg":"hi"}');
      await until(() => vm.received == 2);

      final shownLines = vm.messages.where((m) => m.direction == RealtimeDirection.system).map((m) => m.text).join('\n');
      expect(shownLines, contains('/socket?token=••••••&room=7'), reason: 'only the credential is hidden');
      expect(shownLines, isNot(contains(_secret)));

      final exported = vm.exportLog();
      expect(exported, isNot(contains(_secret)));
      expect(exported, isNot(contains(_jwt)));
      expect(exported, isNot(contains('hunter2hunter2')));
      expect(exported, contains('"note":"hello"'), reason: 'the rest of a message stays readable');
      expect(exported, contains('"msg":"hi"'));
      expect(exported, contains('room=7'));
    });

    test('an error that quotes the URL is masked too', () async {
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = server.port;
      await server.close(force: true);
      vm.url = '127.0.0.1:$closedPort/socket?token=$_secret';
      await vm.connect();
      expect(vm.isConnected, isFalse);
      final everything = '${vm.error}\n${vm.messages.map((m) => m.text).join('\n')}\n${vm.exportLog()}';
      expect(everything, isNot(contains(_secret)));
      expect(vm.error, isNotNull);
    });
  });

  group('Server-Sent Events in a browser', () {
    test('are switched off with an explanation, never half working', () async {
      vm.dispose();
      vm = RealtimeViewModel(const RealtimeConnector(supportsLiveSse: false), () async => resolver());
      expect(vm.sseSupported, isFalse);
      vm.setMode(RealtimeMode.sse);
      expect(vm.mode, RealtimeMode.webSocket);
      expect(vm.error, contains('browser'));

      // Even a mode that got set another way does not start a request that could never deliver an event.
      vm
        ..mode = RealtimeMode.sse
        ..url = 'http://{{host}}/events';
      var requests = 0;
      server.listen((req) {
        requests++;
        req.response.close();
      });
      await vm.connect();
      expect(vm.status, RealtimeStatus.disconnected);
      expect(vm.error, contains('Server-Sent Events cannot be streamed live in the browser'));
      expect(requests, 0);
    });

    test('the connector itself refuses too', () async {
      await expectLater(
        const RealtimeConnector(supportsLiveSse: false).connectSse(Uri.parse('http://127.0.0.1:${server.port}/events')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('desktop and mobile builds support them', () {
      expect(const RealtimeConnector(supportsLiveSse: true).supportsLiveSse, isTrue);
      expect(RealtimeViewModel(const RealtimeConnector(supportsLiveSse: true), () async => resolver()).sseSupported, isTrue);
    });
  });
}
