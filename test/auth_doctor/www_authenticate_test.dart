// How a WWW-Authenticate header is taken apart: RFC 9110 section 11.6.1 and RFC 6750 section 3.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/auth_doctor/domain/services/token_evidence.dart';
import 'package:postpilot/features/auth_doctor/domain/services/www_authenticate.dart';

void main() {
  group('WwwAuthenticate.parse', () {
    test('a Bearer challenge with the RFC 6750 error parameters', () {
      final challenges = WwwAuthenticate.parse(
        'Bearer realm="example", error="invalid_token", error_description="The access token expired", scope="read write"',
      );

      expect(challenges, hasLength(1));
      final bearer = challenges.single;
      expect(bearer.scheme, 'Bearer');
      expect(bearer.realm, 'example');
      expect(bearer.error, 'invalid_token');
      expect(bearer.errorDescription, 'The access token expired');
      expect(bearer.scopes, ['read', 'write']);
    });

    test('several challenges in one header, each with its own parameters', () {
      final challenges = WwwAuthenticate.parse('Basic realm="intranet", Bearer realm="api", error="invalid_request"');

      expect(challenges.map((c) => c.scheme), ['Basic', 'Bearer']);
      expect(challenges.first.realm, 'intranet');
      expect(challenges.last.realm, 'api');
      expect(challenges.last.error, 'invalid_request');
      expect(challenges.first.error, isNull);
    });

    test('a quoted string is read whole: a comma or the word Digest inside a realm does not start a new challenge', () {
      final challenges = WwwAuthenticate.parse('Digest realm="a, Digest b", nonce="n1", qop="auth,auth-int", algorithm=SHA-256, stale=true');

      expect(challenges, hasLength(1));
      expect(challenges.single.realm, 'a, Digest b');
      expect(challenges.single.params['nonce'], 'n1');
      expect(challenges.single.params['qop'], 'auth,auth-int');
      expect(challenges.single.params['algorithm'], 'SHA-256');
      expect(challenges.single.params['stale'], 'true');
    });

    test('a scheme with no parameters, and one that carries a token68', () {
      final bare = WwwAuthenticate.parse('Negotiate');
      expect(bare.single.scheme, 'Negotiate');
      expect(bare.single.params, isEmpty);

      final withToken = WwwAuthenticate.parse('Negotiate YIIB+gYGKwYBBQUCoIIB7jCC==');
      expect(withToken.single.token68, 'YIIB+gYGKwYBBQUCoIIB7jCC==');
      expect(withToken.single.params, isEmpty);

      final mixed = WwwAuthenticate.parse('NTLM, Negotiate, Basic realm="x"');
      expect(mixed.map((c) => c.scheme), ['NTLM', 'Negotiate', 'Basic']);
    });

    test('escaped quotes inside a quoted value', () {
      final challenges = WwwAuthenticate.parse(r'Bearer error_description="the \"exp\" claim is in the past"');

      expect(challenges.single.errorDescription, 'the "exp" claim is in the past');
    });

    test('names are case-insensitive, and scheme matching ignores case', () {
      final challenge = WwwAuthenticate.parse('bearer ERROR="invalid_token"').single;

      expect(challenge.isScheme('Bearer'), isTrue);
      expect(challenge.error, 'invalid_token');
    });

    test('nothing, or an empty header, is no challenge', () {
      expect(WwwAuthenticate.parse(null), isEmpty);
      expect(WwwAuthenticate.parse('   '), isEmpty);
    });
  });

  group('TokenEvidence', () {
    test('a token is its first four characters and its length', () {
      const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln';

      expect(TokenEvidence.of(token), 'eyJh… (${token.length} characters)');
    });

    test('a value too short to show a prefix harmlessly shows only its length', () {
      expect(TokenEvidence.of('secret1234'), '10 characters');
      expect(TokenEvidence.of('x'), '1 character');
      expect(TokenEvidence.of(''), 'empty');
    });

    test('a header value keeps its scheme and hides the rest', () {
      expect(TokenEvidence.ofHeader('Bearer abcdefghijklmnop'), 'Bearer abcd… (16 characters)');
      expect(TokenEvidence.ofHeader('Bearer'), '6 characters');
    });

    test('text the server wrote is masked, put on one line and clipped', () {
      final quoted = TokenEvidence.quote('Invalid token\nsk_live_abcdefghijklmnop1234 was rejected');

      expect(quoted, isNot(contains('\n')));
      expect(quoted, isNot(contains('abcdefghijklmnop1234')));
      expect(TokenEvidence.quote('a' * 300, max: 20), hasLength(20));
      expect(TokenEvidence.quote('a' * 300, max: 20), endsWith('…'));
    });
  });
}
