// The first questions about a 401: was a credential sent at all, was it the one that was meant, and was it written correctly.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'auth_doctor_fixtures.dart';

void main() {
  group('no credential at all', () {
    test('a 401 with no Authorization, cookie, key header or key parameter says so, and it is certain', () {
      final findings = AuthDoctor.diagnose(rejected(headers: const {'Accept': 'application/json'}, authType: AuthType.none));

      final none = byId(findings, 'credential.none-sent');
      expect(none.confidence, FindingConfidence.certain);
      expect(none.explanation, contains('"No Auth"'));
      expect(none.fix, contains('Auth tab'));
      expect(findings.first.id, 'credential.none-sent');
    });

    test('a 403 gets the same finding, one level lower: many servers answer an anonymous call with 403', () {
      final findings = AuthDoctor.diagnose(rejected(status: 403, headers: const {'Accept': '*/*'}, authType: AuthType.none));

      expect(byId(findings, 'credential.none-sent').confidence, FindingConfidence.likely);
    });

    test('a cookie, an API-key header and a key in the query string each count as a credential', () {
      for (final input in [
        rejected(headers: const {'Cookie': 'session=abc123'}, authType: AuthType.none),
        rejected(headers: const {'X-Api-Key': 'k_0123456789abcdef'}, authType: AuthType.apiKey, apiKeyName: 'X-Api-Key'),
        rejected(headers: const {}, url: 'https://api.example.com/v1/orders?api_key=k_0123456789abcdef', authType: AuthType.apiKey, apiKeyLocation: ApiKeyLocation.query),
      ]) {
        expect(ids(AuthDoctor.diagnose(input)), isNot(contains('credential.none-sent')), reason: input.url);
      }
    });

    test('a CSRF header is not a credential', () {
      final findings = AuthDoctor.diagnose(rejected(headers: const {'X-CSRF-Token': 'abcdef0123456789'}, authType: AuthType.none));

      expect(ids(findings), contains('credential.none-sent'));
    });

    test('Digest auth sends its credential only after the challenge, so an empty header list is not "nothing sent"', () {
      final findings = AuthDoctor.diagnose(rejected(headers: const {}, authType: AuthType.digest));

      expect(ids(findings), isNot(contains('credential.none-sent')));
    });

    test('the explanation follows the auth type: an API key without a name, OAuth without a token, an auth that inherits nothing', () {
      expect(byId(AuthDoctor.diagnose(rejected(headers: const {}, authType: AuthType.apiKey)), 'credential.none-sent').explanation, contains('no name'));
      expect(byId(AuthDoctor.diagnose(rejected(headers: const {}, authType: AuthType.oauth2)), 'credential.none-sent').explanation, contains('no access token yet'));
      expect(byId(AuthDoctor.diagnose(rejected(headers: const {}, authType: AuthType.inherit)), 'credential.none-sent').explanation, contains('inherit'));
    });

    test('a request the doctor could not rebuild is not accused of sending nothing', () {
      final findings = AuthDoctor.diagnose(rejected(headers: const {}, authType: AuthType.none, requestKnown: false));

      expect(ids(findings), isNot(contains('credential.none-sent')));
      expect(findings, isNotEmpty);
    });

    test('a 407 needs Proxy-Authorization, not Authorization', () {
      final withoutProxyCredential = AuthDoctor.diagnose(rejected(
        status: 407,
        headers: const {'Authorization': 'Bearer opaque-token-0123456789abcdef'},
        responseHeaders: const {'Proxy-Authenticate': 'Basic realm="corp-proxy"'},
      ));

      expect(byId(withoutProxyCredential, 'credential.no-proxy-credential').confidence, FindingConfidence.certain);
      expect(ids(withoutProxyCredential), isNot(contains('credential.none-sent')));
    });
  });

  group('the variable that feeds the credential', () {
    test('an undefined {{token}} is named, with the environment that is active', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer {{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
      ));

      final undefined = byId(findings, 'credential.variable-undefined');
      expect(undefined.confidence, FindingConfidence.certain);
      expect(undefined.title, '{{token}} is not defined');
      expect(undefined.explanation, contains('the active environment is "Production"'));
      expect(undefined.evidence, contains('Active environment: Production.'));
      // The literal placeholder on the wire is the same fault, not a second finding.
      expect(ids(findings), isNot(contains('credential.placeholder')));
      expect(findings.first.id, 'credential.variable-undefined');
    });

    test('with no environment selected the explanation says so', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer {{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
      ));

      final undefined = byId(findings, 'credential.variable-undefined');
      expect(undefined.explanation, contains('no environment is selected'));
      expect(undefined.evidence, contains('No environment is active.'));
    });

    test('an empty variable is certain, names the environment that holds it, and does not also say the header is empty', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer '},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
        variables: const {'token': AuthVariableFact(name: 'token', isEmpty: true, isSecret: true, scopeName: 'Production')},
      ));

      final empty = byId(findings, 'credential.variable-empty');
      expect(empty.confidence, FindingConfidence.certain);
      expect(empty.title, '{{token}} is empty');
      expect(empty.explanation, contains('environment "Production"'));
      expect(empty.evidence, contains('{{token}} is empty in the environment "Production" (a secret variable).'));
      expect(ids(findings), isNot(contains('credential.empty')));
    });

    test('a variable that has a value is not blamed', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer opaque-token-0123456789abcdef'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
        variables: const {'token': AuthVariableFact(name: 'token', scopeName: 'Production')},
      ));

      expect(ids(findings), isNot(contains('credential.variable-undefined')));
      expect(ids(findings), isNot(contains('credential.variable-empty')));
    });

    test('a variable in a query key and in a cookie is found the same way', () {
      final query = AuthDoctor.diagnose(rejected(
        headers: const {},
        url: 'https://api.example.com/v1/orders?api_key=',
        queryTemplates: const {'api_key': '{{apiKey}}'},
        authType: AuthType.apiKey,
        apiKeyLocation: ApiKeyLocation.query,
        variables: const {'apiKey': AuthVariableFact(name: 'apiKey', isEmpty: true)},
      ));
      expect(byId(query, 'credential.variable-empty').explanation, contains('"api_key" query parameter'));

      final cookie = AuthDoctor.diagnose(rejected(
        headers: const {'Cookie': ''},
        headerTemplates: const {'Cookie': 'session={{session}}'},
        authType: AuthType.none,
      ));
      expect(ids(cookie), contains('credential.variable-undefined'));
    });
  });

  group('the value that was sent', () {
    test('a token that is the word null or undefined', () {
      for (final word in ['null', 'undefined', 'NaN']) {
        final findings = AuthDoctor.diagnose(withBearer(word));
        final literal = byId(findings, 'credential.literal-null');
        expect(literal.confidence, FindingConfidence.certain, reason: word);
        expect(literal.title, 'The token is the word "${word.toLowerCase()}"');
        expect(literal.fix, contains('extractor'));
      }
    });

    test('a doubled scheme word: Bearer Bearer', () {
      final findings = AuthDoctor.diagnose(withBearer('Bearer abcdef0123456789'));

      final doubled = byId(findings, 'credential.double-scheme');
      expect(doubled.confidence, FindingConfidence.certain);
      expect(doubled.fix, contains('only one place'));
      expect(findings.first.id, 'credential.double-scheme');
    });

    test('a space or a line break inside the token', () {
      final spaced = AuthDoctor.diagnose(withBearer('abcdef012345 6789abcdef'));
      expect(byId(spaced, 'credential.whitespace').confidence, FindingConfidence.certain);

      final newline = AuthDoctor.diagnose(withBearer('abcdef0123456789abcdef\n'));
      expect(byId(newline, 'credential.whitespace').confidence, FindingConfidence.certain);
    });

    test('a scheme that carries spaces of its own is not whitespace in the token', () {
      const signed = 'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261008/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7';
      final findings = AuthDoctor.diagnose(rejected(headers: const {'Authorization': signed}, authType: AuthType.awsSignatureV4));

      expect(ids(findings), isNot(contains('credential.whitespace')));
      expect(ids(findings), isNot(contains('credential.no-scheme')));
    });

    test('a bare scheme word, or nothing after it, is an empty credential', () {
      for (final value in ['Bearer ', 'Bearer', '']) {
        final findings = AuthDoctor.diagnose(rejected(headers: {'Authorization': value}));
        expect(byId(findings, 'credential.empty').confidence, FindingConfidence.certain, reason: '"$value"');
      }
    });

    test('a token in quotes is likely, a token with spaces around it is likely', () {
      final quoted = AuthDoctor.diagnose(withBearer('"abcdef0123456789abcdef"'));
      expect(byId(quoted, 'credential.quoted').confidence, FindingConfidence.likely);

      final padded = AuthDoctor.diagnose(rejected(headers: const {'X-Api-Key': ' k_0123456789abcdef'}, authType: AuthType.apiKey, apiKeyName: 'X-Api-Key'));
      expect(byId(padded, 'credential.padding').confidence, FindingConfidence.likely);
    });

    test('a bare token in Authorization, with no Bearer in front, is likely; an API key under that name is not', () {
      const bare = {'Authorization': 'abcdef0123456789abcdef'};
      expect(byId(AuthDoctor.diagnose(rejected(headers: bare)), 'credential.no-scheme').confidence, FindingConfidence.likely);
      expect(ids(AuthDoctor.diagnose(rejected(headers: bare, authType: AuthType.apiKey, apiKeyName: 'Authorization'))), isNot(contains('credential.no-scheme')));
    });

    test('Basic credentials that are not user:password, or have an empty half', () {
      String basic(String text) => 'Basic ${base64.encode(utf8.encode(text))}';

      final noColon = AuthDoctor.diagnose(rejected(headers: {'Authorization': basic('justausername')}, authType: AuthType.basic));
      expect(byId(noColon, 'credential.basic-malformed').confidence, FindingConfidence.likely);

      final notBase64 = AuthDoctor.diagnose(rejected(headers: const {'Authorization': 'Basic user:password'}, authType: AuthType.basic));
      expect(ids(notBase64), contains('credential.basic-malformed'));

      final emptyPassword = AuthDoctor.diagnose(rejected(headers: {'Authorization': basic('alice:')}, authType: AuthType.basic));
      final half = byId(emptyPassword, 'credential.basic-empty-half');
      expect(half.confidence, FindingConfidence.certain);
      expect(half.title, 'The Basic password is empty');

      final emptyUser = AuthDoctor.diagnose(rejected(headers: {'Authorization': basic(':s3cret')}, authType: AuthType.basic));
      expect(byId(emptyUser, 'credential.basic-empty-half').title, 'The Basic user name is empty');

      final fine = AuthDoctor.diagnose(rejected(headers: {'Authorization': basic('alice:s3cret-pass')}, authType: AuthType.basic));
      expect(ids(fine), isNot(contains('credential.basic-malformed')));
      expect(ids(fine), isNot(contains('credential.basic-empty-half')));
    });

    test('a placeholder that reached the server unresolved', () {
      final findings = AuthDoctor.diagnose(withBearer('{{session}}'));

      expect(byId(findings, 'credential.placeholder').confidence, FindingConfidence.certain);
    });

    test('a credential in the query string is checked like one in a header', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {},
        url: 'https://api.example.com/v1/orders?access_token=null&page=2',
        authType: AuthType.none,
      ));

      final literal = byId(findings, 'credential.literal-null');
      expect(literal.explanation, contains('"access_token" query parameter'));
    });

    test('a request that could not be rebuilt gets no claim about its credential', () {
      final findings = AuthDoctor.diagnose(rejected(headers: const {'Authorization': 'Bearer null'}, requestKnown: false));

      expect(ids(findings), isNot(contains('credential.literal-null')));
    });
  });

  group('which responses the doctor answers', () {
    test('401, 403, 407, 419 and 498 always; a 400 only when its body talks about the token', () {
      expect([for (final s in [401, 403, 407, 419, 498]) AuthDoctor.appliesTo(s)], everyElement(isTrue));
      expect(AuthDoctor.appliesTo(400, '{"error":"invalid_token","error_description":"The access token expired"}'), isTrue);
      expect(AuthDoctor.appliesTo(400, 'Invalid JWT signature'), isTrue);
      expect(AuthDoctor.appliesTo(400, '{"error":"name is required"}'), isFalse);
      expect(AuthDoctor.appliesTo(400), isFalse);
      expect([for (final s in [200, 201, 204, 302, 404, 429, 500, 503]) AuthDoctor.appliesTo(s, 'invalid token')], everyElement(isFalse));
    });

    test('anything else gets no findings', () {
      expect(AuthDoctor.diagnose(rejected(status: 200)), isEmpty);
      expect(AuthDoctor.diagnose(rejected(status: 500, body: 'invalid token')), isEmpty);
    });

    test('a rejection nothing else explains still gets one honest, hedged answer', () {
      final findings = AuthDoctor.diagnose(rejected());

      expect(findings.first.id, 'generic.401');
      expect(findings.first.confidence, FindingConfidence.possible);
      // The token is opaque, so the doctor says that it could not look inside it.
      expect(ids(findings), contains('token.opaque'));
      expect(findings.every((f) => f.confidence == FindingConfidence.possible), isTrue);
    });
  });
}
