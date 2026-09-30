import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/presentation/widgets/simple_markdown.dart';

import 'support/pump_app.dart';

const _document = '''
# Title

Some **bold** and *italic* text with `code` and a [link](https://x.dev/docs).

> A quoted line

- first
- second
  - nested

1. one
2. two

```json
{"a": 1}
```

| Name | Age |
| :--- | ---: |
| Ann | 30 |

---

Last paragraph
''';

void main() {
  late List<MethodCall> launches;
  late bool launchResult;

  setUp(() {
    launches = [];
    launchResult = true;
  });

  void mockLauncher(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launches.add(call);
        return launchResult;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      ),
    );
  }

  group('rendering', () {
    testWidgets('shows every kind of block', (tester) async {
      await tester.pumpWidget(themedApp(const SingleChildScrollView(child: SimpleMarkdown(data: _document))));

      expect(find.text('Title', findRichText: true), findsOneWidget);
      expect(find.text('Some bold and italic text with code and a link.', findRichText: true), findsOneWidget);
      expect(find.text('A quoted line', findRichText: true), findsOneWidget);
      expect(find.text('first', findRichText: true), findsOneWidget);
      expect(find.text('nested', findRichText: true), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('◦'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('{"a": 1}'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Ann', findRichText: true), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Last paragraph', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('styles bold, italic, code and links', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: 'a **b** *i* `c` [l](https://x.dev)')));

      final spans = allSpans(richTextOf(tester, 'a b i c l').text).toList();
      TextSpan styled(String text) => spans.firstWhere((s) => s.toPlainText() == text && s.style != null);

      expect(styled('b').style?.fontWeight, FontWeight.w700);
      expect(styled('i').style?.fontStyle, FontStyle.italic);
      expect(styled('c').style?.fontFamily, 'monospace');
      expect(styled('c').style?.backgroundColor, isNotNull);
      expect(styled('l').style?.decoration, TextDecoration.underline);
      expect(spans.firstWhere((s) => s.text == 'l').recognizer, isA<TapGestureRecognizer>());
      expect(spans.firstWhere((s) => s.text == 'a ').recognizer, isNull);
    });

    testWidgets('headings shrink with their level', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '# One\n\n## Two\n\n### Three\n\n###### Six\n\ntext')));

      // The first span is the one Text wraps around ours.
      double sizeOf(String text) => allSpans(richTextOf(tester, text).text).elementAt(1).style!.fontSize!;
      expect(sizeOf('One'), greaterThan(sizeOf('Two')));
      expect(sizeOf('Two'), greaterThan(sizeOf('Three')));
      expect(sizeOf('Three'), greaterThan(sizeOf('Six')));
      expect(sizeOf('Six'), lessThanOrEqualTo(sizeOf('text')));
    });

    testWidgets('an ordered list starts at its own number', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '7. seven\n8. eight')));

      expect(find.text('7.'), findsOneWidget);
      expect(find.text('8.'), findsOneWidget);
    });

    testWidgets('renders in the dark theme too', (tester) async {
      await tester.pumpWidget(themedApp(const SingleChildScrollView(child: SimpleMarkdown(data: _document)), dark: true));

      expect(tester.takeException(), isNull);
      expect(find.text('Title', findRichText: true), findsOneWidget);
    });

    testWidgets('empty text renders nothing and does not fail', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '')));

      expect(tester.takeException(), isNull);
      expect(find.byType(RichText), findsNothing);
    });

    testWidgets('changed text is parsed again', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: 'first')));
      expect(find.text('first', findRichText: true), findsOneWidget);

      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '# second')));
      expect(find.text('first', findRichText: true), findsNothing);
      expect(find.text('second', findRichText: true), findsOneWidget);
    });

    testWidgets('a table wider than the space wraps instead of overflowing', (tester) async {
      final longCell = List.filled(30, 'wordy').join(' ');
      await tester.pumpWidget(themedApp(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: SimpleMarkdown(data: '| Key | Value |\n|---|---|\n| header | $longCell |'),
        ),
      )));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Table)).width, lessThanOrEqualTo(300));
    });

    testWidgets('a long code line scrolls sideways instead of overflowing', (tester) async {
      await tester.pumpWidget(themedApp(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: SimpleMarkdown(data: '```\n${'x' * 400}\n```')),
      )));

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('a deep mix of nested lists and quotes lays out', (tester) async {
      final nested = List.generate(8, (i) => '${'  ' * i}- level $i').join('\n');
      await tester.pumpWidget(themedApp(SingleChildScrollView(child: SimpleMarkdown(data: '> > > deep quote\n\n$nested'))));

      expect(tester.takeException(), isNull);
      expect(find.text('level 7', findRichText: true), findsOneWidget);
    });
  });

  group('selection', () {
    testWidgets('text is selectable by default and can be switched off', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: 'text')));
      expect(find.byType(SelectionArea), findsOneWidget);

      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: 'text', selectable: false)));
      expect(find.byType(SelectionArea), findsNothing);
    });
  });

  group('scrollable', () {
    testWidgets('builds long documents lazily', (tester) async {
      final data = List.generate(400, (i) => 'Paragraph $i').join('\n\n');
      await tester.pumpWidget(themedApp(SizedBox(height: 400, child: SimpleMarkdown(data: data, scrollable: true))));

      expect(find.text('Paragraph 0', findRichText: true), findsOneWidget);
      expect(find.text('Paragraph 399', findRichText: true), findsNothing);
      expect(find.byType(RichText).evaluate().length, lessThan(60));

      await tester.drag(find.byType(ListView), const Offset(0, -1000000));
      await tester.pump();
      expect(find.text('Paragraph 399', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('links', () {
    testWidgets('a web link is handed to the browser', (tester) async {
      mockLauncher(tester);
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '[docs](https://x.dev/docs?a=1)')));

      await tester.tap(find.text('docs', findRichText: true));
      await tester.pump();

      expect(launches, hasLength(1));
      expect(launches.single.method, 'launch');
      expect((launches.single.arguments as Map)['url'], 'https://x.dev/docs?a=1');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a mail link is allowed', (tester) async {
      mockLauncher(tester);
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '<mailto:team@x.dev>')));

      await tester.tap(find.text('mailto:team@x.dev', findRichText: true));
      await tester.pump();

      expect((launches.single.arguments as Map)['url'], 'mailto:team@x.dev');
    });

    testWidgets('says so when the link could not be opened', (tester) async {
      mockLauncher(tester);
      launchResult = false;
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '[docs](https://x.dev)')));

      await tester.tap(find.text('docs', findRichText: true));
      await tester.pump();

      expect(find.text('Could not open the link'), findsOneWidget);
    });

    testWidgets('links that are not web or mail links are never launched', (tester) async {
      mockLauncher(tester);
      for (final url in ['javascript:alert(1)', 'file:///etc/passwd', 'data:text/html,x', '#top', '/relative']) {
        await tester.pumpWidget(themedApp(SimpleMarkdown(data: '[go]($url)')));
        await tester.tap(find.text('go', findRichText: true));
        await tester.pump();
        expect(find.text('Could not open the link'), findsOneWidget, reason: url);
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
        await tester.pump();
      }

      expect(launches, isEmpty);
    });

    testWidgets('a platform that cannot launch anything does not crash the page', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '[docs](https://x.dev)')));

      await tester.tap(find.text('docs', findRichText: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Could not open the link'), findsOneWidget);
    });

    testWidgets('gesture recognizers are disposed with the text', (tester) async {
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '[a](https://x.dev) [b](https://y.dev)')));
      await tester.pumpWidget(themedApp(const SimpleMarkdown(data: '[a](https://x.dev) [c](https://z.dev)')));
      await tester.pumpWidget(themedApp(const SizedBox()));

      expect(tester.takeException(), isNull);
    });
  });
}
