import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/effective_request_options.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults are the behaviour before settings existed', () {
      const settings = AppSettings();

      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.requestTimeoutSeconds, 30);
      expect(settings.followRedirects, isTrue);
      expect(settings.maxRedirects, 10);
      expect(settings.verifySsl, isTrue);
      expect(settings.sendNoCacheHeader, isFalse);
      expect(settings.maxResponseSizeMb, 50);
      expect(settings.trimKeysAndValues, isFalse);
      expect(settings.proxy.mode, ProxyMode.system);
    });

    test('a customised document survives a JSON round trip', () {
      const settings = AppSettings(
        themeMode: AppThemeMode.dark,
        requestTimeoutSeconds: 0,
        followRedirects: false,
        maxRedirects: 3,
        verifySsl: false,
        sendNoCacheHeader: true,
        maxResponseSizeMb: 0,
        trimKeysAndValues: true,
        proxy: ProxySettings(
          mode: ProxyMode.custom,
          host: 'proxy.local',
          port: 3128,
          username: 'ann',
          password: 'p:ss@word',
          bypass: 'localhost, *.corp.example',
        ),
      );

      expect(AppSettings.fromJson(settings.toJson()), settings);
      expect(AppSettings.decode(settings.encode()), settings);
    });

    test('a document with no keys is the defaults, and a key it lacks keeps its default', () {
      expect(AppSettings.fromJson(const {}), const AppSettings());
      expect(
        AppSettings.fromJson(const {'verifySsl': false}),
        const AppSettings(verifySsl: false),
      );
      expect(
        AppSettings.fromJson(const {'proxy': {'mode': 'custom'}}).proxy,
        const ProxySettings(mode: ProxyMode.custom),
      );
    });

    test('a value of the wrong type falls back for that field only', () {
      final settings = AppSettings.fromJson(const {
        'themeMode': 42,
        'requestTimeoutSeconds': 'soon',
        'followRedirects': 'yes',
        'maxRedirects': null,
        'verifySsl': false,
        'proxy': 'direct',
      });

      expect(settings, const AppSettings(verifySsl: false));
    });

    test('an unknown enum name falls back to its default', () {
      final settings = AppSettings.fromJson(const {
        'themeMode': 'sepia',
        'proxy': {'mode': 'socks'},
      });

      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.proxy.mode, ProxyMode.system);
    });

    test('a number below its range reads as absent, one above it is capped', () {
      final settings = AppSettings.fromJson({
        'requestTimeoutSeconds': -5,
        'maxRedirects': 0,
        'maxResponseSizeMb': -1,
        'proxy': {'port': 0},
      });

      expect(settings.requestTimeoutSeconds, 30, reason: 'a negative timeout must not turn into "no timeout"');
      expect(settings.maxRedirects, 10);
      expect(settings.maxResponseSizeMb, 50, reason: 'a negative size must not turn into "unlimited"');
      expect(settings.proxy.port, ProxySettings.defaultPort);

      final capped = AppSettings.fromJson({
        'requestTimeoutSeconds': 1 << 40,
        'maxRedirects': 100000,
        'proxy': {'port': 99999},
      });
      expect(capped.requestTimeoutSeconds, AppSettings.maxTimeoutSeconds);
      expect(capped.maxRedirects, AppSettings.maxRedirectsLimit);
      expect(capped.proxy.port, 65535);
    });

    test('a whole number written as a double is read as that number', () {
      expect(AppSettings.fromJson(const {'requestTimeoutSeconds': 45.0}).requestTimeoutSeconds, 45);
    });

    test('decode returns the defaults for nothing, blank, corrupt and non-object text', () {
      for (final source in [null, '', '   ', '{not json', '[1, 2]', '"text"', '42', 'null']) {
        expect(AppSettings.decode(source), const AppSettings(), reason: '$source');
      }
    });

    test('copyWith changes only what it is given', () {
      const original = AppSettings(requestTimeoutSeconds: 12, proxy: ProxySettings(host: 'p'));
      final changed = original.copyWith(verifySsl: false);

      expect(changed.verifySsl, isFalse);
      expect(changed.requestTimeoutSeconds, 12);
      expect(changed.proxy.host, 'p');
      expect(changed, isNot(original));
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
  });

  group('RequestSettings', () {
    test('an empty override set is empty and writes no keys', () {
      expect(RequestSettings.none.isEmpty, isTrue);
      expect(RequestSettings.none.toJson(), isEmpty);
    });

    test('only the overridden keys are written, and they round trip', () {
      const settings = RequestSettings(followRedirects: false, timeoutSeconds: 0);

      expect(settings.isEmpty, isFalse);
      expect(settings.toJson(), {'followRedirects': false, 'timeoutSeconds': 0});
      expect(RequestSettings.decode(settings.encode()), settings);
      expect(
        RequestSettings.fromJson(const RequestSettings(verifySsl: true, sendNoCacheHeader: false).toJson()),
        const RequestSettings(verifySsl: true, sendNoCacheHeader: false),
      );
    });

    test('missing, mistyped and corrupt data reads as "use global"', () {
      expect(RequestSettings.fromJson(const {}), RequestSettings.none);
      expect(
        RequestSettings.fromJson(const {'followRedirects': 'no', 'verifySsl': 1, 'timeoutSeconds': 'x'}),
        RequestSettings.none,
      );
      expect(RequestSettings.fromJson(const {'timeoutSeconds': -3}), RequestSettings.none);
      for (final source in [null, '', '{oops', '[]', '7']) {
        expect(RequestSettings.decode(source), RequestSettings.none, reason: '$source');
      }
    });

    test('the with-methods set one field and can put it back to "use global"', () {
      final overridden = RequestSettings.none.withVerifySsl(false).withTimeoutSeconds(5).withFollowRedirects(true);

      expect(overridden, const RequestSettings(verifySsl: false, timeoutSeconds: 5, followRedirects: true));
      expect(overridden.withVerifySsl(null).withTimeoutSeconds(null).withFollowRedirects(null), RequestSettings.none);
      expect(overridden.withSendNoCacheHeader(true).sendNoCacheHeader, isTrue);
    });
  });

  group('EffectiveRequestOptions.resolve', () {
    test('with no override the global settings are used as they are', () {
      const app = AppSettings(
        requestTimeoutSeconds: 12,
        followRedirects: false,
        maxRedirects: 4,
        verifySsl: false,
        sendNoCacheHeader: true,
        maxResponseSizeMb: 2,
        trimKeysAndValues: true,
      );

      for (final overrides in [null, RequestSettings.none]) {
        final options = EffectiveRequestOptions.resolve(app, overrides);

        expect(options.timeout, const Duration(seconds: 12));
        expect(options.followRedirects, isFalse);
        expect(options.maxRedirects, 4);
        expect(options.verifySsl, isFalse);
        expect(options.sendNoCache, isTrue);
        expect(options.maxResponseBytes, 2 * 1024 * 1024);
        expect(options.trimKeysAndValues, isTrue);
      }
    });

    test('a request override beats the global setting, in both directions', () {
      const off = AppSettings(followRedirects: false, verifySsl: false, sendNoCacheHeader: false);
      const on = AppSettings(followRedirects: true, verifySsl: true, sendNoCacheHeader: true);

      final forcedOn = EffectiveRequestOptions.resolve(
        off,
        const RequestSettings(followRedirects: true, verifySsl: true, sendNoCacheHeader: true),
      );
      expect((forcedOn.followRedirects, forcedOn.verifySsl, forcedOn.sendNoCache), (true, true, true));

      final forcedOff = EffectiveRequestOptions.resolve(
        on,
        const RequestSettings(followRedirects: false, verifySsl: false, sendNoCacheHeader: false),
      );
      expect((forcedOff.followRedirects, forcedOff.verifySsl, forcedOff.sendNoCache), (false, false, false));
    });

    test('an override of one option leaves the others on the global setting', () {
      const app = AppSettings(verifySsl: false, requestTimeoutSeconds: 9);

      final options = EffectiveRequestOptions.resolve(app, const RequestSettings(followRedirects: false));

      expect(options.followRedirects, isFalse);
      expect(options.verifySsl, isFalse);
      expect(options.timeout, const Duration(seconds: 9));
    });

    test('a timeout of 0 means no timeout, globally or per request, and beats a global timeout', () {
      expect(EffectiveRequestOptions.resolve(const AppSettings(requestTimeoutSeconds: 0), null).timeout, isNull);
      expect(
        EffectiveRequestOptions.resolve(const AppSettings(), const RequestSettings(timeoutSeconds: 0)).timeout,
        isNull,
      );
      expect(
        EffectiveRequestOptions.resolve(const AppSettings(requestTimeoutSeconds: 0), const RequestSettings(timeoutSeconds: 8))
            .timeout,
        const Duration(seconds: 8),
      );
    });

    test('a response size of 0 means unlimited', () {
      expect(EffectiveRequestOptions.resolve(const AppSettings(maxResponseSizeMb: 0), null).maxResponseBytes, isNull);
      expect(EffectiveRequestOptions.resolve(const AppSettings(maxResponseSizeMb: 1), null).maxResponseBytes, 1048576);
    });

    test('the proxy comes from the global settings, with its bypass text split into patterns', () {
      const app = AppSettings(
        proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.local', port: 3128, bypass: 'localhost, *.corp.example;10.0.0.1'),
      );

      final proxy = EffectiveRequestOptions.resolve(app, null).proxy;

      expect(proxy.mode, ProxyMode.custom);
      expect(proxy.host, 'proxy.local');
      expect(proxy.port, 3128);
      expect(proxy.bypass, ['localhost', '*.corp.example', '10.0.0.1']);
    });

    test('toApiOptions carries exactly what was resolved', () {
      final options = EffectiveRequestOptions.resolve(
        const AppSettings(requestTimeoutSeconds: 7, maxRedirects: 2, maxResponseSizeMb: 3),
        const RequestSettings(followRedirects: false, verifySsl: false),
      ).toApiOptions();

      expect(options.timeout, const Duration(seconds: 7));
      expect(options.followRedirects, isFalse);
      expect(options.maxRedirects, 2);
      expect(options.verifySsl, isFalse);
      expect(options.maxResponseBytes, 3 * 1024 * 1024);
      expect(options.proxy, ProxyConfig.system);
    });

    test('the default API options are what the client did before settings existed', () {
      const options = ApiRequestOptions();

      expect(options.timeout, const Duration(seconds: 30));
      expect(options.followRedirects, isTrue);
      expect(options.maxRedirects, 10);
      expect(options.verifySsl, isTrue);
      expect(options.proxy.mode, ProxyMode.system);
      expect(options.maxResponseBytes, isNull);
    });
  });

  group('ProxySettings.toConfig', () {
    const custom = ProxyMode.custom;

    test('a host pasted as a URL loses its scheme and trailing slash', () {
      expect(const ProxySettings(mode: custom, host: ' http://proxy.local/ ').toConfig().host, 'proxy.local');
      expect(const ProxySettings(mode: custom, host: 'HTTPS://proxy.local///').toConfig().host, 'proxy.local');
      expect(const ProxySettings(mode: custom, host: 'proxy.local').toConfig().host, 'proxy.local');
    });

    test('bypass text splits on commas, semicolons and whitespace and drops blanks', () {
      expect(
        const ProxySettings(mode: custom, bypass: ' a.com,, b.com ;c.com\n d.com ').toConfig().bypass,
        ['a.com', 'b.com', 'c.com', 'd.com'],
      );
      expect(const ProxySettings(mode: custom, bypass: '').toConfig().bypass, isEmpty);
    });

    test('a proxy that is not custom carries nothing but its mode, however much is filled in', () {
      const filledIn = ProxySettings(host: 'proxy.local', port: 3128, username: 'ann', password: 'secret', bypass: 'a.com');

      expect(filledIn.toConfig(), ProxyConfig.system);
      expect(filledIn.copyWith(mode: ProxyMode.none).toConfig(), ProxyConfig.none);
      expect(filledIn.copyWith(mode: custom).toConfig().password, 'secret');
    });
  });

  group('ProxyConfig', () {
    ProxyConfig proxy(List<String> bypass) => ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: bypass);

    test('a plain host matches itself and its subdomains, not lookalikes', () {
      final config = proxy(['example.com']);

      expect(config.bypasses(Uri.parse('https://example.com/x')), isTrue);
      expect(config.bypasses(Uri.parse('https://api.example.com/x')), isTrue);
      expect(config.bypasses(Uri.parse('https://EXAMPLE.com/x')), isTrue);
      expect(config.bypasses(Uri.parse('https://notexample.com/x')), isFalse);
      expect(config.bypasses(Uri.parse('https://example.com.evil.io/x')), isFalse);
    });

    test('a wildcard or leading dot covers the subdomains, and * covers everything', () {
      expect(proxy(['*.corp.example']).bypasses(Uri.parse('http://a.corp.example')), isTrue);
      expect(proxy(['.corp.example']).bypasses(Uri.parse('http://a.b.corp.example')), isTrue);
      expect(proxy(['*.corp.example']).bypasses(Uri.parse('http://other.example')), isFalse);
      expect(proxy(['*']).bypasses(Uri.parse('http://anything.at.all')), isTrue);
    });

    test('an entry with a port only matches that port, and an IP literal matches exactly', () {
      final config = proxy(['localhost:3000', '10.0.0.5']);

      expect(config.bypasses(Uri.parse('http://localhost:3000/x')), isTrue);
      expect(config.bypasses(Uri.parse('http://localhost:8080/x')), isFalse);
      expect(config.bypasses(Uri.parse('http://10.0.0.5:9/x')), isTrue);
      expect(config.bypasses(Uri.parse('http://10.0.0.50/x')), isFalse);
    });

    test('blank entries and an empty list bypass nothing', () {
      expect(proxy(const []).bypasses(Uri.parse('http://localhost')), isFalse);
      expect(proxy(const ['', '  ']).bypasses(Uri.parse('http://localhost')), isFalse);
    });

    test('a custom proxy is usable only with a host and a valid port', () {
      expect(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 8080).isUsableCustom, isTrue);
      expect(const ProxyConfig(mode: ProxyMode.custom, host: '', port: 8080).isUsableCustom, isFalse);
      expect(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 0).isUsableCustom, isFalse);
      expect(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 70000).isUsableCustom, isFalse);
      expect(const ProxyConfig(mode: ProxyMode.system, host: 'p', port: 8080).isUsableCustom, isFalse);
    });

    test('equality covers every field, including the bypass list', () {
      const a = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: ['x']);

      expect(a, const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: ['x']));
      expect(a.hashCode, const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: ['x']).hashCode);
      expect(a, isNot(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: ['y'])));
      expect(a, isNot(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 2, bypass: ['x'])));
      expect(a, isNot(const ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, username: 'u', bypass: ['x'])));
    });
  });
}
