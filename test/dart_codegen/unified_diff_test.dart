// The line diff and the "what would be written" plan. Every expected hunk header below was counted by hand from the
// inputs (1-based line numbers, three lines of context), not read back from the implementation.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/entities/generated_file.dart';
import 'package:postpilot/features/dart_codegen/domain/services/file_change_plan.dart';
import 'package:postpilot/features/dart_codegen/domain/services/unified_diff.dart';

String _lines(Iterable<String> lines) => lines.join('\n');
List<String> _numbered(int count) => [for (var i = 1; i <= count; i++) 'l$i'];

void main() {
  group('UnifiedDiff', () {
    test('identical texts have no hunks', () {
      final diff = UnifiedDiff.compute('a\nb\n', 'a\nb\n');
      expect(diff.isEmpty, isTrue);
      expect(diff.format(), '');
      expect(diff.added, 0);
      expect(diff.removed, 0);
    });

    test('line endings and trailing blank lines are not a change', () {
      expect(UnifiedDiff.compute('a\r\nb\r\n', 'a\nb').isEmpty, isTrue);
      expect(UnifiedDiff.compute('a\nb\n\n\n', 'a\nb').isEmpty, isTrue);
      expect(UnifiedDiff.compute('a\nb', 'a \nb').isEmpty, isFalse, reason: 'trailing spaces inside the text are real');
    });

    test('one changed line in ten has three lines of context on each side', () {
      final before = _numbered(10);
      final after = [...before]..[4] = 'X';
      final diff = UnifiedDiff.compute(_lines(before), _lines(after));
      expect(diff.hunks, hasLength(1));
      expect(diff.hunks.single.header, '@@ -2,7 +2,7 @@');
      expect(diff.hunks.single.lines.map((l) => l.prefixed).toList(), [' l2', ' l3', ' l4', '-l5', '+X', ' l6', ' l7', ' l8']);
      expect(diff.added, 1);
      expect(diff.removed, 1);
    });

    test('an appended line', () {
      final diff = UnifiedDiff.compute('a\nb', 'a\nb\nc');
      expect(diff.hunks.single.header, '@@ -1,2 +1,3 @@');
      expect(diff.hunks.single.lines.map((l) => l.prefixed).toList(), [' a', ' b', '+c']);
    });

    test('a new file is all additions from line 0', () {
      final diff = UnifiedDiff.compute('', 'x\ny');
      expect(diff.hunks.single.header, '@@ -0,0 +1,2 @@');
      expect(diff.added, 2);
      expect(diff.removed, 0);
    });

    test('an emptied file is all removals', () {
      final diff = UnifiedDiff.compute('x\ny', '');
      expect(diff.hunks.single.header, '@@ -1,2 +0,0 @@');
      expect(diff.removed, 2);
    });

    test('two distant changes make two hunks, two close ones share one', () {
      final before = _numbered(20);
      final far = [...before]
        ..[1] = 'B'
        ..[18] = 'S';
      final two = UnifiedDiff.compute(_lines(before), _lines(far));
      expect(two.hunks.map((h) => h.header).toList(), ['@@ -1,5 +1,5 @@', '@@ -16,5 +16,5 @@']);

      final near = [...before]
        ..[1] = 'B'
        ..[5] = 'F';
      final one = UnifiedDiff.compute(_lines(before), _lines(near));
      expect(one.hunks, hasLength(1));
      // l1..l9: the context of line 2 reaches l5, the context of line 6 starts at l3.
      expect(one.hunks.single.header, '@@ -1,9 +1,9 @@');
    });

    test('a block replaced by a longer one keeps the surrounding lines as context', () {
      final diff = UnifiedDiff.compute('a\nb\nc\nd', 'a\nX\nY\nZ\nd');
      expect(diff.hunks.single.lines.map((l) => l.prefixed).toList(), [' a', '-b', '-c', '+X', '+Y', '+Z', ' d']);
      expect(diff.hunks.single.header, '@@ -1,4 +1,5 @@');
    });

    test('a moved line is a removal and an addition, nothing else', () {
      final diff = UnifiedDiff.compute('a\nb\nc\nd', 'a\nc\nd\nb');
      expect(diff.removed, 1);
      expect(diff.added, 1);
      expect(diff.hunks.single.lines.where((l) => l.kind != DiffLineKind.context).map((l) => l.prefixed).toList(), ['-b', '+b']);
    });

    test('format writes the headers like diff -u', () {
      final text = UnifiedDiff.compute('a\nb', 'a\nB').format(beforeLabel: 'a/x.dart', afterLabel: 'b/x.dart');
      expect(text, '--- a/x.dart\n+++ b/x.dart\n@@ -1,2 +1,2 @@\n a\n-b\n+B');
    });

    test('a huge unrelated middle falls back to a plain replacement instead of a giant table', () {
      final before = [for (var i = 0; i < 3000; i++) 'old $i'];
      final after = [for (var i = 0; i < 3000; i++) 'new $i'];
      final diff = UnifiedDiff.compute(_lines(before), _lines(after));
      expect(diff.removed, 3000);
      expect(diff.added, 3000);
    });
  });

  group('FileChangePlan', () {
    const created = GeneratedFile('lib/new.dart', 'class New {}');
    const changed = GeneratedFile('lib/changed.dart', 'class A {\n  int b;\n}');
    const same = GeneratedFile('lib/same.dart', 'class Same {}');
    const shared = GeneratedFile('lib/core/api_client.dart', 'generated', shared: true);

    final plan = FileChangePlan.compute(
      [created, changed, same, shared],
      {
        'lib/changed.dart': 'class A {\n  int a;\n}\n',
        'lib/same.dart': 'class Same {}\r\n',
        'lib/core/api_client.dart': 'the project\'s own',
      },
    );

    test('sorts every file into new, changed, up to date or a shared file kept', () {
      expect(plan.created.map((c) => c.path), ['lib/new.dart']);
      expect(plan.changed.map((c) => c.path), ['lib/changed.dart']);
      expect(plan.unchanged.map((c) => c.path), ['lib/same.dart']);
      expect(plan.keptShared.map((c) => c.path), ['lib/core/api_client.dart']);
    });

    test('only the new and the changed files are written, in the order given', () {
      expect(plan.toWrite.map((f) => f.path), ['lib/new.dart', 'lib/changed.dart']);
      expect(plan.hasWork, isTrue);
    });

    test('a shared file that is missing is new, one that exists is never replaced', () {
      final fresh = FileChangePlan.compute([shared], const {});
      expect(fresh.created.map((c) => c.path), ['lib/core/api_client.dart']);
      expect(plan.keptShared.single.diff, isNull);
    });

    test('the diff of a changed file shows exactly its change, a new file is diffed against /dev/null', () {
      final text = plan.changed.single.diffText;
      expect(text, startsWith('--- a/lib/changed.dart\n+++ b/lib/changed.dart\n'));
      expect(text, contains('-  int a;\n+  int b;'));
      expect(plan.created.single.diffText, startsWith('--- /dev/null\n+++ b/lib/new.dart\n@@ -0,0 +1,1 @@\n+class New {}'));
    });

    test('nothing to write when every file already matches', () {
      final quiet = FileChangePlan.compute([same], {'lib/same.dart': 'class Same {}'});
      expect(quiet.hasWork, isFalse);
      expect(quiet.toWrite, isEmpty);
    });
  });
}
