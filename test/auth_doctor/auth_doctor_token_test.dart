// What the token itself says, read with the app's JWT decoder. The clock is fixed at 2026-10-08 12:00:00 UTC, and every duration
// below is worked out by hand from it.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'auth_doctor_fixtures.dart';

void main() {
  group('expiry', () {
    // 12:00:00 minus 3 h 12 min 5 s is 08:47:55.
    final expiredAt = clock.subtract(const Duration(hours: 3, minutes: 12, seconds: 5));

    test('an expired token says when, and how long ago, in words a person can act on', () {
      final token = jwt({'sub': 'u1', 'iat': epoch(expiredAt) - 900, 'exp': epoch(expiredAt)});
      final findings = AuthDoctor.diagnose(withBearer(token));

      final expired = byId(findings, 'jwt.expired');
      expect(expired.confidence, FindingConfidence.certain);
      expect(expired.title, 'The token has expired');
      expect(expired.explanation, contains('expired at 2026-10-08 08:47 UTC'));
      expect(expired.explanation, contains('3 hours 12 minutes before this response'));
      expect(expired.evidence, contains('exp: 2026-10-08 08:47 UTC (3 hours 12 minutes ago)'));
      expect(expired.evidence, contains('Lifetime of the token: 15 minutes.'));
      expect(findings.first.id, 'jwt.expired');
    });

    test('the evidence shows the first four characters of the token and its length, never the token', () {
      final token = jwt({'exp': epoch(expiredAt)});
      final findings = AuthDoctor.diagnose(withBearer(token));

      final expired = byId(findings, 'jwt.expired');
      expect(expired.evidence.first, 'The "Authorization" header: Bearer eyJh… (${token.length} characters)');
      expect(allText(findings), isNot(contains(token)));
      expect(allText(findings), isNot(contains(token.substring(4, 40))));
    });

    test('the fix names the variable the token was written with', () {
      final token = jwt({'exp': epoch(expiredAt)});
      final input = rejected(
        headers: {'Authorization': 'Bearer $token'},
        headerTemplates: const {'Authorization': 'Bearer {{accessToken}}'},
      );

      expect(byId(AuthDoctor.diagnose(input), 'jwt.expired').fix, contains('save it in {{accessToken}}'));
    });

    test('a token that is still valid is not blamed', () {
      final findings = AuthDoctor.diagnose(withBearer(freshJwt()));

      expect(ids(findings).where((id) => id.startsWith('jwt.')), isEmpty);
    });

    test('what the server said is added to the evidence, and its own invalid_token card is not repeated', () {
      final token = jwt({'exp': epoch(expiredAt)});
      final findings = AuthDoctor.diagnose(withBearer(
        token,
        responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api", error="invalid_token", error_description="The access token expired"'},
      ));

      expect(byId(findings, 'jwt.expired').evidence, contains('The server said: "The access token expired"'));
      expect(ids(findings), isNot(contains('challenge.invalid-token')));
    });

    test('a token in a custom header, or in the query string, is read as well', () {
      final token = jwt({'exp': epoch(expiredAt)});

      final header = AuthDoctor.diagnose(rejected(headers: {'X-Auth-Token': token}, authType: AuthType.apiKey, apiKeyName: 'X-Auth-Token'));
      expect(byId(header, 'jwt.expired').evidence.first, 'The "X-Auth-Token" header: eyJh… (${token.length} characters)');

      final query = AuthDoctor.diagnose(rejected(headers: const {}, url: 'https://api.example.com/v1/orders?access_token=$token'));
      expect(byId(query, 'jwt.expired').evidence.first, startsWith('The "access_token" query parameter: eyJh…'));
    });
  });

  group('clocks: nbf and iat', () {
    test('a token that is not valid yet says by how long, and what the server\'s own clock says', () {
      final token = jwt({'nbf': epoch(clock) + 90, 'exp': epoch(clock) + 3600});
      final findings = AuthDoctor.diagnose(withBearer(token, responseHeaders: const {'Date': 'Thu, 08 Oct 2026 12:10:00 GMT'}));

      final early = byId(findings, 'jwt.not-yet-valid');
      expect(early.confidence, FindingConfidence.certain);
      expect(early.explanation, contains('which is 1 minute 30 seconds after this response'));
      expect(early.evidence, contains('nbf: 2026-10-08 12:01 UTC (in 1 minute 30 seconds)'));
      expect(early.evidence, contains('The server\'s Date header is 10 minutes ahead of this computer.'));
    });

    test('a token issued five minutes in the future is a clock problem; thirty seconds is within tolerance', () {
      final skewed = AuthDoctor.diagnose(withBearer(jwt({'iat': epoch(clock) + 300, 'exp': epoch(clock) + 3600})));
      final finding = byId(skewed, 'jwt.issued-in-future');
      expect(finding.confidence, FindingConfidence.likely);
      expect(finding.explanation, contains('5 minutes after this response'));

      final fine = AuthDoctor.diagnose(withBearer(jwt({'iat': epoch(clock) + 30, 'exp': epoch(clock) + 3600})));
      expect(ids(fine), isNot(contains('jwt.issued-in-future')));
    });

    test('the Date header is only mentioned when the two clocks really differ', () {
      final token = jwt({'nbf': epoch(clock) + 90});
      final close = AuthDoctor.diagnose(withBearer(token, responseHeaders: const {'Date': 'Thu, 08 Oct 2026 12:01:00 GMT'}));

      expect(byId(close, 'jwt.not-yet-valid').evidence.where((e) => e.contains('Date header')), isEmpty);
    });
  });

  group('algorithm, kind, audience, issuer', () {
    test('alg none is an unsigned token', () {
      final token = jwt({'sub': 'u1', 'exp': epoch(clock) + 3600}, header: {'alg': 'none'});
      final findings = AuthDoctor.diagnose(withBearer(token));

      final unsigned = byId(findings, 'jwt.alg-none');
      expect(unsigned.confidence, FindingConfidence.likely);
      expect(unsigned.evidence, contains('header alg: none'));
    });

    test('an ID token, or a refresh token, where an access token is needed', () {
      final id = AuthDoctor.diagnose(withBearer(freshJwt({'token_use': 'id'})));
      expect(byId(id, 'jwt.wrong-kind').title, 'This is an ID token, not an access token');

      final refresh = AuthDoctor.diagnose(withBearer(freshJwt({'typ': 'Refresh'})));
      expect(byId(refresh, 'jwt.wrong-kind').title, 'This is a refresh token, not an access token');
      expect(byId(refresh, 'jwt.wrong-kind').fix, contains('access_token'));
    });

    test('an audience that names another host is likely the cause; one that matches, or is only an identifier, is not', () {
      final other = AuthDoctor.diagnose(withBearer(freshJwt({'aud': 'https://api.other.com'})));
      final audience = byId(other, 'jwt.audience');
      expect(audience.confidence, FindingConfidence.likely);
      expect(audience.evidence, containsAll(['aud: https://api.other.com', 'Request host: api.example.com']));

      for (final aud in <Object>[
        ['https://api.example.com/', 'billing'],
        'orders-api',
        'example.com',
        'https://api.example.com',
      ]) {
        expect(ids(AuthDoctor.diagnose(withBearer(freshJwt({'aud': aud})))), isNot(contains('jwt.audience')), reason: '$aud');
      }
    });

    test('an issuer on another domain is only possible; one on the same domain is nothing', () {
      final other = AuthDoctor.diagnose(withBearer(freshJwt({'iss': 'https://login.microsoftonline.com/tenant/v2.0'})));
      expect(byId(other, 'jwt.issuer').confidence, FindingConfidence.possible);

      final same = AuthDoctor.diagnose(withBearer(freshJwt({'iss': 'https://auth.example.com'})));
      expect(ids(same), isNot(contains('jwt.issuer')));
    });

    test('a staging identity provider against a production host is likely', () {
      final findings = AuthDoctor.diagnose(withBearer(
        freshJwt({'iss': 'https://staging-auth.other.com/'}),
        url: 'https://prod-api.acme.com/v1/orders',
      ));

      final issuer = byId(findings, 'jwt.issuer');
      expect(issuer.confidence, FindingConfidence.likely);
      expect(issuer.title, 'The token comes from a staging login, the API is production');
    });
  });

  group('scope and role', () {
    const insufficient = {'WWW-Authenticate': 'Bearer error="insufficient_scope", scope="orders:write orders:read"'};

    test('the scopes the server asks for, against the ones in the token', () {
      final findings = AuthDoctor.diagnose(withBearer(freshJwt({'scope': 'orders:read profile'}), status: 403, responseHeaders: insufficient));

      final scope = byId(findings, 'token.missing-scope');
      expect(scope.confidence, FindingConfidence.certain);
      expect(scope.title, 'The token lacks a scope or role the API asks for');
      expect(scope.explanation, contains('Missing: "orders:write"'));
      expect(scope.evidence, containsAll(['Required: orders:write orders:read', 'In the token: orders:read profile']));
      // The server's own card would say the same thing again.
      expect(ids(findings), isNot(contains('challenge.insufficient-scope')));
    });

    test('a token with no scope claim at all says that', () {
      final findings = AuthDoctor.diagnose(withBearer(freshJwt(), status: 403, responseHeaders: insufficient));

      expect(byId(findings, 'token.missing-scope').explanation, contains('has no scope or role claim at all'));
    });

    test('scp as a list, and roles under realm_access, count: the token is then not the one lacking them', () {
      final scp = AuthDoctor.diagnose(withBearer(freshJwt({'scp': ['orders:write', 'orders:read']}), status: 403, responseHeaders: insufficient));
      expect(ids(scp), isNot(contains('token.missing-scope')));
      // The server still says so, and the card admits that the token does list them.
      expect(byId(scp, 'challenge.insufficient-scope').explanation, contains('although'));

      const needsRole = {'WWW-Authenticate': 'Bearer error="insufficient_scope", scope="orders-admin"'};
      final keycloak = AuthDoctor.diagnose(withBearer(
        freshJwt({'realm_access': {'roles': ['orders-admin']}}),
        status: 403,
        responseHeaders: needsRole,
      ));
      expect(ids(keycloak), isNot(contains('token.missing-scope')));
      expect(byId(keycloak, 'challenge.insufficient-scope').explanation, contains('"orders-admin"'));
    });

    test('a scope or role named only in the body is likely, not certain', () {
      final findings = AuthDoctor.diagnose(withBearer(
        freshJwt({'scope': 'orders:read'}),
        status: 403,
        body: '{"message":"Missing required scope: reports.read"}',
      ));

      final scope = byId(findings, 'token.missing-scope');
      expect(scope.confidence, FindingConfidence.likely);
      expect(scope.evidence, contains('Required: reports.read'));
    });

    test('the server\'s insufficient_scope is its own finding when the token cannot be read', () {
      final findings = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403, responseHeaders: insufficient));

      final scope = byId(findings, 'challenge.insufficient-scope');
      expect(scope.confidence, FindingConfidence.certain);
      expect(scope.explanation, contains('"orders:write" and "orders:read"'));
    });
  });

  group('a token that is not a JWT', () {
    test('it is said that it cannot be inspected, as a possibility', () {
      final findings = AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef'));

      final opaque = byId(findings, 'token.opaque');
      expect(opaque.confidence, FindingConfidence.possible);
      expect(opaque.evidence.first, 'The "Authorization" header: Bearer opaq… (29 characters)');
    });

    test('but not when something certain was found already, and not for a 403', () {
      expect(ids(AuthDoctor.diagnose(withBearer('null'))), isNot(contains('token.opaque')));
      expect(ids(AuthDoctor.diagnose(withBearer('opaque-token-0123456789abcdef', status: 403))), isNot(contains('token.opaque')));
    });
  });
}
