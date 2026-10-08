// The "Clean up (recommended)" choice of the import dialog: offered for a HAR recording and for nothing else, on by default, passed on to the
// importer, and laid out on a desktop window and on a phone in both themes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/presentation/import_any_dialog.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';
import 'har_fixtures.dart';

final class _Importer implements UseCase<ImportSummary, ImportAnyParams> {
  final calls = <ImportAnyParams>[];
  Completer<ImportSummary>? hold;

  @override
  Future<ImportSummary> call(ImportAnyParams params) {
    calls.add(params);
    return hold?.future ?? Future.value(const ImportSummary(format: ImportFormat.har, collectionIds: [1], collectionName: 'Shop', requests: 3));
  }
}

const _optionTitle = 'Clean up (recommended)';
const _postman = '{"info":{"name":"P"},"item":[]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Importer importer;

  setUp(() async {
    await locator.reset();
    importer = _Importer();
    locator.registerFactory<ImportAnyViewModel>(() => ImportAnyViewModel(importer));
  });

  Future<void> open(WidgetTester tester, {double width = 1200, bool dark = false}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Builder(builder: (context) => Center(child: FilledButton(onPressed: () => ImportAnyDialog.show(context), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  bool ticked(WidgetTester tester) => tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value!;

  for (final (width, dark) in [(1200.0, false), (1200.0, true), (420.0, false), (420.0, true)]) {
    testWidgets('a HAR recording shows the option, ticked, without overflow at ${width.round()} px, ${dark ? 'dark' : 'light'}', (tester) async {
      await open(tester, width: width, dark: dark);

      await paste(tester, shopHarText());

      expect(find.text('Detected: HAR recording'), findsOneWidget);
      expect(find.text(_optionTitle), findsOneWidget);
      expect(find.textContaining('Tokens and keys become empty secret variables'), findsOneWidget);
      expect(ticked(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no other format is offered it', (tester) async {
    await open(tester);

    await paste(tester, _postman);
    expect(find.text('Detected: Postman collection'), findsOneWidget);
    expect(find.text(_optionTitle), findsNothing);

    await paste(tester, 'curl https://a.test');
    expect(find.text(_optionTitle), findsNothing);

    await paste(tester, 'hello there');
    expect(find.text(_optionTitle), findsNothing);
  });

  testWidgets('the recording is imported cleaned up unless the box is unticked', (tester) async {
    await open(tester);
    await paste(tester, shopHarText());

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(importer.calls.single.format, isNull);
    expect(importer.calls.single.cleanHar, isTrue);
  });

  testWidgets('unticked, the recording is imported as recorded', (tester) async {
    await open(tester);
    await paste(tester, shopHarText());

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(ticked(tester), isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(importer.calls.single.cleanHar, isFalse);
  });

  testWidgets('a format that is not HAR never sends the option, even though the box is ticked underneath', (tester) async {
    await open(tester);
    await paste(tester, _postman);

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(importer.calls.single.cleanHar, isFalse);
  });

  testWidgets('the box cannot be changed while the import runs', (tester) async {
    importer.hold = Completer<ImportSummary>();
    await open(tester);
    await paste(tester, shopHarText());

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();

    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged, isNull);

    importer.hold!.complete(const ImportSummary(format: ImportFormat.har, collectionIds: [1], collectionName: 'Shop', requests: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
