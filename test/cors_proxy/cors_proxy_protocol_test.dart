import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_diagnosis.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_protocol.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_settings.dart';

void main() {
  group('origins', () {
    test('an origin is written the way a browser writes it', () {
      expect(CorsProxyOrigins.normalize('HTTPS://App.Example.com/'), 'https://app.example.com');
      expect(CorsProxyOrigins.normalize('http://localhost:80'), 'http://localhost');
      expect(CorsProxyOrigins.normalize('https://x.com:443'), 'https://x.com');
      expect(CorsProxyOrigins.normalize('http://[::1]:3000'), 'http://[::1]:3000');
      expect(CorsProxyOrigins.normalize(' http://192.168.1.5:3000 '), 'http://192.168.1.5:3000');
    });

    test('anything that is not an origin is refused, a wildcard above all', () {
      for (final bad in ['*', 'https://*.example.com', 'ftp://x.com', 'https://x.com/path', 'http://a.com?x=1', 'null', '', 'x.com']) {
        expect(CorsProxyOrigins.normalize(bad), isNull, reason: bad);
      }
      final parsed = CorsProxyOrigins.parseList('https://a.example.com, *');
      expect(parsed.error, contains('wildcard'));
      expect(parsed.origins, isEmpty);
    });

    test('a list is split on commas and spaces and holds each origin once', () {
      final parsed = CorsProxyOrigins.parseList('https://a.example.com,https://B.example.com https://a.example.com/\nhttp://localhost:5000');
      expect(parsed.error, isNull);
      expect(parsed.origins, ['https://a.example.com', 'https://b.example.com', 'http://localhost:5000']);
    });

    test('pages on this computer are allowed, look-alike host names are not', () {
      final origins = CorsProxyOrigins(['https://app.example.com']);
      for (final ok in [
        'http://localhost:5000',
        'https://localhost',
        'http://127.0.0.1:3000',
        'http://127.5.6.7',
        'http://[::1]:8080',
        'https://app.example.com',
        'https://APP.example.com',
      ]) {
        expect(origins.allows(ok), isTrue, reason: ok);
      }
      for (final no in [
        'http://localhost.evil.com',
        'http://127.0.0.1.evil.com',
        'http://10.0.0.1:3000',
        'http://app.example.com',
        'https://app.example.com:8443',
        'https://evil.example',
        'null',
        '',
      ]) {
        expect(origins.allows(no), isFalse, reason: no);
      }
    });
  });

  group('wrong tokens', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('a caller that sent ten wrong tokens in a minute is locked out until the oldest has aged out', () {
      final attempts = CorsProxyAttempts();
      for (var i = 0; i < CorsProxyAttempts.maxFailures - 1; i++) {
        attempts.recordFailure('10.0.0.5', t0.add(Duration(seconds: i)));
      }
      expect(attempts.isLocked('10.0.0.5', t0.add(const Duration(seconds: 10))), isFalse);

      attempts.recordFailure('10.0.0.5', t0.add(const Duration(seconds: 10)));
      expect(attempts.isLocked('10.0.0.5', t0.add(const Duration(seconds: 11))), isTrue);
      expect(attempts.isLocked('10.0.0.6', t0.add(const Duration(seconds: 11))), isFalse, reason: 'other callers are not affected');
      expect(attempts.isLocked('10.0.0.5', t0.add(CorsProxyAttempts.window + const Duration(seconds: 1))), isFalse);
    });

    test('a good token clears the count', () {
      final attempts = CorsProxyAttempts();
      for (var i = 0; i < CorsProxyAttempts.maxFailures; i++) {
        attempts.recordFailure('10.0.0.5', t0);
      }
      attempts.clear('10.0.0.5');
      expect(attempts.isLocked('10.0.0.5', t0), isFalse);
    });
  });

  group('token', () {
    test('a generated token is 32 URL-safe characters and never repeats', () {
      final a = CorsProxyToken.generate();
      final b = CorsProxyToken.generate();
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
      expect(a, isNot(b));
      expect(CorsProxyToken.problem(a), isNull);
    });

    test('a chosen token must be long enough and fit a header', () {
      expect(CorsProxyToken.problem('short'), contains('at least 8'));
      expect(CorsProxyToken.problem('has a space 123'), contains('visible ASCII'));
      expect(CorsProxyToken.problem('tökén-12345'), contains('visible ASCII'));
      expect(CorsProxyToken.problem('x' * 257), contains('at most 256'));
      expect(CorsProxyToken.problem('abcdefgh'), isNull);
    });

    test('a proxy other devices can reach needs a longer token, and a shell-safe one can be typed as it is', () {
      expect(CorsProxyToken.lanProblem('abcdefgh'), contains('at least 16'));
      expect(CorsProxyToken.lanProblem('abcdefghijklmnop'), isNull);
      expect(CorsProxyToken.lanProblem(CorsProxyToken.generate()), isNull);
      expect(CorsProxyToken.isShellSafe(CorsProxyToken.generate()), isTrue);
      expect(CorsProxyToken.isShellSafe('proxy-token_1.2~'), isTrue);
      for (final bad in [r'a;rm -rf /', r'$(whoami)aaaa', 'a b', '`id`', 'a&b', "it's", 'a|b']) {
        expect(CorsProxyToken.isShellSafe(bad), isFalse, reason: bad);
      }
    });

    test('a token matches only itself', () {
      expect(CorsProxyToken.matches('abcdefgh', 'abcdefgh'), isTrue);
      expect(CorsProxyToken.matches('abcdefgi', 'abcdefgh'), isFalse);
      expect(CorsProxyToken.matches('abcdefg', 'abcdefgh'), isFalse);
      expect(CorsProxyToken.matches('abcdefghX', 'abcdefgh'), isFalse);
      expect(CorsProxyToken.matches('', 'abcdefgh'), isFalse);
      expect(CorsProxyToken.matches(null, 'abcdefgh'), isFalse);
    });

    test('the same random source gives the same token', () {
      expect(CorsProxyToken.generate(random: Random(7)), CorsProxyToken.generate(random: Random(7)));
    });
  });

  group('Set-Cookie header', () {
    final cookies = [
      'sid=a1b2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; HttpOnly',
      'name="quo\\"ted"; Path=/; x=é',
    ];

    test('is ASCII only and survives the trip with the commas of Expires', () {
      final encoded = CorsProxyProtocol.encodeSetCookies(cookies);

      expect(encoded.codeUnits.every((u) => u >= 0x20 && u < 0x7f), isTrue, reason: encoded);
      expect(encoded, contains('${String.fromCharCode(0x5c)}u00e9'), reason: 'a backslash, u and the code of the accented letter');
      expect(CorsProxyProtocol.decodeSetCookies(encoded), cookies);
    });

    test('a value that is not ours is one cookie, and nothing is none', () {
      expect(CorsProxyProtocol.decodeSetCookies('plain=cookie; Path=/'), ['plain=cookie; Path=/']);
      expect(CorsProxyProtocol.decodeSetCookies('["a=1", 2]'), ['["a=1", 2]']);
      expect(CorsProxyProtocol.decodeSetCookies(''), isEmpty);
      expect(CorsProxyProtocol.decodeSetCookies('[]'), isEmpty);
    });
  });

  group('target address', () {
    ({Uri? uri, CorsProxyRefusal? refusal}) parse(String? header, {Set<String> own = const {}}) =>
        CorsProxyTargets.parse(header, ownPort: 8787, ownHosts: own);

    test('an http or https address is accepted with its query', () {
      expect(parse('https://api.example.com/users?page=2').uri.toString(), 'https://api.example.com/users?page=2');
      expect(parse('http://localhost:3000/x').uri, isNotNull);
    });

    test('a missing, broken or non-http address is a 400 that says why', () {
      expect(parse(null).refusal!.code, 'missing_target');
      expect(parse('  ').refusal!.code, 'missing_target');
      expect(parse('not a url').refusal!.code, 'invalid_target');
      expect(parse('https://').refusal!.code, 'invalid_target');
      expect(parse('/relative/path').refusal!.code, 'unsupported_scheme');
      for (final scheme in ['ftp://x.com/a', 'file:///etc/passwd', 'javascript:alert(1)', 'ws://x.com']) {
        final refusal = parse(scheme).refusal!;
        expect((refusal.status, refusal.code), (400, 'unsupported_scheme'), reason: scheme);
      }
    });

    test('the proxy itself is refused, under every name it has', () {
      for (final self in [
        'http://localhost:8787/x',
        'http://127.0.0.1:8787',
        'http://127.9.9.9:8787/a',
        'http://[::1]:8787/',
        'http://0.0.0.0:8787/',
        'http://192.168.1.5:8787/a',
        'http://mybox:8787/',
      ]) {
        final refusal = parse(self, own: {'192.168.1.5', 'mybox'}).refusal;
        expect((refusal?.status, refusal?.code), (508, 'proxy_loop'), reason: self);
      }
      expect(parse('http://localhost:8788/x').refusal, isNull, reason: 'another port is another server');
      expect(parse('http://192.168.1.5:80/x', own: {'192.168.1.5'}).refusal, isNull);
      expect(parse('https://localhost/x').refusal, isNull, reason: 'port 443');
    });
  });

  group('settings', () {
    test('an address is read the way people type it', () {
      expect(CorsProxySettings.parseUrl('localhost:8787').toString(), 'http://localhost:8787');
      expect(CorsProxySettings.parseUrl(' http://127.0.0.1:9000/ignored?x=1 ').toString(), 'http://127.0.0.1:9000');
      expect(CorsProxySettings.parseUrl('https://proxy.example.com').toString(), 'https://proxy.example.com');
      expect(CorsProxySettings.parseUrl('ftp://x'), isNull);
      expect(CorsProxySettings.parseUrl('has space'), isNull);
      expect(CorsProxySettings.parseUrl(''), isNull);
    });

    test('a route exists only while the proxy is on and its address is usable', () {
      expect(const CorsProxySettings().route, isNull);
      expect(const CorsProxySettings(enabled: true, url: '???').route, isNull);
      final route = const CorsProxySettings(enabled: true, token: ' tok-123456 ').route!;
      expect(route.base.toString(), 'http://localhost:8787');
      expect(route.token, 'tok-123456');
      expect(route.authority, 'localhost:8787');
    });

    test('every http call is proxied except one to the proxy itself', () {
      final route = const CorsProxySettings(enabled: true).route!;
      expect(route.proxies(Uri.parse('https://api.example.com/x')), isTrue);
      expect(route.proxies(Uri.parse('http://localhost:3000/x')), isTrue);
      expect(route.proxies(Uri.parse('http://localhost:8787/__postpilot/health')), isFalse);
      expect(route.proxies(Uri.parse('https://localhost:8787/x')), isTrue, reason: 'other scheme, other server');
      expect(route.proxies(Uri.parse('ws://api.example.com/x')), isFalse);
      expect(route.endpointFor(Uri.parse('https://api.example.com/v1/users?a=1')).toString(), 'http://localhost:8787/v1/users');
      expect(route.endpointFor(Uri.parse('https://api.example.com')).toString(), 'http://localhost:8787/');
    });
  });

  group('connection test messages', () {
    final base = Uri.parse('http://localhost:8787');

    test('each way to fail names the cause and the fix', () {
      expect(CorsProxyDiagnosis.refused(base, 401, 'token_required').kind, CorsProxyTestKind.tokenMissing);
      final wrong = CorsProxyDiagnosis.refused(base, 401, 'token_invalid');
      expect(wrong.kind, CorsProxyTestKind.tokenWrong);
      expect(wrong.message, contains('--token'));
      final origin = CorsProxyDiagnosis.refused(base, 403, 'origin_not_allowed', pageOrigin: 'https://app.example.com');
      expect(origin.kind, CorsProxyTestKind.originNotAllowed);
      expect(origin.message, contains('--allow-origin https://app.example.com'));
      expect(CorsProxyDiagnosis.refused(base, 403, 'host_not_allowed').kind, CorsProxyTestKind.hostNotAllowed);
      final other = CorsProxyDiagnosis.refused(base, 404, null);
      expect(other.kind, CorsProxyTestKind.notAProxy);
      expect(other.message, contains('status 404'));
    });

    test('an unreachable address is told apart: not running, blocked by the browser, mixed content', () {
      final notRunning = CorsProxyDiagnosis.unreachable(base, reachable: false);
      expect(notRunning.kind, CorsProxyTestKind.notRunning);
      expect(notRunning.message, contains('dart run bin/postpilot.dart proxy'));
      expect(CorsProxyDiagnosis.unreachable(base).kind, CorsProxyTestKind.notRunning);

      final blocked = CorsProxyDiagnosis.unreachable(base, reachable: true, pageOrigin: 'https://app.example.com');
      expect(blocked.kind, CorsProxyTestKind.blocked);
      expect(blocked.message, contains('--allow-origin https://app.example.com'));
      expect(blocked.message, contains('local network access'));

      final mixed = CorsProxyDiagnosis.unreachable(Uri.parse('http://192.168.1.10:8787'), reachable: false, pageOrigin: 'https://app.example.com');
      expect(mixed.kind, CorsProxyTestKind.mixedContent);
      final loopbackOverHttps = CorsProxyDiagnosis.unreachable(base, reachable: false, pageOrigin: 'https://app.example.com');
      expect(loopbackOverHttps.kind, CorsProxyTestKind.notRunning, reason: 'http://localhost is exempt from mixed content');
    });
  });
}
