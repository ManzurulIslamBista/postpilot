// How the doctor's input is gathered from the app's own stores: the request as a send would build it, the templates beside it, and what
// the variable scopes and the environments say, without a single value.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'package:postpilot/features/auth_doctor/domain/usecases/build_auth_doctor_input_usecase.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'auth_doctor_fixtures.dart';

ApiResponseEntity _response(int status, {String body = '', Map<String, String> headers = const {}}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: status == 401 ? 'Unauthorized' : '',
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: const Duration(milliseconds: 40),
    );

/// An environment repository that cannot be read, as a database that failed would be.
final class _BrokenEnvironments implements EnvironmentRepository {
  @override
  Stream<List<EnvironmentEntity>> watchAll() => Stream.error(StateError('database is locked'));
  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.error(StateError('database is locked'));
  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) => Stream.error(StateError('database is locked'));
  @override
  Future<int> create(String name) => throw UnimplementedError();
  @override
  Future<void> rename(int id, String name) => throw UnimplementedError();
  @override
  Future<void> setActive(int id) => throw UnimplementedError();
  @override
  Future<void> clearActive() => throw UnimplementedError();
  @override
  Future<void> delete(int id) => throw UnimplementedError();
  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) => throw UnimplementedError();
  @override
  Future<void> deleteVariable(int id) => throw UnimplementedError();
  @override
  Future<Map<String, String>> getActiveVariables() async => {};
}

