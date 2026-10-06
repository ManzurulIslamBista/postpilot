import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';

void main() {
  late _RecordingApiClient client;
  late _RecordingHistory history;
  late SendRequestUseCase sendRequest;

  setUp(() {
    client = _RecordingApiClient();
    history = _RecordingHistory();
    sendRequest = SendRequestUseCase(
      client,
      BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals()),
      history,
      _NoCollectionAuth(),
    );
  });

  test('a URL typed without a scheme is sent as http://', () async {
    await sendRequest(_request('localhost:3000/api/users'));

    expect(client.sent.single.url, 'http://localhost:3000/api/users');
  });

  test('a URL with no host is rejected as invalid before anything is sent or recorded', () async {
    for (final url in ['', 'http://', 'https:///users']) {
      await expectLater(sendRequest(_request(url)), throwsA(isA<InvalidUrlException>()), reason: '"$url"');
    }

    expect(client.sent, isEmpty);
    expect(history.recordedUrls, isEmpty);
  });

  test('a scheme the HTTP client cannot speak is rejected as invalid', () async {
    await expectLater(sendRequest(_request('ftp://example.com/file')), throwsA(isA<InvalidUrlException>()));

    expect(client.sent, isEmpty);
  });

  test('the cancel token reaches the client', () async {
    final token = ApiCancelToken();

    await sendRequest(_request('https://api.example.com/users'), cancelToken: token);

    expect(client.sent.single.cancelToken, same(token));
  });

  test('a send the client aborts is not recorded to history', () async {
    client.failWith = const NetworkException('cancelled', kind: NetworkErrorKind.cancelled);

    await expectLater(
      sendRequest(_request('https://api.example.com/users')),
      throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.cancelled)),
    );

    expect(history.recordedUrls, isEmpty);
  });

  group('data variables', () {
    ApiRequestEntity dataRequest() => ApiRequestEntity(
          id: 1,
          collectionId: 1,
          folderId: null,
          name: 'r',
          method: HttpMethod.post,
          url: 'https://api.example.com/users/{{id}}',
          headers: [KeyValueItem(key: 'X-Row', value: '{{id}}')],
          queryParams: [KeyValueItem(key: 'q', value: '{{name}}')],
          body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
          auth: const RequestAuth(),
        );

    SendRequestUseCase sendWith({Map<String, String> environment = const {}, RequestAuth? collectionAuth}) =>
        SendRequestUseCase(
          client,
          BuildVariableResolverUseCase(_NoCollectionVariables(), _Environment(environment), _NoGlobals()),
          history,
          _CollectionAuth(collectionAuth),
        );

    test('fill the url, query, headers, body and inherited auth, and beat a variable of the same name', () async {
      final useCase = sendWith(
        environment: {'id': 'from-environment', 'name': 'from-environment'},
        collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: 'tok-{{id}}'),
      );

      await useCase(dataRequest(), dataVariables: {'id': '7', 'name': 'Ada'});

      final spec = client.sent.single;
      expect(spec.url, 'https://api.example.com/users/7?q=Ada');
      expect(spec.headers['X-Row'], '7');
      expect(spec.headers['Authorization'], 'Bearer tok-7');
      expect(utf8.decode(spec.body as List<int>), '{"name":"Ada"}');
    });

    test('reach the environment values that reference them', () async {
      final useCase = sendWith(environment: {'id': 'user-{{row}}', 'name': 'Ada'});

      await useCase(dataRequest(), dataVariables: {'row': '9'});

      expect(client.sent.single.headers['X-Row'], 'user-9');
    });

    test('belong to one send: the next one without them resolves through the ordinary scopes', () async {
      final useCase = sendWith(environment: {'id': 'from-environment', 'name': 'env-name'});

      await useCase(dataRequest(), dataVariables: {'id': '7'});
      await useCase(dataRequest());

      expect(client.sent.map((s) => s.headers['X-Row']), ['7', 'from-environment']);
    });

    test('are recorded to history as the URL was written, so a row value never lands in the History list', () async {
      final useCase = sendWith();

      await useCase(dataRequest(), dataVariables: {'id': '7', 'name': 'Ada'});

      expect(history.recordedUrls, ['https://api.example.com/users/{{id}}?q={{name}}']);
    });

    test('travel with the cancel token', () async {
      final token = ApiCancelToken();

      await sendWith()(dataRequest(), cancelToken: token, dataVariables: {'id': '7', 'name': 'Ada'});

      expect(client.sent.single.cancelToken, same(token));
      expect(client.sent.single.headers['X-Row'], '7');
    });
  });

  group('undefined variables', () {
    SendRequestUseCase sendWith(Map<String, String> environment, {RequestAuth? collectionAuth}) => SendRequestUseCase(
          client,
          BuildVariableResolverUseCase(_NoCollectionVariables(), _Environment(environment), _NoGlobals()),
          history,
          _CollectionAuth(collectionAuth),
        );

    Future<InvalidRequestException> failure(Future<Object?> send) async {
      try {
        await send;
      } on InvalidRequestException catch (e) {
        return e;
      }
      fail('expected an InvalidRequestException');
    }

    test('a {{baseUrl}} nothing defines is refused by name instead of being sent to DNS as %7b%7bbaseurl%7d%7d', () async {
      final error = await failure(sendWith({})(_request('{{baseUrl}}/users')));

      expect(error.message, contains('{{baseUrl}} (used in the URL) is not defined'));
      expect(error.message, startsWith('Not a valid http(s) URL: "http://{{baseUrl}}/users"'));
      expect(client.sent, isEmpty);
      expect(history.recordedUrls, isEmpty);
    });

    test('with the variable defined the same request is sent', () async {
      await sendWith({'baseUrl': 'https://api.test'})(_request('{{baseUrl}}/users'));

      expect(client.sent.single.url, 'https://api.test/users');
    });

    test('every undefined variable is named, wherever it is used', () async {
      final request = ApiRequestEntity(
        id: 1,
        collectionId: 1,
        folderId: null,
        name: 'r',
        method: HttpMethod.post,
        url: 'https://api.test/{{id}}',
        headers: [KeyValueItem(key: 'X-Tenant', value: '{{tenant}}')],
        queryParams: const [],
        body: const RequestBody(type: BodyType.raw, rawText: '{"a":"{{payload}}"}'),
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
      );

      final error = await failure(sendWith({})(request));

      expect(error.message, contains('{{id}} (used in the URL)'));
      expect(error.message, contains('{{tenant}} (used in the "X-Tenant" header)'));
      expect(error.message, contains('{{payload}} (used in the request body)'));
      expect(error.message, contains('{{token}} (used in the Bearer token)'));
      expect(error.message, isNot(contains('Not a valid http(s) URL')), reason: 'the host itself is fine');
      expect(client.sent, isEmpty);
    });

    test('a variable defined with an empty value, and the built-in dynamic ones, are not undefined', () async {
      final request = ApiRequestEntity(
        id: 1,
        collectionId: 1,
        folderId: null,
        name: 'r',
        method: HttpMethod.get,
        url: r'https://api.test/items/{{$guid}}',
        headers: [KeyValueItem(key: 'X-Empty', value: '{{empty}}')],
        queryParams: const [],
        body: RequestBody.empty,
        auth: const RequestAuth(type: AuthType.none),
      );

      await sendWith({'empty': ''})(request);

      expect(client.sent.single.headers['X-Empty'], '');
      expect(client.sent.single.url, matches(RegExp(r'^https://api\.test/items/[0-9a-f-]{36}$')));
    });

    test('an undefined variable inside the value of a defined one is found too', () async {
      final error = await failure(sendWith({'baseUrl': 'https://{{host}}'})(_request('{{baseUrl}}/users')));

      expect(error.message, contains('{{host}}'));
    });

    test('a secret in the URL is not quoted by the error', () async {
      final error = await failure(sendWith({})(_request('{{baseUrl}}/users?api_key=s3cret-value')));

      expect(error.message, isNot(contains('s3cret-value')));
    });

    test('the way the error offers to send {{text}} literally works: a variable whose value is its own token', () async {
      final request = ApiRequestEntity(
        id: 1,
        collectionId: 1,
        folderId: null,
        name: 'r',
        method: HttpMethod.post,
        url: 'https://api.test/mail',
        headers: const [],
        queryParams: const [],
        body: const RequestBody(type: BodyType.raw, rawText: '{"subject":"Hello {{name}}"}'),
        auth: const RequestAuth(type: AuthType.none),
      );
      final error = await failure(sendWith({})(request));
      expect(error.message, contains('define a variable named name whose value is {{name}}'));

      await sendWith({'name': '{{name}}'})(request);

      expect(utf8.decode(client.sent.single.body as List<int>), '{"subject":"Hello {{name}}"}');
    });

    test('a code snippet is still printed for a request that is not ready to send, tokens and all', () async {
      final snippet = await GenerateCodeSnippetUseCase(
        BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals()),
        _NoCollectionAuth(),
      )(GenerateCodeSnippetParams(_request('{{baseUrl}}/users'), const CurlGenerator()));

      expect(snippet, contains('{{baseUrl}}/users'));
    });

    test('a variable of the inherited collection auth is checked', () async {
      final useCase = sendWith({}, collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{coll}}'));
      final request = _request('https://api.test/x').copyWith(auth: const RequestAuth(type: AuthType.inherit));

      final error = await failure(useCase(request));

      expect(error.message, contains('{{coll}} (used in the Bearer token)'));
    });
  });

  group('history', () {
    test('a history that cannot be written does not turn a received response into a failed send', () async {
      final useCase = SendRequestUseCase(
        client,
        BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals()),
        _FailingHistory(),
        _NoCollectionAuth(),
      );

      final response = await useCase(_request('https://api.example.com/users'));

      expect(response.statusCode, 200);
      expect(client.sent, hasLength(1));
    });
  });
}

ApiRequestEntity _request(String url) => ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'r',
      method: HttpMethod.get,
      url: url,
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(type: AuthType.none),
    );

final class _RecordingApiClient implements ApiClient {
  final List<ApiRequestSpec> sent = [];
  NetworkException? failWith;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(spec);
    return const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
  }
}

final class _RecordingHistory implements HistoryRepository {
  final List<String> recordedUrls = [];

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async =>
      recordedUrls.add(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FailingHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async =>
      throw StateError('database is locked');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _CollectionAuth implements CollectionAuthRepository {
  final RequestAuth? auth;
  _CollectionAuth(this.auth);

  @override
  Future<String?> getAuthJson(int collectionId) async => auth?.toJsonString();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Environment implements EnvironmentRepository {
  final Map<String, String> variables;
  _Environment(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionVariables implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoEnvironment implements EnvironmentRepository {
  @override
  Future<Map<String, String>> getActiveVariables() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoGlobals implements GlobalVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
