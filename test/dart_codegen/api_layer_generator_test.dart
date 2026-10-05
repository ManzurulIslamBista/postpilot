import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';

List<ApiSpecRequest> _sample() => const [
      ApiSpecRequest(
        name: 'Get user',
        method: 'GET',
        url: '{{baseUrl}}/users/{{userId}}?expand=profile',
        exampleResponse: '{"id":1,"name":"Ann","created_at":"2026-10-02T10:00:00Z"}',
      ),
      ApiSpecRequest(
        name: 'List users',
        method: 'GET',
        url: '{{baseUrl}}/users',
        query: [('page', '{{page}}'), ('limit', '20')],
        exampleResponse: '[{"id":1,"name":"Ann"},{"id":2,"name":"Bob"}]',
      ),
      ApiSpecRequest(
        name: 'Create user',
        method: 'POST',
        url: '{{baseUrl}}/users',
        bodyKind: ApiBodyKind.json,
        bodyText: '{"name":"Ann","age":{{age}}}',
        exampleResponse: '{"id":3}',
      ),
      ApiSpecRequest(
        name: 'Delete user',
        method: 'DELETE',
        url: '{{baseUrl}}/users/:id',
        headers: [('X-Tenant', '{{tenant}}'), ('Authorization', 'Bearer {{token}}')],
      ),
      ApiSpecRequest(
        name: 'Orders',
        method: 'GET',
        url: '{{baseUrl}}/orders',
        folders: ['Billing'],
      ),
      ApiSpecRequest(
        name: 'Search',
        method: 'POST',
        url: '{{baseUrl}}/graphql',
        bodyKind: ApiBodyKind.graphql,
        bodyText: 'query { me { id } }',
        folders: ['Billing'],
      ),
    ];

