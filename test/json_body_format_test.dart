import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/body_editor.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/json_body_format.dart';

String beautify(String source) => JsonBodyFormat.beautify(source).text!;
String minify(String source) => JsonBodyFormat.minify(source).text!;

void main() {
  group('JsonBodyFormat.beautify', () {
    test('indents objects and arrays by two spaces with one member per line', () {
      expect(beautify('{"a":1,"b":[1,2,{"c":null}],"d":{}}'), '''
{
  "a": 1,
  "b": [
    1,
    2,
    {
      "c": null
    }
  ],
  "d": {}
}''');
    });

    test('writes empty containers as {} and [] whatever whitespace they held', () {
      expect(beautify('{ \n }'), '{}');
      expect(beautify('[ \t\n]'), '[]');
      expect(beautify('{"a":[ ],"b":{ }}'), '{\n  "a": [],\n  "b": {}\n}');
    });

    test('accepts any JSON value at the top level and trims the space around it', () {
      expect(beautify('  "text"  '), '"text"');
      expect(beautify('\n-0.5e+10\n'), '-0.5e+10');
      expect(beautify('true'), 'true');
      expect(beautify('null'), 'null');
    });

    test('leaves numbers exactly as written instead of round-tripping them through a double', () {
      expect(beautify('[1.0, 1E+2, 12345678901234567890, -0, 0.10, 1e-7]'), '[\n  1.0,\n  1E+2,\n  12345678901234567890,\n  -0,\n  0.10,\n  1e-7\n]');
    });

    test('leaves strings and their escapes exactly as written', () {
      const literal = '"caf\\u00e9 \\n \\/ \\" \\\\ \\ud83d\\ude00 tab\\t \u{e9} \u{1F600}"';
      expect(beautify('[$literal]'), '[\n  $literal\n]');
    });

    test('keeps key order and duplicate keys', () {
      expect(beautify('{"b":1,"a":2,"b":3}'), '{\n  "b": 1,\n  "a": 2,\n  "b": 3\n}');
    });

    test('reads input with CRLF, tabs and a byte order mark', () {
      expect(beautify('\u{feff}{\r\n\t"a" :\t1 ,\r\n"b":[\r\n2]\r\n}'), '{\n  "a": 1,\n  "b": [\n    2\n  ]\n}');
    });

    test('is idempotent', () {
      const docs = ['{"a":[1,{"b":[]}],"c":"x"}', '[[[]],{}]', '"s"', '{"a":{"b":{"c":{}}}}'];
      for (final doc in docs) {
        expect(beautify(beautify(doc)), beautify(doc), reason: doc);
      }
    });

    test('stops indenting past depth 64 so nesting cannot balloon the output', () {
      final deep = '${'[' * 100}${']' * 100}';
      final lines = beautify(deep).split('\n');
      expect(lines.map((l) => l.length - l.trimLeft().length).reduce((a, b) => a > b ? a : b), 128);
    });

    test('survives nesting far deeper than any call stack', () {
      const depth = 20000;
      final result = JsonBodyFormat.beautify('${'[' * depth}${']' * depth}');
      expect(result.text, isNotNull);
      expect(result.text!.split('\n').length, depth * 2 - 1, reason: 'one line per bracket, the innermost pair sharing one');
    });
  });

  group('JsonBodyFormat.minify', () {
    test('drops the whitespace between tokens and keeps it inside strings', () {
      expect(minify('{\n  "a b" : [ 1 , 2 ],\n  "c": { "d": "x  y" }\n}'), '{"a b":[1,2],"c":{"d":"x  y"}}');
    });

    test('keeps numbers, escapes and duplicate keys as written', () {
      expect(minify('{ "a": 1.0, "a": 1E5, "s": "\\u00e9\\n" }'), '{"a":1.0,"a":1E5,"s":"\\u00e9\\n"}');
    });

    test('agrees with beautify in both directions', () {
      const docs = ['{"a":[1,{"b":[]}],"c":"x y"}', '[[[]],{}]', '"s"', '{"x":{{id}},"y":[{{a}},{{b}}]}'];
      for (final doc in docs) {
        expect(minify(beautify(doc)), minify(doc), reason: doc);
        expect(beautify(minify(doc)), beautify(doc), reason: doc);
      }
    });

    test('survives extreme nesting', () {
      const depth = 200000;
      final deep = '${'[' * depth}${']' * depth}';
      expect(minify(deep), deep);
    });
  });

  group('JsonBodyFormat with {{variable}} placeholders', () {
    test('accepts a placeholder wherever a value may stand and leaves it as written', () {
      expect(
        beautify(r'{"id": {{userId}}, "tags": [{{a}}, {{b.c}}, {{$guid}}, {{x-y}}], "s": "{{x}}"}'),
        '{\n  "id": {{userId}},\n  "tags": [\n    {{a}},\n    {{b.c}},\n    {{\$guid}},\n    {{x-y}}\n  ],\n  "s": "{{x}}"\n}',
      );
    });

    test('accepts a body that is nothing but a placeholder', () {
      expect(beautify(' {{payload}} '), '{{payload}}');
      expect(minify('{{payload}}'), '{{payload}}');
    });

    test('still rejects a malformed placeholder', () {
      for (final bad in ['{{x}', '{{ x }}', '{{}}', '[{{x]', '{"a": {{x y}}}']) {
        expect(JsonBodyFormat.beautify(bad).error, isNotNull, reason: bad);
      }
    });
  });

  group('JsonBodyFormat errors', () {
    void expectError(String source, String message) {
      final result = JsonBodyFormat.beautify(source);
      expect(result.text, isNull, reason: source);
      expect(result.error, message, reason: source);
      expect(JsonBodyFormat.minify(source).error, message, reason: 'minify: $source');
    }

    test('says an empty body has nothing to format', () {
      expectError('', 'Nothing to format: the body is empty');
      expectError('  \n\t ', 'Nothing to format: the body is empty');
    });

    test('points at the line and column where the JSON breaks', () {
      expectError('{"a":1', 'Invalid JSON: Unexpected end of JSON (line 1, column 7)');
      expectError('{"a":}', "Invalid JSON: Expected a value, found '}' (line 1, column 6)");
      expectError('{a:1}', "Invalid JSON: Expected a property name in double quotes, found 'a' (line 1, column 2)");
      expectError('{"a" 1}', "Invalid JSON: Expected ':' after the property name, found '1' (line 1, column 6)");
      expectError('{"a":1,}', "Invalid JSON: Trailing comma before '}' (line 1, column 8)");
      expectError('[1,]', "Invalid JSON: Trailing comma before ']' (line 1, column 4)");
      expectError('[1 2]', "Invalid JSON: Expected ',' or ']', found '2' (line 1, column 4)");
      expectError('{"a":1 "b":2}', "Invalid JSON: Expected ',' or '}', found '\"' (line 1, column 8)");
      expectError('{"a":1} x', "Invalid JSON: Unexpected 'x' after the end of the JSON value (line 1, column 9)");
    });

    test('counts lines across LF, CRLF and CR line breaks', () {
      const message = "Invalid JSON: Expected a value, found '}' (line 4, column 1)";
      expectError('{\n  "a": 1,\n  "b":\n}', message);
      expectError('{\r\n  "a": 1,\r\n  "b":\r\n}', message);
      expectError('{\r  "a": 1,\r  "b":\r}', message);
    });

    test('rejects malformed numbers', () {
      expectError('[01]', 'Invalid JSON: Numbers cannot have leading zeros (line 1, column 2)');
      expectError('[1.]', 'Invalid JSON: Invalid number (line 1, column 2)');
      expectError('[-]', 'Invalid JSON: Invalid number (line 1, column 2)');
      expectError('[1e]', 'Invalid JSON: Invalid number (line 1, column 2)');
      expectError('[.5]', "Invalid JSON: Expected a value, found '.' (line 1, column 2)");
      expectError('[+1]', "Invalid JSON: Expected a value, found '+' (line 1, column 2)");
      expectError('[NaN]', "Invalid JSON: Expected a value, found 'N' (line 1, column 2)");
    });

    test('rejects malformed strings', () {
      expectError('["a', 'Invalid JSON: Unterminated string (line 1, column 2)');
      expectError('["a\nb"]', 'Invalid JSON: Unescaped control character in a string (line 1, column 4)');
      expectError('["\\x"]', 'Invalid JSON: Invalid escape sequence in a string (line 1, column 3)');
      expectError('["\\u12"]', 'Invalid JSON: Invalid \\u escape in a string (line 1, column 3)');
      expectError("{'a':1}", "Invalid JSON: Expected a property name in double quotes, found ''' (line 1, column 2)");
    });

    test('rejects wrongly cased literals, comments and stray whitespace characters', () {
      expectError('[True]', "Invalid JSON: Expected a value, found 'T' (line 1, column 2)");
      expectError('[nul]', "Invalid JSON: Expected a value, found 'n' (line 1, column 2)");
      expectError('// note\n{}', "Invalid JSON: Expected a value, found '/' (line 1, column 1)");
      expectError('{"a":\u{a0}1}', 'Invalid JSON: Expected a value, found U+00A0 (line 1, column 6)');
    });

    test('names an unclosed placeholder', () {
      expectError('{"a": {{x}', 'Invalid JSON: Invalid {{variable}} placeholder (line 1, column 7)');
    });
  });

  group('BodyEditor Beautify / Minify', () {
    late RequestBody body;
    late List<RequestBody> emitted;

    Future<void> pumpEditor(WidgetTester tester, RequestBody initial) async {
      body = initial;
      emitted = [];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: StatefulBuilder(
                builder: (context, setState) => BodyEditor(
                  body: body,
                  onChanged: (next) => setState(() {
                    body = next;
                    emitted.add(next);
                  }),
                ),
              ),
            ),
          ),
        ),
      );
    }

    TextEditingController rawController(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!;

    const raw = RequestBody(type: BodyType.raw);

    testWidgets('offers the buttons for a raw JSON body only', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawContentType: RawContentType.json));
      expect(find.text('Beautify'), findsOneWidget);
      expect(find.text('Minify'), findsOneWidget);

      await pumpEditor(tester, raw.copyWith(rawContentType: RawContentType.xml));
      expect(find.text('Beautify'), findsNothing);
      expect(find.text('Minify'), findsNothing);

      await pumpEditor(tester, const RequestBody(type: BodyType.urlEncoded));
      expect(find.text('Beautify'), findsNothing);

      await pumpEditor(tester, const RequestBody(type: BodyType.graphql));
      expect(find.text('Beautify'), findsNothing);
    });

    testWidgets('Beautify replaces the text, reports it and puts the cursor at the end', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"a":1,"b":[1,2]}'));

      await tester.tap(find.text('Beautify'));
      await tester.pump();

      const pretty = '{\n  "a": 1,\n  "b": [\n    1,\n    2\n  ]\n}';
      expect(rawController(tester).text, pretty);
      expect(body.rawText, pretty);
      expect(emitted.length, 1);
      expect(rawController(tester).selection, const TextSelection.collapsed(offset: pretty.length));
    });

    testWidgets('Minify squeezes the text and reports it', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{\n  "a": 1,\n  "b": [ 1, 2 ]\n}'));

      await tester.tap(find.text('Minify'));
      await tester.pump();

      expect(rawController(tester).text, '{"a":1,"b":[1,2]}');
      expect(body.rawText, '{"a":1,"b":[1,2]}');
      expect(rawController(tester).selection, const TextSelection.collapsed(offset: 17));
    });

    testWidgets('handles {{variable}} placeholders', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"id":{{userId}},"n":"{{name}}"}'));

      await tester.tap(find.text('Beautify'));
      await tester.pump();

      expect(body.rawText, '{\n  "id": {{userId}},\n  "n": "{{name}}"\n}');
    });

    testWidgets('an invalid body gets an inline hint and is left untouched', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"a":'));

      await tester.tap(find.text('Beautify'));
      await tester.pump();

      expect(find.text('Invalid JSON: Unexpected end of JSON (line 1, column 6)'), findsOneWidget);
      expect(rawController(tester).text, '{"a":');
      expect(emitted, isEmpty);
    });

    testWidgets('the hint goes away as soon as the text is edited', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"a":'));
      await tester.tap(find.text('Minify'));
      await tester.pump();
      expect(find.textContaining('Invalid JSON'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '{"a":1}');
      await tester.pump();

      expect(find.textContaining('Invalid JSON'), findsNothing);
      expect(body.rawText, '{"a":1}');
    });

    testWidgets('an empty body says there is nothing to format', (tester) async {
      await pumpEditor(tester, raw);
      await tester.tap(find.text('Beautify'));
      await tester.pump();
      expect(find.text('Nothing to format: the body is empty'), findsOneWidget);
    });

    testWidgets('reformatting text that is already formatted changes and reports nothing', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"a":1}'));
      await tester.tap(find.text('Minify'));
      await tester.pump();
      expect(emitted, isEmpty);
    });

    testWidgets('typing reports the text and the cursor stays where the user put it', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: 'abc'));
      final editable = tester.state<EditableTextState>(find.byType(EditableText));

      editable.userUpdateTextEditingValue(
        const TextEditingValue(text: 'aXbc', selection: TextSelection.collapsed(offset: 2)),
        SelectionChangedCause.keyboard,
      );
      await tester.pump();

      expect(body.rawText, 'aXbc');
      expect(rawController(tester).selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('shows a body text that was changed from outside the field', (tester) async {
      late StateSetter rebuild;
      body = raw.copyWith(rawText: 'first');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return BodyEditor(body: body, onChanged: (next) => body = next);
              },
            ),
          ),
        ),
      );
      expect(rawController(tester).text, 'first');

      rebuild(() => body = body.copyWith(rawText: 'second'));
      await tester.pump();

      expect(rawController(tester).text, 'second');
    });

    testWidgets('keeps the raw text when switching to another body type and back', (tester) async {
      await pumpEditor(tester, raw.copyWith(rawText: '{"keep":true}'));

      await tester.tap(find.byType(DropdownButton<BodyType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GraphQL').last);
      await tester.pumpAndSettle();
      expect(body.type, BodyType.graphql);

      await tester.tap(find.byType(DropdownButton<BodyType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Raw').last);
      await tester.pumpAndSettle();

      expect(body.type, BodyType.raw);
      expect(rawController(tester).text, '{"keep":true}');
    });

    testWidgets('form fields still use the key/value editor', (tester) async {
      await pumpEditor(tester, RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'a', value: '1')]));
      expect(find.text('Bulk edit'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'a'), findsOneWidget);
    });

    testWidgets('switching from form data to url-encoded leaves bulk mode instead of carrying its text over', (tester) async {
      final formFields = [KeyValueItem(key: 'a', value: '1')];
      await pumpEditor(
        tester,
        RequestBody(type: BodyType.formData, formFields: formFields, urlEncodedFields: [KeyValueItem(key: 'b', value: '2')]),
      );
      await tester.tap(find.text('Bulk edit'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'a:1');

      // No pumpAndSettle: the focused bulk field's blinking caret never lets it settle.
      await tester.tap(find.byType(DropdownButton<BodyType>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('x-www-form-urlencoded').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(body.type, BodyType.urlEncoded);
      expect(find.text('Bulk edit'), findsOneWidget, reason: 'the new list starts in row mode');
      expect(find.widgetWithText(TextFormField, 'b'), findsOneWidget);
      expect(body.formFields, same(formFields));
      expect(emitted.length, 1, reason: 'only the type change was reported');
    });

    testWidgets('wraps its controls instead of overflowing when the window is narrow', (tester) async {
      // The test font (Ahem) makes text roughly twice as wide as a real one, so 420px
      // here is as tight as a phone: the four controls need about 850px in a row.
      tester.view.physicalSize = const Size(420, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpEditor(tester, raw.copyWith(rawContentType: RawContentType.json, rawText: '{"a":'));
      await tester.tap(find.text('Beautify'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Beautify'), findsOneWidget);
      expect(find.text('Minify'), findsOneWidget);
    });
  });
}
