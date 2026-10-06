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
      expect(header, contains('algorithm=SHA-256'), reason: 'the response says which algorithm it used');
    });
  });

  // RFC 7616 §3.9.1 uses this challenge for its MD5 and SHA-256 examples. Every
  // expected `response` below was computed independently with Python's hashlib
  // (`hashlib.md5` / `sha256` / `new('sha512_256')`), following RFC 7616 §3.4.1-3.4.2;
  // the MD5 and SHA-256 ones are also the values printed in the RFC.
  group('RFC 7616 example challenge', () {
    String challengeFor(String algorithm, {String qop = 'auth'}) =>
        'Digest realm="http-auth@example.org", qop="$qop", algorithm=$algorithm, '
        'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", '
        'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"';

    String answer(String algorithm, {String qop = 'auth', String method = 'GET', List<int> body = const []}) =>
        DigestAuthChallenge.parse(challengeFor(algorithm, qop: qop))!.buildAuthorizationHeader(
          username: 'Mufasa',
          password: 'Circle of Life',
          method: method,
          digestUri: '/dir/index.html',
          body: body,
          cnonce: 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
        );

    const expected = {
      'MD5': '8ca523f5e9506fed4657c9700eebdbec',
      'SHA-256': '753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1',
      'SHA-512-256': '430d05014cecc49cab6fbe03176d41a1da86cbfe24a16580e22aaad928d960d0',
      'MD5-sess': 'e783283f46242139c486a698fec7211d',
      'SHA-256-sess': '2fd51b3a77ad75bad6afad6003e818d767133c46d9e2749e7f5232ae1ea3efd7',
      'SHA-512-256-sess': '3f2a34f923c38b0fb26dce2fdfc2ce326c23cecf86fbb1444f3e51fbbc2cb92e',
    };

    for (final entry in expected.entries) {
      test('${entry.key} gives the right response', () {
        final header = answer(entry.key);

        expect(header, contains('response="${entry.value}"'));
        expect(header, contains('algorithm=${entry.key.toUpperCase()}'));
        expect(header, contains('qop=auth,'));
        expect(header, contains('nc=00000001'));
        expect(header, contains('cnonce="f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"'));
        expect(header, contains('opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"'));
        expect(header, contains('uri="/dir/index.html"'));
      });
    }

    test('a list of qualities of protection is answered with auth, in the hash and in the header', () {
      final header = answer('MD5', qop: 'auth,auth-int');

      expect(header, contains('response="8ca523f5e9506fed4657c9700eebdbec"'));
      expect(header, contains('qop=auth,'));
      expect(header, isNot(contains('auth-int')), reason: 'the header names exactly one quality');
    });

    test('auth is picked wherever it sits in the list', () {
      final header = answer('MD5', qop: 'auth-int, auth');

      expect(header, contains('response="8ca523f5e9506fed4657c9700eebdbec"'));
      expect(header, contains('qop=auth,'));
    });

    test('auth-int alone covers the request body in the hash', () {
      final md5Header = answer('MD5', qop: 'auth-int', method: 'POST', body: '{"a":1}'.codeUnits);
      final sha256Header = answer('SHA-256', qop: 'auth-int', method: 'POST', body: '{"a":1}'.codeUnits);

      expect(md5Header, contains('response="15b188edd42ec64280df76d316ec198e"'));
      expect(md5Header, contains('qop=auth-int,'));
      expect(sha256Header, contains('response="193d6834c8f5b21e6b707fdd7de62ad0b3514493466cf33958098aa6d3836274"'));
    });

    test('auth-int with no body hashes the empty body', () {
      expect(answer('MD5', qop: 'auth-int'), contains('response="8804a53d3640a40a4f73cea12c5ba451"'));
    });

    test('without a qop the old form is used for any algorithm, and no cnonce or nc is sent', () {
      final challenge = DigestAuthChallenge.parse(
        'Digest realm="http-auth@example.org", algorithm=SHA-256, nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"',
      )!;

      final header = challenge.buildAuthorizationHeader(
        username: 'Mufasa',
        password: 'Circle of Life',
        method: 'GET',
        digestUri: '/dir/index.html',
        cnonce: 'ignored',
      );

      expect(header, contains('response="a1306b0595a6c7fe96c448631fb5cfbd5107bd1fe1da729d978dd7446b812363"'));
      expect(header, isNot(contains('cnonce')));
      expect(header, isNot(contains('nc=')));
      expect(header, isNot(contains('qop')));
    });

    test('a quote or backslash in the user name is escaped, so the header stays well formed', () {
      final header = DigestAuthChallenge.parse(challengeFor('MD5'))!.buildAuthorizationHeader(
        username: r'a"b\c',
        password: 'p',
        method: 'GET',
        digestUri: '/',
        cnonce: 'c',
      );

      expect(header, contains(r'username="a\"b\\c"'));
    });
  });

  group('DigestAuthChallenge.parse of several challenges and algorithms', () {
    test('picks the first Digest challenge it can answer, skipping Basic ones', () {
      final challenge = DigestAuthChallenge.parse(
        'Basic realm="b", Digest realm="first", nonce="n1", algorithm=SHA-256, '
        'Digest realm="second", nonce="n2", algorithm=MD5',
      )!;

      expect(challenge.realm, 'first');
      expect(challenge.nonce, 'n1');
      expect(challenge.algorithm, 'SHA-256');
      expect(challenge.explicitAlgorithm, isTrue);
    });

    test('skips a challenge whose algorithm it does not know', () {
      final challenge = DigestAuthChallenge.parse(
        'Digest realm="a", nonce="n1", algorithm=SHA-3-512, Digest realm="b", nonce="n2", algorithm=MD5',
      )!;

      expect(challenge.realm, 'b');
    });

    test('is null when it can answer none: unknown algorithm, or no quality of protection it knows', () {
      expect(DigestAuthChallenge.parse('Digest realm="a", nonce="n", algorithm=SHA-3-512'), isNull);
      expect(DigestAuthChallenge.parse('Digest realm="a", nonce="n", qop="auth-conf"'), isNull);
    });

    test('a comma, a quote or the word Digest inside a realm does not start another directive or challenge', () {
      final challenge = DigestAuthChallenge.parse(r'Digest realm="My, \"Digest\" Server", nonce="n", qop="auth"')!;

      expect(challenge.realm, 'My, "Digest" Server');
      expect(challenge.nonce, 'n');
      expect(challenge.qop, 'auth');
    });

    test('an algorithm the server does not name is MD5, and is not announced', () {
      final challenge = DigestAuthChallenge.parse('Digest realm="r", nonce="n"')!;

      expect(challenge.algorithm, 'MD5');
      expect(challenge.explicitAlgorithm, isFalse);
      expect(
        challenge.buildAuthorizationHeader(username: 'u', password: 'p', method: 'GET', digestUri: '/', cnonce: 'c'),
        isNot(contains('algorithm=')),
      );
    });

    test('algorithm names are read in any case', () {
      expect(DigestAuthChallenge.parse('Digest nonce="n", algorithm=sha-256')!.algorithm, 'SHA-256');
      expect(DigestAuthChallenge.parse('Digest nonce="n", algorithm=md5-SESS')!.algorithm, 'MD5-SESS');
    });
  });
}
