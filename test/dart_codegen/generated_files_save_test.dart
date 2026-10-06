import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/generated_files_writer.dart';
import 'package:postpilot/features/dart_codegen/domain/entities/generated_file.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/generated_files_save.dart';

/// Real file IO finishes outside the fake clock a widget test runs on: alternate between letting it
/// finish and letting the widgets react, until [condition] holds.
Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'timed out waiting');
}

const _files = [
  GeneratedFile('lib/core/network/api_client.dart', 'generated client', shared: true),
  GeneratedFile('lib/features/shop/data/ds.dart', 'generated data source'),
  GeneratedFile('lib/features/shop/shop_injection.dart', 'generated injection'),
];

/// One run of the save flow, started from a button.
final class _Flow {
  WriteFilesResult? result;
  bool finished = false;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('postpilot_save_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File at(String relative) => File('${dir.path}/$relative');

  void put(String relative, String content) {
    at(relative).parent.createSync(recursive: true);
    at(relative).writeAsStringSync(content);
  }

  Future<_Flow> start(WidgetTester tester) async {
    final flow = _Flow();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => saveGeneratedFiles(context, dir.path, _files).then((r) {
                flow.result = r;
                flow.finished = true;
              }),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    return flow;
  }

  bool dialogShown() => find.byType(AlertDialog).evaluate().isNotEmpty;

  testWidgets('shared files already in the project are kept without asking', (tester) async {
    put('lib/core/network/api_client.dart', 'my own client');
    final flow = await start(tester);
    await _until(tester, () => flow.finished || dialogShown());
    expect(dialogShown(), isFalse, reason: 'nothing else exists, so there is nothing to confirm');
    final result = flow.result!;
    expect(at('lib/core/network/api_client.dart').readAsStringSync(), 'my own client');
    expect(result.skipped, ['lib/core/network/api_client.dart']);
    expect(result.written, ['lib/features/shop/data/ds.dart', 'lib/features/shop/shop_injection.dart']);
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'generated data source');
  });

  testWidgets('an existing ordinary file is asked about; "keep them" writes only what is new', (tester) async {
    put('lib/features/shop/data/ds.dart', 'my edits');
    final flow = await start(tester);
    await _until(tester, dialogShown);
    expect(find.text('1 file already exists'), findsOneWidget);
    expect(find.text('lib/features/shop/data/ds.dart'), findsOneWidget);
    expect(find.text('Replace it'), findsOneWidget);
    expect(flow.finished, isFalse, reason: 'nothing is written before the answer');
    expect(at('lib/features/shop/shop_injection.dart').existsSync(), isFalse);

    await tester.tap(find.text('Keep them, write the rest'));
    await _until(tester, () => flow.finished);
    final result = flow.result!;
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'my edits');
    expect(result.skipped, ['lib/features/shop/data/ds.dart']);
    expect(result.written, ['lib/core/network/api_client.dart', 'lib/features/shop/shop_injection.dart']);
  });

  testWidgets('"replace" overwrites the ordinary file but still not a shared one', (tester) async {
    put('lib/features/shop/data/ds.dart', 'my edits');
    put('lib/core/network/api_client.dart', 'my own client');
    final flow = await start(tester);
    await _until(tester, dialogShown);
    // Only the ordinary file is in the question: the shared one is not up for replacing.
    expect(find.text('1 file already exists'), findsOneWidget);
    expect(find.text('lib/core/network/api_client.dart'), findsNothing);
    await tester.tap(find.text('Replace it'));
    await _until(tester, () => flow.finished);
    final result = flow.result!;
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'generated data source');
    expect(at('lib/core/network/api_client.dart').readAsStringSync(), 'my own client');
    expect(result.overwritten, ['lib/features/shop/data/ds.dart']);
    expect(result.skipped, ['lib/core/network/api_client.dart']);
  });

  testWidgets('cancelling writes nothing at all', (tester) async {
    put('lib/features/shop/data/ds.dart', 'my edits');
    final flow = await start(tester);
    await _until(tester, dialogShown);
    await tester.tap(find.text('Cancel'));
    await _until(tester, () => flow.finished);
    expect(flow.result, isNull);
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'my edits');
    expect(at('lib/features/shop/shop_injection.dart').existsSync(), isFalse);
    expect(at('lib/core/network/api_client.dart').existsSync(), isFalse);
  });

  testWidgets('the result dialog lists what was written, replaced and kept', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showWriteResult(
                context,
                '/work/app',
                const WriteFilesResult(
                  written: ['lib/a.dart', 'lib/b.dart', 'lib/c.dart'],
                  overwritten: ['lib/b.dart'],
                  skipped: ['lib/core/network/api_client.dart', 'lib/core/usecases/usecase.dart'],
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to /work/app'), findsOneWidget);
    expect(find.text('2 new files written'), findsOneWidget);
    expect(find.text('1 file replaced'), findsOneWidget);
    expect(find.text('2 existing files kept as they were'), findsOneWidget);
    expect(find.text('lib/core/usecases/usecase.dart'), findsOneWidget);
    expect(find.textContaining('check that it still matches'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the result dialog says so when nothing could be written', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showWriteResult(context, '/work/app', const WriteFilesResult(skipped: ['lib/x.dart'])),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing was written'), findsOneWidget);
    expect(find.text('1 existing file kept as it was'), findsOneWidget);
  });
}
