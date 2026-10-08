// Real sockets, no widget binding (see cors_proxy_engine_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/cli_proxy.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_engine.dart';

const _token = 'cli-token-123456';

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  group('the command line', () {
    test('defaults to loopback on 8787 with a random token', () {
      final config = ProxyArgs.parse(const []).config;

      expect(config.host, '127.0.0.1');
      expect(config.port, 8787);
      expect(config.allowedOrigins, isEmpty);
      expect(config.insecure, isFalse);
      expect(config.token, hasLength(32));
      expect(ProxyArgs.parse(const []).config.token, isNot(config.token));
    });

    test('reads every option, in both forms, with origins repeated and comma separated', () {
      final config = ProxyArgs.parse([
        '--port=0',
        '--allow-origin',
        'https://a.example.com,https://B.example.com/',
        '--allow-origin=https://c.example.com',
        '--token',
        _token,
        '--allow-lan',
        '--insecure',
      ]).config;

      expect(config.port, 0);
      expect(config.allowedOrigins, ['https://a.example.com', 'https://b.example.com', 'https://c.example.com']);
      expect(config.token, _token);
      expect(config.host, '0.0.0.0');
      expect(config.listensOnAllInterfaces, isTrue);
      expect(config.insecure, isTrue);
    });

    test('the token may come from the environment, which keeps it out of the process list; the option wins', () {
      expect(ProxyArgs.parse(const [], environment: {'POSTPILOT_PROXY_TOKEN': _token}).config.token, _token);
      expect(ProxyArgs.parse(['--token', 'option-token-1234'], environment: {'POSTPILOT_PROXY_TOKEN': _token}).config.token, 'option-token-1234');
      expect(() => ProxyArgs.parse(const [], environment: {'POSTPILOT_PROXY_TOKEN': 'short'}), throwsFormatException);
    });

    test('on this computer a short token is fine; on the network a random one is made, or a long one must be given', () {
      expect(ProxyArgs.parse(['--token', 'password1']).config.token, 'password1');
      expect(ProxyArgs.parse(['--allow-lan']).config.token, hasLength(32));
      expect(ProxyArgs.parse(['--allow-lan', '--token', 'a-long-token-of-16+']).config.token, 'a-long-token-of-16+');
      expect(() => ProxyArgs.parse(const [], environment: {'POSTPILOT_PROXY_TOKEN': 'password1'}), returnsNormally);
    });

    test('a mistake is a message that says what to fix', () {
      String problem(List<String> args) {
        try {
          ProxyArgs.parse(args);
        } on FormatException catch (e) {
          return e.message;
        }
        fail('expected a FormatException for $args');
      }

      expect(problem(['--port', 'abc']), contains('--port needs a whole number from 0 to 65535, got "abc"'));
      expect(problem(['--port', '70000']), contains('0 to 65535'));
      expect(problem(['--port']), '--port needs a value.');
      expect(problem(['--allow-origin', '*']), contains('wildcard'));
      expect(problem(['--allow-origin', 'example.com']), contains('is not an origin'));
      expect(problem(['--token', 'short']), contains('at least 8'));
      expect(problem(['--allow-lan', '--token', 'password1']), contains('at least 16'));
      expect(problem(['--bogus']), 'Unknown option --bogus.');
    });
  });

  group('running', () {
    Future<({Future<int> exit, CorsProxyEngine engine, StringBuffer out, Completer<void> stop})> start(List<String> args) async {
      final out = StringBuffer();
      final stop = Completer<void>();
      final ready = Completer<CorsProxyEngine>();
      final exit = runProxyCommand(args, out: out, err: out, environment: const {}, until: stop.future, onStarted: ready.complete);
      final engine = await ready.future.timeout(const Duration(seconds: 10));
      return (exit: exit, engine: engine, out: out, stop: stop);
    }

    test('prints what to paste into the web app, serves, and stops on request', () async {
      final run = await start(['--port', '0', '--token', _token, '--allow-origin', 'https://app.example.com']);
      final port = run.engine.port!;

      expect(run.out.toString(), contains('URL:    http://localhost:$port'));
      expect(run.out.toString(), contains('Token:  $_token'));
      expect(run.out.toString(), contains('https://app.example.com'));
      expect(run.out.toString(), contains('Settings > CORS proxy'));
      expect(run.out.toString(), isNot(contains('WARNING')));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/__postpilot/health'));
      request.headers.set('X-PostPilot-Token', _token);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(jsonDecode(await utf8.decodeStream(response)), containsPair('ok', true));

      run.stop.complete();
      expect(await run.exit, 0);
      await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2)), throwsA(isA<SocketException>()));
    });

    test('--allow-lan prints a loud warning and listens on every interface', () async {
      final run = await start(['--port', '0', '--allow-lan']);

      expect(run.engine.config!.listensOnAllInterfaces, isTrue);
      expect(run.out.toString(), contains('WARNING: --allow-lan'));
      expect(run.out.toString(), contains('Anyone who gets the token'));

      run.stop.complete();
      expect(await run.exit, 0);
    });

    test('lists each call without a header or a body, and masks the query', () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((req) {
        req.response
          ..write('ok')
          ..close();
      });
      final run = await start(['--port', '0', '--token', _token]);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.postUrl(Uri.parse('http://127.0.0.1:${run.engine.port}/'));
      request.headers
        ..set('X-PostPilot-Token', _token)
        ..set('X-PostPilot-Url', 'http://127.0.0.1:${upstream.port}/things?api_key=SUPERSECRETVALUE')
        ..set('Authorization', 'Bearer s3cr3t-bearer');
      request.write('password=topsecret');
      await (await request.close()).drain<void>();
      for (var i = 0; i < 100 && !run.out.toString().contains('/things'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final text = run.out.toString();
      expect(text, matches(RegExp(r'POST 127\.0\.0\.1:\d+/things\?api_key=\S+ 200 \d+ ms')));
      for (final secret in ['SUPERSECRETVALUE', 's3cr3t-bearer', 'topsecret']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }

      run.stop.complete();
      await run.exit;
    });

    test('a taken port is exit code 1 with the reason, a mistake is exit code 2', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final busy = StringBuffer();
      expect(await runProxyCommand(['--port', '${taken.port}'], out: busy, err: busy, environment: const {}, until: Future<void>.value()), 1);
      expect(busy.toString(), contains('already in use'));

      final wrong = StringBuffer();
      expect(await runProxyCommand(['--port', 'x'], out: wrong, err: wrong, environment: const {}), 2);
      expect(wrong.toString(), contains('Usage:'));

      final help = StringBuffer();
      expect(await runProxyCommand(['--help'], out: help, err: help, environment: const {}), 0);
      expect(help.toString(), allOf(contains('--allow-origin'), contains('--token'), contains('--allow-lan'), contains('--insecure')));
    });
  });

  group('postpilot proxy through the main command', () {
    test('is dispatched, and the usage lists it', () async {
      final (out, outBuf) = _capture();
      final (err, errBuf) = _capture();

      final code = await runCli(['proxy', '--help'], out: out, err: err, environment: const {});
      await out.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(code, 0);
      expect(outBuf.toString(), contains('postpilot proxy [options]'));
      expect(errBuf.toString(), isEmpty);

      final (out2, outBuf2) = _capture();
      expect(await runCli(['--help'], out: out2, err: err, environment: const {}), 0);
      await out2.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(outBuf2.toString(), contains('postpilot proxy [options]'));

      final (out3, _) = _capture();
      final (err3, errBuf3) = _capture();
      expect(await runCli(['proxy', '--wat'], out: out3, err: err3, environment: const {}), 2);
      await err3.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errBuf3.toString(), contains('Unknown option --wat.'));
    });
  });
}
