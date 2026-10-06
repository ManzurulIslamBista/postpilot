import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
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
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

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

void main() {
  late _Client client;
  late _Scripts scripts;

  Future<RequestBuilderViewModel> viewModelFor(String url) async {
    client = _Client();
    scripts = _Scripts();
    final resolver = BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals());
    final vm = RequestBuilderViewModel(
      _Requests(_request(url)),
      SendRequestUseCase(client, resolver, _NoHistory(), _NoCollectionAuth()),
      GenerateCodeSnippetUseCase(resolver, _NoCollectionAuth()),
      RunRequestScriptsUseCase(scripts, resolver, _NoEnvironment(), _NoGlobals()),
    );
    addTearDown(vm.dispose);
    await vm.load(1);
    return vm;
  }

  test('a network failure shows the one line its client wrote, and keeps the technical text expandable', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.failWith = const NetworkException(
      "The connection errored: Failed host lookup: 'api.example.com' This indicates an error which most likely cannot be solved by the library.",
      kind: NetworkErrorKind.connectionError,
      summary: 'Couldn\'t find the server "api.example.com" — check the spelling of the host name.',
    );

    await vm.send();

    expect(vm.errorMessage, 'Couldn\'t find the server "api.example.com" — check the spelling of the host name.');
    expect(vm.errorDetail, contains('Failed host lookup'));
    expect(vm.response, isNull);
  });

  test('a failure whose client wrote no summary is still told by kind, never as "something went wrong"', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    final messages = <NetworkErrorKind, String?>{};

    for (final kind in NetworkErrorKind.values.where((k) => k != NetworkErrorKind.cancelled)) {
      client.failWith = NetworkException('boom ($kind)', kind: kind);
      await vm.send();
      messages[kind] = vm.errorMessage;
    }

    expect(messages[NetworkErrorKind.timeout], contains('timed out'));
    expect(messages[NetworkErrorKind.timeout], contains('"Request timeout" in Settings'));
    expect(messages[NetworkErrorKind.connectionError], startsWith('Couldn\'t reach the server'));
    expect(messages[NetworkErrorKind.badResponse], contains('could not be read'));
    expect(messages[NetworkErrorKind.other], 'The request failed: boom (NetworkErrorKind.other)');
    for (final message in messages.values) {
      expect(message, isNot(contains('Something went wrong')));
    }
  });

  test('an undefined variable is named inline, with nothing to expand', () async {
    final vm = await viewModelFor('{{baseUrl}}/users');

    await vm.send();

    expect(vm.errorMessage, contains('{{baseUrl}} (used in the URL) is not defined'));
    expect(vm.errorDetail, isNull);
    expect(client.sent, isEmpty);
  });

  test('a URL that cannot be sent says what it needs, and keeps the URL (masked) in the details', () async {
    final vm = await viewModelFor('ftp://example.com/file?api_key=s3cret-key');

    await vm.send();

    expect(vm.errorMessage, "That URL isn't valid — it needs an http(s) scheme and a host, e.g. https://api.example.com/users");
    expect(vm.errorDetail, startsWith('Not a valid http(s) URL: "ftp://example.com/file?api_key='));
    expect(vm.errorDetail, isNot(contains('s3cret-key')));
  });

  test('a FormatException is a bad URL or header, not an unreachable server', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.failWith = const FormatException('Invalid port', 'https://h.test:abc/?token=s3cret-token', 15);

    await vm.send();

    expect(vm.errorMessage, startsWith('The URL or a header could not be read: Invalid port'));
    expect(vm.errorMessage, isNot(contains('reach the server')));
    expect(vm.errorMessage, isNot(contains('s3cret-token')));
    expect(vm.errorDetail, isNot(contains('s3cret-token')));
  });

  test('a URL quoted by a failure is masked in the line and in the details', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.failWith = const NetworkException(
      'Could not load https://api.example.com/users?api_key=s3cret-key&page=2 because of a fault.',
      kind: NetworkErrorKind.other,
    );

    await vm.send();

    expect(vm.errorMessage, startsWith('The request failed: Could not load https://api.example.com/users?api_key='));
    expect(vm.errorMessage, contains('page=2'));
    expect(vm.errorMessage, isNot(contains('s3cret-key')));
    expect(vm.errorDetail, isNot(contains('s3cret-key')));
  });

  test('a summary that quotes a secret is masked too', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.failWith = const NetworkException(
      'details',
      kind: NetworkErrorKind.other,
      summary: 'Failed for https://u:hunter2@api.example.com/x?token=abc123xyz',
    );

    await vm.send();

    expect(vm.errorMessage, isNot(contains('hunter2')));
    expect(vm.errorMessage, isNot(contains('abc123xyz')));
  });

  test('an error of a type nobody planned for says what it was', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.throwAnything = StateError('the pool is closed');

    await vm.send();

    expect(vm.errorMessage, 'The request failed: Bad state: the pool is closed');
  });

  test('a later good send clears the error', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.failWith = const NetworkException('x', kind: NetworkErrorKind.timeout);
    await vm.send();
    expect(vm.errorMessage, isNotNull);

    client.failWith = null;
    await vm.send();

    expect(vm.errorMessage, isNull);
    expect(vm.errorDetail, isNull);
    expect(vm.response!.statusCode, 200);
  });

  test('a failed send drops the previous response, which this send never produced', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    await vm.send();
    expect(vm.response, isNotNull);

    client.failWith = const NetworkException('x', kind: NetworkErrorKind.timeout);
    await vm.send();

    expect(vm.response, isNull);
  });

  test('a cancelled send shows no error', () async {
    final vm = await viewModelFor('https://api.example.com/users');
    client.gate = Completer<void>();

    final sending = vm.send();
    await pumpEventQueue();
    vm.cancelSend();
    await sending;

    expect(vm.errorMessage, isNull);
    expect(vm.isSending, isFalse);
  });

  group('when the response arrived but the tests could not run', () {
    test('says so instead of blaming the connection, and keeps the response', () async {
      final vm = await viewModelFor('https://api.example.com/users');
      scripts.failWith = const FormatException('Unexpected character', 'bad {{ json', 4);

      await vm.send();

      expect(vm.response!.statusCode, 200);
      expect(vm.errorMessage, startsWith('The response arrived, but the tests and variable saves could not run: '));
      expect(vm.errorMessage, contains('Unexpected character'));
      expect(vm.errorMessage, isNot(contains('reach the server')));
    });

    test('with the repository down, the same', () async {
      final vm = await viewModelFor('https://api.example.com/users');
      scripts.failWith = StateError('database is locked');

      await vm.send();

      expect(vm.response, isNotNull);
      expect(vm.errorMessage, 'The response arrived, but the tests and variable saves could not run: Bad state: database is locked');
    });
  });
}

final class _Client implements ApiClient {
  final List<ApiRequestSpec> sent = [];
  Object? failWith;
  Object? throwAnything;
  Completer<void>? gate;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    final gate = this.gate;
    if (gate != null) {
      await Future.any([gate.future, if (spec.cancelToken != null) spec.cancelToken!.whenCancelled]);
      if (spec.cancelToken?.isCancelled ?? false) {
        throw const NetworkException('cancelled', kind: NetworkErrorKind.cancelled);
      }
    }
    final failure = throwAnything ?? failWith;
    if (failure != null) throw failure;
    return ApiHttpResponse(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode('{}'),
      duration: Duration.zero,
    );
  }
}

final class _Requests implements RequestRepository {
  final ApiRequestEntity request;
  _Requests(this.request);

  @override
  Future<ApiRequestEntity?> findById(int id) async => request;

  @override
  Stream<ApiRequestEntity?> watchById(int id) => const Stream.empty();

  @override
  Future<void> saveRequest(ApiRequestEntity request) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Scripts implements RequestScriptsRepository {
  Object? failWith;

  @override
  Future<RequestScriptsEntity?> get(int requestId) async {
    final failure = failWith;
    if (failure != null) throw failure;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

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
