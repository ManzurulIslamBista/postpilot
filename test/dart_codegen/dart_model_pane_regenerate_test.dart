// "JSON to models" with a remembered version: paste a response, remember the classes, paste a changed response and the
// panel says what changed (breaking or not) before the code. The class name is the source: another name starts afresh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/dart_codegen/domain/repositories/model_snapshot_store.dart';
import 'package:postpilot/features/dart_codegen/domain/services/model_schema_diff.dart';
import 'package:postpilot/features/dart_codegen/presentation/widgets/dart_model_pane.dart';

final class _MemoryStore implements ModelSnapshotStore {
  final saved = <String, SchemaSnapshot>{};

  @override
  Future<SchemaSnapshot?> load(String source) async => saved[source];

  @override
  Future<void> save(String source, SchemaSnapshot snapshot) async => saved[source] = snapshot;

  @override
  Future<void> forget(String source) async => saved.remove(source);
}

const _v1 = '{"id":1,"email":"a@example.com","total":5}';
const _v2 = '{"id":1,"mail":"a@example.com","total":5.5,"vip":true}';

Finder _jsonField() => find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Paste a JSON response'));

void main() {
  late _MemoryStore store;

  setUp(() async {
    await locator.reset();
    store = _MemoryStore();
    locator.registerSingleton<ModelSnapshotStore>(store);
  });

  tearDown(() => locator.reset());

  Future<void> pump(WidgetTester tester, {Size size = const Size(1000, 700)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: DartModelPane(initialJson: _v1, initialName: 'User')),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final size in const [Size(1000, 700), Size(420, 800)]) {
    testWidgets('remember a version, paste a changed response, read what changed (${size.width.toInt()}px)', (tester) async {
      await pump(tester, size: size);
      expect(find.byKey(const ValueKey('model-diff-panel')), findsNothing, reason: 'nothing remembered yet');
      expect(find.text('Remember this version'), findsOneWidget);

      await tester.tap(find.text('Remember this version'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(store.saved.keys, ['samples:user']);
      expect(find.text('The classes are the same as in the remembered version.'), findsOneWidget);
      expect(find.text('Remember this version'), findsNothing, reason: 'it is the remembered one');

      await tester.enterText(_jsonField(), _v2);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('3 changes since the remembered version: 2 breaking, 1 non-breaking'), findsOneWidget);
      // On a phone the panel is a short scrolling strip: only its first rows are built.
      if (size.width > 800) expect(find.textContaining('looks renamed to mail'), findsOneWidget);
      expect(find.text('Remember this version'), findsOneWidget, reason: 'to make the new shape the baseline');

      await tester.tap(find.text('Remember this version'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('The classes are the same as in the remembered version.'), findsOneWidget);
    });
  }

  testWidgets('another class name is another source: it starts without a baseline', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Remember this version'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.widgetWithText(TextField, 'User'), 'Account');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('model-diff-panel')), findsNothing);
    expect(find.text('Remember this version'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Account'), ' USER ');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('model-diff-panel')), findsOneWidget, reason: 'the key is the trimmed, lower-cased class name');
  });

  testWidgets('without a store registered the pane still works and offers nothing to remember', (tester) async {
    await locator.reset();
    await pump(tester);
    expect(find.text('Remember this version'), findsNothing);
    expect(find.textContaining('class User'), findsWidgets);
  });
}
