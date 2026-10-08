import 'dart:convert';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';

/// The moment every test of the doctor treats as "now".
final clock = DateTime.utc(2026, 10, 8, 12);

int epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

String _part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A JWT whose parts are the standard base64url of JSON, as any identity provider writes them. The signature is not a real one: the
/// doctor never verifies it.
String jwt(Map<String, Object?> payload, {Map<String, Object?>? header}) =>
    '${_part(header ?? {'alg': 'HS256', 'typ': 'JWT'})}.${_part(payload)}.c2lnbmF0dXJlLW5vdC1yZWFs';

/// A JWT that is valid for an hour from [clock].
String freshJwt([Map<String, Object?> extra = const {}]) =>
    jwt({'sub': 'u1', 'iat': epoch(clock) - 60, 'exp': epoch(clock) + 3600, ...extra});

/// A rejected request and response with only what a test cares about. The request defaults to a GET with an opaque Bearer token.
AuthDoctorInput rejected({
  int status = 401,
  String method = 'GET',
  String url = 'https://api.example.com/v1/orders',
  Map<String, String>? headers,
  AuthType authType = AuthType.bearer,
  String apiKeyName = '',
  ApiKeyLocation apiKeyLocation = ApiKeyLocation.header,
  Map<String, String> headerTemplates = const {},
  Map<String, String> queryTemplates = const {},
  bool requestKnown = true,
  Map<String, String> responseHeaders = const {},
  String body = '',
  String? environment,
  Map<String, AuthVariableFact> variables = const {},
  List<AuthEnvironmentFacts> others = const [],
  List<AuthRedirectHop> redirects = const [],
}) =>
    AuthDoctorInput(
      method: method,
      url: url,
      headers: headers ?? const {'Authorization': 'Bearer opaque-token-0123456789abcdef'},
      authType: authType,
      apiKeyName: apiKeyName,
      apiKeyLocation: apiKeyLocation,
      headerTemplates: headerTemplates,
      queryTemplates: queryTemplates,
      requestKnown: requestKnown,
      status: status,
      responseHeaders: responseHeaders,
      responseBody: body,
      environmentName: environment,
      variables: variables,
      otherEnvironments: others,
      redirects: redirects,
      now: clock,
    );

/// A request that carries [token] as a Bearer token.
AuthDoctorInput withBearer(
  String token, {
  int status = 401,
  Map<String, String> responseHeaders = const {},
  String body = '',
  String url = 'https://api.example.com/v1/orders',
  String method = 'GET',
}) =>
    rejected(
      status: status,
      headers: {'Authorization': 'Bearer $token'},
      responseHeaders: responseHeaders,
      body: body,
      url: url,
      method: method,
    );

Iterable<String> ids(Iterable<AuthFinding> findings) => findings.map((f) => f.id);

AuthFinding byId(Iterable<AuthFinding> findings, String id) => findings.firstWhere((f) => f.id == id, orElse: () => throw StateError('no finding "$id" in ${ids(findings).toList()}'));

/// Every word a finding says, for checks that must not find a secret in any of it.
String allText(Iterable<AuthFinding> findings) => findings.map((f) => f.toPlainText()).join('\n');
