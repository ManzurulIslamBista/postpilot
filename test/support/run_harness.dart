import 'dart:convert';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

/// Answers every request with a 200 and remembers the URLs in the order they arrived: the order a run sent them.
final class FakeRunClient implements ApiClient {
  final List<String> sent = [];

  /// Runs while a request is "in flight", before it is answered: lets a test change the collection mid-run.
  Future<void> Function(String url)? beforeAnswer;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec.url);
    await beforeAnswer?.call(spec.url);
    return ApiHttpResponse(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode('{"ok":true}'),
      duration: const Duration(milliseconds: 5),
    );
  }

  /// The last path segment of each URL sent: `https://api.test/Login` -> `Login`.
  List<String> get sentNames => [for (final url in sent) Uri.parse(url).pathSegments.last];
}

/// The real send and scripts use cases over the repositories given, with no variables, auth, scripts or history
/// of their own, so a run only does what ordering and selection ask of it.
CollectionRunnerService buildRunner(
  RequestRepository requests,
  CollectionRepository collections,
  FakeRunClient client,
) {
  final resolver = BuildVariableResolverUseCase(_NoVariables(), _NoEnvironment(), _Globals());
  final send = SendRequestUseCase(client, resolver, _NoHistory(), _NoAuth());
  final scripts = RunRequestScriptsUseCase(_NoScripts(), resolver, _NoEnvironment(), _Globals());
  return CollectionRunnerService.withFolders(requests, send, scripts, collections, (_) async {});
}

/// The request editor's view model over [requests], sending through [client].
RequestBuilderViewModel buildBuilder(RequestRepository requests, FakeRunClient client) {
  final resolver = BuildVariableResolverUseCase(_NoVariables(), _NoEnvironment(), _Globals());
  return RequestBuilderViewModel(
    requests,
    SendRequestUseCase(client, resolver, _NoHistory(), _NoAuth()),
    GenerateCodeSnippetUseCase(resolver, _NoAuth()),
    RunRequestScriptsUseCase(_NoScripts(), resolver, _NoEnvironment(), _Globals()),
  );
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoVariables implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoEnvironment implements EnvironmentRepository {
  @override
  Future<Map<String, String>> getActiveVariables() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Globals implements GlobalVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap() async => const {};

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(const []);

  @override
  Future<void> upsert(GlobalVariableEntity variable) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoScripts implements RequestScriptsRepository {
  @override
  Future<RequestScriptsEntity?> get(int requestId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}
