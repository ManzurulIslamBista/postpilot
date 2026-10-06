import 'dart:io' show HandshakeException, HttpException, OSError, SocketException;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/network_failure.dart';

const _url = 'https://api.example.com/users?api_key=s3cret-key&page=2';

DioException _failure(
  DioExceptionType type, {
  Object? error,
  String? message,
  String url = _url,
}) =>
    DioException(requestOptions: RequestOptions(path: url), type: type, error: error, message: message);

String _summary(
  DioException e, {
  ApiRequestOptions options = const ApiRequestOptions(),
  bool web = false,
}) =>
    NetworkFailure.summarize(e, options, web: web);

void main() {
  group('what the failure says', () {
    test('a host that does not resolve names the host, and nothing of the URL beyond it', () {
      final summary = _summary(_failure(
        DioExceptionType.connectionError,
        error: const SocketException("Failed host lookup: 'api.example.com'", osError: OSError('No such host is known', 11001)),
      ));

      expect(summary, startsWith('Couldn\'t find the server "api.example.com"'));
      expect(summary, contains('DNS'));
      expect(summary, isNot(contains('s3cret-key')));
      expect(summary, isNot(contains('/users')));
    });

    test('the DNS wording of Linux and macOS is recognised as well', () {
      for (final text in [
        'No address associated with hostname',
        'nodename nor servname provided, or not known',
        'Temporary failure in name resolution',
      ]) {
        expect(_summary(_failure(DioExceptionType.connectionError, error: SocketException(text))), contains('Couldn\'t find the server'), reason: text);
      }
    });

    test('a refused connection names host and port and says what to check', () {
      for (final text in ['Connection refused', 'The remote computer refused the network connection.']) {
        final summary = _summary(_failure(
          DioExceptionType.connectionError,
          error: SocketException(text),
          url: 'http://localhost:8443/x',
        ));

        expect(summary, 'The server at localhost:8443 refused the connection — check that it is running and that the port is right.');
      }
    });

    test('a default port is left out of the name, a custom one kept', () {
      expect(
        _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection refused'), url: 'https://h.test:443/')),
        contains('server at h.test refused'),
      );
      expect(
        _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection refused'), url: 'http://h.test:80/')),
        contains('server at h.test refused'),
      );
    });

    test('a connection that dropped mid-request, before any answer, or mid-body is told apart', () {
      final reset = _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection reset by peer')));
      final forcibly = _summary(_failure(
        DioExceptionType.connectionError,
        error: const SocketException('An existing connection was forcibly closed by the remote host.'),
      ));
      final early = _summary(_failure(
        DioExceptionType.connectionError,
        error: const HttpException('Connection closed before full header was received'),
      ));
      final midBody = _summary(_failure(
        DioExceptionType.unknown,
        error: const HttpException('Connection closed while receiving data'),
      ));

      expect(reset, contains('dropped the connection'));
      expect(forcibly, contains('dropped the connection'));
      expect(early, contains('closed the connection without answering'));
      expect(early, contains('https where it expects http'));
      expect(midBody, contains('before the whole response arrived'));
    });

    test('an unreachable network says so', () {
      expect(
        _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Network is unreachable'))),
        contains('can\'t be reached from this network'),
      );
    });
  });

  group('timeouts name the limit that was set', () {
    String connect(Duration? timeout) =>
        _summary(_failure(DioExceptionType.connectionTimeout), options: ApiRequestOptions(timeout: timeout));
    String receive(Duration? timeout) =>
        _summary(_failure(DioExceptionType.receiveTimeout), options: ApiRequestOptions(timeout: timeout));

    test('a connection that never came up', () {
      expect(connect(const Duration(seconds: 30)), startsWith('Could not connect to api.example.com within 30 seconds'));
      expect(connect(const Duration(seconds: 30)), contains('"Request timeout" in Settings'));
    });

    test('a server that never answered', () {
      expect(receive(const Duration(seconds: 7)), startsWith('The server at api.example.com did not answer within 7 seconds'));
    });

    test('the unit follows the size of the value', () {
      expect(receive(const Duration(seconds: 1)), contains('within 1 second.'));
      expect(receive(const Duration(milliseconds: 1500)), contains('within 1.5 seconds'));
      expect(receive(const Duration(milliseconds: 500)), contains('within 500 ms'));
      expect(receive(const Duration(minutes: 2)), contains('within 120 seconds'));
    });

    test('without a limit set (waiting for ever) no number is blamed', () {
      expect(connect(null), 'The connection to api.example.com timed out — the server may be down or blocked by a firewall.');
      expect(receive(Duration.zero), 'The server at api.example.com took too long to answer.');
    });

    test('sending and transforming time out the same way', () {
      expect(
        _summary(_failure(DioExceptionType.sendTimeout), options: const ApiRequestOptions(timeout: Duration(seconds: 3))),
        contains('within 3 seconds'),
      );
    });
  });

  group('TLS', () {
    const selfSigned = HandshakeException(
      'Handshake error in client (OS Error: \n\tCERTIFICATE_VERIFY_FAILED: self signed certificate(handshake.cc:393))',
    );

    test('an untrusted certificate says why and points at the Verify SSL setting', () {
      final summary = _summary(_failure(DioExceptionType.unknown, error: selfSigned));

      expect(summary, contains('the server\'s certificate is self-signed'));
      expect(summary, endsWith('If you trust this server, turn off "Verify SSL certificates" in Settings.'));
    });

    test('with verification already off the hint is not repeated', () {
      final summary = _summary(
        _failure(DioExceptionType.unknown, error: selfSigned),
        options: const ApiRequestOptions(verifySsl: false),
      );

      expect(summary, isNot(contains('Verify SSL')));
      expect(summary, contains('self-signed'));
    });

    test('the other certificate problems have their own words', () {
      String reason(String text) => _summary(_failure(DioExceptionType.unknown, error: HandshakeException(text)));

      expect(reason('CERTIFICATE_VERIFY_FAILED: certificate has expired(handshake.cc:393)'), contains('has expired'));
      expect(reason('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate(handshake.cc:393)'), contains('authority this device does not trust'));
      expect(reason('CERTIFICATE_VERIFY_FAILED: Hostname mismatch(handshake.cc:393)'), contains('different host name'));
      expect(reason('CERTIFICATE_VERIFY_FAILED: something new(handshake.cc:393)'), contains('could not be verified'));
    });

    test('Dio\'s own bad-certificate error is treated the same', () {
      final summary = _summary(_failure(DioExceptionType.badCertificate));

      expect(summary, contains('Verify SSL certificates'));
    });

    test('HTTPS spoken to a server that talks plain HTTP is recognised, with no certificate hint', () {
      final summary = _summary(_failure(
        DioExceptionType.unknown,
        error: const HandshakeException('Handshake error in client (OS Error: \n\tWRONG_VERSION_NUMBER(tls_record.cc:242))'),
      ));

      expect(summary, 'The server at api.example.com doesn\'t speak HTTPS on this port — try http:// in the URL, or check the port.');
    });

    test('a handshake that fails for no reason it can name still says what failed', () {
      final summary = _summary(_failure(DioExceptionType.unknown, error: const HandshakeException('Connection terminated during handshake')));

      expect(summary, startsWith('The secure connection to api.example.com could not be set up (TLS handshake failed).'));
    });
  });

  group('the rest', () {
    test('a response that cannot be held in memory points at the size limit', () {
      final summary = _summary(_failure(DioExceptionType.unknown, error: StateError('Out of Memory')));

      expect(summary, contains('too large to hold in memory'));
      expect(summary, contains('"Max response size"'));
    });

    test('a body that cannot be decompressed is called corrupt', () {
      final summary = _summary(_failure(DioExceptionType.unknown, error: const FormatException('Filter error, bad data')));

      expect(summary, 'The response from api.example.com could not be decoded (corrupt or wrongly compressed body).');
    });

    test('a URL the parser refused says so, quoting only the first line of the complaint', () {
      final summary = _summary(_failure(
        DioExceptionType.unknown,
        error: const FormatException('Invalid port', 'http://h.test:abc/?api_key=s3cret-key', 14),
      ));

      expect(summary, startsWith('The URL could not be read — FormatException: Invalid port'));
      expect(summary, isNot(contains('s3cret-key')));
    });

    test('a cancel is a cancel', () {
      expect(_summary(_failure(DioExceptionType.cancel)), 'Request cancelled');
    });

    test('in a browser a failed connection also names CORS', () {
      final summary = _summary(_failure(DioExceptionType.connectionError, message: 'XMLHttpRequest error.'), web: true);

      expect(summary, contains('CORS'));
    });

    test('a connection failure it cannot classify still names the host and the first line of the cause', () {
      final summary = _summary(_failure(
        DioExceptionType.connectionError,
        error: const SocketException('Something nobody has seen before\nsecond line'),
      ));

      expect(summary, 'Couldn\'t reach the server at api.example.com — SocketException: Something nobody has seen before');
    });

    test('an unknown error says what failed, not "something went wrong"', () {
      final summary = _summary(_failure(DioExceptionType.unknown, error: StateError('weird')));

      expect(summary, 'The request failed: Bad state: weird');
    });

    test('a failure with nothing to go on is still a sentence', () {
      expect(_summary(_failure(DioExceptionType.unknown)), 'The request failed: unknown error');
    });
  });

  group('through a custom proxy, the proxy is what is blamed', () {
    const proxy = ProxyConfig(mode: ProxyMode.custom, host: 'proxy.corp', port: 3128, username: 'ann', password: 'hunter2');
    const options = ApiRequestOptions(proxy: proxy);

    test('refused and unresolvable', () {
      expect(
        _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection refused')), options: options),
        contains('The proxy at proxy.corp:3128 refused the connection'),
      );
      expect(
        _summary(_failure(DioExceptionType.connectionError, error: const SocketException("Failed host lookup: 'proxy.corp'")), options: options),
        contains('Couldn\'t find the proxy "proxy.corp"'),
      );
    });

    test('never with its credentials', () {
      final summary = _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection refused')), options: options);

      expect(summary, isNot(contains('hunter2')));
      expect(summary, isNot(contains('ann')));
    });

    test('a host the proxy is bypassed for is blamed as itself', () {
      const bypassing = ApiRequestOptions(
        proxy: ProxyConfig(mode: ProxyMode.custom, host: 'proxy.corp', port: 3128, bypass: ['example.com']),
      );

      final summary = _summary(_failure(DioExceptionType.connectionError, error: const SocketException('Connection refused')), options: bypassing);

      expect(summary, contains('The server at api.example.com refused'));
    });
  });
}
