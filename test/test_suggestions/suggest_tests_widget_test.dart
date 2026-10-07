// The Suggest tests tab and the Drift chip, in both themes at a desktop width and a phone width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'package:postpilot/features/test_suggestions/presentation/view_models/baseline_view_model.dart';
import 'package:postpilot/features/test_suggestions/presentation/view_models/suggestions_view_model.dart';
import 'package:postpilot/features/test_suggestions/presentation/widgets/drift_chip.dart';
import 'package:postpilot/features/test_suggestions/presentation/widgets/suggest_tests_tab.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'baseline_support.dart';
import 'response_fixtures.dart';

const _sizes = [Size(1200, 900), Size(420, 800)];

String _label(bool dark, Size size) => '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

Future<void> _pump(WidgetTester tester, Widget child, {required Size size, required bool dark}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: child),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

ApiRequestEntity _request(HttpMethod method) => ApiRequestEntity(
      id: 7,
      collectionId: 1,
      folderId: null,
      name: 'List orders',
      method: method,
      url: 'https://shop.test/orders',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(),
    );

void main() {
  late InMemoryDb db;
  late InMemoryBaselines baselines;
  late SuggestionsViewModel suggestions;
  late BaselineViewModel baseline;
  final made = <ChangeNotifier>[];
  final first = response(ordersBody());
  var asked = 0;

  void build({HttpMethod method = HttpMethod.get, ApiResponseEntity? current, Future<ApiResponseEntity> Function(ApiRequestEntity)? send}) {
    final shown = current ?? first;
    suggestions = SuggestionsViewModel(
      requestId: 7,
      response: shown,
      scripts: db.scriptsRepository,
      request: () => _request(method),
      send: send ?? (r) async => response(ordersBody(queueDepth: 99), ms: 200),
      confirmSend: (r) async {
        asked++;
        return true;
      },
    );
    baseline = BaselineViewModel(
      requestId: 7,
      response: shown,
      baselines: baselines,
      settings: db.requestSettingsRepository,
      stability: () => suggestions.stability,
      saveFile: (name, bytes) async => '/tmp/$name',
    );
    made.addAll([suggestions, baseline]);
    suggestions.load();
    baseline.load();
  }

  setUp(() {
    db = InMemoryDb();
    baselines = InMemoryBaselines();
    asked = 0;
  });

  tearDown(() {
    for (final vm in made) {
      vm.dispose();
    }
    made.clear();
  });

  for (final dark in [false, true]) {
    for (final size in _sizes) {
      final label = _label(dark, size);

      group('suggestions ($label)', () {
        testWidgets('shows the proposals grouped, with the recommended ones ticked and a confidence on each', (tester) async {
          build();
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline), size: size, dark: dark);
          expect(find.text('status is 200'), findsOneWidget);
          expect(find.text('Content-Type is application/json; charset=utf-8'), findsOneWidget);
          expect(find.text('BASICS · 3'), findsOneWidget);
          expect(find.text('Add 3 selected'), findsOneWidget);
          expect(find.text('High'), findsWidgets);
          expect(find.text('Find values that change by themselves'), findsOneWidget);
          final status = tester.widget<Checkbox>(find.byType(Checkbox).first);
          expect(status.value, isTrue);
        });

        testWidgets('ticking a row changes the count; Add writes the rows, and Undo takes them out again', (tester) async {
          build();
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline), size: size, dark: dark);
          await tester.tap(find.text('response time is under 500 ms'));
          await _settle(tester);
          expect(find.text('Add 4 selected'), findsOneWidget);
          expect(find.text('4 selected'), findsOneWidget);

          await tester.tap(find.text('Add 4 selected'));
          await _settle(tester);
          expect(ScriptsJsonCodec.decodeAssertions(db.scripts[7]!.assertionsJson).map((a) => a.type), [
            AssertionType.statusEquals,
            AssertionType.headerEquals,
            AssertionType.responseTimeBelowMs,
            AssertionType.jsonSchema,
          ]);
          expect(find.text('Added 4 tests'), findsOneWidget);
          expect(find.text('In Tests tab'), findsWidgets);
          expect(find.text('Add 0 selected'), findsOneWidget);

          await tester.tap(find.text('Undo'));
          await _settle(tester);
          expect(ScriptsJsonCodec.decodeAssertions(db.scripts[7]!.assertionsJson), isEmpty);
          expect(find.text('Added 4 tests'), findsNothing);
          expect(find.text('In Tests tab'), findsNothing);
        });

        testWidgets('Send again finds the values that change, and says which', (tester) async {
          build();
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline), size: size, dark: dark);
          await tester.scrollUntilVisible(find.text('body.queueDepth equals 12'), 300, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
          expect(find.text('body.queueDepth equals 12'), findsOneWidget);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 100000)); // back to the probe card at the top
          await tester.pump();
          await tester.tap(find.text('Send again to detect changing values'));
          await _settle(tester);
          expect(find.text('Compared two answers'), findsOneWidget);
          expect(find.text('body.queueDepth equals 12'), findsNothing);
          expect(find.text('body.queueDepth'), findsOneWidget, reason: 'listed among the fields that change');
          expect(asked, 1, reason: 'the production lock was asked');
        });

        testWidgets('a POST needs a warning acknowledged before it can be sent again', (tester) async {
          var sends = 0;
          build(method: HttpMethod.post, send: (r) async {
            sends++;
            return first;
          });
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline), size: size, dark: dark);
          expect(find.text('POST can change data'), findsOneWidget);
          final button = find.widgetWithText(FilledButton, 'Send again to detect changing values');
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
          await tester.tap(find.byType(CheckboxListTile));
          await _settle(tester);
          expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
          await tester.tap(button);
          await _settle(tester);
          expect(sends, 1);
        });

        testWidgets('a response that is not JSON says so and offers only the basics', (tester) async {
          build(current: response('<html></html>', headers: const {'Content-Type': 'text/html'}));
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline), size: size, dark: dark);
          expect(find.textContaining('The body is not JSON'), findsOneWidget);
          expect(find.text('status is 200'), findsOneWidget);
          expect(find.text('body has the fields and types seen here'), findsNothing);
        });
      });

      group('baseline and drift ($label)', () {
        testWidgets('records a baseline, then shows no drift for the same response', (tester) async {
          build();
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline, initialSection: TestsSection.baseline), size: size, dark: dark);
          expect(find.text('No baseline yet'), findsOneWidget);
          await tester.tap(find.text('Record baseline'));
          await _settle(tester);
          expect(find.textContaining('Baseline recorded: status 200'), findsWidgets);
          expect(find.text('No drift'), findsOneWidget);
          expect(baselines.rows.containsKey(7), isTrue);
        });

        testWidgets('lists the changes by seriousness; Accept takes one over, Accept all the rest', (tester) async {
          await baselines.save(7, BaselineRecorder.record(response({'id': 1, 'name': 'Ann', 'plan': 'free'})));
          build(current: response({'id': 1, 'plan': 'pro', 'email': 'a@b.co'}));
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline, initialSection: TestsSection.baseline), size: size, dark: dark);
          expect(find.text('1 breaking · 1 non-breaking · 1 info'), findsOneWidget);
          expect(find.text('BREAKING · 1'), findsOneWidget);
          expect(find.text('body.name was removed.'), findsOneWidget);
          expect(find.text('body.email is new (string).'), findsOneWidget);

          await tester.tap(find.text('Accept').first);
          await _settle(tester);
          expect(find.text('body.name was removed.'), findsNothing);
          expect(find.text('0 breaking · 1 non-breaking · 1 info'), findsOneWidget);

          await tester.tap(find.text('Accept all'));
          await _settle(tester);
          expect(find.text('No drift'), findsOneWidget);
        });

        testWidgets('Enforce baseline in runs is saved with the request, and Reset asks first', (tester) async {
          await baselines.save(7, BaselineRecorder.record(response({'a': 1})));
          build(current: response({'a': 1}));
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline, initialSection: TestsSection.baseline), size: size, dark: dark);
          await tester.tap(find.byType(Switch));
          await _settle(tester);
          expect(db.requestSettings[7]!.baseline.enforce, isTrue);

          await tester.tap(find.text('Reset baseline'));
          await _settle(tester);
          expect(find.text('Reset the baseline?'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await _settle(tester);
          expect(baselines.rows.containsKey(7), isTrue, reason: 'cancelled');

          await tester.tap(find.text('Reset baseline'));
          await _settle(tester);
          await tester.tap(find.text('Reset'));
          await _settle(tester);
          expect(baselines.rows, isEmpty);
          expect(find.text('No baseline yet'), findsOneWidget);
          expect(db.requestSettings.containsKey(7), isFalse, reason: 'enforcing was turned off with it');
        });

        testWidgets('a response cut off at the size limit cannot be recorded, and says so', (tester) async {
          build(current: response('{"a":', truncated: true));
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, baseline: baseline, initialSection: TestsSection.baseline), size: size, dark: dark);
          expect(find.textContaining('cut off at the size limit'), findsOneWidget);
          final record = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Record baseline'));
          expect(record.onPressed, isNull);
        });

        testWidgets('without a place to keep baselines the section says so', (tester) async {
          build();
          await _pump(tester, SuggestTestsPanel(suggestions: suggestions, initialSection: TestsSection.baseline), size: size, dark: dark);
          expect(find.text('Baselines are not available here'), findsOneWidget);
        });
      });

      group('the drift chip ($label)', () {
        Future<void> chip(WidgetTester tester, ApiResponseEntity shown, {VoidCallback? onOpen}) =>
            _pump(tester, Align(alignment: Alignment.topLeft, child: DriftChip(requestId: 7, response: shown, repository: baselines, onOpen: onOpen)), size: size, dark: dark);

        testWidgets('is not there for a request without a baseline', (tester) async {
          await chip(tester, first);
          expect(find.textContaining('Drift'), findsNothing);
        });

        testWidgets('says clean, N non-breaking, N breaking, N info, or not checked', (tester) async {
          await baselines.save(7, BaselineRecorder.record(response({'a': 1, 'b': 'x'})));
          await chip(tester, response({'a': 1, 'b': 'x'}));
          expect(find.text('Drift: clean'), findsOneWidget);

          await chip(tester, response({'a': 1, 'b': 'x', 'c': true}));
          expect(find.text('Drift: 1 non-breaking'), findsOneWidget);

          await chip(tester, response({'a': 1}));
          expect(find.text('Drift: 1 breaking'), findsOneWidget);

          await chip(tester, response({'a': 1, 'b': 'y'}));
          expect(find.text('Drift: 1 info'), findsOneWidget);

          await chip(tester, response('{"a":', truncated: true));
          expect(find.text('Drift: not checked'), findsOneWidget);
        });

        testWidgets('follows the baseline: it appears when one is recorded and goes when it is reset', (tester) async {
          await chip(tester, first);
          expect(find.textContaining('Drift'), findsNothing);
          await baselines.save(7, BaselineRecorder.record(first));
          await _settle(tester);
          expect(find.text('Drift: clean'), findsOneWidget);
          await baselines.delete(7);
          await _settle(tester);
          expect(find.textContaining('Drift'), findsNothing);
        });

        testWidgets('opens the baseline view when pressed', (tester) async {
          await baselines.save(7, BaselineRecorder.record(first));
          var opened = 0;
          await chip(tester, first, onOpen: () => opened++);
          await tester.tap(find.text('Drift: clean'));
          expect(opened, 1);
        });
      });
    }
  }
}
