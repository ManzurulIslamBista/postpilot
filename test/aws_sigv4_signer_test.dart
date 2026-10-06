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

    group('canonical headers and the path of a service other than S3', () {
      const amzDate = '20150830T123600Z';

      test('a path is URI-encoded twice: the %20 the wire carries becomes %2520', () {
        final canonical = signer
            .canonicalRequest(method: 'GET', uri: Uri.parse('https://example.amazonaws.com/example space/'), headers: const {}, body: const [], amzDate: amzDate)
            .request;

        expect(canonical.split('\n')[1], '/example%2520space/');
        // Computed independently with python hmac/hashlib over the canonical request above.
        final signed = signer.sign(
          method: 'GET',
          uri: Uri.parse('https://example.amazonaws.com/example space/'),
          headers: const {},
          body: const [],
          now: fixedNow,
        );
        expect(signed['Authorization'], endsWith('Signature=09a854f8ec075a831e1014e970f8ee8d93c858eac7a09dd7c067f3782499cfb1'));
      });

      test('a character Dart leaves unencoded in a path is encoded as AWS wants, then again', () {
        final signed = signer.sign(
          method: 'GET',
          uri: Uri.parse('https://example.amazonaws.com/items/a:b'),
          headers: const {},
          body: const [],
          now: fixedNow,
        );

        // `a:b` -> `a%3Ab` -> `a%253Ab`
        expect(signed['Authorization'], endsWith('Signature=3c21b5410ed4bc8bfa0be9cb2f08ed8f976d7982cba65e4572e9c5893d3230d6'));
      });

      test('no x-amz-content-sha256 header is added or signed', () {
        final signed = signer.sign(method: 'GET', uri: uri, headers: const {}, body: const [], now: fixedNow);

        expect(signed.keys, isNot(contains('X-Amz-Content-Sha256')));
        expect(signed['Authorization'], contains('SignedHeaders=host;x-amz-date,'));
      });

      test('a run of spaces in a header value is folded into one and the ends are trimmed', () {
        final signed = signer.sign(
          method: 'GET',
          uri: uri,
          headers: {'X-Test': '  a   b \t c '},
          body: const [],
          now: fixedNow,
        );

        expect(signed['Authorization'], contains('SignedHeaders=host;x-amz-date;x-test,'));
        expect(signed['Authorization'], endsWith('Signature=2b817e0f638792d21e89450fee9f41ea4f8d412e31d5729cc797bee8428c53a6'));
      });
    });

    // The four worked examples of "Signature Calculations for the Authorization
    // Header" in the Amazon S3 API reference (access key AKIAIOSFODNN7EXAMPLE,
    // bucket examplebucket, 2013-05-24). The expected signatures are the ones
    // printed there, and were reproduced independently with python hmac/hashlib.
    group('Amazon S3 documented examples', () {
      const s3 = AwsSigV4Signer(
        accessKey: 'AKIAIOSFODNN7EXAMPLE',
        secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
        service: 's3',
      );
      final date = DateTime.utc(2013, 5, 24);
      const host = 'https://examplebucket.s3.amazonaws.com';

      test('GET Object with a Range header', () {
        final signed = s3.sign(
          method: 'GET',
          uri: Uri.parse('$host/test.txt'),
          headers: {'Range': 'bytes=0-9'},
          body: const [],
          now: date,
        );

        expect(signed['X-Amz-Content-Sha256'], emptyBodySha256);
        expect(
          signed['Authorization'],
          'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
          'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
          'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
        );
      });

      test(r'PUT Object: the $ in the key is encoded once, to %24', () {
        final uri = Uri.parse('$host/test\$file.text');
        final body = 'Welcome to Amazon S3.'.codeUnits;
        final headers = {'Date': 'Fri, 24 May 2013 00:00:00 GMT', 'x-amz-storage-class': 'REDUCED_REDUNDANCY'};

        final signed = s3.sign(method: 'PUT', uri: uri, headers: headers, body: body, now: date);
        final canonical = s3.canonicalRequest(method: 'PUT', uri: uri, headers: headers, body: body, amzDate: '20130524T000000Z');

        expect(canonical.request.split('\n')[1], '/test%24file.text');
        expect(signed['X-Amz-Content-Sha256'], '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072');
        expect(
          signed['Authorization'],
          'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
          'SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, '
          'Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
        );
      });

      test('GET Bucket lifecycle (a query parameter without a value)', () {
        final signed = s3.sign(method: 'GET', uri: Uri.parse('$host/?lifecycle'), headers: const {}, body: const [], now: date);

        expect(
          signed['Authorization'],
          endsWith(
            'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
            'Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543',
          ),
        );
      });

      test('GET Bucket (list objects) with two query parameters', () {
        final signed = s3.sign(
          method: 'GET',
          uri: Uri.parse('$host/?max-keys=2&prefix=J'),
          headers: const {},
          body: const [],
          now: date,
        );

        expect(signed['Authorization'], endsWith('Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7'));
      });

      test('a path the wire already carries encoded stays singly encoded', () {
        final signed = s3.sign(method: 'GET', uri: Uri.parse('$host/a%20b/c'), headers: const {}, body: const [], now: date);
        final canonical = s3.canonicalRequest(
          method: 'GET',
          uri: Uri.parse('$host/a%20b/c'),
          headers: const {},
          body: const [],
          amzDate: '20130524T000000Z',
        );

        expect(canonical.request.split('\n')[1], '/a%20b/c');
        expect(signed['Authorization'], endsWith('Signature=eb957281a2d99bc3ba98405e621dd6d7ad4b330ad04c784ea9f43664f7129d61'));
      });

      test('an x-amz-content-sha256 the request sets itself is signed as it is, and not added a second time', () {
        final signed = s3.sign(
          method: 'GET',
          uri: Uri.parse('$host/test.txt'),
          headers: {'x-amz-content-sha256': 'UNSIGNED-PAYLOAD'},
          body: const [],
          now: date,
        );

        expect(signed.keys.map((k) => k.toLowerCase()), isNot(contains('x-amz-content-sha256')));
        expect(signed['Authorization'], endsWith('Signature=5c0d4ff29e72b8f94c5b6720369921e587e39bf7a64e456887dec4b43a2d1b77'));
      });

      test('the service name is matched without regard to case or padding', () {
        const shouting = AwsSigV4Signer(
          accessKey: 'AKIAIOSFODNN7EXAMPLE',
          secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
          region: 'us-east-1',
          service: ' S3 ',
        );

        final signed = shouting.sign(method: 'GET', uri: Uri.parse('$host/test.txt'), headers: const {}, body: const [], now: date);

        expect(signed['X-Amz-Content-Sha256'], emptyBodySha256);
      });
    });
  });
}
