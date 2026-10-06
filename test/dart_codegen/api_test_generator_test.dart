// The generated test tree for the shop collection in shop_api_fixture.dart. What each generated file must contain is worked out by hand
// from that collection and from what ApiLayerGenerator emits: paths from the URL templates, a test value for each argument
// (`test-` plus its name in kebab case), the query a call sends, the status each saved example was saved under.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_test_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/pubspec_lock_versions.dart';
import 'shop_api_fixture.dart';

ApiTestsResult _generate({
  DartModelStyle style = DartModelStyle.plain,
  bool domain = true,
  bool allNullable = false,
  TestFramework framework = TestFramework.flutterTest,
  Map<String, String> locked = const {},
  List<ApiSpecRequest>? requests,
}) =>
    const ApiTestGenerator().generate(
      'Shop API',
      requests ?? shopApiRequests(),
      options: ApiTestOptions(
        layer: ApiLayerOptions(packageName: 'shop_app', modelStyle: style, domainLayer: domain, allNullable: allNullable),
        framework: framework,
        lockedVersions: locked,
      ),
    );

String _file(ApiTestsResult r, String path) => r.files.firstWhere((f) => f.path == path, orElse: () => throw StateError('missing $path in ${r.files.map((f) => f.path)}')).content;

const _models = 'test/features/shop_api/data/models';
const _ds = 'test/features/shop_api/data/datasources';
const _repo = 'test/features/shop_api/data/repositories';
const _uc = 'test/features/shop_api/domain/usecases';

