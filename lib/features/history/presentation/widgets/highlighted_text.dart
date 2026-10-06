import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/presentation/widgets/response_body_formatter.dart' show findMatches;

/// [text] cut into spans with every case-insensitive occurrence of [query]
/// marked; one plain span when there is nothing to mark. [style] goes on the
/// spans that are not marked.
List<TextSpan> highlightedSpans(BuildContext context, String text, String query, {TextStyle? style}) {
  final matches = query.isEmpty ? const <int>[] : findMatches(text, query);
  if (matches.isEmpty) return [TextSpan(text: text, style: style)];
  final mark = (style ?? const TextStyle()).copyWith(backgroundColor: context.colors.mainAccent.withValues(alpha: 0.35));
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final start in matches) {
    if (start > cursor) spans.add(TextSpan(text: text.substring(cursor, start), style: style));
    spans.add(TextSpan(text: text.substring(start, start + query.length), style: mark));
    cursor = start + query.length;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor), style: style));
  return spans;
}

/// [text] with the search marked, for the list of results.
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;

  const HighlightedText({super.key, required this.text, this.query = '', this.style, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(children: highlightedSpans(context, text, query, style: style)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
