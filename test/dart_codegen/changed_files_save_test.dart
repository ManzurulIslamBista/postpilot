// "Write changed files only": the generated set is compared with a real folder, the preview shows what would change as
// a diff, and after a yes only the new and the changed files are written. Real file IO finishes outside the fake clock
// of a widget test, so each step lets it finish and then lets the widgets react.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/generated_files_writer.dart';
import 'package:postpilot/features/dart_codegen/domain/entities/generated_file.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/generated_files_save.dart';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'timed out waiting');
}

const _files = [
  GeneratedFile('lib/core/network/api_client.dart', 'generated client', shared: true),
  GeneratedFile('lib/features/shop/data/ds.dart', 'class Ds {\n  int b;\n}'),
  GeneratedFile('lib/features/shop/shop_injection.dart', 'generated injection'),
  GeneratedFile('lib/features/shop/data/models/new_model.dart', 'class NewModel {}'),
];

final class _Flow {
  WriteFilesResult? result;
  bool finished = false;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('postpilot_changed_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File at(String relative) => File('${dir.path}/$relative');

  void put(String relative, String content) {
    at(relative).parent.createSync(recursive: true);
    at(relative).writeAsStringSync(content);
  }

  void seed() {
    put('lib/core/network/api_client.dart', 'my own client');
    put('lib/features/shop/data/ds.dart', 'class Ds {\r\n  int a;\r\n}\r\n');
    put('lib/features/shop/shop_injection.dart', 'generated injection\n');
  }

  Future<_Flow> start(WidgetTester tester, [List<GeneratedFile> files = _files]) async {
    final flow = _Flow();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => saveChangedGeneratedFiles(context, dir.path, files).then((r) {
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

  testWidgets('shows what changes as a diff, then writes only the new and the changed files', (tester) async {
    seed();
    final flow = await start(tester);
    await _until(tester, dialogShown);
    expect(find.text('Write changed files only'), findsOneWidget);
    expect(find.text('1 new · 1 changed · 1 already up to date · 1 shared kept as they are'), findsOneWidget);
    expect(find.text('lib/features/shop/data/ds.dart'), findsOneWidget);
    expect(find.text('lib/features/shop/data/models/new_model.dart'), findsOneWidget);
    expect(find.text('lib/features/shop/shop_injection.dart'), findsNothing, reason: 'it is up to date: nothing to preview');
    expect(find.text('lib/core/network/api_client.dart'), findsNothing);
    // The first tile (the changed file) is open: its diff is the change, in unified form.
    final diff = tester.widget<SelectableText>(find.byType(SelectableText).first).textSpan!.toPlainText();
    expect(diff, contains('--- a/lib/features/shop/data/ds.dart'));
    expect(diff, contains('-  int a;\n+  int b;'));

    await tester.tap(find.text('Write 2 files'));
    await _until(tester, () => flow.finished);
    final result = flow.result!;
    expect(result.written, ['lib/features/shop/data/ds.dart', 'lib/features/shop/data/models/new_model.dart']);
    expect(result.overwritten, ['lib/features/shop/data/ds.dart']);
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'class Ds {\n  int b;\n}');
    expect(at('lib/features/shop/data/models/new_model.dart').readAsStringSync(), 'class NewModel {}');
    // Not touched: the identical file keeps its own line ending, the shared file is the project's.
    expect(at('lib/features/shop/shop_injection.dart').readAsStringSync(), 'generated injection\n');
    expect(at('lib/core/network/api_client.dart').readAsStringSync(), 'my own client');
  });

  testWidgets('cancel writes nothing', (tester) async {
    seed();
    final flow = await start(tester);
    await _until(tester, dialogShown);
    await tester.tap(find.text('Cancel'));
    await _until(tester, () => flow.finished);
    expect(flow.result, isNull);
    expect(at('lib/features/shop/data/ds.dart').readAsStringSync(), 'class Ds {\r\n  int a;\r\n}\r\n');
    expect(at('lib/features/shop/data/models/new_model.dart').existsSync(), isFalse);
  });

  testWidgets('a folder that is already up to date says so and writes nothing', (tester) async {
    put('lib/features/shop/shop_injection.dart', 'generated injection');
    final flow = await start(tester, const [GeneratedFile('lib/features/shop/shop_injection.dart', 'generated injection')]);
    await _until(tester, dialogShown);
    expect(find.text('Everything is up to date'), findsOneWidget);
    expect(find.textContaining('nothing is written'), findsOneWidget);
    expect(find.textContaining('Write '), findsNothing, reason: 'no write button when there is nothing to write');
    await tester.tap(find.text('Close'));
    await _until(tester, () => flow.finished);
    expect(flow.result!.written, isEmpty, reason: 'in sync, not cancelled');
  });

  testWidgets('into an empty folder every file is new, shared ones included', (tester) async {
    final flow = await start(tester);
    await _until(tester, dialogShown);
    expect(find.text('4 new · 0 changed · 0 already up to date'), findsOneWidget);
    await tester.tap(find.text('Write 4 files'));
    await _until(tester, () => flow.finished);
    expect(flow.result!.written, hasLength(4));
    expect(at('lib/core/network/api_client.dart').readAsStringSync(), 'generated client');
  });

  group('readFilesInFolder', () {
    test('returns the text of the files that exist, and leaves out folders and missing paths', () async {
      put('a.dart', 'A');
      put('lib/b.dart', 'B');
      Directory('${dir.path}/lib/folder').createSync(recursive: true);
      final read = await readFilesInFolder(dir.path, ['a.dart', 'lib/b.dart', 'lib/missing.dart', 'lib/folder']);
      expect(read, {'a.dart': 'A', 'lib/b.dart': 'B'});
    });

    test('rejects a path that leaves the folder', () async {
      await expectLater(readFilesInFolder(dir.path, ['../outside.dart']), throwsArgumentError);
      await expectLater(readFilesInFolder(dir.path, ['/etc/passwd']), throwsArgumentError);
    });

    test('a folder that does not exist is an error, not an empty answer', () async {
      await expectLater(readFilesInFolder('${dir.path}/nope', ['a.dart']), throwsArgumentError);
    });
  });
}
