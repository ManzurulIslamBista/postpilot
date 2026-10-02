import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_result.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/script_run_result.dart';
import 'package:postpilot/features/scripting/presentation/widgets/script_results_view.dart';

import 'documentation/support/pump_app.dart';

const _allPass = ScriptRunResult(
  assertions: [
    AssertionResult(name: 'Status is 2xx', passed: true, actual: '200'),
    AssertionResult(name: 'access_token exists', passed: true, actual: 'abc'),
  ],
  extracted: [ExtractionResult(key: 'accessToken', scope: ExtractorScope.environment, value: 'abc')],
);

const _oneFails = ScriptRunResult(
  assertions: [
    AssertionResult(name: 'Status is 2xx', passed: true, actual: '200'),
    AssertionResult(name: 'body has id', passed: false, actual: 'missing'),
  ],
  extracted: [],
);

void main() {
  testWidgets('a clean run folds down to its one-line summary, leaving the room to the response', (tester) async {
    await tester.pumpWidget(themedApp(const ScriptResultsView(result: _allPass)));

    expect(find.text('2/2 tests passed · 1/1 variables saved'), findsOneWidget);
    expect(find.text('Status is 2xx'), findsNothing);
    expect(find.text('access_token exists'), findsNothing);
  });

  testWidgets('tapping the summary shows every check, and tapping again hides them', (tester) async {
    await tester.pumpWidget(themedApp(const ScriptResultsView(result: _allPass)));

    await tester.tap(find.text('2/2 tests passed · 1/1 variables saved'));
    await tester.pump();
    expect(find.text('Status is 2xx'), findsOneWidget);
    expect(find.text('access_token exists'), findsOneWidget);
    expect(find.textContaining('accessToken'), findsOneWidget);

    await tester.tap(find.text('2/2 tests passed · 1/1 variables saved'));
    await tester.pump();
    expect(find.text('Status is 2xx'), findsNothing);
  });

  testWidgets('a failing check opens the list by itself, since that is what needs reading', (tester) async {
    await tester.pumpWidget(themedApp(const ScriptResultsView(result: _oneFails)));

    expect(find.text('1/2 tests passed'), findsOneWidget);
    expect(find.text('body has id'), findsOneWidget);
    expect(find.text('missing'), findsOneWidget);
  });

  testWidgets('a new verdict resets the fold: success folds away, failure opens', (tester) async {
    Widget view(ScriptRunResult r) => themedApp(ScriptResultsView(result: r));

    await tester.pumpWidget(view(_oneFails));
    expect(find.text('body has id'), findsOneWidget);

    await tester.pumpWidget(view(_allPass));
    await tester.pump();
    expect(find.text('Status is 2xx'), findsNothing);

    await tester.pumpWidget(view(_oneFails));
    await tester.pump();
    expect(find.text('body has id'), findsOneWidget);
  });

  testWidgets('a request without scripts shows nothing', (tester) async {
    await tester.pumpWidget(themedApp(const ScriptResultsView(result: ScriptRunResult.empty)));
    expect(find.byType(InkWell), findsNothing);
  });
}
