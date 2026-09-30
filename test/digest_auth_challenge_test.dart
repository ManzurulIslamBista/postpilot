import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/digest_auth_challenge.dart';

void main() {
  group('DigestAuthChallenge.parse', () {
    test('extracts directives from a real WWW-Authenticate header', () {
      final challenge = DigestAuthChallenge.parse(
        'Digest realm="testrealm@host.com", qop="auth", '
        'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      );

      expect(challenge, isNotNull);
      expect(challenge!.realm, 'testrealm@host.com');
      expect(challenge.nonce, 'dcd98b7102dd2f0e8b11d0f600bfb0c093');
      expect(challenge.qop, 'auth');
      expect(challenge.opaque, '5ccc069c403ebaf9f0171e9517f40e41');
      expect(challenge.algorithm, 'MD5', reason: 'RFC 2617 defaults to MD5 when no algorithm directive is present');
    });

    test('returns null for a non-Digest scheme or missing header', () {
      expect(DigestAuthChallenge.parse('Basic realm="x"'), isNull);
      expect(DigestAuthChallenge.parse(null), isNull);
    });

    test('returns null when the mandatory nonce directive is missing', () {
      expect(DigestAuthChallenge.parse('Digest realm="x"'), isNull);
    });
  });

  group('DigestAuthChallenge.buildAuthorizationHeader', () {
    // The classic worked example from RFC 2617 §3.5 — HA1/HA2/response were
    // independently recomputed with Python's hashlib (not from memory) to
    // serve as ground truth here.
    const challenge = DigestAuthChallenge(
      realm: 'testrealm@host.com',
      nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
      qop: 'auth',
    );

    test('matches the RFC 2617 worked example byte-for-byte', () {
      final header = challenge.buildAuthorizationHeader(
        username: 'Mufasa',
        password: 'Circle Of Life',
        method: 'GET',
        digestUri: '/dir/index.html',
        cnonce: '0a4f113b',
      );

      expect(header, contains('username="Mufasa"'));
      expect(header, contains('realm="testrealm@host.com"'));
      expect(header, contains('nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(header, contains('cnonce="0a4f113b"'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('qop=auth'));
      expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
    });

    test('omits qop/nc/cnonce when the server challenge has no qop', () {
      const noQop = DigestAuthChallenge(realm: 'r', nonce: 'n');
      final header = noQop.buildAuthorizationHeader(
        username: 'u',
        password: 'p',
        method: 'GET',
        digestUri: '/',
        cnonce: 'ignored',
      );

      expect(header, isNot(contains('qop=')));
      expect(header, isNot(contains('cnonce=')));
      expect(header, isNot(contains('nc=')));
    });

    test('uses SHA-256 when the challenge specifies it', () {
      const sha256Challenge = DigestAuthChallenge(
        realm: 'testrealm@host.com',
        nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
        qop: 'auth',
        algorithm: 'SHA-256',
      );
      final header = sha256Challenge.buildAuthorizationHeader(
        username: 'Mufasa',
        password: 'Circle Of Life',
        method: 'GET',
        digestUri: '/dir/index.html',
        cnonce: '0a4f113b',
      );

      expect(header, contains('response="5abdd07184ba512a22c53f41470e5eea7dcaa3a93a59b630c13dfe0a5dc6e38b"'));
    });
  });
}
