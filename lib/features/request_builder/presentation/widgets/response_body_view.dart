import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import 'json_syntax.dart';
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
  // Tokenising is linear in the body size, so it is redone only when the shown
  // text changes, not on every search keystroke or rebuild.
  String? _tokenizedText;
  List<SyntaxRange> _tokens = const [];

  List<SyntaxRange> _syntaxFor(String text) {
    if (widget.formatter.kind != ResponseContentKind.json || text.length > maxHighlightedChars) return const [];
    if (!identical(text, _tokenizedText)) {
      _tokenizedText = text;
      _tokens = tokenizeJson(text);
    }
    return _tokens;
  }

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
    final colors = context.colors;
    final accent = colors.mainAccent;
    final text = formatter.displayTextFor(widget.mode);
    TextStyle syntaxStyle(SyntaxKind kind) => TextStyle(
      color: switch (kind) {
        SyntaxKind.key => colors.syntaxKey,
        SyntaxKind.string => colors.syntaxString,
        SyntaxKind.number => colors.syntaxNumber,
        SyntaxKind.keyword => colors.syntaxKeyword,
        SyntaxKind.punctuation => colors.secondaryText,
      },
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.topLeft,
        child: SelectableText.rich(
          TextSpan(
            style: context.textStyles.mono,
            children: buildBodySpans(
              text: text,
              syntax: _syntaxFor(text),
              syntaxStyle: syntaxStyle,
              matches: widget.matchIndices,
              queryLength: widget.query.length,
              currentMatch: widget.currentMatch,
              highlight: TextStyle(backgroundColor: accent.withValues(alpha: 0.35)),
              current: TextStyle(backgroundColor: accent.withValues(alpha: 0.85)),
            ),
          ),
        ),
      ),
    );
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
