// The Settings tab shares its row with flow and pagination: resetting the four overrides must not touch them, and
// editing one override must not lose them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/request_settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/request_settings_tab.dart';
import '../settings/fakes/fake_settings_repositories.dart';

const _flow = FlowSettings(retry: RetryPolicy(enabled: true, maxRetries: 4), alwaysRun: true);
const _pagination = PaginationSettings(enabled: true, kind: PaginationKind.page, param: 'page', itemsPath: 'rows');

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

  group('RequestSettingsViewModel', () {
    test('"use global for everything" drops the four overrides and keeps flow and pagination', () async {
      requests.stored[7] = const RequestSettings(verifySsl: false, timeoutSeconds: 5, flow: _flow, pagination: _pagination);
      await viewModel.load(7);

      viewModel.clear();
      await viewModel.flush();

      expect(viewModel.overrides, const RequestSettings(flow: _flow, pagination: _pagination));
      expect(requests.saves.last.settings, const RequestSettings(flow: _flow, pagination: _pagination));
    });

    test('with only flow and pagination there is nothing to reset: no save at all', () async {
      requests.stored[7] = const RequestSettings(flow: _flow, pagination: _pagination);
      await viewModel.load(7);

      viewModel.clear();
      await viewModel.flush();

      expect(requests.saves, isEmpty);
    });

    test('an override edited in the Settings tab is saved together with the flow the request already had', () async {
      requests.stored[7] = const RequestSettings(flow: _flow, pagination: _pagination);
      await viewModel.load(7);

      viewModel.setVerifySsl(false);
      await viewModel.flush();

      expect(requests.saves.single.settings, const RequestSettings(verifySsl: false, flow: _flow, pagination: _pagination));
    });

    test('a request with nothing stored still has no overrides, and "none" is still empty', () async {
      await viewModel.load(7);

      expect(viewModel.overrides, RequestSettings.none);
      expect(viewModel.overrides.isEmpty, isTrue);
    });
  });

  group('the Settings tab', () {
    tearDown(() => locator.reset());

    Future<void> pump(WidgetTester tester, RequestSettings stored) async {
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      requests.stored[7] = stored;
      locator.registerFactory<RequestSettingsViewModel>(() => RequestSettingsViewModel(requests, global));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SingleChildScrollView(child: RequestSettingsTab(requestId: 7, isWeb: false))),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder resetButton() =>
        find.ancestor(of: find.text('Use global settings for everything'), matching: find.bySubtype<TextButton>()).first;

    testWidgets('the reset button is off while the request only has a flow', (tester) async {
      await pump(tester, const RequestSettings(flow: _flow, pagination: _pagination));

      expect(tester.widget<TextButton>(resetButton()).onPressed, isNull);
    });

    testWidgets('the reset button is on once an override is set', (tester) async {
      await pump(tester, const RequestSettings(verifySsl: false, flow: _flow));

      expect(tester.widget<TextButton>(resetButton()).onPressed, isNotNull);
    });

    testWidgets('pressing it resets the overrides and leaves the flow', (tester) async {
      await pump(tester, const RequestSettings(verifySsl: false, timeoutSeconds: 5, flow: _flow, pagination: _pagination));

      await tester.tap(resetButton());
      await tester.pumpAndSettle();

      expect(requests.stored[7], const RequestSettings(flow: _flow, pagination: _pagination));
      expect(tester.widget<TextButton>(resetButton()).onPressed, isNull);
    });
  });
}
