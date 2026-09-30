import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/bulk_edit_text.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/key_value_editor.dart';

KeyValueItem row(String key, String value, {bool enabled = true}) =>
    KeyValueItem(key: key, value: value, enabled: enabled);

/// `key=value`, with a `//` prefix on a disabled row: easy to compare and to read in a failure.
List<String> shape(List<KeyValueItem> items) => [
      for (final i in items) '${i.enabled ? '' : '//'}${i.key}=${i.value}',
    ];

void main() {
  group('BulkEditText.serialize', () {
    test('writes one key:value line per row and marks disabled rows with //', () {
      expect(
        BulkEditText.serialize([row('Accept', 'application/json'), row('X-Debug', '1', enabled: false)]),
        'Accept:application/json\n//X-Debug:1',
      );
    });

    test('is empty for no rows', () {
      expect(BulkEditText.serialize(const []), '');
    });

    test('skips rows that are entirely empty but keeps a key-only or value-only row', () {
      expect(BulkEditText.serialize([row('', ''), row('flag', ''), row('', 'orphan'), row('', '', enabled: false)]), 'flag:\n:orphan');
    });

    test('keeps a row on one line when its text holds line breaks', () {
      expect(BulkEditText.serialize([row('k', 'a\nb\r\nc\rd')]), 'k:a b c d');
    });
  });

  group('BulkEditText.parse', () {
    test('splits each line at its first colon so values may hold colons and URLs', () {
      expect(shape(BulkEditText.parse('Referer:https://x.test:8080/a?b=c:d')), ['Referer=https://x.test:8080/a?b=c:d']);
    });

    test('trims the key and the value', () {
      expect(shape(BulkEditText.parse('  Key  :   Some value  \n\tOther:x\t')), ['Key=Some value', 'Other=x']);
    });

    test('reads a line without a colon as a key with an empty value', () {
      expect(shape(BulkEditText.parse('Accept')), ['Accept=']);
    });

    test('reads a leading // as a disabled row, with or without spaces after it', () {
      expect(shape(BulkEditText.parse('//a:1\n// b : 2\n   //c:3\nd:4')), ['//a=1', '//b=2', '//c=3', 'd=4']);
    });

    test('does not mistake a // inside a value for the disabled marker', () {
      expect(shape(BulkEditText.parse('Location:https://a.test/x')), ['Location=https://a.test/x']);
    });

    test('ignores blank lines, whitespace-only lines and a lone // or colon', () {
      expect(shape(BulkEditText.parse('\n\n  \t \na:1\n\n//\n:\n   :   \nb:2\n')), ['a=1', 'b=2']);
    });

    test('keeps a value-only line whose key is empty', () {
      expect(shape(BulkEditText.parse(':orphan')), ['=orphan']);
    });

    test('reads CRLF and lone CR line endings', () {
      expect(shape(BulkEditText.parse('a:1\r\nb:2\rc:3')), ['a=1', 'b=2', 'c=3']);
    });

    test('is empty for empty text', () {
      expect(BulkEditText.parse(''), isEmpty);
      expect(BulkEditText.parse('  \n \n'), isEmpty);
    });
  });

  group('BulkEditText.parse identity', () {
    test('keeps the id of the row at the same position and key when only the value changes', () {
      final previous = [row('a', '1'), row('b', '2')];
      final parsed = BulkEditText.parse('a:1\nb:changed', previous: previous);
      expect([for (final i in parsed) i.id], [previous[0].id, previous[1].id]);
      expect(shape(parsed), ['a=1', 'b=changed']);
    });

    test('keeps the id when a row is switched off or on', () {
      final previous = [row('a', '1'), row('b', '2', enabled: false)];
      final parsed = BulkEditText.parse('//a:1\nb:2', previous: previous);
      expect([for (final i in parsed) i.id], [previous[0].id, previous[1].id]);
      expect(shape(parsed), ['//a=1', 'b=2']);
    });

    test('gives a row a fresh id when its key changes or it is new', () {
      final previous = [row('a', '1'), row('b', '2')];
      final parsed = BulkEditText.parse('a:1\nrenamed:2\nextra:3', previous: previous);
      expect(parsed[0].id, previous[0].id);
      expect(parsed[1].id, isNot(previous[1].id));
      expect(parsed[1].id, isNot(previous[0].id));
      expect({for (final i in parsed) i.id}.length, 3);
    });

    test('lines without previous rows all get distinct ids', () {
      final parsed = BulkEditText.parse('a:1\nb:2\nc:3');
      expect({for (final i in parsed) i.id}.length, 3);
    });

    test('aligns positions after skipping blank previous rows and blank lines', () {
      final previous = [row('', ''), row('a', '1'), row('', '', enabled: false), row('b', '2')];
      final parsed = BulkEditText.parse('a:1\n\nb:changed', previous: previous);
      expect([for (final i in parsed) i.id], [previous[1].id, previous[3].id]);
    });

    test('never hands the same id to two rows, even for duplicated lines', () {
      final previous = [row('a', '1')];
      final parsed = BulkEditText.parse('a:1\na:1\na:2', previous: previous);
      expect(parsed.length, 3);
      expect({for (final i in parsed) i.id}.length, 3);
      expect(parsed[0], same(previous[0]));
    });

    test('a line that is exactly what a row writes out is that very row, wherever it moved', () {
      final previous = [row('a', '1'), row('b', '2'), row('c', '3')];
      final parsed = BulkEditText.parse('c:3\na:1\nnew:9\nb:2', previous: previous);
      expect(parsed[0], same(previous[2]));
      expect(parsed[1], same(previous[0]));
      expect(parsed[3], same(previous[1]));
      expect(shape(parsed), ['c=3', 'a=1', 'new=9', 'b=2']);
    });

    test('keeps rows the format cannot spell losslessly while their line is untouched', () {
      final previous = [
        row('ns:key', 'v'),
        row('padded', '  spaced  '),
        row('multi', 'line1\nline2'),
        row('plain', '1'),
      ];
      final text = BulkEditText.serialize(previous);
      final parsed = BulkEditText.parse('inserted:0\n$text', previous: previous);
      expect(parsed[1], same(previous[0]));
      expect(parsed[2], same(previous[1]));
      expect(parsed[3], same(previous[2]));
      expect(parsed[4], same(previous[3]));
      expect(parsed[1].key, 'ns:key');
      expect(parsed[2].value, '  spaced  ');
      expect(parsed[3].value, 'line1\nline2');
    });

    test('rebuilds only the lines that were edited', () {
      final previous = [row('ns:key', 'v'), row('plain', '1')];
      final parsed = BulkEditText.parse('ns:key:v\nplain:2', previous: previous);
      expect(parsed[0], same(previous[0]));
      expect(shape(parsed), ['ns:key=v', 'plain=2']);
      expect(parsed[1].id, previous[1].id);
    });

    test('a round trip through the text changes nothing, blank rows aside', () {
      final rows = [
        row('a', '1'),
        row('', ''),
        row('b', 'x:y', enabled: false),
        row('ns:key', ' padded '),
        row('multi', 'a\nb'),
        row('', 'value only'),
        row('key only', ''),
      ];
      final parsed = BulkEditText.parse(BulkEditText.serialize(rows), previous: rows);
      final expected = [for (final r in rows) if (r.key.isNotEmpty || r.value.isNotEmpty) r];
      expect(parsed.length, expected.length);
      for (var i = 0; i < parsed.length; i++) {
        expect(parsed[i], same(expected[i]));
      }
    });

    test('a round trip of ordinary rows survives without previous rows', () {
      final rows = [row('Accept', 'application/json'), row('X-Off', '1', enabled: false), row('q', 'a:b')];
      expect(shape(BulkEditText.parse(BulkEditText.serialize(rows))), shape(rows));
    });
  });

  group('BulkEditText.sameRows', () {
    final a = row('a', '1');

    test('is true for the same rows and false for any difference', () {
      expect(BulkEditText.sameRows([a], [a]), isTrue);
      expect(BulkEditText.sameRows(const [], const []), isTrue);
      expect(BulkEditText.sameRows([a], [a.copyWith(value: '2')]), isFalse);
      expect(BulkEditText.sameRows([a], [a.copyWith(key: 'b')]), isFalse);
      expect(BulkEditText.sameRows([a], [a.copyWith(enabled: false)]), isFalse);
      expect(BulkEditText.sameRows([a], [row('a', '1')]), isFalse, reason: 'different id');
      expect(BulkEditText.sameRows([a], [a, a]), isFalse);
    });
  });

  group('KeyValueEditor', () {
    late List<KeyValueItem> items;
    late List<List<KeyValueItem>> emitted;

    Future<void> pumpEditor(WidgetTester tester, List<KeyValueItem> initial) async {
      items = initial;
      emitted = [];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: KeyValueEditor(
                  items: items,
                  onChanged: (next) => setState(() {
                    items = next;
                    emitted.add(next);
                  }),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Finder bulkField() => find.byType(TextField);
    String bulkText(WidgetTester tester) => tester.widget<TextField>(bulkField()).controller!.text;

    Future<void> toBulk(WidgetTester tester) async {
      await tester.tap(find.text('Bulk edit'));
      await tester.pump();
    }

    Future<void> toRows(WidgetTester tester) async {
      await tester.tap(find.text('Key-Value edit'));
      await tester.pump();
    }

    testWidgets('shows the rows as text, with disabled rows behind //', (tester) async {
      await pumpEditor(tester, [row('a', '1'), row('b', '2', enabled: false)]);
      expect(find.byType(Checkbox), findsNWidgets(2));

      await toBulk(tester);

      expect(find.byType(Checkbox), findsNothing);
      expect(bulkText(tester), 'a:1\n//b:2');
      expect(find.text('Key-Value edit'), findsOneWidget);
      expect(emitted, isEmpty, reason: 'switching mode alone changes nothing');
    });

    testWidgets('hands every edit to onChanged at once and keeps row identities', (tester) async {
      final start = [row('a', '1'), row('b', '2')];
      await pumpEditor(tester, start);
      await toBulk(tester);

      await tester.enterText(bulkField(), 'a:1\n//b:changed\nc:3');

      expect(shape(items), ['a=1', '//b=changed', 'c=3']);
      expect(items[0].id, start[0].id);
      expect(items[1].id, start[1].id);
      expect(bulkText(tester), 'a:1\n//b:changed\nc:3', reason: "the parent's echo must not touch the text");
    });

    testWidgets('does not emit for edits that change no row', (tester) async {
      await pumpEditor(tester, [row('a', '1')]);
      await toBulk(tester);

      await tester.enterText(bulkField(), 'a:1\n\n   \n');
      await tester.enterText(bulkField(), '  a : 1  ');

      expect(emitted, isEmpty);
    });

    testWidgets('returns to rows built from what was typed', (tester) async {
      await pumpEditor(tester, [row('a', '1')]);
      await toBulk(tester);
      await tester.enterText(bulkField(), 'a:1\n//b:2\nc:3');

      await toRows(tester);

      expect(find.byType(Checkbox), findsNWidgets(3));
      expect([for (final c in tester.widgetList<Checkbox>(find.byType(Checkbox))) c.value], [true, false, true]);
      expect(find.widgetWithText(TextFormField, 'b'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'c'), findsOneWidget);
    });

    testWidgets('leaves an untouched row with a colon in its key exactly as it was through a round trip', (tester) async {
      final start = [row('ns:key', 'v'), row('plain', '1')];
      await pumpEditor(tester, start);

      await toBulk(tester);
      await tester.enterText(bulkField(), 'inserted:0\n${bulkText(tester)}');
      await toRows(tester);

      expect(shape(items), ['inserted=0', 'ns:key=v', 'plain=1']);
      expect(items[1], same(start[0]));
      expect(find.widgetWithText(TextFormField, 'ns:key'), findsOneWidget);
    });

    testWidgets('keeps a typed-in-bulk change when the editor is rebuilt away and back', (tester) async {
      await pumpEditor(tester, [row('a', '1')]);
      await toBulk(tester);
      await tester.enterText(bulkField(), 'a:1\nb:2');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: KeyValueEditor(items: items, onChanged: (_) {})),
        ),
      );

      expect(find.widgetWithText(TextFormField, 'b'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
    });

    testWidgets('lays out without overflowing in a narrow column, in both modes', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpEditor(tester, [row('Authorization', 'Bearer ' * 12)]);
      await toBulk(tester);
      expect(tester.takeException(), isNull);
      await toRows(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('row mode still applies a fast key edit and value edit to the same row', (tester) async {
      await pumpEditor(tester, [row('', '')]);
      final editables = find.byType(EditableText);
      final key = tester.state<EditableTextState>(editables.at(0));
      final value = tester.state<EditableTextState>(editables.at(1));

      // Both land before the parent has rebuilt, as a fast typist's would.
      key.userUpdateTextEditingValue(const TextEditingValue(text: 'Accept'), SelectionChangedCause.keyboard);
      value.userUpdateTextEditingValue(const TextEditingValue(text: 'text/html'), SelectionChangedCause.keyboard);
      await tester.pump();

      expect(shape(items), ['Accept=text/html']);
    });

    testWidgets('row mode keeps adding, editing and removing rows', (tester) async {
      await pumpEditor(tester, [row('a', '1'), row('b', '2')]);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(items.length, 3);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pump();
      expect(shape(items), ['b=2', '=']);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(shape(items), ['//b=2', '=']);
    });
  });
}
