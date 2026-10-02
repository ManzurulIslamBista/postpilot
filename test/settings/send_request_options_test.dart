import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
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
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'fakes/fake_settings_repositories.dart';

void main() {
  late _ScriptedApiClient client;
  late FakeSettingsRepository globalSettings;
  late FakeRequestSettingsRepository requestSettings;

  SendRequestUseCase buildUseCase({bool withSettings = true}) => SendRequestUseCase(
        client,
        BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals()),
        _NoHistory(),
        _NoCollectionAuth(),
        withSettings ? globalSettings : null,
        withSettings ? requestSettings : null,
      );

  setUp(() {
    client = _ScriptedApiClient();
    globalSettings = FakeSettingsRepository();
    requestSettings = FakeRequestSettingsRepository();
  });

  group('without settings repositories', () {
    test('the request goes out with the default settings', () async {
      await buildUseCase(withSettings: false)(_request());

      final options = client.sent.single.options;
      expect(options.timeout, const Duration(seconds: 30));
      expect(options.followRedirects, isTrue);
      expect(options.maxRedirects, 10);
      expect(options.verifySsl, isTrue);
      expect(options.proxy, ProxyConfig.system);
      expect(options.maxResponseBytes, 50 * 1024 * 1024);
      expect(client.sent.single.headers, isNot(contains('Cache-Control')));
    });

    test('the code that never heard of settings still builds the use case with four arguments', () async {
      final useCase = SendRequestUseCase(
        client,
        BuildVariableResolverUseCase(_NoCollectionVariables(), _NoEnvironment(), _NoGlobals()),
        _NoHistory(),
        _NoCollectionAuth(),
      );

      final response = await useCase(_request());

      expect(response.statusCode, 200);
    });
  });

  group('global settings', () {
    test('reach the client as the request\'s options', () async {
      globalSettings.changeElsewhere(const AppSettings(
        requestTimeoutSeconds: 12,
        followRedirects: false,
        maxRedirects: 3,
        verifySsl: false,
        maxResponseSizeMb: 2,
        proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.local', port: 3128, bypass: 'localhost'),
      ));

      await buildUseCase()(_request());

      final options = client.sent.single.options;
      expect(options.timeout, const Duration(seconds: 12));
      expect(options.followRedirects, isFalse);
      expect(options.maxRedirects, 3);
      expect(options.verifySsl, isFalse);
      expect(options.maxResponseBytes, 2 * 1024 * 1024);
      expect(options.proxy.mode, ProxyMode.custom);
      expect(options.proxy.host, 'proxy.local');
      expect(options.proxy.port, 3128);
      expect(options.proxy.bypass, ['localhost']);
    });

    test('a timeout and a size limit of 0 mean none', () async {
      globalSettings.changeElsewhere(const AppSettings(requestTimeoutSeconds: 0, maxResponseSizeMb: 0));

      await buildUseCase()(_request());

      expect(client.sent.single.options.timeout, isNull);
      expect(client.sent.single.options.maxResponseBytes, isNull);
    });

    test('are read on every send, so a change applies to the next request without a restart', () async {
      final useCase = buildUseCase();

      await useCase(_request());
      globalSettings.changeElsewhere(const AppSettings(verifySsl: false));
      await useCase(_request());

      expect(client.sent.map((s) => s.options.verifySsl), [true, false]);
    });
  });

  group('per-request overrides', () {
    test('beat the global settings for that request', () async {
      globalSettings.changeElsewhere(const AppSettings(followRedirects: true, verifySsl: true, requestTimeoutSeconds: 30));
      requestSettings.stored[1] = const RequestSettings(followRedirects: false, verifySsl: false, timeoutSeconds: 5);

      await buildUseCase()(_request(id: 1));

      final options = client.sent.single.options;
      expect(options.followRedirects, isFalse);
      expect(options.verifySsl, isFalse);
      expect(options.timeout, const Duration(seconds: 5));
    });

    test('apply only to their own request', () async {
      requestSettings.stored[1] = const RequestSettings(verifySsl: false);
      final useCase = buildUseCase();

      await useCase(_request(id: 1));
      await useCase(_request(id: 2));

      expect(client.sent.map((s) => s.options.verifySsl), [false, true]);
    });

    test('an override of 0 seconds waits forever even when the global timeout is set', () async {
      requestSettings.stored[1] = const RequestSettings(timeoutSeconds: 0);

      await buildUseCase()(_request(id: 1));

      expect(client.sent.single.options.timeout, isNull);
    });

    test('a request whose overrides cannot be read is sent with the global settings', () async {
      globalSettings.changeElsewhere(const AppSettings(requestTimeoutSeconds: 7));
      requestSettings.getFailure = StateError('unreadable');

      await buildUseCase()(_request());

      expect(client.sent.single.options.timeout, const Duration(seconds: 7));
    });
  });

  group('the no-cache header', () {
    test('is added when the global setting is on', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      await buildUseCase()(_request());

      expect(client.sent.single.headers['Cache-Control'], 'no-cache');
    });

    test('is not added when the setting is off', () async {
      await buildUseCase()(_request());

      expect(client.sent.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cache-control')));
    });

    test('leaves a Cache-Control the request sets itself alone, whatever its case', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      for (final name in ['Cache-Control', 'cache-control', 'CACHE-CONTROL']) {
        client.sent.clear();
        await buildUseCase()(_request(headers: [KeyValueItem(key: name, value: 'max-age=60')]));

        expect(client.sent.single.headers, {name: 'max-age=60'}, reason: name);
      }
    });

    test('follows a per-request override in either direction', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));
      requestSettings.stored[1] = const RequestSettings(sendNoCacheHeader: false);
      final useCase = buildUseCase();

      await useCase(_request(id: 1));
      expect(client.sent.last.headers.keys, isNot(contains('Cache-Control')));

      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: false));
      requestSettings.stored[1] = const RequestSettings(sendNoCacheHeader: true);
      await useCase(_request(id: 1));
      expect(client.sent.last.headers['Cache-Control'], 'no-cache');
    });

    test('keeps the request\'s own headers', () async {
      globalSettings.changeElsewhere(const AppSettings(sendNoCacheHeader: true));

      await buildUseCase()(_request(headers: [KeyValueItem(key: 'X-Trace', value: 'abc')]));

      expect(client.sent.single.headers, {'X-Trace': 'abc', 'Cache-Control': 'no-cache'});
    });
  });

  group('trimming keys and values', () {
    final padded = [KeyValueItem(key: '  X-Trace ', value: ' abc  ')];

    test('is applied when the global setting is on', () async {
      globalSettings.changeElsewhere(const AppSettings(trimKeysAndValues: true));

      await buildUseCase()(_request(headers: padded));

      expect(client.sent.single.headers, {'X-Trace': 'abc'});
    });

    test('is not applied when it is off', () async {
      await buildUseCase()(_request(headers: padded));

      expect(client.sent.single.headers, {'  X-Trace ': ' abc  '});
    });

    test('also tidies the query string of the URL that is sent', () async {
      globalSettings.changeElsewhere(const AppSettings(trimKeysAndValues: true));

      await buildUseCase()(_request(params: [KeyValueItem(key: ' q ', value: ' hello ')]));

      expect(client.sent.single.url, 'https://api.example.com/items?q=hello');
    });
  });

  group('the response', () {
    test('says when the client cut its body off', () async {
      client.next = const ApiHttpResponse(
        statusCode: 200,
        statusMessage: 'OK',
        headers: {},
        bodyBytes: [1, 2, 3],
        duration: Duration.zero,
        truncated: true,
      );

      final response = await buildUseCase()(_request());

      expect(response.truncated, isTrue);
      expect(response.bodyBytes, [1, 2, 3]);
    });

    test('is not marked truncated when it was not', () async {
      final response = await buildUseCase()(_request());

      expect(response.truncated, isFalse);
    });
  });

  group('the digest retry', () {
    const challenge = 'Digest realm="api", nonce="abc123", qop="auth", algorithm=MD5';

    test('goes out with the same options and headers as the first attempt', () async {
      globalSettings.changeElsewhere(const AppSettings(
        sendNoCacheHeader: true,
        verifySsl: false,
        requestTimeoutSeconds: 9,
        maxResponseSizeMb: 1,
      ));
      client.script = [
        const ApiHttpResponse(
          statusCode: 401,
          statusMessage: 'Unauthorized',
          headers: {'www-authenticate': challenge},
          bodyBytes: [],
          duration: Duration.zero,
        ),
      ];

      await buildUseCase()(_request(auth: const RequestAuth(type: AuthType.digest, basicUsername: 'ann', basicPassword: 'pw')));

      expect(client.sent, hasLength(2));
      final first = client.sent[0];
      final retry = client.sent[1];
      expect(retry.options.verifySsl, isFalse);
      expect(retry.options.timeout, const Duration(seconds: 9));
      expect(retry.options.maxResponseBytes, 1024 * 1024);
      expect(retry.headers['Cache-Control'], 'no-cache');
      expect(retry.headers['Authorization'], startsWith('Digest '));
      expect(first.headers['Cache-Control'], 'no-cache');
      expect(first.headers, isNot(contains('Authorization')));
    });

    test('signs the request-uri with its query string, as it goes on the request line', () async {
      client.script = [
        const ApiHttpResponse(
          statusCode: 401,
          statusMessage: 'Unauthorized',
          headers: {'www-authenticate': challenge},
          bodyBytes: [],
          duration: Duration.zero,
        ),
      ];

      await buildUseCase()(_request(
        params: [KeyValueItem(key: 'page', value: '2')],
        auth: const RequestAuth(type: AuthType.digest, basicUsername: 'ann', basicPassword: 'pw'),
      ));

      expect(client.sent[1].url, 'https://api.example.com/items?page=2');
      expect(client.sent[1].headers['Authorization'], contains('uri="/items?page=2"'));
    });

    test('digestRequestUri keeps the query and falls back to "/" for an empty path', () {
      expect(digestRequestUri('https://h.example/api/items?page=2&x=a%20b'), '/api/items?page=2&x=a%20b');
      expect(digestRequestUri('https://h.example/api/items'), '/api/items');
      expect(digestRequestUri('https://h.example'), '/');
      expect(digestRequestUri('https://h.example?x=1'), '/?x=1');
    });
  });
}

ApiRequestEntity _request({
  int id = 1,
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> params = const [],
  RequestAuth auth = const RequestAuth(type: AuthType.none),
}) =>
    ApiRequestEntity(
      id: id,
      collectionId: 1,
      folderId: null,
      name: 'r',
      method: HttpMethod.get,
      url: 'https://api.example.com/items',
      headers: headers,
      queryParams: params,
      body: RequestBody.empty,
      auth: auth,
    );

/// Records every spec sent; answers from [script] first, then with [next].
final class _ScriptedApiClient implements ApiClient {
  final List<ApiRequestSpec> sent = [];
  List<ApiHttpResponse> script = [];
  ApiHttpResponse next = const ApiHttpResponse(
    statusCode: 200,
    statusMessage: 'OK',
    headers: {},
    bodyBytes: [],
    duration: Duration.zero,
  );

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    return script.isEmpty ? next : script.removeAt(0);
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
