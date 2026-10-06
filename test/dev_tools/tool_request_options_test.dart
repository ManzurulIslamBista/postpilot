// The developer tools used to send their own calls with default options, so the
// proxy, the "do not verify certificates" switch and the timeout from Settings
// applied to every request tab except Odoo Studio, the GraphQL explorer and the
// AI assistant. These tests look at what each of them hands to the ApiClient.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/ai_assistant/data/ai_client.dart';
import 'package:postpilot/features/ai_assistant/data/ai_settings_store.dart';
import 'package:postpilot/features/graphql/presentation/graphql_explorer_view_model.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/settings_repository.dart';
import 'package:postpilot/features/settings/domain/services/tool_request_options.dart';

final class _Recording implements ApiClient {
  final specs = <ApiRequestSpec>[];
  final String body;
  _Recording(this.body);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    specs.add(spec);
    return ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: utf8.encode(body), duration: Duration.zero);
  }
}

final class _Settings implements SettingsRepository {
  @override
  final AppSettings current;
  _Settings(this.current);

  @override
  Future<void> load() async {}
  @override
  Stream<AppSettings> watch() => Stream.value(current);
  @override
  Future<void> save(AppSettings settings) async {}
  @override
  Future<void> reset() async {}
}

final class _Key implements AiSettingsStore {
  @override
  Future<String?> apiKey() async => 'sk-test';
  @override
  Future<void> saveApiKey(String key) async {}
  @override
  Future<void> clearApiKey() async {}
  @override
  Future<String> model() async => 'claude-test';
  @override
  Future<void> saveModel(String model) async {}
}

const _corporate = AppSettings(
  requestTimeoutSeconds: 12,
  followRedirects: false,
  maxRedirects: 3,
  verifySsl: false,
  maxResponseSizeMb: 1,
  proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.corp.test', port: 3128, bypass: 'localhost'),
);

void expectCorporate(ApiRequestOptions o, {Duration? timeout, int? cap}) {
  expect(o.verifySsl, isFalse, reason: 'certificate checking is off in Settings');
  expect(o.followRedirects, isFalse);
  expect(o.maxRedirects, 3);
  expect(o.proxy.mode, ProxyMode.custom);
  expect(o.proxy.host, 'proxy.corp.test');
  expect(o.proxy.port, 3128);
  expect(o.proxy.bypass, ['localhost']);
  expect(o.timeout, timeout ?? const Duration(seconds: 12));
  expect(o.maxResponseBytes, cap ?? 1024 * 1024, reason: 'the 1 MB limit of the settings is below the tool\'s own');
}

void main() {
  group('ToolRequestOptions', () {
    test('without settings it is the plain default plus the tool\'s own cap', () {
      final o = ToolRequestOptions.resolve(null, maxResponseBytes: 5);
      expect(o.timeout, const Duration(seconds: 30));
      expect(o.verifySsl, isTrue);
      expect(o.proxy.mode, ProxyMode.system);
      expect(o.followRedirects, isTrue);
      expect(o.maxResponseBytes, 5);
    });

    test('settings win for timeout, redirects, TLS and proxy; the smaller size limit wins', () {
      final o = ToolRequestOptions.resolve(_Settings(_corporate), maxResponseBytes: 8 * 1024 * 1024);
      expectCorporate(o);
      expect(ToolRequestOptions.resolve(_Settings(_corporate), maxResponseBytes: 100).maxResponseBytes, 100);
      expect(ToolRequestOptions.resolve(_Settings(const AppSettings(maxResponseSizeMb: 0)), maxResponseBytes: 100).maxResponseBytes, 100);
      expect(ToolRequestOptions.resolve(_Settings(const AppSettings(maxResponseSizeMb: 0))).maxResponseBytes, isNull);
    });

    test('a minimum timeout raises a short one but never turns "wait forever" into a limit', () {
      const ninety = Duration(seconds: 90);
      expect(ToolRequestOptions.resolve(_Settings(_corporate), minTimeout: ninety).timeout, ninety);
      expect(ToolRequestOptions.resolve(_Settings(const AppSettings(requestTimeoutSeconds: 300)), minTimeout: ninety).timeout, const Duration(seconds: 300));
      expect(ToolRequestOptions.resolve(_Settings(const AppSettings(requestTimeoutSeconds: 0)), minTimeout: ninety).timeout, isNull);
    });
  });

  test('Odoo Studio sends with the app\'s network settings', () async {
    final api = _Recording('{"lang":"en_US"}');
    await OdooClient(api, settings: _Settings(_corporate))
        .call(const OdooConnection(baseUrl: 'https://odoo.test', apiKey: 'k'), const OdooCall(model: 'res.users', method: 'context_get'));
    expectCorporate(api.specs.single.options);
    expect(api.specs.single.url, 'https://odoo.test/json/2/res.users/context_get');
  });

  test('Odoo Studio keeps its own 8 MB limit when the settings allow more', () async {
    final api = _Recording('{}');
    await OdooClient(api, settings: _Settings(const AppSettings(maxResponseSizeMb: 50)))
        .call(const OdooConnection(baseUrl: 'https://odoo.test', apiKey: 'k'), const OdooCall(model: 'm', method: 'x'));
    expect(api.specs.single.options.maxResponseBytes, 8 * 1024 * 1024);
  });

  test('the GraphQL explorer sends its introspection query with the app\'s network settings', () async {
    final api = _Recording('{"data":{"__schema":{}}}');
    final vm = GraphqlExplorerViewModel(api, () async => VariableResolver({}), settings: _Settings(_corporate))..url = 'https://gql.test/graphql';
    await vm.fetch();
    expectCorporate(api.specs.single.options);
    vm.dispose();
  });

  test('the AI assistant sends with the app\'s proxy and TLS settings and waits at least 90 seconds', () async {
    final api = _Recording('{"content":[{"type":"text","text":"hello"}]}');
    final client = AiClient(api, _Key(), appSettings: _Settings(_corporate));
    expect(await client.complete(system: 's', user: 'u'), 'hello');
    expectCorporate(api.specs.single.options, timeout: const Duration(seconds: 90), cap: 1024 * 1024);

    final patient = _Recording('{"content":[{"type":"text","text":"x"}]}');
    await AiClient(patient, _Key(), appSettings: _Settings(const AppSettings(requestTimeoutSeconds: 300))).complete(system: 's', user: 'u');
    expect(patient.specs.single.options.timeout, const Duration(seconds: 300));

    final forever = _Recording('{"content":[{"type":"text","text":"x"}]}');
    await AiClient(forever, _Key(), appSettings: _Settings(const AppSettings(requestTimeoutSeconds: 0))).complete(system: 's', user: 'u');
    expect(forever.specs.single.options.timeout, isNull);
  });

  test('every tool still works without settings (the old constructors)', () async {
    final odoo = _Recording('{}');
    await OdooClient(odoo).call(const OdooConnection(baseUrl: 'odoo.test', apiKey: 'k'), const OdooCall(model: 'm', method: 'x'));
    expect(odoo.specs.single.options.timeout, const Duration(seconds: 30));
    expect(odoo.specs.single.options.maxResponseBytes, 8 * 1024 * 1024);

    final ai = _Recording('{"content":[{"type":"text","text":"x"}]}');
    await AiClient(ai, _Key()).complete(system: 's', user: 'u');
    expect(ai.specs.single.options.timeout, const Duration(seconds: 90));
    expect(ai.specs.single.options.maxResponseBytes, 4 * 1024 * 1024);
  });
}
