// A diagnosis is shown, copied into a bug report and kept in a dialog: it must never carry a credential, whatever went wrong and
// whatever the server echoed back.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'auth_doctor_fixtures.dart';

void main() {
  final expired = jwt({'sub': 'u1', 'exp': epoch(clock) - 7200, 'scope': 'orders:read', 'aud': 'https://api.other.com'});
  const opaque = 'xk93Lm2QpR7vNc84TzWb61HdYf05AsEg';
  const apiKey = 'sk_live_4eC39HqLyjWDarjtT1zdp7dc';
  final basic = 'Basic ${base64.encode(utf8.encode('alice:Tr0ub4dor&3-horse'))}';

  /// Every scenario carries one secret and says what was wrong with the request.
  final scenarios = <String, (AuthDoctorInput, String)>{
    'an expired JWT': (withBearer(expired), expired),
    'a JWT whose server echoes it back': (withBearer(expired, body: '{"error":"invalid_token","error_description":"Invalid token $expired"}'), expired),
    'an opaque token the server echoes back': (withBearer(opaque, body: '{"message":"Unknown token $opaque"}'), opaque),
    'an opaque token echoed in a challenge': (
      withBearer(opaque, responseHeaders: {'WWW-Authenticate': 'Bearer error="invalid_token", error_description="token $opaque is not known"'}),
      opaque,
    ),
    'an API key in a header': (
      rejected(headers: {'X-Api-Key': apiKey}, authType: AuthType.apiKey, apiKeyName: 'X-Api-Key', body: '{"error":"Missing or invalid api_key query parameter"}'),
      apiKey,
    ),
    'an API key in the query string': (
      rejected(headers: const {}, url: 'https://api.example.com/v1/orders?api_key=$apiKey', authType: AuthType.apiKey, apiKeyLocation: ApiKeyLocation.query, body: 'Use the X-API-Key header, not $apiKey'),
      apiKey,
    ),
    'a Basic credential': (rejected(headers: {'Authorization': basic}, authType: AuthType.basic, responseHeaders: const {'WWW-Authenticate': 'Bearer realm="api"'}), basic.substring(6)),
    'a token that is written twice': (withBearer('Bearer $opaque'), opaque),
    'a token with a space in it': (withBearer('${opaque.substring(0, 10)} ${opaque.substring(10)}'), opaque.substring(10)),
    'a cookie': (rejected(status: 403, method: 'POST', headers: {'Cookie': 'sessionid=$opaque'}, authType: AuthType.none, body: 'CSRF verification failed'), opaque),
    'a token in a 407': (
      rejected(status: 407, headers: {'Proxy-Authorization': 'Basic ${base64.encode(utf8.encode('proxy:$opaque'))}'}, responseHeaders: const {'Proxy-Authenticate': 'Basic realm="corp"'}),
      base64.encode(utf8.encode('proxy:$opaque')),
    ),
  };

  for (final entry in scenarios.entries) {
    test('${entry.key}: no finding contains the secret, or a long piece of it', () {
      final (input, secret) = entry.value;
      final findings = AuthDoctor.diagnose(input);

      expect(findings, isNotEmpty);
      final text = allText(findings);
      expect(text, isNot(contains(secret)));
      // Not even the middle of it: only the first four characters and the length may appear.
      expect(text, isNot(contains(secret.substring(secret.length ~/ 3, secret.length ~/ 3 + 12))));
    });
  }

  test('a variable\'s value is not in the input, so it cannot be in a finding: only whether it has one', () {
    const fact = AuthVariableFact(name: 'token', isEmpty: false, isSecret: true, scopeName: 'Production');
    final findings = AuthDoctor.diagnose(rejected(
      headerTemplates: const {'Authorization': 'Bearer {{token}}'},
      variables: const {'token': fact},
      environment: 'Production',
    ));

    expect(findings, isNotEmpty);
    expect(allText(findings), isNot(contains('opaque-token-0123456789abcdef')));
  });

  test('the first four characters of an opaque token and its length are what the evidence may say', () {
    final findings = AuthDoctor.diagnose(withBearer(opaque));

    expect(byId(findings, 'token.opaque').evidence.first, 'The "Authorization" header: Bearer xk93… (${opaque.length} characters)');
  });
}
