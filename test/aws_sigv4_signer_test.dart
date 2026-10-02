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

    group('canonical request', () {
      const amzDate = '20150830T123600Z';

      String canonicalFor(String url, {Map<String, String> headers = const {}}) =>
          signer.canonicalRequest(method: 'GET', uri: Uri.parse(url), headers: headers, body: const [], amzDate: amzDate).request;

      test('signs the port a non-default port puts in the Host header', () {
        expect(canonicalFor('http://localhost:4566/bucket'), contains('\nhost:localhost:4566\n'));
        expect(canonicalFor('http://minio.local:9000/'), contains('\nhost:minio.local:9000\n'));
        expect(canonicalFor('https://example.com:8443/'), contains('\nhost:example.com:8443\n'));
      });

      test('leaves the default port out, as dart:io does', () {
        expect(canonicalFor('https://example.com:443/'), contains('\nhost:example.com\n'));
        expect(canonicalFor('http://example.com:80/'), contains('\nhost:example.com\n'));
        expect(canonicalFor('https://example.com/'), contains('\nhost:example.com\n'));
        expect(canonicalFor('http://example.com:443/'), contains('\nhost:example.com:443\n'), reason: '443 is not http default');
      });

      test('brackets an IPv6 host, as the Host header does', () {
        expect(canonicalFor('http://[::1]:4566/'), contains('\nhost:[::1]:4566\n'));
      });

      test('a port changes the signature', () {
        final plain = signer.sign(method: 'GET', uri: Uri.parse('http://localhost/'), headers: const {}, body: const [], now: fixedNow);
        final ported = signer.sign(method: 'GET', uri: Uri.parse('http://localhost:4566/'), headers: const {}, body: const [], now: fixedNow);

        expect(plain['Authorization'], isNot(ported['Authorization']));
      });

      test('signs every value of a repeated query parameter, sorted by name and then value', () {
        final canonical = canonicalFor('https://example.com/?tag=b&tag=a&Alpha=z&tag=c');

        expect(canonical.split('\n')[2], 'Alpha=z&tag=a&tag=b&tag=c');
      });

      test('sorts by the encoded name and encodes names and values as AWS asks', () {
        final canonical = canonicalFor('https://example.com/?b=x%20y&a=%C3%A9&a2=1&a=1');

        expect(canonical.split('\n')[2], 'a=%C3%A9&a=1&a2=1&b=x%20y');
      });

      test('a parameter without a value is signed with an empty one', () {
        expect(canonicalFor('https://example.com/?acl').split('\n')[2], 'acl=');
      });

      test('a repeated parameter changes the signature', () {
        final one = signer.sign(method: 'GET', uri: Uri.parse('https://example.com/?tag=a'), headers: const {}, body: const [], now: fixedNow);
        final two = signer.sign(method: 'GET', uri: Uri.parse('https://example.com/?tag=a&tag=b'), headers: const {}, body: const [], now: fixedNow);

        expect(one['Authorization'], isNot(two['Authorization']));
      });
    });

    test('a non-empty body changes the signature (payload hash is part of the canonical request)', () {
      final empty = signer.sign(method: 'POST', uri: uri, headers: const {}, body: const [], now: fixedNow);
      final withBody = signer.sign(method: 'POST', uri: uri, headers: const {}, body: 'hello'.codeUnits, now: fixedNow);
      expect(empty['Authorization'], isNot(withBody['Authorization']));
    });
  });
}
