import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import 'response_body_formatter.dart';

// Context kept around the current match when it is scrolled into view.
const _revealMargin = 48.0;

class ResponseBodyView extends StatefulWidget {
  final ResponseBodyFormatter formatter;
  final ResponseBodyMode mode;
  final String query;
  final List<int> matchIndices;

  /// Index into [matchIndices] of the match to emphasise and keep in view.
  final int currentMatch;

  const ResponseBodyView({
    super.key,
    required this.formatter,
    required this.mode,
    required this.query,
    required this.matchIndices,
    this.currentMatch = 0,
  });

  @override
  State<ResponseBodyView> createState() => _ResponseBodyViewState();
}

class _ResponseBodyViewState extends State<ResponseBodyView> {
  @override
  void didUpdateWidget(covariant ResponseBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final matches = widget.matchIndices;
    final moved = widget.currentMatch != oldWidget.currentMatch || !identical(matches, oldWidget.matchIndices);
    if (matches.isNotEmpty && moved) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrentMatch());
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = widget.formatter;
    if (formatter.kind == ResponseContentKind.image) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.topLeft,
          child: Image.memory(
            formatter.bytes,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => Text("Couldn't decode image", style: context.textStyles.mono),
          ),
        ),
      );
    }
    final accent = context.colors.mainAccent;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectableText.rich(
        TextSpan(
          style: context.textStyles.mono,
          children: _spans(
            formatter.displayTextFor(widget.mode),
            TextStyle(backgroundColor: accent.withValues(alpha: 0.35)),
            TextStyle(backgroundColor: accent.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(String text, TextStyle highlight, TextStyle current) {
    final matches = widget.matchIndices;
    if (matches.isEmpty) return [TextSpan(text: text)];
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i];
      final end = start + widget.query.length;
      if (start > cursor) spans.add(TextSpan(text: text.substring(cursor, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: i == widget.currentMatch ? current : highlight));
      cursor = end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }

  // The text is one paragraph inside a scroll view, so the current match is
  // scrolled to via the paragraph's own render object, which knows where each
  // character actually landed.
  void _revealCurrentMatch() {
    if (!mounted) return;
    final matches = widget.matchIndices;
    if (matches.isEmpty) return;
    final editable = _findEditable(context.findRenderObject());
    if (editable == null || !editable.attached || !editable.hasSize) return;
    final start = matches[widget.currentMatch.clamp(0, matches.length - 1)];
    final caret = editable.getLocalRectForCaret(TextPosition(offset: start));
    editable.showOnScreen(
      rect: caret.inflate(_revealMargin),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  RenderEditable? _findEditable(RenderObject? root) {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    if (root != null) visit(root);
    return found;
  }
}