void main() {
  late InMemoryDb db;
  late int collection;
  late int production;
  late int staging;

  BuildAuthDoctorInputUseCase builder({EnvironmentRepository? environments, DateTime Function()? now}) {
    final resolver = BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository);
    return BuildAuthDoctorInputUseCase(
      PrepareRequestUseCase(resolver, db.collectionAuthRepository),
      ListVariablesUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository),
      environments ?? db.environmentRepository,
      now: now ?? () => clock,
    );
  }

  Future<ApiRequestEntity> request(String url, {RequestAuth auth = const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'), List<KeyValueItem> headers = const [], List<KeyValueItem> query = const [], RequestBody body = RequestBody.empty}) async {
    final id = await addRequest(db, collection, 'List orders', url: url, auth: auth, headers: headers, query: query, body: body);
    return (await db.requestRepository.findById(id))!;
  }

  Future<void> envVariable(int environmentId, String key, String value, {bool secret = false}) => db.environmentRepository.upsertVariable(
        EnvironmentVariableEntity(id: 0, environmentId: environmentId, key: key, value: value, isSecret: secret, enabled: true),
      );

  setUp(() async {
    db = InMemoryDb();
    collection = await db.collectionRepository.createCollection('Shop');
    await db.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: collection, key: 'baseUrl', value: 'https://api.shop.test', enabled: true));
    production = await db.environmentRepository.create('Production');
    staging = await db.environmentRepository.create('Staging');
    await envVariable(production, 'token', '', secret: true);
    await envVariable(staging, 'token', 'stg-token-0123456789abcdef', secret: true);
    // The in-memory repository has no setActive: the flag is flipped on the row.
    final at = db.environments.indexWhere((e) => e.id == production);
    db.environments[at] = EnvironmentEntity(id: production, name: 'Production', isActive: true);
  });

  test('the request as a send builds it, with the templates it was written as', () async {
    final input = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));

    expect(input.method, 'GET');
    expect(input.url, 'https://api.shop.test/orders');
    expect(input.headers['Authorization'], 'Bearer ');
    expect(input.headerTemplates, {'Authorization': 'Bearer {{token}}'});
    expect(input.urlTemplate, '{{baseUrl}}/orders');
    expect(input.authType, AuthType.bearer);
    expect(input.requestKnown, isTrue);
    expect(input.status, 401);
    expect(input.now, clock);
  });

  test('what the scopes say about each variable: whether it has a value, never the value', () async {
    final input = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));

    expect(input.environmentName, 'Production');
    expect(input.variables.keys, containsAll(['token', 'baseUrl']));
    final token = input.variables['token']!;
    expect(token.isEmpty, isTrue);
    expect(token.isSecret, isTrue);
    expect(token.source, 'environment');
    expect(token.scopeName, 'Production');
    final baseUrl = input.variables['baseUrl']!;
    expect(baseUrl.isEmpty, isFalse);
    expect(baseUrl.source, 'collection');
  });

  test('the other environments, with the credential variables they fill in', () async {
    await envVariable(staging, 'unrelated', 'x');

    final input = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));

    expect(input.otherEnvironments, hasLength(1));
    expect(input.otherEnvironments.single.name, 'Staging');
    expect(input.otherEnvironments.single.filledVariables, {'token'});
  });

  test('together they let the doctor say the variable is empty here and set in Staging', () async {
    final input = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));
    final findings = AuthDoctor.diagnose(input);

    expect(findings.first.id, 'credential.variable-empty');
    expect(findings.first.confidence, FindingConfidence.certain);
    expect(byId(findings, 'environment.variable-elsewhere').title, '{{token}} has a value in "Staging", not here');
    expect(allText(findings), isNot(contains('stg-token-0123456789abcdef')));
  });

  test('query rows, header rows and the query written in the URL are all templates', () async {
    final input = await builder()(AuthDoctorSubject(
      request: await request(
        '{{baseUrl}}/orders?token={{token}}',
        auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'X-Api-Key', apiKeyValue: '{{token}}'),
        headers: [KeyValueItem(key: 'X-Tenant', value: '{{token}}'), KeyValueItem(key: 'X-Off', value: '{{gone}}', enabled: false)],
        query: [KeyValueItem(key: 'api_key', value: '{{token}}')],
      ),
      response: _response(401),
    ));

    expect(input.queryTemplates, {'token': '{{token}}', 'api_key': '{{token}}'});
    expect(input.headerTemplates, {'X-Tenant': '{{token}}', 'X-Api-Key': '{{token}}'});
    expect(input.apiKeyName, 'X-Api-Key');
    expect(input.apiKeyLocation, ApiKeyLocation.header);
    expect(input.headers.keys, containsAll(['X-Tenant', 'X-Api-Key']));
  });

  test('Basic auth and the collection\'s own auth are templates too', () async {
    final basic = await builder()(AuthDoctorSubject(
      request: await request('{{baseUrl}}/orders', auth: const RequestAuth(type: AuthType.basic, basicUsername: '{{user}}', basicPassword: '{{password}}')),
      response: _response(401),
    ));
    expect(basic.headerTemplates['Authorization'], 'Basic {{user}}:{{password}}');
    expect(basic.headers['Authorization'], startsWith('Basic '));

    await db.collectionAuthRepository.setAuthJson(collection, const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}').toJsonString());
    final inherited = await builder()(AuthDoctorSubject(
      request: await request('{{baseUrl}}/orders', auth: const RequestAuth(type: AuthType.inherit)),
      response: _response(401),
    ));
    expect(inherited.authType, AuthType.bearer);
    expect(inherited.headerTemplates['Authorization'], 'Bearer {{token}}');
  });

  test('the response: status, headers and the body as text, cut at 256 KB', () async {
    final input = await builder()(AuthDoctorSubject(
      request: await request('{{baseUrl}}/orders'),
      response: _response(401, body: '{"error":"invalid_token","note":"é"}', headers: const {'www-authenticate': 'Bearer realm="api"'}),
    ));
    expect(input.responseHeaders, {'www-authenticate': 'Bearer realm="api"'});
    expect(input.responseBody, '{"error":"invalid_token","note":"é"}');

    final big = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(403, body: 'a' * 300000)));
    expect(big.responseBody, hasLength(256 * 1024));
  });

  test('the time is the one the response arrived at, else the injected clock', () async {
    final arrived = DateTime.utc(2026, 10, 8, 11, 30);
    final withTime = await builder()(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401), receivedAt: arrived));
    final without = await builder(now: () => DateTime.utc(2030))(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));

    expect(withTime.now, arrived);
    expect(without.now, DateTime.utc(2030));
  });

  test('a request that cannot be built any more is passed on as one the doctor knows nothing about', () async {
    final broken = await request(
      '{{baseUrl}}/graphql',
      body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ orders { id } }', graphqlVariables: '{not json'),
    );
    final input = await builder()(AuthDoctorSubject(request: broken, response: _response(401)));

    expect(input.requestKnown, isFalse);
    expect(input.headers, isEmpty);
    expect(input.url, '{{baseUrl}}/graphql');
    expect(AuthDoctor.diagnose(input).map((f) => f.id), isNot(contains('credential.none-sent')));
  });

  test('stores that cannot be read cost hints, not the whole diagnosis', () async {
    final input = await builder(environments: _BrokenEnvironments())(AuthDoctorSubject(request: await request('{{baseUrl}}/orders'), response: _response(401)));

    expect(input.environmentName, isNull);
    expect(input.otherEnvironments, isEmpty);
    expect(input.headerTemplates, {'Authorization': 'Bearer {{token}}'});
    expect(input.requestKnown, isTrue);
  });

  test('a method other than GET is carried', () async {
    final id = await addRequest(db, collection, 'Create', method: HttpMethod.post, url: '{{baseUrl}}/orders', auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'x'));
    final created = (await db.requestRepository.findById(id))!;

    final input = await builder()(AuthDoctorSubject(request: created, response: _response(403)));

    expect(input.method, 'POST');
  });
}