void main() {
  group('the files', () {
    final r = _generate();
    final paths = r.files.map((f) => f.path).toSet();

    test('helpers, an API client test, one test per model, per data source, per repository and per use case set', () {
      expect(paths, containsAll([
        'test/helpers/fixture_loader.dart',
        'test/helpers/json_matchers.dart',
        'test/core/network/api_client_test.dart',
        // The five DTOs the saved examples and the JSON request body gave: list users, get user, create user (both ways), list orders.
        '$_models/list_users_response_test.dart',
        '$_models/get_user_response_test.dart',
        '$_models/create_user_request_test.dart',
        '$_models/create_user_response_test.dart',
        '$_models/list_orders_response_test.dart',
        // Three groups: the Users and Orders folders, and the loose Health request under the collection's name.
        '$_ds/users_remote_data_source_test.dart',
        '$_ds/orders_remote_data_source_test.dart',
        '$_ds/shop_api_remote_data_source_test.dart',
        '$_repo/users_repository_impl_test.dart',
        '$_repo/orders_repository_impl_test.dart',
        '$_repo/shop_api_repository_impl_test.dart',
        '$_uc/users_usecases_test.dart',
        '$_uc/orders_usecases_test.dart',
        '$_uc/shop_api_usecases_test.dart',
      ]));
      expect(paths, hasLength(r.files.length), reason: 'no file twice');
      expect(r.files.where((f) => f.path.endsWith('_test.dart')), hasLength(1 + 5 + 3 + 3 + 3));
    });

    test('the helpers are shared files, so a project that has its own keeps it', () {
      expect([for (final f in r.files) if (f.shared) f.path]..sort(), [
        'test/core/network/api_client_test.dart',
        'test/helpers/fixture_loader.dart',
        'test/helpers/json_matchers.dart',
      ]);
    });

    test('one fixture per model and per saved example the tests use, named after what they are for', () {
      final fixtures = {for (final p in paths) if (p.startsWith('test/fixtures/')) p.substring('test/fixtures/shop_api/'.length)};
      expect(fixtures, {
        // The models' own examples.
        'list_users_response.json',
        'get_user_response.json',
        'create_user_request.json',
        'create_user_response.json',
        'list_orders_response.json',
        // Examples saved with an error status, one per status, and a text one.
        'users_list_users_401.json',
        'users_list_users_502.txt',
        'users_get_user_404.json',
        'users_create_user_422.json',
        // A response and a body that are JSON but have no DTO (a list of numbers, a list of operations).
        'users_rename_user_request.json',
        'users_rename_user_response.json',
        // The plain-text answer of the loose request.
        'shop_api_health_response.txt',
      });
    });

    test('nothing is generated for an empty collection', () {
      final empty = const ApiTestGenerator().generate('X', const []);
      expect(empty.files, isEmpty);
      expect(empty.notes, ['The collection has no requests.']);
    });
  });

  group('fixtures hold no secret', () {
    final r = _generate();

    test('a secret by name is masked, a number under a secret name is zeroed, dates and variables stay', () {
      final users = jsonDecode(_file(r, 'test/fixtures/shop_api/list_users_response.json')) as Map<String, dynamic>;
      final first = (users['data'] as List).first as Map<String, dynamic>;
      expect(first['api_token'], '••••••');
      expect(first['pin'], 0);
      expect(first['created_at'], '2026-10-02T10:00:00Z');
      expect(first['email'], 'ann@example.com');
      final request = jsonDecode(_file(r, 'test/fixtures/shop_api/create_user_request.json')) as Map<String, dynamic>;
      expect(request['password'], '••••••');
      expect(request['age'], '{{age}}');
      expect(request['name'], 'Ann');
    });

    test('no generated file contains a credential from the examples', () {
      for (final f in r.files) {
        expect(f.content, isNot(contains(shopSecretToken)), reason: f.path);
        expect(f.content, isNot(contains('hunter2-secret')), reason: f.path);
      }
      expect(_file(r, 'test/fixtures/shop_api/list_users_response.json'), isNot(contains('$shopSecretPin')));
    });

    test('a date under a secret-looking name is still a date, so the fixture parses; the token next to it is masked', () {
      final out = _generate(requests: const [
        ApiSpecRequest(
          name: 'Refresh',
          method: 'GET',
          url: '{{baseUrl}}/refresh',
          exampleResponse: '{"token_expires_at":"2026-10-02T10:00:00Z","refresh_token":"abcdefghijklmnopqrstuvwxyz1234","tokens":["abcdefghijklmnopqrstuvwxyz1234"]}',
        ),
      ]);
      final fixture = jsonDecode(_file(out, 'test/fixtures/shop_api/refresh_response.json')) as Map<String, dynamic>;
      expect(fixture['token_expires_at'], '2026-10-02T10:00:00Z');
      expect(fixture['refresh_token'], '••••••');
      expect(fixture['tokens'], ['••••••']);
    });

    test('a text answer is masked too', () {
      final out = _generate(requests: const [
        ApiSpecRequest(
          name: 'Health',
          method: 'GET',
          url: '{{baseUrl}}/health',
          exampleResponse: 'token=abcdefghijklmnopqrstuvwxyz1234 ok',
          examples: [ApiSpecExample(name: 'Up', statusCode: 200, body: 'token=abcdefghijklmnopqrstuvwxyz1234 ok')],
        ),
      ]);
      final text = out.files.firstWhere((f) => f.path.endsWith('.txt')).content;
      expect(text, isNot(contains('abcdefghijklmnopqrstuvwxyz1234')));
      expect(text, contains('token=••••••'));
    });
  });

  group('model tests', () {
    final r = _generate();

    test('an object response: each scalar of the saved example, the nested objects and lists, then the round trip', () {
      final t = _file(r, '$_models/get_user_response_test.dart');
      expect(t, contains("import 'package:shop_app/features/shop_api/data/models/get_user_response.dart';"));
      expect(t, contains("import '../../../../helpers/fixture_loader.dart';"));
      expect(t, contains("Map<String, dynamic> item() => loadJsonObjectFixture('shop_api/get_user_response.json');"));
      expect(t, contains('expect(model.id, 42);'));
      expect(t, contains("expect(model.name, 'Ann');"));
      expect(t, contains("expect(model.address.city, 'Oslo');"));
      expect(t, contains('expect(model.address.geo.lat, closeTo(59.91, 1e-9));'));
      expect(t, contains('expect(model.orders, hasLength(2));'));
      expect(t, contains('expect(model.orders[0].id, 10);'));
      // 9.99 and 20 are both orders' totals, so the field is a double.
      expect(t, contains('expect(model.orders[0].total, closeTo(9.99, 1e-9));'));
      expect(t, contains("expect(model.joined, DateTime.parse('2026-01-15'));"));
      expect(t, contains('expect(jsonDecode(jsonEncode(model)), jsonEquivalentTo(item()));'));
      expect(t, isNot(contains('optional fields')), reason: 'no field of this example is nullable');
    });

    test('a list response is read item by item, and the optional field of the second item gets its own test', () {
      final t = _file(r, '$_models/list_orders_response_test.dart');
      expect(t, contains("List<dynamic> fixture() => loadJsonListFixture('shop_api/list_orders_response.json');"));
      expect(t, contains('Map<String, dynamic> item() => fixture().first as Map<String, dynamic>;'));
      expect(t, contains('final models = fixture().map((e) => ListOrdersResponse.fromJson(e as Map<String, dynamic>)).toList();'));
      expect(t, contains('expect(jsonDecode(jsonEncode(models)), jsonEquivalentTo(fixture()));'));
      expect(t, contains("expect(model.placedAt, DateTime.parse('2026-10-03'));"));
      // `note` is only in the second order.
      expect(t, contains('expect(model.note, isNull);'));
      expect(t, contains("const {'note'}.contains(key)"));
    });

    test('lists of text, and secrets already masked in the fixture', () {
      final t = _file(r, '$_models/list_users_response_test.dart');
      expect(t, contains("expect(model.data[0].tags, ['vip', 'beta']);"));
      expect(t, contains("expect(model.data[0].apiToken, '••••••');"));
      expect(t, contains('expect(model.data[0].pin, 0);'));
      expect(t, contains('expect(model.total, 2);'));
      expect(t, isNot(contains('manager')), reason: 'a field that is only ever null has no type to check');
    });

    test('the request DTO of a JSON body has its own round trip', () {
      final t = _file(r, '$_models/create_user_request_test.dart');
      expect(t, contains("expect(model.age, '{{age}}');"));
      expect(t, contains("expect(model.password, '••••••');"));
    });

    test('freezed adds value equality and copyWith; plain keeps to the round trip', () {
      final freezed = _file(_generate(style: DartModelStyle.freezed), '$_models/get_user_response_test.dart');
      expect(freezed, contains('(freezed value equality)'));
      expect(freezed, contains('expect(model.copyWith(), model);'));
      expect(freezed, contains('Needs the freezed part files (run build_runner).'));
      expect(_file(r, '$_models/get_user_response_test.dart'), isNot(contains('copyWith')));
      final json = _file(_generate(style: DartModelStyle.jsonSerializable), '$_models/get_user_response_test.dart');
      expect(json, isNot(contains('copyWith')));
      expect(json, contains('json_serializable part files'));
    });

    test('with every field optional, every field is read back as null when its key is missing, and copyWith is checked', () {
      final t = _file(_generate(allNullable: true), '$_models/get_user_response_test.dart');
      expect(t, contains("const {'id', 'name', 'address', 'orders', 'joined'}.contains(key)"));
      expect(t, contains('expect(model.address, isNull);'));
      expect(t, contains('expect(model.address!.city, \'Oslo\');'), reason: 'a nullable object is asserted not null, then read with !');
      expect(t, contains('expect(model.orders![0].id, 10);'));
      expect(t, contains('copyWith with no arguments keeps every value'));
    });

    test('a model with sixty fields is not asserted line by line', () {
      final big = jsonEncode({for (var i = 0; i < 60; i++) 'field$i': i});
      final out = _generate(requests: [ApiSpecRequest(name: 'Big', method: 'GET', url: '{{baseUrl}}/big', exampleResponse: big)]);
      final t = _file(out, '$_models/big_response_test.dart');
      expect(RegExp(r'expect\(model\.field\d+, \d+\);').allMatches(t), hasLength(40));
    });
  });

  group('data source tests', () {
    final r = _generate();
    final users = _file(r, '$_ds/users_remote_data_source_test.dart');

    test('Dio on http_mock_adapter, with the generated client, an empty base URL and a bearer token', () {
      expect(users, contains("import 'package:http_mock_adapter/http_mock_adapter.dart';"));
      expect(users, contains("import 'package:shop_app/core/network/api_client.dart';"));
      expect(users, contains("import 'package:shop_app/features/shop_api/data/datasources/users_remote_data_source.dart';"));
      expect(users, contains("dio = createApiClient(baseUrl: '', tokenProvider: () async => 'test-token');"));
      expect(users, contains('adapter = DioAdapter(dio: dio);'));
      expect(users, contains('dataSource = UsersRemoteDataSource(dio);'));
      expect(users, contains('sent.add(options);'));
    });

    test('a list with query parameters: all of them sent with test values, then only the defaults', () {
      expect(users, contains("queryParameters: <String, dynamic>{'page': 'test-page', 'limit': 'test-limit', 'status': 'test-status'},"));
      expect(users, contains("final result = await dataSource.listUsers(page: 'test-page', limit: 'test-limit', status: 'test-status');"));
      expect(users, contains("expect(sent.single.queryParameters, <String, dynamic>{'page': 'test-page', 'limit': 'test-limit', 'status': 'test-status'});"));
      // Without arguments `page` (no default) is left out and `limit` and `status` fall back to what the request had.
      expect(users, contains("queryParameters: <String, dynamic>{'limit': '20', 'status': 'active'},"));
      expect(users, contains('await dataSource.listUsers();'));
    });

    test('a path with a variable: the mocked route, the recorded path and method', () {
      expect(users, contains("'/users/test-user-id',"));
      expect(users, contains("final result = await dataSource.getUser(userId: 'test-user-id');"));
      expect(users, contains("expect(sent.single.path, '/users/test-user-id');"));
      expect(users, contains("expect(sent.single.method, 'GET');"));
      expect(users, contains('expect(sent.single.queryParameters, isEmpty);'));
      expect(users, contains('adapter.onPatch('));
      expect(users, contains('adapter.onDelete('));
      expect(users, contains("'/users/test-id',"), reason: ':id of the PATCH and DELETE routes');
    });

    test('a JSON body is read from its fixture and matched by the mock; a header argument is asserted', () {
      expect(users, contains("final body = CreateUserRequest.fromJson(loadJsonObjectFixture('shop_api/create_user_request.json'));"));
      expect(users, contains('data: body.toJson(),'));
      expect(users, contains("dataSource.createUser(tenant: 'test-tenant', body: body)"));
      expect(users, contains("expect(sent.single.headers['X-Tenant'], 'test-tenant');"));
      expect(users, contains("server.reply(201, loadJsonFixture('shop_api/create_user_response.json'))"));
      // A list as the body: its fixture, matched as it is.
      expect(users, contains("final body = loadJsonListFixture('shop_api/users_rename_user_request.json');"));
      expect(users, contains('data: body,'));
    });

    test('the auth header is asserted on every successful call, the bearer token being the interceptor\'s', () {
      expect(RegExp(r"expect\(sent\.single\.headers\['Authorization'\], 'Bearer test-token'\);").allMatches(users), hasLength(5));
      expect(users, isNot(contains("'Authorization': ")));
    });

    test('error cases come from the examples saved with an error status, one per status', () {
      expect(users, contains("test('List users: GET /users fails with a DioException on a 401 answer (Unauthorized)'"));
      expect(users, contains("server.reply(401, loadJsonFixture('shop_api/users_list_users_401.json'))"));
      expect(users, contains("test('List users: GET /users fails with a DioException on a 502 answer (Gateway)'"));
      expect(users, contains("server.reply(502, loadTextFixture('shop_api/users_list_users_502.txt'))"));
      expect(users, contains("server.reply(404, loadJsonFixture('shop_api/users_get_user_404.json'))"));
      expect(users, contains("server.reply(422, loadJsonFixture('shop_api/users_create_user_422.json'))"));
      expect(users, contains("throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 404))"));
    });

    test('a call with no error example still gets a plain 500, and one with no success example a made-up answer', () {
      expect(users, contains("server.reply(500, <String, dynamic>{'message': 'Internal Server Error'})"));
      expect(users, contains("server.reply(200, <String, dynamic>{'ok': true})"));
      expect(users, contains("expect(result, <String, dynamic>{'ok': true});"));
    });

    test('a response that is a list of numbers is compared as JSON; a text answer is just checked to be there', () {
      expect(users, contains("expect(result, jsonEquivalentTo(loadJsonFixture('shop_api/users_rename_user_response.json')));"));
      final loose = _file(r, '$_ds/shop_api_remote_data_source_test.dart');
      expect(loose, contains("server.reply(200, loadTextFixture('shop_api/shop_api_health_response.txt'))"));
      expect(loose, contains('expect(result, isNotNull);'));
    });

    test('a multipart form and a GraphQL body have no data source test, and the notes say which', () {
      final orders = _file(r, '$_ds/orders_remote_data_source_test.dart');
      expect(orders, contains("group('listOrders'"));
      expect(orders, isNot(contains('uploadReceipt')));
      expect(orders, isNot(contains('search(')));
      expect(r.notes.any((n) => n.contains('No data source test for Upload receipt, Search')), isTrue);
    });

    test('a collection of only untestable calls writes no data source file at all', () {
      final out = _generate(requests: const [ApiSpecRequest(name: 'Form', method: 'POST', url: '{{baseUrl}}/f', bodyKind: ApiBodyKind.form)]);
      expect(out.files.any((f) => f.path.contains('data/datasources')), isFalse);
      expect(out.files.any((f) => f.path.contains('data/repositories')), isTrue, reason: 'the repository can still be tested');
    });
  });

  group('repository and use case tests', () {
    final r = _generate();

    test('mocktail on the data source; the DTO comes back unchanged and a failure is not caught', () {
      final t = _file(r, '$_repo/users_repository_impl_test.dart');
      expect(t, contains('class _MockUsersRemoteDataSource extends Mock implements UsersRemoteDataSource {}'));
      expect(t, contains('repository = UsersRepositoryImpl(remote);'));
      expect(t, contains("when(() => remote.getUser(userId: 'test-user-id')).thenAnswer((_) async => sample);"));
      expect(t, contains("final sample = GetUserResponse.fromJson(loadJsonObjectFixture('shop_api/get_user_response.json'));"));
      expect(t, contains('expect(result, same(sample));'));
      expect(t, contains("verify(() => remote.getUser(userId: 'test-user-id')).called(1);"));
      expect(t, contains('thenAnswer((_) => Future<GetUserResponse>.error(error));'));
      expect(t, contains('await expectLater(repository.getUser(userId: \'test-user-id\'), throwsA(same(error)));'));
      expect(t, contains("RequestOptions(path: '/users/test-user-id')"));
      // The failure is a future error, not a throw: a repository method returns a Future either way.
      expect(t, isNot(contains('thenThrow')));
    });

    test('arguments that are DTOs are the same object on both sides of the call; lists and maps come from fixtures or literals', () {
      final t = _file(r, '$_repo/users_repository_impl_test.dart');
      expect(t, contains("final body = CreateUserRequest.fromJson(loadJsonObjectFixture('shop_api/create_user_request.json'));"));
      expect(t, contains("when(() => remote.createUser(tenant: 'test-tenant', body: body)).thenAnswer((_) async => sample);"));
      expect(t, contains('thenAnswer((_) => Future<List<dynamic>>.error(error));'));
      expect(t, contains("final sample = <String, dynamic>{'ok': true};"));
    });

    test('a list response is rebuilt item by item from its fixture', () {
      final t = _file(r, '$_repo/orders_repository_impl_test.dart');
      expect(t, contains("final sample = loadJsonListFixture('shop_api/list_orders_response.json').map((e) => ListOrdersResponse.fromJson(e as Map<String, dynamic>)).toList();"));
      expect(t, contains('Future<List<ListOrdersResponse>>.error(error)'));
    });

    test('use cases: the params class with the same test values, const when nothing else is needed, NoParams for none', () {
      final t = _file(r, '$_uc/users_usecases_test.dart');
      expect(t, contains('class _MockUsersRepository extends Mock implements UsersRepository {}'));
      expect(t, contains("await ListUsersUseCase(repository)(const ListUsersParams(page: 'test-page', limit: 'test-limit', status: 'test-status'));"));
      expect(t, contains("await GetUserUseCase(repository)(const GetUserParams(userId: 'test-user-id'));"));
      expect(t, contains("await CreateUserUseCase(repository)(CreateUserParams(tenant: 'test-tenant', body: body));"));
      expect(t, isNot(contains('const CreateUserParams')), reason: 'a DTO read from a fixture is not a constant');
      expect(t, contains("import 'package:shop_app/features/shop_api/domain/usecases/get_user_usecase.dart';"));
      final loose = _file(r, '$_uc/shop_api_usecases_test.dart');
      expect(loose, contains('await HealthUseCase(repository)(const NoParams());'));
      expect(loose, contains("import 'package:shop_app/core/usecases/usecase.dart';"));
      expect(t, isNot(contains("core/usecases/usecase.dart")), reason: 'every use case of the Users group has parameters');
    });

    test('without the domain layer there are no repository or use case tests', () {
      final out = _generate(domain: false);
      expect(out.files.any((f) => f.path.contains('/repositories/') || f.path.contains('/usecases/')), isFalse);
      expect(out.files.any((f) => f.path.contains('data/datasources')), isTrue);
    });
  });

  group('the API client test', () {
    test('base URL, the JSON Accept header and the bearer token with a recording adapter', () {
      final t = _file(_generate(), 'test/core/network/api_client_test.dart');
      expect(t, contains("import 'package:shop_app/core/network/api_client.dart';"));
      expect(t, contains('class _RecordingAdapter implements HttpClientAdapter'));
      expect(t, contains("expect(adapter.requests.single.headers['Authorization'], 'Bearer test-token');"));
      expect(t, contains("expect(adapter.requests.single.headers['Accept'], 'application/json');"));
      expect(t, contains('sends no Authorization header when the provider has no token'));
      expect(t, contains("'token-\${++calls}'"));
    });
  });

  group('the test package and the dependencies', () {
    test('flutter_test by default: dev_dependencies with mocktail and a command for the packages no version could be confirmed for', () {
      final r = _generate();
      expect(r.devDependencies, '''
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
  # http_mock_adapter: add it at its current version with the command below,
  # no version of it could be confirmed when these tests were generated.
''');
      expect(r.addCommand, 'flutter pub add --dev mocktail http_mock_adapter');
      for (final f in r.files.where((f) => f.path.endsWith('_test.dart'))) {
        expect(f.content, contains("import 'package:flutter_test/flutter_test.dart';"), reason: f.path);
        expect(f.content, isNot(contains("package:test/test.dart")), reason: f.path);
      }
      expect(_file(r, 'test/helpers/json_matchers.dart'), contains("import 'package:flutter_test/flutter_test.dart';"));
    });

    test('package:test: its own import everywhere, a caret version, and `dart pub add`', () {
      final r = _generate(framework: TestFramework.dartTest);
      expect(r.devDependencies, startsWith('dev_dependencies:\n  test: ^1.25.8\n  mocktail: ^1.0.4\n'));
      expect(r.addCommand, 'dart pub add --dev test mocktail http_mock_adapter');
      for (final f in r.files.where((f) => f.path.endsWith('.dart'))) {
        expect(f.content, isNot(contains('flutter_test')), reason: f.path);
      }
      expect(_file(r, 'test/helpers/json_matchers.dart'), contains("import 'package:test/test.dart';"));
    });

    test('versions the project already resolved are used, and nothing is left to add', () {
      final r = _generate(locked: {'mocktail': '1.0.5', 'http_mock_adapter': '0.6.1'});
      expect(r.devDependencies, contains('  mocktail: ^1.0.5\n'));
      expect(r.devDependencies, contains('  http_mock_adapter: ^0.6.1\n'));
      expect(r.devDependencies, isNot(contains('no version of it could be confirmed')));
      expect(r.addCommand, isEmpty);
    });

    test('a package already in the lock is not asked for again, the other still is', () {
      expect(_generate(locked: {'mocktail': '1.0.4'}).addCommand, 'flutter pub add --dev http_mock_adapter');
      expect(_generate(locked: {'http_mock_adapter': '0.6.1'}).addCommand, 'flutter pub add --dev mocktail');
      expect(_generate(framework: TestFramework.dartTest, locked: {'test': '1.26.0'}).addCommand, 'dart pub add --dev mocktail http_mock_adapter');
    });

    test('a pubspec.lock is read for the versions it resolved; anything else gives nothing', () {
      const lock = '''
packages:
  mocktail:
    dependency: "direct dev"
    description: {name: mocktail, url: "https://pub.dev"}
    source: hosted
    version: "1.0.5"
  path:
    dependency: "direct main"
    description: {name: path, url: "https://pub.dev"}
    source: hosted
    version: "1.9.1"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
sdks:
  dart: ">=3.0.0 <4.0.0"
''';
      expect(PubspecLockVersions.parse(lock), {'mocktail': '1.0.5', 'path': '1.9.1'});
      expect(PubspecLockVersions.parse(''), isEmpty);
      expect(PubspecLockVersions.parse('this is not yaml: ['), isEmpty);
      expect(PubspecLockVersions.parse('just: a map'), isEmpty);
      expect(PubspecLockVersions.parse('- a\n- list'), isEmpty);
    });

    test('notes: the generated styles need build_runner, and the tests need the project root', () {
      final plain = _generate();
      expect(plain.notes.any((n) => n.contains('build_runner')), isFalse);
      expect(plain.notes.any((n) => n.contains('Run the tests from the project root (`flutter test`)')), isTrue);
      expect(_generate(framework: TestFramework.dartTest).notes.any((n) => n.contains('(`dart test`)')), isTrue);
      final freezed = _generate(style: DartModelStyle.freezed);
      expect(freezed.notes.any((n) => n.contains('freezed') && n.contains('.freezed.dart')), isTrue);
      expect(_generate(style: DartModelStyle.jsonSerializable).notes.any((n) => n.contains('json_serializable') && !n.contains('.freezed.dart')), isTrue);
    });
  });

  group('the plan the tests are built on', () {
    final requests = shopApiRequests();
    final plan = const ApiLayerGenerator().plan('Shop API', requests, options: const ApiLayerOptions(packageName: 'shop_app'));

    test('groups, method names and models are what generate() writes', () {
      expect(plan.groups.keys, ['Users', 'Orders', 'ShopApi']);
      expect(plan.groups['Users']!.map((o) => o.methodName), ['listUsers', 'getUser', 'createUser', 'renameUser', 'deleteUser']);
      expect(plan.models.keys, hasLength(5));
      final generated = const ApiLayerGenerator().generate('Shop API', requests, options: const ApiLayerOptions(packageName: 'shop_app'));
      expect(plan.modelFiles.keys.toSet(), {for (final f in generated.files) if (f.path.contains('/models/')) f.path});
      final get = plan.groups['Users']![1];
      expect(get.responseModel!.root, 'GetUserResponse');
      expect(get.useCaseParamsName, 'GetUserParams');
      expect(plan.groups['ShopApi']!.single.useCaseParamsName, 'NoParams');
    });

    test('a path, a query and a header can be worked out for given arguments', () {
      final users = plan.groups['Users']!;
      expect(ApiTextPart.evaluate(users[1].pathParts, {'userId': 'a b/c'}), '/users/a%20b%2Fc');
      final list = users[0];
      expect([for (final q in list.queryEntries) q.key], ['page', 'limit', 'status']);
      expect(list.queryEntries.first.onlyIfSet, 'page');
      expect(list.queryEntries[1].onlyIfSet, isNull, reason: 'a default is always sent');
      expect(ApiTextPart.evaluate(users[2].headerEntries.single.parts, {'tenant': 'acme'}), 'acme');
    });

    test('a query built from several arguments keeps its pieces', () {
      final p = const ApiLayerGenerator().plan('X', const [
        ApiSpecRequest(name: 'Find', method: 'GET', url: '{{baseUrl}}/find', query: [('q', '{{term}}*'), ('lang', 'en')]),
      ]);
      final op = p.groups.values.single.single;
      expect(op.queryEntries.first.expr, r"'${term}*'");
      expect(ApiTextPart.evaluate(op.queryEntries.first.parts, {'term': 'ann'}), 'ann*');
      expect(op.params.map((x) => '${x.name}:${x.kind.name}'), ['term:query', 'lang:query']);
    });
  });
}
