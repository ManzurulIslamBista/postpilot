import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
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
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'settings/fakes/fake_settings_repositories.dart';

void main() {
  late _RecordingApiClient client;
  late FakeSettingsRepository globalSettings;
  late FakeRequestSettingsRepository requestSettings;

  BuildVariableResolverUseCase resolver() =>
      BuildVariableResolverUseCase(_NoCollectionVariables(), _Environment(const {'tenant': 'acme'}), _NoGlobals());

  SendRequestUseCase sender() =>
      SendRequestUseCase(client, resolver(), _NoHistory(), _NoCollectionAuth(), globalSettings, requestSettings);

  GenerateCodeSnippetUseCase snippets() => GenerateCodeSnippetUseCase(
        resolver(),
        _NoCollectionAuth(),
        settings: globalSettings,
        requestSettings: requestSettings,
      );

  /// What the app sends for [request], and what a snippet for it is built from.
  Future<({ApiRequestSpec sent, ResolvedRequestSpec snippet})> sendAndSnippet(ApiRequestEntity request) async {
    await sender()(request);
    final generator = _CapturingGenerator();
    await snippets()(GenerateCodeSnippetParams(request, generator));
    return (sent: client.sent.single, snippet: generator.spec!);
  }

  void expectSame(({ApiRequestSpec sent, ResolvedRequestSpec snippet}) both) {
    expect(both.snippet.method, both.sent.method);
    expect(both.snippet.url, both.sent.url);
    expect(both.snippet.headers, both.sent.headers);
    expect(both.snippet.bodyBytes, both.sent.body);
  }

  setUp(() {
    client = _RecordingApiClient();
    globalSettings = FakeSettingsRepository();
    requestSettings = FakeRequestSettingsRepository();
  });

  group('a copied snippet equals what is sent', () {
    test('with the default settings', () async {
      final both = await sendAndSnippet(_request());

      expectSame(both);
      expect(both.snippet.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cache-control')));
      expect(both.snippet.headers['  X-Trace '], ' abc ', reason: 'nothing is trimmed unless asked to');
    });

    test('with the no-cache header on', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      final both = await sendAndSnippet(_request());

      expectSame(both);
      expect(both.snippet.headers['Cache-Control'], 'no-cache');
    });

    test('with trimming on: header and query keys and values, and the urlencoded body', () async {
      globalSettings.changeElsewhere(const AppSettings(trimKeysAndValues: true));

      final both = await sendAndSnippet(_request());

      expectSame(both);
      expect(both.snippet.headers['X-Trace'], 'abc');
      expect(both.snippet.url, 'https://api.example.com/items?q=hello');
      expect(String.fromCharCodes(both.snippet.bodyBytes!), 'name=Ann');
    });

    test('with both options on, and a signed auth header alongside', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true, trimKeysAndValues: true));

      final both = await sendAndSnippet(_request(auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'tok')));

      expectSame(both);
      expect(both.snippet.headers, containsPair('Cache-Control', 'no-cache'));
      expect(both.snippet.headers, containsPair('Authorization', 'Bearer tok'));
      expect(both.snippet.headers, containsPair('X-Trace', 'abc'));
    });

    test('a Cache-Control the request sets itself stays as written in both', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      final both = await sendAndSnippet(_request(extraHeaders: [KeyValueItem(key: 'cache-control', value: 'max-age=60')]));

      expectSame(both);
      expect(both.snippet.headers['cache-control'], 'max-age=60');
      expect(both.snippet.headers, isNot(contains('Cache-Control')));
    });

    test('a per-request override wins over the global setting, in either direction', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));
      requestSettings.stored[1] = const RequestSettings(sendNoCacheHeader: false);
      final off = await sendAndSnippet(_request());
      client.sent.clear();

      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: false));
      requestSettings.stored[1] = const RequestSettings(sendNoCacheHeader: true);
      final on = await sendAndSnippet(_request());

      expectSame(off);
      expectSame(on);
      expect(off.snippet.headers, isNot(contains('Cache-Control')));
      expect(on.snippet.headers['Cache-Control'], 'no-cache');
    });

    test('a request whose overrides cannot be read is snippeted with the global settings, as it is sent', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));
      requestSettings.getFailure = StateError('unreadable');

      final both = await sendAndSnippet(_request());

      expectSame(both);
      expect(both.snippet.headers['Cache-Control'], 'no-cache');
    });

    test('a settings change shows in the next snippet without a restart', () async {
      final useCase = snippets();
      final generator = _CapturingGenerator();

      await useCase(GenerateCodeSnippetParams(_request(), generator));
      final before = generator.spec!.headers;
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));
      await useCase(GenerateCodeSnippetParams(_request(), generator));

      expect(before, isNot(contains('Cache-Control')));
      expect(generator.spec!.headers['Cache-Control'], 'no-cache');
    });

    test('the real cURL snippet carries the header the send has', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      final text = await snippets()(GenerateCodeSnippetParams(_request(), const CurlGenerator()));
      await sender()(_request());

      expect(text, contains("--header 'Cache-Control: no-cache'"));
      expect(client.sent.single.headers['Cache-Control'], 'no-cache');
    });
  });

  group('without settings repositories', () {
    test('the snippet is built with the defaults, as before settings existed', () async {
      final useCase = GenerateCodeSnippetUseCase(resolver(), _NoCollectionAuth());
      final generator = _CapturingGenerator();

      await useCase(GenerateCodeSnippetParams(_request(), generator));

      expect(generator.spec!.headers, {'  X-Trace ': ' abc ', 'Content-Type': 'application/x-www-form-urlencoded'});
      expect(generator.spec!.url, 'https://api.example.com/items?+q+=+hello+');
    });
  });
}

ApiRequestEntity _request({
  RequestAuth auth = const RequestAuth(type: AuthType.none),
  List<KeyValueItem> extraHeaders = const [],
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'r',
      method: HttpMethod.post,
      url: 'https://api.example.com/items',
      headers: [KeyValueItem(key: '  X-Trace ', value: ' abc '), ...extraHeaders],
      queryParams: [KeyValueItem(key: ' q ', value: ' hello ')],
      body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [KeyValueItem(key: ' name ', value: ' Ann ')]),
      auth: auth,
    );

final class _CapturingGenerator implements CodeGenerator {
  ResolvedRequestSpec? spec;

  @override
  String get id => 'capture';

  @override
  String get label => 'Capture';

  @override
  String generate(ResolvedRequestSpec spec) {
    this.spec = spec;
    return '';
  }
}

final class _RecordingApiClient implements ApiClient {
  final List<ApiRequestSpec> sent = [];

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    return const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
  }
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

final class _Environment implements EnvironmentRepository {
  final Map<String, String> variables;
  _Environment(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoGlobals implements GlobalVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
