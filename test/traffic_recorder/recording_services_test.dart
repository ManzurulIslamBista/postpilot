import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/device_helper/data/network_info.dart';
import 'package:postpilot/features/traffic_recorder/data/recorder_cli.dart';
import 'package:postpilot/features/traffic_recorder/data/recorder_config.dart';
import 'package:postpilot/features/traffic_recorder/domain/entities/recorded_exchange.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/lan_addresses.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/noise_filter.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/path_normalizer.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recorder_connect.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recorder_headers.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recording_buffer.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recording_exports.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/traffic_masking.dart';
import 'exchange_fixtures.dart';


void main() {
  group('PathNormalizer', () {
    test('turns numeric ids into variables named after the segment before them', () {
      final n = PathNormalizer.normalize('/users/42/posts/9');
      expect(n.template, '/users/{{userId}}/posts/{{postId}}');
      expect(n.display, '/users/{userId}/posts/{postId}');
      expect([for (final v in n.variables) '${v.name}=${v.value}'], ['userId=42', 'postId=9']);
    });

    test('recognises UUIDs and long hex ids and names them apart', () {
      expect(PathNormalizer.normalize('/orders/123e4567-e89b-12d3-a456-426614174000').template, '/orders/{{orderUuid}}');
      expect(PathNormalizer.normalize('/items/507f1f77bcf86cd799439011').template, '/items/{{itemId}}');
      // Six hex digits are a word, not an id.
      expect(PathNormalizer.normalize('/colors/abc123').template, '/colors/abc123');
    });

    test('falls back to id when nothing precedes, and numbers repeated names', () {
      expect(PathNormalizer.normalize('/42').template, '/{{id}}');
      expect(PathNormalizer.normalize('/a/1/2').template, '/a/{{aId}}/{{id}}');
      expect(PathNormalizer.normalize('/users/1/users/2').template, '/users/{{userId}}/users/{{userId2}}');
    });

    test('singularises sensibly and keeps words that only look plural', () {
      expect(PathNormalizer.normalize('/categories/7').template, '/categories/{{categoryId}}');
      expect(PathNormalizer.normalize('/blog-posts/3').template, '/blog-posts/{{blogPostId}}');
      expect(PathNormalizer.normalize('/status/200').template, '/status/{{statusId}}');
      expect(PathNormalizer.normalize('/addresses/5').template, '/addresses/{{addressId}}');
    });

    test('leaves literal paths, a trailing slash and the root alone', () {
      expect(PathNormalizer.normalize('/v1/health').template, '/v1/health');
      expect(PathNormalizer.normalize('/users/abc').template, '/users/abc');
      expect(PathNormalizer.normalize('/users/42/').template, '/users/{{userId}}/');
      expect(PathNormalizer.normalize('/').template, '/');
      expect(PathNormalizer.normalize('/users/42').variables.single.value, '42');
    });
  });

  group('NoiseFilter', () {
    test('recognises static files by extension, ignoring the query and dotfiles', () {
      expect(NoiseFilter.isStaticAsset('/static/app.js?v=3'), isTrue);
      expect(NoiseFilter.isStaticAsset('/img/logo.PNG'), isTrue);
      expect(NoiseFilter.isStaticAsset('/api/users'), isFalse);
      expect(NoiseFilter.isStaticAsset('/api/v1.2'), isFalse);
      expect(NoiseFilter.isStaticAsset('/files/.hidden'), isFalse);
      expect(NoiseFilter.isStaticAsset('/downloads/report.'), isFalse);
      expect(NoiseFilter.isStaticAsset('/api/data.json'), isFalse);
    });

    test('recognises analytics hosts and their subdomains only', () {
      expect(NoiseFilter.isAnalyticsHost('www.google-analytics.com'), isTrue);
      expect(NoiseFilter.isAnalyticsHost('o123.ingest.sentry.io'), isTrue);
      expect(NoiseFilter.isAnalyticsHost('sentry.io'), isTrue);
      expect(NoiseFilter.isAnalyticsHost('notsentry.io'), isFalse);
      expect(NoiseFilter.isAnalyticsHost('api.example.com'), isFalse);
    });

    test('a preflight is an OPTIONS that asks for a method; a plain OPTIONS is a real call', () {
      final preflight = exchange(method: 'OPTIONS', requestHeaders: const [RecordedHeader('access-control-request-method', 'POST')]);
      final plain = exchange(method: 'OPTIONS');
      expect(NoiseFilter.reasonFor(preflight), NoiseReason.preflight);
      expect(NoiseFilter.reasonFor(plain), isNull);
    });

    test('a call the recorder answered itself is always noise, the others follow their switches', () {
      final refused = exchange(kind: RecordedKind.refused, path: '/chat');
      final asset = exchange(path: '/app.js');
      expect(NoiseFilter.reasonFor(refused, skipAssets: false, skipAnalytics: false, skipPreflights: false), NoiseReason.notForwarded);
      expect(NoiseFilter.reasonFor(asset), NoiseReason.staticAsset);
      expect(NoiseFilter.reasonFor(asset, skipAssets: false), isNull);
      expect(NoiseFilter.reasonFor(exchange(url: 'https://api.mixpanel.com', path: '/track')), NoiseReason.analytics);
    });
  });

  group('RecordedExchange text', () {
    test('decodes text types, honours latin1, and refuses declared binary types', () {
      final json = exchange(responseBody: '{"a":"é"}');
      expect(json.responseText, '{"a":"é"}');
      final latin = RecordedExchange(
        id: 1,
        startedAt: DateTime.utc(2026),
        duration: Duration.zero,
        method: 'GET',
        url: 'x',
        path: '/',
        status: 200,
        responseHeaders: const [RecordedHeader('Content-Type', 'text/plain; charset=ISO-8859-1')],
        responseBody: Uint8List.fromList([0x63, 0x61, 0x66, 0xE9]),
        responseBodySize: 4,
      );
      expect(latin.responseText, 'café');
      final png = exchange(responseHeaders: const [RecordedHeader('content-type', 'image/png')], responseBody: 'not really');
      expect(png.responseText, isNull);
    });

    test('a body without a type is text when it decodes cleanly and holds no NUL byte', () {
      final plain = exchange(responseHeaders: const [], responseBody: 'hello');
      expect(plain.responseText, 'hello');
      final binary = RecordedExchange(
        id: 2,
        startedAt: DateTime.utc(2026),
        duration: Duration.zero,
        method: 'GET',
        url: 'x',
        path: '/',
        status: 200,
        responseBody: Uint8List.fromList([0x68, 0x00, 0x69]),
        responseBodySize: 3,
      );
      expect(binary.responseText, isNull);
      expect(exchange().responseText, isNull, reason: 'no body at all');
    });
  });

  group('RecorderHeaders', () {
    test('Accept-Encoding keeps what the recorder can inflate and falls back to identity', () {
      expect(RecorderHeaders.readableAcceptEncoding('gzip, deflate, br, zstd'), 'gzip, deflate');
      expect(RecorderHeaders.readableAcceptEncoding('br;q=1.0, gzip;q=0.8'), 'gzip;q=0.8');
      expect(RecorderHeaders.readableAcceptEncoding('br'), 'identity');
      expect(RecorderHeaders.readableAcceptEncoding('*'), 'identity');
      expect(RecorderHeaders.readableAcceptEncoding(''), 'identity');
    });

    test('authority and origin leave out a default port and bracket IPv6', () {
      expect(RecorderHeaders.authorityOf(Uri.parse('https://api.example.com')), 'api.example.com');
      expect(RecorderHeaders.authorityOf(Uri.parse('https://api.example.com:8443')), 'api.example.com:8443');
      expect(RecorderHeaders.authorityOf(Uri.parse('http://x:80')), 'x');
      expect(RecorderHeaders.authorityOf(Uri.parse('http://[::1]:3000')), '[::1]:3000');
      expect(RecorderHeaders.originOf(Uri.parse('https://api.example.com:8443/v2')), 'https://api.example.com:8443');
    });

    test('the forwarded address is origin, path prefix, then the app\'s path and query', () {
      expect(RecorderHeaders.upstreamUri(Uri.parse('https://api.example.com/v2'), '/users?x=1').toString(), 'https://api.example.com/v2/users?x=1');
      expect(RecorderHeaders.upstreamUri(Uri.parse('https://api.example.com/v2/'), '/users').toString(), 'https://api.example.com/v2/users');
      expect(RecorderHeaders.upstreamUri(Uri.parse('https://api.example.com'), '/').toString(), 'https://api.example.com/');
    });

    test('names this computer and private networks, not the internet', () {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2', '192.168.1.5', '172.16.0.1', '172.31.255.255', 'printer.local', '::1']) {
        expect(RecorderHeaders.isLocalHost(host), isTrue, reason: host);
      }
      for (final host in ['172.32.0.1', '8.8.8.8', 'example.com', '192.169.0.1', '256.1.1.1']) {
        expect(RecorderHeaders.isLocalHost(host), isFalse, reason: host);
      }
    });

    test('Origin and Referer are rewritten only when they name the recorder', () {
      final upstream = Uri.parse('https://api.example.com');
      String rewrite(String v) => RecorderHeaders.rewriteOriginLike(v, upstream: upstream, hostHeader: '192.168.1.5:8099', localPort: 8099);
      expect(rewrite('http://192.168.1.5:8099'), 'https://api.example.com');
      expect(rewrite('http://10.0.2.2:8099/page?x=1'), 'https://api.example.com/page?x=1');
      expect(rewrite('http://localhost:8099'), 'https://api.example.com');
      expect(rewrite('http://localhost:5173'), 'http://localhost:5173');
      expect(rewrite('https://app.example.com/home'), 'https://app.example.com/home');
      expect(rewrite('null'), 'null');
    });
  });

  group('RecorderConfig', () {
    test('reads what people type as an upstream', () {
      expect(RecorderConfig.parseUpstream('api.example.com').toString(), 'https://api.example.com');
      expect(RecorderConfig.parseUpstream(' https://api.example.com/v2/ ').toString(), 'https://api.example.com/v2');
      expect(RecorderConfig.parseUpstream('http://localhost:3000')!.port, 3000);
      expect(RecorderConfig.parseUpstream('https://user:pw@api.example.com?x=1#f').toString(), 'https://api.example.com');
      expect(RecorderConfig.parseUpstream('ftp://x'), isNull);
      expect(RecorderConfig.parseUpstream(''), isNull);
      expect(RecorderConfig.parseUpstream('not a url'), isNull);
    });

    test('says what is wrong with an upstream in words', () {
      expect(RecorderConfig.upstreamProblem(''), contains('Enter the address'));
      expect(RecorderConfig.upstreamProblem('{{baseUrl}}'), contains('{{variable}}'));
      expect(RecorderConfig.upstreamProblem('ftp://x'), contains('http:// or https://'));
      expect(RecorderConfig.upstreamProblem('https://api.example.com'), isNull);
    });

    test('knows when it listens beyond this computer', () {
      final up = Uri.parse('https://x.example');
      expect(RecorderConfig(upstream: up).listensOnAllInterfaces, isFalse);
      expect(RecorderConfig(upstream: up, host: RecorderConfig.allInterfaces).listensOnAllInterfaces, isTrue);
    });
  });

  group('RecorderCliArgs', () {
    test('defaults: loopback, port 8099, the usual switches', () {
      final c = RecorderCliArgs.parse(['--upstream', 'https://api.example.com']).config;
      expect(c.upstream.toString(), 'https://api.example.com');
      expect([c.host, c.port], ['127.0.0.1', 8099]);
      expect([c.allowSelfSigned, c.rewriteHostHeaders, c.keepResponsesReadable, c.useSystemProxy], [false, true, true, false]);
      expect(c.timeout, const Duration(seconds: 60));
    });

    test('every option is read', () {
      final c = RecorderCliArgs.parse([
        '--upstream', 'api.example.com', '--lan', '--port', '0', '--insecure', '--no-rewrite', '--keep-brotli', '--system-proxy', '--timeout', '5', '--max-body', '8',
      ]).config;
      expect([c.host, c.port], ['0.0.0.0', 0]);
      expect([c.allowSelfSigned, c.rewriteHostHeaders, c.keepResponsesReadable, c.useSystemProxy], [true, false, false, true]);
      expect(c.timeout, const Duration(seconds: 5));
      expect(c.maxBodyBytes, 8192);
      expect(RecorderCliArgs.parse(['--help']).help, isTrue);
    });

    test('a mistake is a message, not a stack trace', () {
      FormatException failure(List<String> args) {
        try {
          RecorderCliArgs.parse(args);
        } on FormatException catch (e) {
          return e;
        }
        throw StateError('expected a FormatException for $args');
      }

      expect(failure([]).message, contains('Enter the address'));
      expect(failure(['--upstream', 'https://x.example', '--bogus']).message, 'Unknown option --bogus.');
      expect(failure(['--upstream']).message, '--upstream needs a value.');
      expect(failure(['--upstream', 'https://x.example', '--port', 'abc']).message, '--port needs a whole number.');
    });
  });

  group('RecorderAddresses', () {
    const wifi = LocalAddress('Wi-Fi', '192.168.1.23');

    test('drops virtual adapters, tunnels and link-local addresses and puts Wi-Fi and private ranges first', () {
      final usable = RecorderAddresses.usable(const [
        LocalAddress('vEthernet (WSL)', '172.20.0.1'),
        wifi,
        LocalAddress('Tailscale', '100.101.102.103'),
        LocalAddress('Ethernet', '10.0.0.5'),
        LocalAddress('VirtualBox Host-Only Network', '192.168.56.1'),
        LocalAddress('Local Area Connection', '169.254.1.5'),
        LocalAddress('Ethernet 2', '203.0.113.9'),
        LocalAddress('docker0', '172.17.0.1'),
        LocalAddress('utun3', '10.8.0.2'),
      ]);
      expect([for (final a in usable) a.ip], ['192.168.1.23', '10.0.0.5', '203.0.113.9']);
    });

    test('when only virtual adapters exist they are still offered, link-local never is', () {
      expect([for (final a in RecorderAddresses.usable(const [LocalAddress('vEthernet (WSL)', '172.20.0.1')])) a.ip], ['172.20.0.1']);
      expect(RecorderAddresses.usable(const [LocalAddress('Wi-Fi', '169.254.9.9')]), isEmpty);
      expect(RecorderAddresses.usable(const []), isEmpty);
    });

    test('a carrier-grade NAT address that is not on a VPN-named adapter is still skipped when a better one exists', () {
      final usable = RecorderAddresses.usable(const [LocalAddress('Ethernet 3', '100.64.1.1'), wifi]);
      expect([for (final a in usable) a.ip], ['192.168.1.23']);
    });
  });

  group('RecorderConnect', () {
    const lan = [LocalAddress('Wi-Fi', '192.168.1.23')];

    test('lists this computer, the emulator, a USB phone with its adb command, and the Wi-Fi address', () {
      final options = RecorderConnect.options(port: 8099, allowOtherDevices: true, addresses: lan);
      expect([for (final o in options) o.url], [
        'http://localhost:8099',
        'http://10.0.2.2:8099',
        'http://localhost:8099',
        'http://192.168.1.23:8099',
      ]);
      expect(options[2].command, 'adb reverse tcp:8099 tcp:8099');
      expect(options.every((o) => o.available), isTrue);
    });

    test('the Wi-Fi address is not offered as ready until the recorder listens beyond this computer', () {
      final options = RecorderConnect.options(port: 8099, allowOtherDevices: false, addresses: lan);
      expect(options.last.available, isFalse);
      expect(options.last.note, contains('Also reachable from phones on my network'));
    });

    test('with no network address the Wi-Fi row says to connect, and has no URL', () {
      final last = RecorderConnect.options(port: 1, allowOtherDevices: true, addresses: const []).last;
      expect(last.available, isFalse);
      expect(last.url, isEmpty);
    });

    test('the first address to show is the network one only when other devices may connect', () {
      expect(RecorderConnect.primaryUrl(port: 8099, allowOtherDevices: true, addresses: lan), 'http://192.168.1.23:8099');
      expect(RecorderConnect.primaryUrl(port: 8099, allowOtherDevices: false, addresses: lan), 'http://localhost:8099');
      expect(RecorderConnect.primaryUrl(port: 8099, allowOtherDevices: true, addresses: const []), 'http://localhost:8099');
    });
  });

  group('masking, cURL and HAR', () {
    final secret = exchange(
      method: 'POST',
      path: '/login?api_key=SECRETKEY123&page=2',
      requestHeaders: const [
        RecordedHeader('host', '10.0.2.2:8099'),
        RecordedHeader('authorization', 'Bearer abc123tokenvalue'),
        RecordedHeader('x-api-key', 'k_live_zzzzzzzzzzzzzzzz'),
        RecordedHeader('content-type', 'application/json'),
        RecordedHeader('content-length', '40'),
        RecordedHeader('accept', 'application/json'),
      ],
      requestBody: '{"user":"ada","password":"hunter2"}',
      responseBody: '{"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl","id":1}',
    );

    test('headers are masked by name and the transport ones can be dropped', () {
      final headers = TrafficMasking.headers(secret.requestHeaders, dropTransport: true);
      expect([for (final h in headers) h.name], ['authorization', 'x-api-key', 'content-type', 'accept']);
      expect(headers[0].value, 'Bearer ••••••');
      expect(headers[1].value, '••••••');
      expect(headers[2].value, 'application/json');
      expect(TrafficMasking.headers(secret.requestHeaders, reveal: true)[1].value, 'Bearer abc123tokenvalue');
    });

    test('a cURL command hides credentials by default and shows them when asked', () {
      final masked = RecordingCurl.build(secret);
      expect(masked, contains('curl --request POST'));
      expect(masked, contains('https://api.example.com/login?api_key=••••••&page=2'));
      expect(masked, contains('Bearer ••••••'));
      expect(masked, contains('"password":"••••••"'));
      expect(masked, isNot(contains('hunter2')));
      expect(masked, isNot(contains('abc123tokenvalue')));
      expect(masked, isNot(contains('k_live')));
      expect(masked, isNot(contains('SECRETKEY123')));
      expect(masked.toLowerCase(), isNot(contains('content-length')));
      expect(masked, isNot(contains('10.0.2.2')));

      final real = RecordingCurl.build(secret, reveal: true);
      expect(real, contains('Bearer abc123tokenvalue'));
      expect(real, contains('hunter2'));
      expect(real, contains('api_key=SECRETKEY123'));
    });

    test('a body that was cut or is not text is left out of the cURL command, and the first line says so', () {
      final cut = exchange(method: 'POST', requestBody: '{"a":', requestTruncated: true);
      final text = RecordingCurl.build(cut);
      expect(text, startsWith('# The request body was cut at the recorder\'s size limit'));
      expect(text, isNot(contains('--data-raw')));
      final binary = exchange(method: 'POST', requestHeaders: const [RecordedHeader('content-type', 'image/png')], requestBody: 'png');
      expect(RecordingCurl.build(binary), startsWith('# The request body is not text'));
    });

    test('a HAR file is masked again whatever the live view shows', () {
      final har = jsonDecode(RecordingHar.export([secret])) as Map<String, dynamic>;
      final entry = (har['log']['entries'] as List).single as Map<String, dynamic>;
      final request = entry['request'] as Map<String, dynamic>;
      expect(request['url'], 'https://api.example.com/login?api_key=••••••&page=2');
      final headers = {for (final h in request['headers'] as List) h['name'] as String: h['value'] as String};
      expect(headers.containsKey('host'), isFalse);
      expect(headers.containsKey('content-length'), isFalse);
      expect(headers['authorization'], 'Bearer ••••••');
      expect(headers['x-api-key'], '••••••');
      expect(request['postData']['text'], '{"user":"ada","password":"••••••"}');
      final content = (entry['response'] as Map<String, dynamic>)['content'] as Map<String, dynamic>;
      expect(content['text'], isNot(contains('eyJ')));
      expect(entry['response']['status'], 200);
      final raw = RecordingHar.export([secret]);
      for (final value in ['hunter2', 'abc123tokenvalue', 'k_live', 'SECRETKEY123']) {
        expect(raw, isNot(contains(value)));
      }
    });
  });

  group('RecordingBuffer', () {
    RecordedExchange sized(int id, int bodyBytes) => exchange(id: id, responseBody: 'x' * bodyBytes);

    test('keeps the newest calls up to the count and counts what it dropped', () {
      final buffer = RecordingBuffer(maxCount: 3);
      for (var i = 1; i <= 5; i++) {
        buffer.add(exchange(id: i));
      }
      expect([for (final e in buffer.items) e.id], [3, 4, 5]);
      expect(buffer.dropped, 2);
      expect(buffer.byId(2), isNull);
      expect(buffer.byId(4)!.id, 4);
    });

    test('keeps within a byte budget too, and the newest call always stays', () {
      final buffer = RecordingBuffer(maxCount: 100, maxBytes: 3000);
      buffer.add(sized(1, 1000));
      buffer.add(sized(2, 1000));
      expect(buffer.length, 1, reason: 'two calls of about 2 KB do not fit 3000 bytes');
      expect(buffer.items.single.id, 2);
      buffer.add(sized(3, 50000));
      expect(buffer.items.single.id, 3, reason: 'a call larger than the whole budget is still kept');
      expect(buffer.bytes, buffer.items.single.approximateBytes);
    });

    test('clear empties it and resets the counters', () {
      final buffer = RecordingBuffer(maxCount: 1)
        ..add(exchange(id: 1))
        ..add(exchange(id: 2));
      expect(buffer.dropped, 1);
      buffer.clear();
      expect([buffer.length, buffer.dropped, buffer.bytes], [0, 0, 0]);
      expect(buffer.isEmpty, isTrue);
    });
  });
}
