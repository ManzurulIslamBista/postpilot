import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/request_settings_view_model.dart';
import 'fakes/fake_settings_repositories.dart';

void main() {
  late FakeRequestSettingsRepository requests;
  late FakeSettingsRepository global;
  late RequestSettingsViewModel viewModel;

  setUp(() {
    requests = FakeRequestSettingsRepository();
    global = FakeSettingsRepository();
    viewModel = RequestSettingsViewModel(requests, global);
  });
  tearDown(() => viewModel.dispose());

  group('loading', () {
    test('reads the request\'s stored overrides, and says it is loading meanwhile', () async {
      requests.stored[7] = const RequestSettings(verifySsl: false, timeoutSeconds: 4);

      final loading = viewModel.load(7);
      expect(viewModel.isLoading, isTrue);
      await loading;

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.overrides, const RequestSettings(verifySsl: false, timeoutSeconds: 4));
    });

    test('a request with nothing stored has no overrides', () async {
      await viewModel.load(7);

      expect(viewModel.overrides, RequestSettings.none);
    });

    test('a stored value that cannot be read leaves the request on the global settings', () async {
      requests.getFailure = StateError('unreadable');

      await viewModel.load(7);

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.overrides, RequestSettings.none);
    });

    test('switching to another request drops the first one\'s overrides at once', () async {
      requests.stored[1] = const RequestSettings(verifySsl: false);
      await viewModel.load(1);
      requests.gates[2] = Completer<RequestSettings>();

      final loading = viewModel.load(2);

      expect(viewModel.overrides, RequestSettings.none);
      expect(viewModel.isLoading, isTrue);
      requests.gates[2]!.complete(const RequestSettings(followRedirects: false));
      await loading;
      expect(viewModel.overrides, const RequestSettings(followRedirects: false));
    });

    test('a load that finishes after a newer one has started is ignored', () async {
      requests.gates[1] = Completer<RequestSettings>();
      requests.stored[2] = const RequestSettings(timeoutSeconds: 2);

      final slow = viewModel.load(1);
      final fast = viewModel.load(2);
      await fast;
      requests.gates[1]!.complete(const RequestSettings(verifySsl: false));
      await slow;

      expect(viewModel.overrides, const RequestSettings(timeoutSeconds: 2));
      expect(viewModel.isLoading, isFalse);
    });
  });

  group('the global settings alongside', () {
    test('are the current ones, and follow a later change', () async {
      expect(viewModel.global, const AppSettings());
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      global.changeElsewhere(const AppSettings(verifySsl: false, requestTimeoutSeconds: 0));
      await pumpEventQueue();

      expect(viewModel.global.verifySsl, isFalse);
      expect(viewModel.global.requestTimeoutSeconds, 0);
      expect(notifications, 1, reason: 'the replay of the settings it already had is not news');
    });
  });

  group('editing', () {
    test('an edit shows, notifies, and is written at once, for its own request', () async {
      await viewModel.load(7);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.setFollowRedirects(false);

      expect(viewModel.overrides.followRedirects, isFalse);
      expect(notifications, 1);
      expect(requests.saves.single.requestId, 7);
      expect(requests.saves.single.settings, const RequestSettings(followRedirects: false));
    });

    test('every edit is its own write, each carrying everything overridden so far', () async {
      await viewModel.load(7);

      viewModel.setVerifySsl(false);
      viewModel.setSendNoCacheHeader(true);
      viewModel.setTimeoutSeconds(15);

      expect(requests.saves.map((s) => s.settings), [
        const RequestSettings(verifySsl: false),
        const RequestSettings(verifySsl: false, sendNoCacheHeader: true),
        const RequestSettings(verifySsl: false, sendNoCacheHeader: true, timeoutSeconds: 15),
      ]);
    });

    test('going back to "use global" clears that override, and clearing every one saves none', () async {
      await viewModel.load(7);
      viewModel.setFollowRedirects(false);
      viewModel.setTimeoutSeconds(5);

      viewModel.setFollowRedirects(null);
      expect(requests.saves.last.settings, const RequestSettings(timeoutSeconds: 5));

      viewModel.setTimeoutSeconds(null);
      expect(requests.saves.last.settings, RequestSettings.none);
    });

    test('clear puts every override back to "use global"', () async {
      requests.stored[7] = const RequestSettings(verifySsl: false, followRedirects: true, timeoutSeconds: 1, sendNoCacheHeader: true);
      await viewModel.load(7);

      viewModel.clear();

      expect(viewModel.overrides, RequestSettings.none);
      expect(requests.saves.single.settings, RequestSettings.none);
    });

    test('an edit that changes nothing is neither notified nor written', () async {
      requests.stored[7] = const RequestSettings(verifySsl: false);
      await viewModel.load(7);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.setVerifySsl(false);
      viewModel.setFollowRedirects(null);

      expect(notifications, 0);
      expect(requests.saves, isEmpty);
    });

    test('the timeout override is held within range, and 0 means wait forever', () async {
      await viewModel.load(7);

      viewModel.setTimeoutSeconds(0);
      expect(viewModel.overrides.timeoutSeconds, 0);
      viewModel.setTimeoutSeconds(AppSettings.maxTimeoutSeconds * 3);
      expect(viewModel.overrides.timeoutSeconds, AppSettings.maxTimeoutSeconds);
      viewModel.setTimeoutSeconds(-5);
      expect(viewModel.overrides.timeoutSeconds, 0);
    });

    test('an edit before any request is loaded is ignored', () async {
      viewModel.setVerifySsl(false);

      expect(viewModel.overrides, RequestSettings.none);
      expect(requests.saves, isEmpty);
    });

    test('flush completes once the writes are done', () async {
      await viewModel.load(7);
      viewModel.setFollowRedirects(true);

      await viewModel.flush();

      expect(requests.stored[7], const RequestSettings(followRedirects: true));
    });
  });

  group('switching request', () {
    test('an edit stays with the request it was made on, and the next request starts clean', () async {
      await viewModel.load(1);
      viewModel.setVerifySsl(false);

      await viewModel.load(2);

      expect(requests.saves.single.requestId, 1);
      expect(requests.saves.single.settings, const RequestSettings(verifySsl: false));
      expect(viewModel.overrides, RequestSettings.none, reason: 'request 1\'s edit must not leak into request 2');

      viewModel.setSendNoCacheHeader(true);
      expect(requests.saves.last.requestId, 2);
      expect(requests.saves.last.settings, const RequestSettings(sendNoCacheHeader: true));
    });
  });

  group('failures', () {
    test('a failed save is reported, and the next edit clears it', () async {
      await viewModel.load(7);
      requests.saveFailure = StateError('disk full');
      var notified = false;
      viewModel.addListener(() => notified = true);

      viewModel.setVerifySsl(false);
      await viewModel.flush();

      expect(viewModel.saveError, isNotNull);
      expect(notified, isTrue);
      expect(viewModel.overrides.verifySsl, isFalse, reason: 'the edit stays in effect on screen');

      requests.saveFailure = null;
      viewModel.setSendNoCacheHeader(true);
      expect(viewModel.saveError, isNull);
      await viewModel.flush();

      expect(requests.saves.single.settings, const RequestSettings(verifySsl: false, sendNoCacheHeader: true));
    });
  });

  test('a view model that is disposed hears nothing more from the global settings', () async {
    final other = RequestSettingsViewModel(requests, global);
    var notifications = 0;
    other.addListener(() => notifications++);
    other.dispose();

    global.changeElsewhere(const AppSettings(verifySsl: false));
    await pumpEventQueue();

    expect(notifications, 0);
  });
}
