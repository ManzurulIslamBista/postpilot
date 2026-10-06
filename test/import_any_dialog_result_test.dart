// The unified Import dialog after an import that left things out: it stays open on the list instead of closing
// behind a snackbar, and it recognises Postman environments.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/presentation/import_any_dialog.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';

final class _Importer implements UseCase<ImportSummary, ImportAnyParams> {
  final ImportSummary summary;
  final calls = <ImportAnyParams>[];
  _Importer(this.summary);

  @override
  Future<ImportSummary> call(ImportAnyParams params) async {
    calls.add(params);
    return summary;
  }
}

const _withNotes = ImportSummary(
  format: ImportFormat.postman,
  collectionIds: [1],
  collectionName: 'Shop',
  folders: 1,
  requests: 4,
  skipped: 2,
  notes: [
    'Request "Login": test script statement not converted: tests["x"] = true',
    'Request "Orders": "hawk" authentication is not supported, so it was imported without authentication.',
    'Folder "Auth": 1 variable imported as collection variable (PostPilot has no folder-level variables).',
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  ImportSummary? popped;
  var closed = false;

  setUp(() async {
    await locator.reset();
    popped = null;
    closed = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  Future<_Importer> openDialog(WidgetTester tester, ImportSummary summary) async {
    final importer = _Importer(summary);
    locator.registerFactory<ImportAnyViewModel>(() => ImportAnyViewModel(importer));
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await ImportAnyDialog.show(context);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return importer;
  }

  Future<void> importPostman(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '{"info":{"name":"Shop"},"item":[]}');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
  }

  testWidgets('an import with notes stays open on a list of them, headed by the number skipped', (tester) async {
    await openDialog(tester, _withNotes);

    await importPostman(tester);

    expect(closed, isFalse);
    expect(find.text('Imported with 2 skipped items'), findsOneWidget);
    expect(find.text('Imported "Shop": 1 folder, 4 requests (2 skipped)'), findsWidgets);
    for (final note in _withNotes.notes) {
      expect(find.text(note), findsOneWidget);
    }
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'the paste form is replaced by the result');
  });

  testWidgets('Done closes it and hands back the summary', (tester) async {
    await openDialog(tester, _withNotes);
    await importPostman(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(popped, same(_withNotes));
  });

  testWidgets('Escape on the result list also hands back the summary rather than dropping it', (tester) async {
    await openDialog(tester, _withNotes);
    await importPostman(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(popped, same(_withNotes));
  });

  testWidgets('notes without anything skipped are headed "with 2 notes", not "skipped items"', (tester) async {
    await openDialog(
      tester,
      const ImportSummary(
        format: ImportFormat.postmanEnvironment,
        environments: 1,
        environmentName: 'Dev',
        variables: 3,
        notes: ['1 variable is disabled, as in the export; switch it on to use it.', '1 variable was marked secret (type "secret", or a name that looks like a credential).'],
      ),
    );

    await tester.enterText(find.byType(TextField), '{"name":"Dev","values":[]}');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Imported with 2 notes'), findsOneWidget);
    expect(find.text('Imported "Dev": 1 environment, 3 variables'), findsWidgets);
  });

  testWidgets('a clean import still closes at once', (tester) async {
    await openDialog(tester, const ImportSummary(format: ImportFormat.postman, collectionIds: [1], collectionName: 'Shop', requests: 1));

    await importPostman(tester);

    expect(closed, isTrue);
    expect(find.byType(ImportAnyDialog), findsNothing);
  });

  testWidgets('a pasted Postman environment is detected and the format list offers it', (tester) async {
    await openDialog(tester, _withNotes);

    await tester.enterText(find.byType(TextField), '{"id":"1","name":"Dev","values":[{"key":"a","value":"b","enabled":true}]}');
    await tester.pump();
    expect(find.text('Detected: Postman environment or globals'), findsOneWidget);

    await tester.tap(find.text('Auto-detect'));
    await tester.pumpAndSettle();
    expect(find.text('Postman environment or globals'), findsWidgets);
  });
}
