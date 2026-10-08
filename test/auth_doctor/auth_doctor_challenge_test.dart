// What the server's own challenge and error words say: RFC 6750 error codes, the scheme it asked for, Digest, a proxy, and a key sent
// to the wrong place.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'auth_doctor_fixtures.dart';

const _opaque = 'opaque-token-0123456789abcdef';

void main() {
  group('Bearer errors (RFC 6750)', () {
    test('invalid_token with the server\'s description is explained, and certain', () {
      final findings = AuthDoctor.diagnose(withBearer(
        _opaque,
        responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api", error="invalid_token", error_description="The access token expired"'},
      ));

      final invalid = byId(findings, 'challenge.invalid-token');
      expect(invalid.confidence, FindingConfidence.certain);
      expect(invalid.explanation, 'The server says the token has expired.');
      expect(invalid.fix, contains('Get a new token'));
      expect(invalid.evidence, contains('error_description: "The access token expired"'));
      expect(invalid.evidence, contains('Realm: api'));
      expect(findings.first.id, 'challenge.invalid-token');
    });

    test('a bad signature, a revoked token, a wrong audience and a malformed token each get their own words', () {
      String explain(String description) {
        final findings = AuthDoctor.diagnose(withBearer(
          _opaque,
          responseHeaders: {'WWW-Authenticate': 'Bearer error="invalid_token", error_description="$description"'},
        ));
        return byId(findings, 'challenge.invalid-token').explanation;
      }

      expect(explain('Signature verification failed'), contains('another key or by another issuer'));
      expect(explain('The token was revoked'), 'The server says the token was revoked.');
      expect(explain('Invalid audience'), contains('another audience'));
      expect(explain('Malformed JWT'), contains('could not read the token'));
      expect(explain(''), contains('without saying why'));
    });

    test('invalid_request names the token sent twice', () {
      final input = rejected(
        headers: const {'Authorization': 'Bearer $_opaque'},
        url: 'https://api.example.com/v1/orders?access_token=$_opaque',
        responseHeaders: const {'WWW-Authenticate': 'Bearer error="invalid_request", error_description="Multiple methods used to include access token"'},
      );

      final invalid = byId(AuthDoctor.diagnose(input), 'challenge.invalid-request');
      expect(invalid.explanation, contains('travels twice'));
      expect(invalid.fix, contains('Remove the token from the query string'));
    });
  });

  group('the scheme the server asked for', () {
    test('Bearer sent, Basic asked for', () {
      final findings = AuthDoctor.diagnose(withBearer(_opaque, responseHeaders: const {'WWW-Authenticate': 'Basic realm="intranet"'}));

      final mismatch = byId(findings, 'challenge.scheme-mismatch');
      expect(mismatch.confidence, FindingConfidence.certain);
      expect(mismatch.title, 'The server wants Basic, the request used Bearer');
      expect(mismatch.fix, contains('Basic Auth'));
    });

    test('Basic sent, Bearer asked for', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Basic YWxpY2U6czNjcmV0LXBhc3M='},
        authType: AuthType.basic,
        responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api"'},
      ));

      expect(byId(findings, 'challenge.scheme-mismatch').title, 'The server wants Bearer, the request used Basic');
    });

    test('an API key in a custom header where the server wants an Authorization scheme is likely', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'X-Api-Key': 'k_0123456789abcdef'},
        authType: AuthType.apiKey,
        apiKeyName: 'X-Api-Key',
        responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api"'},
      ));

      final mismatch = byId(findings, 'challenge.scheme-mismatch');
      expect(mismatch.confidence, FindingConfidence.likely);
      expect(mismatch.title, 'The server wants Bearer in the Authorization header');
    });

    test('the scheme the server asked for is not a mismatch', () {
      final findings = AuthDoctor.diagnose(withBearer(_opaque, responseHeaders: const {'WWW-Authenticate': 'Basic realm="a", Bearer realm="b"'}));

      expect(ids(findings), isNot(contains('challenge.scheme-mismatch')));
    });

    test('Negotiate or NTLM alone is Windows integrated authentication, which PostPilot does not do', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Accept': '*/*'},
        authType: AuthType.none,
        responseHeaders: const {'WWW-Authenticate': 'Negotiate, NTLM'},
      ));

      expect(byId(findings, 'challenge.windows-auth').confidence, FindingConfidence.likely);
      expect(byId(findings, 'challenge.windows-auth').explanation, contains('Negotiate and NTLM'));
    });
  });

  group('Digest', () {
    const header = 'Digest realm="files", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", qop="auth", algorithm=MD5';
    final digest = rejected(headers: const {}, authType: AuthType.digest, responseHeaders: const {'WWW-Authenticate': header});

    test('after the client answered the challenge, a 401 means the user name or password is wrong for that realm', () {
      final findings = AuthDoctor.diagnose(digest);

      final refused = byId(findings, 'challenge.digest-refused');
      expect(refused.confidence, FindingConfidence.likely);
      expect(refused.explanation, contains('for the realm "files"'));
      expect(ids(findings), isNot(contains('credential.none-sent')));
    });

    test('stale=true means only the nonce had expired', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {},
        authType: AuthType.digest,
        responseHeaders: const {'WWW-Authenticate': 'Digest realm="files", nonce="n2", qop="auth", stale=true'},
      ));

      expect(byId(findings, 'challenge.digest-stale').confidence, FindingConfidence.certain);
      expect(ids(findings), isNot(contains('challenge.digest-refused')));
    });

    test('an algorithm the client cannot compute is said so, with the algorithm', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {},
        authType: AuthType.digest,
        responseHeaders: const {'WWW-Authenticate': 'Digest realm="files", nonce="n3", algorithm=SHA-1, qop="auth"'},
      ));

      final unsupported = byId(findings, 'challenge.digest-unsupported');
      expect(unsupported.evidence, contains('algorithm: SHA-1'));
    });
  });

  group('407 Proxy Authentication Required', () {
    test('credentials that were sent and refused', () {
      final findings = AuthDoctor.diagnose(rejected(
        status: 407,
        headers: const {'Proxy-Authorization': 'Basic YWxpY2U6czNjcmV0LXBhc3M='},
        responseHeaders: const {'Proxy-Authenticate': 'Basic realm="corp-proxy"'},
      ));

      final refused = byId(findings, 'challenge.proxy-refused');
      expect(refused.explanation, contains('for the realm "corp-proxy"'));
      expect(refused.evidence.first, startsWith('Proxy-Authenticate: Basic realm="corp-proxy"'));
    });
  });

  group('an API key in the wrong place, from the words of the error', () {
    test('sent in a header, but the server\'s message talks about a query parameter', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'X-Api-Key': 'k_0123456789abcdef'},
        authType: AuthType.apiKey,
        apiKeyName: 'X-Api-Key',
        body: '{"error":"Missing or invalid api_key query parameter"}',
      ));

      final wrong = byId(findings, 'apikey.wrong-place-query');
      expect(wrong.confidence, FindingConfidence.likely);
      expect(wrong.fix, contains('Query Params'));
      expect(wrong.evidence, contains('The key travelled in the header X-Api-Key.'));
    });

    test('sent in the query string, but the server wants a header', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {},
        url: 'https://api.example.com/v1/orders?api_key=k_0123456789abcdef',
        authType: AuthType.apiKey,
        apiKeyLocation: ApiKeyLocation.query,
        apiKeyName: 'api_key',
        body: 'Invalid API key: send it in the X-API-Key header',
      ));

      expect(byId(findings, 'apikey.wrong-place-header').fix, contains('Header'));
    });

    test('sent in a header with another name than the one the server names', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Api-Key': 'k_0123456789abcdef'},
        authType: AuthType.apiKey,
        apiKeyName: 'Api-Key',
        body: '{"message":"Invalid or missing X-Subscription-Key header"}',
      ));

      final name = byId(findings, 'apikey.header-name');
      expect(name.title, 'The server names the header X-Subscription-Key');
      expect(name.evidence, contains('Credential headers sent: Api-Key'));
    });

    test('a key in the header the server names is left alone', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'X-Subscription-Key': 'k_0123456789abcdef'},
        authType: AuthType.apiKey,
        apiKeyName: 'X-Subscription-Key',
        body: '{"message":"Invalid X-Subscription-Key header"}',
      ));

      expect(ids(findings), isNot(contains('apikey.header-name')));
      expect(ids(findings), isNot(contains('apikey.wrong-place-query')));
    });
  });
}
