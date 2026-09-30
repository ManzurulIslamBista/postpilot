import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/import_export/domain/entities/backup_export.dart';
import 'package:postpilot/features/import_export/domain/entities/collection_export_result.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/presentation/backup_dialog.dart';
import 'package:postpilot/features/import_export/presentation/export_collection_dialog.dart';
import 'package:postpilot/features/import_export/presentation/import_any_dialog.dart';
import 'package:postpilot/features/import_export/presentation/view_models/backup_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/export_collection_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';

/// A use case that answers with [respond] and remembers what it was asked.
final class _Recorder<Output, Params> implements UseCase<Output, Params> {
  final Future<Output> Function(Params params) respond;
  final calls = <Params>[];
  _Recorder(this.respond);

  @override
  Future<Output> call(Params params) {
    calls.add(params);
    return respond(params);
  }
}

/// A page with one button that opens the dialog under test.
Widget _host(void Function(BuildContext context) open) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(builder: (context) => Center(child: FilledButton(onPressed: () => open(context), child: const Text('open')))),
      ),
    );

Future<void> _openDialog(WidgetTester tester, void Function(BuildContext context) open) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(open));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

bool _isEnabled(WidgetTester tester, String label) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, label)).onPressed != null;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await locator.reset();
    // Clipboard writes go to the platform channel; nothing listens in a test.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  group('ImportAnyDialog', () {
    late _Recorder<ImportSummary, ImportAnyParams> importer;

    setUp(() {
      importer = _Recorder((params) async {
        if (params.text.contains('boom')) throw const ImportException('it exploded.');
        return const ImportSummary(format: ImportFormat.postman, collectionIds: [1], collectionName: 'Pets', folders: 2, requests: 5);
      });
      locator.registerFactory<ImportAnyViewModel>(() => ImportAnyViewModel(importer));
    });

    testWidgets('detects the format, lets you override it, reports errors and confirms a success', (tester) async {
      await _openDialog(tester, (c) => ImportAnyDialog.show(c));

      expect(find.text('Nothing pasted yet'), findsOneWidget);
      expect(_isEnabled(tester, 'Import'), isFalse);

      await tester.enterText(find.byType(TextField), '{"info":{"name":"P"},"item":[]}');
      await tester.pump();
      expect(find.text('Detected: Postman collection'), findsOneWidget);
      expect(_isEnabled(tester, 'Import'), isTrue);

      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pump();
      expect(find.textContaining("Couldn't recognise"), findsOneWidget);
      expect(_isEnabled(tester, 'Import'), isFalse);

      await tester.tap(find.text('Auto-detect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HAR recording').last);
      await tester.pumpAndSettle();
      expect(find.text('Importing as: HAR recording'), findsOneWidget);
      expect(_isEnabled(tester, 'Import'), isTrue);

      await tester.enterText(find.byType(TextField), 'boom');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('Could not import as HAR recording: it exploded.'), findsOneWidget);
      expect(importer.calls.single.format, ImportFormat.har);

      await tester.tap(find.text('HAR recording').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto-detect').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '{"info":{"name":"P"},"item":[]}');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Imported "Pets": 2 folders, 5 requests'), findsOneWidget);
      expect(find.byType(ImportAnyDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says where cURL commands go, and passes the target on', (tester) async {
      await _openDialog(tester, (c) => ImportAnyDialog.show(c, collectionId: 5, folderId: 8));
      await tester.enterText(find.byType(TextField), 'curl https://a.test');
      await tester.pump();

      expect(find.text('Detected: cURL command'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect((importer.calls.single.collectionId, importer.calls.single.folderId), (5, 8));
    });

    testWidgets('cURL commands pasted without a target say they get a new collection', (tester) async {
      await _openDialog(tester, (c) => ImportAnyDialog.show(c));

      await tester.enterText(find.byType(TextField), 'curl https://a.test');
      await tester.pump();

      expect(find.text('Detected: cURL command (into a new collection)'), findsOneWidget);
    });
  });

  group('BackupDialog', () {
    testWidgets('exports with a secrets warning, and restores with friendly errors', (tester) async {
      final export = _Recorder<BackupExport, NoParams>((_) async => BackupExport(
            text: '{"format":"postpilot-backup"}' * 2000,
            collections: 2,
            folders: 3,
            requests: 9,
            environments: 1,
            globalVariables: 4,
          ));
      final restore = _Recorder<ImportSummary, String>((text) async {
        if (text.contains('bad')) throw const ImportException('nope.');
        return const ImportSummary(format: ImportFormat.backup, collectionIds: [1, 2], requests: 4);
      });
      locator.registerFactory<BackupViewModel>(() => BackupViewModel(export, restore));

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host((c) => BackupDialog.show(c)));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 collections, 9 requests, 1 environments, 4 global variables'), findsOneWidget);
      expect(find.textContaining('contains secrets'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.text('Backup copied to clipboard'), findsOneWidget);
      // Snack bars queue: let this one slide in, time out and leave, so the restore's is the next one shown.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restore').first);
      await tester.pumpAndSettle();
      expect(_isEnabled(tester, 'Restore'), isFalse);
      await tester.enterText(find.byType(TextField), 'bad text');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Could not restore this backup: nope.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'good text');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(find.byType(BackupDialog), findsNothing);
      expect(find.text('Restored 2 collections: 4 requests'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a backup that cannot be built shows why instead of a file', (tester) async {
      final export = _Recorder<BackupExport, NoParams>((_) async => throw StateError('database is locked'));
      locator.registerFactory<BackupViewModel>(() => BackupViewModel(export, _Recorder((_) async => throw UnimplementedError())));

      await _openDialog(tester, (c) => BackupDialog.show(c));

      expect(find.textContaining('database is locked'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('ExportCollectionDialog', () {
    late _Recorder<CollectionExportResult, int> openApi;
    late _Recorder<CollectionExportResult, int> curl;

    setUp(() {
      openApi = _Recorder(
        (_) async => const CollectionExportResult(collectionName: 'Pets', text: '{"openapi":"3.0.3"}', itemCount: 3, skipped: 1),
      );
      curl = _Recorder(
        (_) async => const CollectionExportResult(collectionName: 'Pets', text: '#!/usr/bin/env bash\ncurl x', itemCount: 2, skipped: 0),
      );
      locator.registerFactory<ExportCollectionViewModel>(() => ExportCollectionViewModel(openApi, curl));
    });

    testWidgets('OpenAPI: shows the document, what was skipped, and a warning about example values', (tester) async {
      await _openDialog(tester, (c) => ExportCollectionDialog.showOpenApi(c, collectionId: 5));

      expect(find.text('Export as OpenAPI'), findsOneWidget);
      expect(find.textContaining('3 requests exported. 1 skipped'), findsOneWidget);
      expect(find.textContaining('check them for secrets'), findsOneWidget);
      expect(find.text('{"openapi":"3.0.3"}'), findsOneWidget);
      expect(openApi.calls, [5]);
      expect(curl.calls, isEmpty);

      await tester.tap(find.byTooltip('Copy'));
      await tester.pump();
      expect(find.text('Exported to clipboard'), findsOneWidget);
    });

    testWidgets('cURL script: shows the script and warns that secrets are in it', (tester) async {
      await _openDialog(tester, (c) => ExportCollectionDialog.showCurlScript(c, collectionId: 6));

      expect(find.text('Export cURL script'), findsOneWidget);
      expect(find.textContaining('written in plain text'), findsOneWidget);
      expect(find.textContaining('curl x'), findsOneWidget);
      expect(curl.calls, [6]);
      expect(openApi.calls, isEmpty);
    });

    testWidgets('an export that fails shows the reason', (tester) async {
      openApi = _Recorder((_) async => throw const NotFoundException('Collection not found.'));

      await _openDialog(tester, (c) => ExportCollectionDialog.showOpenApi(c, collectionId: 1));

      expect(find.text('Collection not found.'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsNothing);
    });
  });
}
