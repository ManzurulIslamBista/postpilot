import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/aws_sigv4_signer.dart';

void main() {
  // The well-known constant for SHA256("") — also a sanity check that
  // package:crypto behaves as expected in this environment.
  const emptyBodySha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  group('AwsSigV4Signer', () {
    final signer = const AwsSigV4Signer(
      accessKey: 'AKIDEXAMPLE',
      secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
      service: 'service',
    );
    final fixedNow = DateTime.utc(2015, 8, 30, 12, 36, 0);
    final uri = Uri.parse('https://example.amazonaws.com/');

    test('SHA256 of an empty payload matches the well-known constant', () {
      expect(sha256.convert(const []).toString(), emptyBodySha256);
    });

    test('produces a well-formed Authorization header with the right scope', () {
      final result = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);

      expect(result['X-Amz-Date'], '20150830T123600Z');
      expect(
        result['Authorization'],
        startsWith('AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
            'SignedHeaders=host;x-amz-date, Signature='),
      );

      final signature = result['Authorization']!.split('Signature=').last;
      expect(signature, matches(RegExp(r'^[0-9a-f]{64}$')), reason: 'signature must be a 64-char lowercase hex string');
    });

    test('is deterministic for identical inputs', () {
      final a = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);
      final b = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);
      expect(a['Authorization'], b['Authorization']);
    });

    test('changing the secret key changes the signature', () {
      const other = AwsSigV4Signer(
        accessKey: 'AKIDEXAMPLE',
        secretKey: 'a-completely-different-secret',
        region: 'us-east-1',
        service: 'service',
      );
      final a = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);
      final b = other.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);
      expect(a['Authorization'], isNot(b['Authorization']));
    });

    test('changing the HTTP method changes the signature (method is part of the canonical request)', () {
      final get = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);
      final post = signer.sign(method: 'POST', uri: uri, headers: const {}, body: const [], now: fixedNow);
      expect(get['Authorization'], isNot(post['Authorization']));
    });

    test('includes X-Amz-Security-Token and signs it when a session token is set', () {
      const withToken = AwsSigV4Signer(
        accessKey: 'AKIDEXAMPLE',
        secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
        service: 'service',
        sessionToken: 'FQoGZXIvYXdzEXAMPLE',
      );
      final result = withToken.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);

      expect(result['X-Amz-Security-Token'], 'FQoGZXIvYXdzEXAMPLE');
      expect(result['Authorization'], contains('SignedHeaders=host;x-amz-date;x-amz-security-token'));
    });

    test('a non-empty body changes the signature (payload hash is part of the canonical request)', () {
      final empty = signer.sign(method: 'POST', uri: uri, headers: const {}, body: const [], now: fixedNow);
      final withBody = signer.sign(method: 'POST', uri: uri, headers: const {}, body: 'hello'.codeUnits, now: fixedNow);
      expect(empty['Authorization'], isNot(withBody['Authorization']));
    });
  });
}
