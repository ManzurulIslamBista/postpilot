import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/json_syntax.dart';

void main() {
  group('tokenizeJson', () {
    test('classifies keys, strings, numbers, keywords and punctuation', () {
      const text = '{"a": "x", "n": -1.5e3, "t": true, "z": null}';
      String of(SyntaxRange r) => text.substring(r.start, r.end);
      final tokens = tokenizeJson(text);

      expect(tokens.where((t) => t.kind == SyntaxKind.key).map(of), ['"a"', '"n"', '"t"', '"z"']);
      expect(tokens.where((t) => t.kind == SyntaxKind.string).map(of), ['"x"']);
      expect(tokens.where((t) => t.kind == SyntaxKind.number).map(of), ['-1.5e3']);
      expect(tokens.where((t) => t.kind == SyntaxKind.keyword).map(of), ['true', 'null']);
    });

    test('a quote escaped inside a string does not end it', () {
      const text = r'{"k": "say \"hi\" now"}';
      final strings = tokenizeJson(text).where((t) => t.kind == SyntaxKind.string).toList();
      expect(strings, hasLength(1));
      expect(text.substring(strings.single.start, strings.single.end), r'"say \"hi\" now"');
    });

    test('never throws on cut-off or invalid input', () {
      expect(() => tokenizeJson('{"a": "unterminated'), returnsNormally);
      expect(() => tokenizeJson('not json at all \u{1F600}'), returnsNormally);
      expect(tokenizeJson(''), isEmpty);
    });
  });

  group('buildBodySpans', () {
    TextStyle style(SyntaxKind k) => TextStyle(color: Color(0xFF000000 + k.index));
    const highlight = TextStyle(backgroundColor: Color(0xFFAAAAAA));
    const current = TextStyle(backgroundColor: Color(0xFFFFFFFF));

    String joined(List<InlineSpan> spans) => spans.map((s) => (s as TextSpan).text).join();

    test('spans always reassemble the exact text, with syntax and matches overlapping', () {
      const text = '{\n  "name": "Ada",\n  "age": 36\n}';
      final spans = buildBodySpans(
        text: text,
        syntax: tokenizeJson(text),
        syntaxStyle: style,
        matches: [text.indexOf('Ada'), text.indexOf('36')],
        queryLength: 3,
        currentMatch: 0,
        highlight: highlight,
        current: current,
      );
      expect(joined(spans), text);
    });

    test('the current match gets the stronger style and keeps the token colour', () {
      const text = '"abc"';
      final spans = buildBodySpans(
        text: text,
        syntax: tokenizeJson(text),
        syntaxStyle: style,
        matches: [1],
        queryLength: 1,
        currentMatch: 0,
        highlight: highlight,
        current: current,
      );
      final hit = spans.cast<TextSpan>().singleWhere((s) => s.text == 'a');
      expect(hit.style!.backgroundColor, current.backgroundColor);
      expect(hit.style!.color, style(SyntaxKind.string).color);
    });

    test('no syntax and no matches is one plain span', () {
      final spans = buildBodySpans(
        text: 'plain',
        syntax: const [],
        syntaxStyle: style,
        matches: const [],
        queryLength: 0,
        currentMatch: 0,
        highlight: highlight,
        current: current,
      );
      expect(spans, hasLength(1));
      expect(joined(spans), 'plain');
    });
  });
}
