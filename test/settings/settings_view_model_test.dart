// The save delay is a real Timer, so these run under testWidgets, whose fake
// clock `pump(duration)` advances.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'fakes/fake_settings_repositories.dart';

const _delay = Duration(milliseconds: 400);

void _settingsTest(
  String name,
  Future<void> Function(WidgetTester tester, FakeSettingsRepository repository, SettingsViewModel viewModel) body, {
  AppSettings initial = const AppSettings(),
  bool disposesItself = false,
}) {
  testWidgets(name, (tester) async {
    final repository = FakeSettingsRepository(initial);
    final viewModel = SettingsViewModel(repository);
    try {
      await body(tester, repository, viewModel);
    } finally {
      // Not addTearDown: a timer still pending when the test body ends fails the test.
      if (!disposesItself) viewModel.dispose();
    }
  });
}

void main() {
  group('reading', () {
    _settingsTest('starts from the settings the repository already holds', (tester, repository, viewModel) async {
      expect(viewModel.settings.verifySsl, isFalse);
      expect(viewModel.settings.requestTimeoutSeconds, 3);
    }, initial: const AppSettings(verifySsl: false, requestTimeoutSeconds: 3));

    _settingsTest('the theme setting maps onto Flutter\'s ThemeMode', (tester, repository, viewModel) async {
      expect(viewModel.themeMode, ThemeMode.system);
      viewModel.setThemeMode(AppThemeMode.dark);
      expect(viewModel.themeMode, ThemeMode.dark);
      viewModel.setThemeMode(AppThemeMode.light);
      expect(viewModel.themeMode, ThemeMode.light);
      viewModel.setThemeMode(AppThemeMode.system);
      expect(viewModel.themeMode, ThemeMode.system);
    });
  });

  group('saving is debounced', () {
    _settingsTest('a change shows and notifies at once but is not saved yet', (tester, repository, viewModel) async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.setFollowRedirects(false);

      expect(viewModel.settings.followRedirects, isFalse);
      expect(notifications, 1);
      expect(repository.saved, isEmpty);

      await tester.pump(_delay - const Duration(milliseconds: 1));
      expect(repository.saved, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.saved.single.followRedirects, isFalse);
    });

    _settingsTest('a burst of changes is one save, of the last state, once the changes stop', (tester, repository, viewModel) async {
      viewModel.setRequestTimeoutSeconds(1);
      viewModel.setRequestTimeoutSeconds(12);
      await tester.pump(const Duration(milliseconds: 300));
      viewModel.setRequestTimeoutSeconds(123);
      viewModel.setVerifySsl(false);

      await tester.pump(_delay - const Duration(milliseconds: 1));
      expect(repository.saved, isEmpty, reason: 'every change restarts the wait');

      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.requestTimeoutSeconds, 123);
      expect(repository.saved.single.verifySsl, isFalse);

      await tester.pump(const Duration(seconds: 5));
      expect(repository.saved, hasLength(1), reason: 'nothing is left to save');
    });

    _settingsTest('changes made after a save are saved again', (tester, repository, viewModel) async {
      viewModel.setMaxRedirects(3);
      await tester.pump(_delay);
      viewModel.setMaxRedirects(4);
      await tester.pump(_delay);

      expect(repository.saved.map((s) => s.maxRedirects), [3, 4]);
    });

    _settingsTest('setting a value it already has changes nothing, notifies nobody and saves nothing', (tester, repository, viewModel) async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.setVerifySsl(true);
      viewModel.setRequestTimeoutSeconds(30);
      viewModel.setThemeMode(AppThemeMode.system);
      await tester.pump(_delay * 2);

      expect(notifications, 0);
      expect(repository.saved, isEmpty);
    });

    _settingsTest('flush saves at once, and the timer then has nothing left to save', (tester, repository, viewModel) async {
      viewModel.setSendNoCacheHeader(true);

      await viewModel.flush();
      expect(repository.saved.single.sendNoCacheHeader, isTrue);

      await tester.pump(_delay * 2);
      expect(repository.saved, hasLength(1));
    });

    _settingsTest('flush with nothing pending saves nothing', (tester, repository, viewModel) async {
      await viewModel.flush();

      expect(repository.saved, isEmpty);
    });

    _settingsTest('disposing with a change pending still saves it', (tester, repository, viewModel) async {
      viewModel.setTrimKeysAndValues(true);

      viewModel.dispose();
      await tester.pump();

      expect(repository.saved.single.trimKeysAndValues, isTrue);
      await tester.pump(_delay * 2);
      expect(repository.saved, hasLength(1));
    }, disposesItself: true);
  });

  group('setters', () {
    _settingsTest('numbers are held within their range', (tester, repository, viewModel) async {
      viewModel.setRequestTimeoutSeconds(AppSettings.maxTimeoutSeconds * 10);
      expect(viewModel.settings.requestTimeoutSeconds, AppSettings.maxTimeoutSeconds);
      viewModel.setRequestTimeoutSeconds(-4);
      expect(viewModel.settings.requestTimeoutSeconds, 0);

      viewModel.setMaxRedirects(0);
      expect(viewModel.settings.maxRedirects, 1);
      viewModel.setMaxRedirects(100000);
      expect(viewModel.settings.maxRedirects, AppSettings.maxRedirectsLimit);

      viewModel.setMaxResponseSizeMb(-1);
      expect(viewModel.settings.maxResponseSizeMb, 0);
      viewModel.setMaxResponseSizeMb(99999999);
      expect(viewModel.settings.maxResponseSizeMb, AppSettings.maxResponseSizeMbLimit);

      viewModel.setProxyPort(0);
      expect(viewModel.settings.proxy.port, 1);
      viewModel.setProxyPort(70000);
      expect(viewModel.settings.proxy.port, 65535);
    });

    _settingsTest('each setter changes its own field only', (tester, repository, viewModel) async {
      viewModel.setRequestTimeoutSeconds(0);
      viewModel.setFollowRedirects(false);
      viewModel.setMaxRedirects(2);
      viewModel.setVerifySsl(false);
      viewModel.setSendNoCacheHeader(true);
      viewModel.setTrimKeysAndValues(true);
      viewModel.setMaxResponseSizeMb(0);

      expect(
        viewModel.settings,
        const AppSettings(
          requestTimeoutSeconds: 0,
          followRedirects: false,
          maxRedirects: 2,
          verifySsl: false,
          sendNoCacheHeader: true,
          trimKeysAndValues: true,
          maxResponseSizeMb: 0,
        ),
      );
    });

    _settingsTest('the proxy fields are set one by one', (tester, repository, viewModel) async {
      viewModel.setProxyMode(ProxyMode.custom);
      viewModel.setProxyHost('proxy.local');
      viewModel.setProxyPort(3128);
      viewModel.setProxyUsername('ann');
      viewModel.setProxyPassword('secret');
      viewModel.setProxyBypass('localhost, *.corp');

      final proxy = viewModel.settings.proxy;
      expect(proxy.mode, ProxyMode.custom);
      expect(proxy.host, 'proxy.local');
      expect(proxy.port, 3128);
      expect(proxy.username, 'ann');
      expect(proxy.password, 'secret');
      expect(proxy.bypass, 'localhost, *.corp');

      await tester.pump(_delay);
      expect(repository.saved.single.proxy, proxy);
    });
  });

  group('reset', () {
    _settingsTest('puts the defaults back at once, drops a pending save and resets the repository', (tester, repository, viewModel) async {
      viewModel.setVerifySsl(false);
      viewModel.setRequestTimeoutSeconds(9);

      await viewModel.reset();

      expect(viewModel.settings, const AppSettings());
      expect(repository.resets, 1);

      await tester.pump(_delay * 2);
      expect(repository.saved, isEmpty, reason: 'the change reset threw away must not be written back');
    });

    _settingsTest('notifies so the screen redraws', (tester, repository, viewModel) async {
      var notifications = 0;
      viewModel.setVerifySsl(false);
      viewModel.addListener(() => notifications++);

      await viewModel.reset();

      expect(notifications, greaterThan(0));
    });

    _settingsTest('is not undone by the repository announcing the reset', (tester, repository, viewModel) async {
      viewModel.setSendNoCacheHeader(true);
      await viewModel.reset();
      await tester.pump();

      expect(viewModel.settings, const AppSettings());
    });
  });

  group('failures', () {
    _settingsTest('a failed save is reported, and the next change clears it and tries again', (tester, repository, viewModel) async {
      repository.failWith = StateError('disk full');
      viewModel.setVerifySsl(false);
      var notified = false;
      viewModel.addListener(() => notified = true);

      await tester.pump(_delay);

      expect(viewModel.saveError, isNotNull);
      expect(notified, isTrue);
      expect(viewModel.settings.verifySsl, isFalse, reason: 'the change stays in effect');

      repository.failWith = null;
      viewModel.setSendNoCacheHeader(true);
      expect(viewModel.saveError, isNull);
      await tester.pump(_delay);

      expect(repository.saved.single.verifySsl, isFalse);
      expect(repository.saved.single.sendNoCacheHeader, isTrue);
    });

    _settingsTest('a failed reset is reported', (tester, repository, viewModel) async {
      repository.failWith = StateError('disk full');

      await viewModel.reset();

      expect(viewModel.saveError, isNotNull);
      expect(viewModel.settings, const AppSettings());
    });
  });

  group('changes made elsewhere', () {
    _settingsTest('are adopted while nothing of its own is waiting to be saved', (tester, repository, viewModel) async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      repository.changeElsewhere(const AppSettings(themeMode: AppThemeMode.dark));
      await tester.pump();

      expect(viewModel.settings.themeMode, AppThemeMode.dark);
      expect(notifications, 1);
    });

    _settingsTest('are ignored while an edit of its own is still waiting, because that edit is newer', (tester, repository, viewModel) async {
      viewModel.setRequestTimeoutSeconds(5);

      repository.changeElsewhere(const AppSettings(requestTimeoutSeconds: 99));
      await tester.pump();

      expect(viewModel.settings.requestTimeoutSeconds, 5);

      await tester.pump(_delay);
      expect(repository.saved.single.requestTimeoutSeconds, 5);
    });

    _settingsTest('its own saves coming back do not notify a second time', (tester, repository, viewModel) async {
      viewModel.setVerifySsl(false);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await tester.pump(_delay);

      expect(repository.saved, hasLength(1));
      expect(notifications, 0);
    });

    _settingsTest('an old save arriving late does not overwrite a newer edit', (tester, repository, viewModel) async {
      viewModel.setRequestTimeoutSeconds(5);
      await tester.pump(_delay);
      viewModel.setRequestTimeoutSeconds(6);

      repository.changeElsewhere(repository.saved.single);
      await tester.pump();

      expect(viewModel.settings.requestTimeoutSeconds, 6);
    });

    _settingsTest('nothing arrives after it is disposed', (tester, repository, viewModel) async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);
      viewModel.dispose();

      repository.changeElsewhere(const AppSettings(themeMode: AppThemeMode.dark));
      await tester.pump();

      expect(notifications, 0);
    }, disposesItself: true);
  });
}
