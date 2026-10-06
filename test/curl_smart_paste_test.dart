// Pasting a curl command into the URL field fills the whole request. The body it builds must be sent the way the
// command would have sent it: a form without a Content-Type is a form, not text/plain, and -F is multipart.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

final _blank = ApiRequestEntity(
  id: 1,
  collectionId: 1,
  folderId: null,
  name: 'r',
  method: HttpMethod.get,
  url: '',
  headers: [KeyValueItem(key: 'X-Old', value: 'replaced by the pasted headers')],
  queryParams: const [],
  body: const RequestBody(type: BodyType.raw, rawText: 'old body'),
  auth: const RequestAuth(type: AuthType.none),
);

void main() {
  late _Requests requests;

  Future<RequestBuilderViewModel> viewModel() async {
    requests = _Requests(_blank);
    final resolver = BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals());
    final vm = RequestBuilderViewModel(
      requests,
      SendRequestUseCase(_NoClient(), resolver, _NoHistory(), _NoCollectionAuth()),
      GenerateCodeSnippetUseCase(resolver, _NoCollectionAuth()),
      RunRequestScriptsUseCase(_NoScripts(), resolver, _NoEnvironment(), _NoGlobals()),
    );
    addTearDown(vm.dispose);
    await vm.load(1);
    return vm;
  }

  test('a form body pasted without a Content-Type is sent as a form, not as text/plain', () async {
    final vm = await viewModel();

    vm.updateUrl("curl -X POST https://api.test/login -d 'user=ann&pass=pw'");

    final request = vm.request!;
    expect((request.method, request.url), (HttpMethod.post, 'https://api.test/login'));
    expect((request.body.type, request.body.rawContentType, request.body.rawText), (BodyType.raw, RawContentType.text, 'user=ann&pass=pw'));
    expect(request.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/x-www-form-urlencoded')]);
    expect(vm.urlRevision, 1, reason: 'the URL field is told to show the new text');
    expect(requests.saved.last.url, 'https://api.test/login', reason: 'the paste is saved');
  });

  test('a JSON body stays JSON and adds no header; a declared Content-Type is kept as it is', () async {
    final vm = await viewModel();

    vm.updateUrl('curl https://api.test/j -d \'{"a":1}\'');
    expect(vm.request!.body.rawContentType, RawContentType.json);
    expect(vm.request!.headers, isEmpty);

    vm.updateUrl("curl -H 'Content-Type: application/xml' -d '<a/>' https://api.test/x");
    expect(vm.request!.body.rawContentType, RawContentType.xml);
    expect(vm.request!.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/xml')]);
  });

  test('-F fields become form data', () async {
    final vm = await viewModel();

    vm.updateUrl("curl -F 'name=Ann' -F 'role=admin' https://api.test/people");

    final request = vm.request!;
    expect(request.method, HttpMethod.post);
    expect(request.body.type, BodyType.formData);
    expect(request.body.formFields.map((f) => (f.key, f.value)), [('name', 'Ann'), ('role', 'admin')]);
  });

  test('a command with no body leaves the body that was there', () async {
    final vm = await viewModel();

    vm.updateUrl('curl -s -o /dev/null https://api.test/ping');

    expect(vm.request!.url, 'https://api.test/ping');
    expect(vm.request!.body.rawText, 'old body');
  });

  test('a command cut off in the middle of an option is just typed text, not a crash', () async {
    final vm = await viewModel();

    vm.updateUrl('curl https://api.test/ping -H');

    expect(vm.request!.url, 'curl https://api.test/ping -H');
    expect(vm.urlRevision, 0);
  });
}

final class _NoClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Requests implements RequestRepository {
  final ApiRequestEntity request;
  final saved = <ApiRequestEntity>[];
  _Requests(this.request);

  @override
  Future<ApiRequestEntity?> findById(int id) async => request;

  @override
  Stream<ApiRequestEntity?> watchById(int id) => const Stream.empty();

  @override
  Future<void> saveRequest(ApiRequestEntity request) async => saved.add(request);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoScripts implements RequestScriptsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionAuth implements CollectionAuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoCollectionVariables implements CollectionVariableRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoEnvironment implements EnvironmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoGlobals implements GlobalVariableRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