void main() {
  const gen = ApiLayerGenerator();

  String file(ApiLayerResult r, String path) => r.files.firstWhere((f) => f.path == path, orElse: () => throw StateError('missing $path in ${r.files.map((f) => f.path)}')).content;

  test('generates a client, data sources, models, repositories, use cases and DI', () {
    final r = gen.generate('Users API', _sample());
    final paths = r.files.map((f) => f.path).toList();
    expect(paths, containsAll([
      'lib/core/network/api_client.dart',
      'lib/core/usecases/usecase.dart',
      'lib/features/users_api/data/datasources/users_api_remote_data_source.dart',
      'lib/features/users_api/data/datasources/billing_remote_data_source.dart',
      'lib/features/users_api/domain/repositories/users_api_repository.dart',
      'lib/features/users_api/data/repositories/users_api_repository_impl.dart',
      'lib/features/users_api/domain/usecases/get_user_usecase.dart',
      'lib/features/users_api/data/models/get_user_response.dart',
      'lib/features/users_api/data/models/create_user_request.dart',
      'lib/features/users_api/users_api_injection.dart',
    ]));
    expect(paths.toSet().length, paths.length, reason: 'no file is generated twice');
  });

  test('path variables, :params and query parameters become typed parameters', () {
    final r = gen.generate('Users API', _sample());
    final ds = file(r, 'lib/features/users_api/data/datasources/users_api_remote_data_source.dart');
    expect(ds, contains('class UsersApiRemoteDataSource'));
    expect(ds, contains("Future<GetUserResponse> getUser({required String userId, String expand = 'profile'})"));
    expect(ds, contains(r"_dio.get<dynamic>('/users/${userId}'"));
    expect(ds, contains("'expand': expand"));
    expect(ds, contains('Future<List<ListUsersResponse>> listUsers({String? page, String limit = \'20\'})'));
    expect(ds, contains("'limit': limit"));
    expect(ds, contains('required String id'));
    expect(ds, contains(r"'/users/${id}'"));
  });

  test('json bodies get a request DTO; variables inside are quoted so the body parses', () {
    final r = gen.generate('Users API', _sample());
    final ds = file(r, 'lib/features/users_api/data/datasources/users_api_remote_data_source.dart');
    expect(ds, contains('required CreateUserRequest body'));
    expect(ds, contains('data: body.toJson()'));
    expect(file(r, 'lib/features/users_api/data/models/create_user_request.dart'), contains('class CreateUserRequest'));
  });

  test('header variables become parameters; Authorization is left to the interceptor', () {
    final r = gen.generate('Users API', _sample());
    final ds = file(r, 'lib/features/users_api/data/datasources/users_api_remote_data_source.dart');
    expect(ds, contains('required String tenant'));
    expect(ds, contains("headers: {'X-Tenant': tenant}"));
    expect(ds, isNot(contains('token')));
    expect(file(r, 'lib/core/network/api_client.dart'), contains("options.headers['Authorization']"));
  });

  test('graphql requests post the query and variables', () {
    final r = gen.generate('Users API', _sample());
    final ds = file(r, 'lib/features/users_api/data/datasources/billing_remote_data_source.dart');
    expect(ds, contains('query { me { id } }'));
    expect(ds, contains("data: {'query': _searchQuery, 'variables': variables}"));
  });

  test('use cases wrap the repository with a params class', () {
    final r = gen.generate('Users API', _sample());
    final uc = file(r, 'lib/features/users_api/domain/usecases/get_user_usecase.dart');
    expect(uc, contains('class GetUserParams'));
    expect(uc, contains('implements UseCase<GetUserResponse, GetUserParams>'));
    expect(uc, contains('_repository.getUser(userId: params.userId, expand: params.expand)'));
    final noParams = file(r, 'lib/features/users_api/domain/usecases/orders_usecase.dart');
    expect(noParams, contains('UseCase<dynamic, NoParams>'));
  });

  test('base URL is detected: variable noted, absolute origin used as default', () {
    final withVar = gen.generate('Users API', _sample());
    expect(withVar.notes.join(' '), contains('{{baseUrl}}'));
    final absolute = gen.generate('X', const [ApiSpecRequest(name: 'Ping', method: 'GET', url: 'https://api.example.com/v1/ping')]);
    expect(file(absolute, 'lib/core/network/api_client.dart'), contains("defaultValue: 'https://api.example.com'"));
    expect(file(absolute, 'lib/features/x/data/datasources/x_remote_data_source.dart'), contains("'/v1/ping'"));
  });

  test('domain layer can be switched off; model style flows through', () {
    final r = gen.generate('Users API', _sample(),
        options: const ApiLayerOptions(domainLayer: false, modelStyle: DartModelStyle.freezed, packageName: 'my_app'));
    expect(r.files.any((f) => f.path.contains('/usecases/') || f.path.contains('/repositories/')), isFalse);
    expect(file(r, 'lib/features/users_api/data/models/get_user_response.dart'), contains('@freezed'));
    expect(file(r, 'lib/features/users_api/users_api_injection.dart'), isNot(contains('UseCase')));
  });

  test('allNullable flows into the generated DTOs', () {
    final r = gen.generate('Users API', _sample(), options: const ApiLayerOptions(allNullable: true));
    final model = file(r, 'lib/features/users_api/data/models/get_user_response.dart');
    expect(model, contains('final int? id;'));
    expect(model, contains('copyWith('));
    expect(model, isNot(contains('required ')));
    final strict = file(gen.generate('Users API', _sample()), 'lib/features/users_api/data/models/get_user_response.dart');
    expect(strict, contains('required this.id,'));
  });

  test('duplicate request names get distinct methods and models', () {
    final r = gen.generate('Dup', const [
      ApiSpecRequest(name: 'Get', method: 'GET', url: 'https://a.test/x', exampleResponse: '{"a":1}'),
      ApiSpecRequest(name: 'Get', method: 'GET', url: 'https://a.test/y', exampleResponse: '{"b":1}'),
    ]);
    final ds = file(r, 'lib/features/dup/data/datasources/dup_remote_data_source.dart');
    expect(ds, contains('Future<GetResponse> get('));
    expect(ds, contains('Future<Get2Response> get2('));
  });

  test('an empty collection yields a note, not files', () {
    final r = gen.generate('Empty', const []);
    expect(r.files, isEmpty);
    expect(r.notes, isNotEmpty);
  });
}
