// Share, Timing and Ask AI used to read the saved request: `{{baseUrl}}/users`,
// no query parameters, no auth header. They now read the request as the sender
// builds it, which holds the real values, so the masking has to be done on that.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/ai_assistant/domain/ai_tasks.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import 'package:postpilot/features/response_tools/domain/services/bug_report_builder.dart';
import 'package:postpilot/features/response_tools/domain/services/resolved_secrets.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/response_tools/presentation/view_models/response_tools_view_model.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

const _customerRef = 'cust-8842-private';
const _apiToken = 'tok-abcdef123456';
const _globalSalt = 'pepper-98765-global';

ApiResponseEntity _response() => ApiResponseEntity(
      statusCode: 201,
      statusMessage: 'Created',
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList(utf8.encode('{"id":7,"echo":"$_customerRef"}')),
      duration: const Duration(milliseconds: 40),
    );

void main() {
  late AppDatabase db;
  late DriftRepos repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
  });
  tearDown(() => db.close());

  Future<int> seedRequest({String url = '{{baseUrl}}/users'}) async {
    final collection = await repos.collectionRepository.createCollection('Shop');
    await repos.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: collection, key: 'baseUrl', value: 'https://api.test', enabled: true));
    final env = await repos.environmentRepository.create('Prod');
    Future<void> variable(String key, String value, {bool secret = false}) => repos.environmentRepository
        .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: env, key: key, value: value, isSecret: secret, enabled: true));
    // `customerRef` is flagged secret by the user; `apiToken` is secret by its name.
    await variable('customerRef', _customerRef, secret: true);
    await variable('apiToken', _apiToken);
    await variable('host', 'localhost:3000');
    await repos.environmentRepository.setActive(env);
    await repos.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'salt', value: _globalSalt, isSecret: true, enabled: true));
    return addRequest(
      repos,
      collection,
      'Create user',
      method: HttpMethod.post,
      url: url,
      headers: [KeyValueItem(key: 'X-Customer-Ref', value: '{{customerRef}}'), KeyValueItem(key: 'X-Salt', value: '{{salt}}')],
      query: [KeyValueItem(key: 'page', value: '2')],
      body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '{"ref":"{{customerRef}}","note":"hi"}'),
      auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{apiToken}}'),
    );
  }

  ResponseToolsViewModel viewModel(int requestId, {bool prepare = true}) => ResponseToolsViewModel(
        repos.requestRepository,
        repos.scriptsRepository,
        repos.exampleRepository,
        ResponseHistory(),
        ResponseToolsData.from(requestId: requestId, requestName: 'Create user', response: _response()),
        prepareRequest: prepare
            ? PrepareRequestUseCase(
                BuildVariableResolverUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository),
                repos.collectionAuthRepository,
              )
            : null,
        environments: repos.environmentRepository,
        globals: repos.globalVariableRepository,
      );

  test('the tools see the request as the sender builds it', () async {
    final vm = viewModel(await seedRequest());
    await vm.load();
    expect(vm.prepared, isNotNull, reason: vm.prepareError);
    expect(vm.requestMethod, 'POST');
    expect(vm.requestUrl, 'https://api.test/users?page=2', reason: 'variable resolved, query parameter in the URL');
    expect(vm.requestHeaders['Authorization'], 'Bearer $_apiToken', reason: 'the auth header is part of what is sent');
    expect(vm.requestHeaders['X-Customer-Ref'], _customerRef);
    expect(vm.requestBodyText, '{"ref":"$_customerRef","note":"hi"}');
  });

  test('a host typed without a scheme is http://, as the sender sends it (not https://)', () async {
    final vm = viewModel(await seedRequest(url: '{{host}}/ping'));
    await vm.load();
    expect(vm.prepared!.spec.url, 'http://localhost:3000/ping?page=2');
  });

  test('the secret variables are found: flagged ones, by name, and the globals', () async {
    final vm = viewModel(await seedRequest());
    await vm.load();
    expect(vm.secretValues, containsAll([_customerRef, _apiToken, _globalSalt]));
    expect(vm.secretValues, isNot(contains('https://api.test')), reason: 'a base URL is not a secret');
    expect(vm.secretValues.first.length, greaterThanOrEqualTo(vm.secretValues.last.length), reason: 'longest first');
  });

  test('Share: the report is built from the resolved request and no secret survives, whatever it is called', () async {
    final vm = viewModel(await seedRequest());
    await vm.load();
    final report = BugReportBuilder.build(
      method: vm.requestMethod,
      url: vm.requestUrl,
      requestHeaders: vm.requestHeaders,
      requestBody: vm.requestBodyText,
      statusCode: 201,
      statusText: 'Created',
      responseHeaders: vm.data.response.headers,
      responseBody: vm.data.bodyText,
      note: 'I sent $_customerRef by mistake',
      secretValues: vm.secretValues,
    );
    expect(report, contains('POST https://api.test/users?page=2'));
    expect(report, contains('"note": "hi"'), reason: 'the rest of the body stays readable');
    expect(report, contains('X-Customer-Ref: ••••••'));
    for (final secret in [_customerRef, _apiToken, _globalSalt]) {
      expect(report, isNot(contains(secret)), reason: secret);
    }
    // Without the extra step the names `ref` and `X-Customer-Ref` give nothing away: this is why it exists.
    final unmasked = BugReportBuilder.build(
      method: vm.requestMethod,
      url: vm.requestUrl,
      requestHeaders: vm.requestHeaders,
      requestBody: vm.requestBodyText,
      statusCode: 201,
    );
    expect(unmasked, contains(_customerRef));
  });

  test('Ask AI: what is sent is the resolved request, masked', () async {
    final vm = viewModel(await seedRequest());
    await vm.load();
    final prompt = AiTasks.explainInput(
      method: vm.requestMethod,
      url: vm.requestUrl,
      statusCode: 201,
      statusText: 'Created',
      requestHeaders: vm.requestHeaders,
      requestBody: vm.requestBodyText,
      responseHeaders: vm.data.response.headers,
      responseBody: vm.data.bodyText,
      secretValues: vm.secretValues,
    );
    expect(prompt, contains('POST https://api.test/users?page=2'));
    expect(prompt, contains('"note":"hi"'));
    for (final secret in [_customerRef, _apiToken, _globalSalt]) {
      expect(prompt, isNot(contains(secret)), reason: secret);
    }
  });

  test('without a request builder the saved request is used, as before', () async {
    final vm = viewModel(await seedRequest(), prepare: false);
    await vm.load();
    expect(vm.prepared, isNull);
    expect(vm.requestUrl, '{{baseUrl}}/users');
    expect(vm.requestHeaders['X-Customer-Ref'], '{{customerRef}}');
    expect(vm.requestBodyText, '{"ref":"{{customerRef}}","note":"hi"}');
    expect(vm.secretValues, isEmpty);
  });

  group('ResolvedSecrets', () {
    test('only secrets are collected, and too-short or plain values are left alone', () {
      final resolver = VariableResolver.layered([
        {'apiKey': 'abc', 'password': 'true', 'db_password': 'hunter2hunter2', 'baseUrl': 'https://x.test', 'note': 'visible-value'},
        {'secretAlias': '{{db_password}}', 'token': '{{undefinedThing}}'},
      ]);
      expect(ResolvedSecrets.valuesOf(resolver), ['hunter2hunter2']);
      expect(ResolvedSecrets.valuesOf(resolver, flaggedKeys: {'note'}), ['hunter2hunter2', 'visible-value']);
    });

    test('a value inside a longer one is hidden whole', () {
      expect(ResolvedSecrets.mask('a abcdef-extra b abcdef', ['abcdef-extra', 'abcdef']), 'a •••••• b ••••••');
      expect(ResolvedSecrets.mask('nothing here', const []), 'nothing here');
    });
  });
}
