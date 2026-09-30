import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';

/// The real app theme, which the documentation widgets read their colours and
/// text styles from.
Widget themedApp(Widget child, {bool dark = false}) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: child),
    );

/// A window big enough for the fixed-size dialogs.
void useLargeWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The plain text of the [RichText] that shows exactly [text].
RichText richTextOf(WidgetTester tester, String text) =>
    tester.widget<RichText>(find.text(text, findRichText: true));

/// Every [TextSpan] under [root], including [root].
Iterable<TextSpan> allSpans(InlineSpan root) sync* {
  if (root is TextSpan) {
    yield root;
    for (final child in root.children ?? const <InlineSpan>[]) {
      yield* allSpans(child);
    }
  }
}
