import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/markdown_node.dart';
import '../../domain/services/markdown_parser.dart';
import '../../domain/services/safe_link.dart';

/// Renders Markdown with the app theme. Text can be selected across blocks and
/// links open in the browser. With [scrollable] the blocks are built lazily in
/// a list of their own, which suits long documents.
class SimpleMarkdown extends StatefulWidget {
  final String data;
  final bool selectable;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  const SimpleMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<SimpleMarkdown> createState() => _SimpleMarkdownState();
}

class _SimpleMarkdownState extends State<SimpleMarkdown> {
  late List<MarkdownBlock> _blocks = MarkdownParser.parse(widget.data);

  @override
  void didUpdateWidget(covariant SimpleMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _blocks = MarkdownParser.parse(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.scrollable
        ? ListView.separated(
            padding: widget.padding,
            itemCount: _blocks.length,
            itemBuilder: (context, index) => _block(context, _blocks[index], 0),
            separatorBuilder: (_, _) => const SizedBox(height: _blockSpacing),
          )
        : Padding(
            padding: widget.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: _blockSpacing,
              children: [for (final block in _blocks) _block(context, block, 0)],
            ),
          );
    return widget.selectable ? SelectionArea(child: content) : content;
  }
}

const double _blockSpacing = 10;
const _bullets = ['•', '◦', '▪'];

Widget _block(BuildContext context, MarkdownBlock block, int depth) => switch (block) {
      MarkdownHeading(:final level, :final content) =>
        Semantics(header: true, child: _InlineText(content, style: _headingStyle(context, level))),
      MarkdownParagraph(:final content) => _InlineText(content, style: context.textStyles.body),
      MarkdownCodeBlock(:final code) => _CodeBlock(code),
      MarkdownQuote(:final children) => _quote(context, children, depth),
      final MarkdownList list => _list(context, list, depth),
      MarkdownRule() => const Divider(height: 24),
      final MarkdownTable table => _table(context, table),
    };

TextStyle _headingStyle(BuildContext context, int level) {
  final base = context.textStyles.heading;
  return switch (level) {
    1 => base.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
    2 => base.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
    3 => base.copyWith(fontSize: 18),
    4 => base.copyWith(fontSize: 16),
    _ => base.copyWith(fontSize: 14),
  };
}

Widget _quote(BuildContext context, List<MarkdownBlock> children, int depth) => Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: context.colors.border, width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [for (final child in children) _block(context, child, depth)],
      ),
    );

Widget _list(BuildContext context, MarkdownList list, int depth) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: list.ordered ? 32 : 20,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    list.ordered ? '${list.start + i}.' : _bullets[depth % _bullets.length],
                    textAlign: TextAlign.right,
                    style: context.textStyles.body,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [for (final block in list.items[i]) _block(context, block, depth + 1)],
                ),
              ),
            ],
          ),
      ],
    );

Widget _table(BuildContext context, MarkdownTable table) {
  Widget cell(List<MarkdownInline> content, int column, {bool header = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _InlineText(
          content,
          style: header ? context.textStyles.body.copyWith(fontWeight: FontWeight.w700) : context.textStyles.body,
          textAlign: switch (table.alignments[column]) {
            MarkdownColumnAlign.center => TextAlign.center,
            MarkdownColumnAlign.right => TextAlign.right,
            _ => TextAlign.left,
          },
        ),
      );

  return Table(
    defaultColumnWidth: const IntrinsicColumnWidth(),
    border: TableBorder.all(color: context.colors.border),
    children: [
      TableRow(
        decoration: BoxDecoration(color: context.colors.sidebarBackground),
        children: [for (var c = 0; c < table.header.length; c++) cell(table.header[c], c, header: true)],
      ),
      for (final row in table.rows)
        TableRow(children: [for (var c = 0; c < row.length; c++) cell(row[c], c)]),
    ],
  );
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.appBackground,
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text(code, style: context.textStyles.mono)),
      );
}

/// Inline Markdown as one piece of rich text. It owns the gesture recognizers
/// of its links, so it is the one place that has to dispose them.
class _InlineText extends StatefulWidget {
  final List<MarkdownInline> content;
  final TextStyle style;
  final TextAlign textAlign;

  const _InlineText(this.content, {required this.style, this.textAlign = TextAlign.start});

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    return Text.rich(
      TextSpan(style: widget.style, children: _spans(context, widget.content)),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _spans(BuildContext context, List<MarkdownInline> nodes, [TapGestureRecognizer? link]) =>
      [for (final node in nodes) _span(context, node, link)];

  /// A tap is delivered to the innermost span under the pointer, so a link's
  /// [link] recognizer has to sit on every span that holds its text.
  InlineSpan _span(BuildContext context, MarkdownInline node, TapGestureRecognizer? link) {
    final cursor = link == null ? null : SystemMouseCursors.click;
    return switch (node) {
      MarkdownText(:final text) => TextSpan(text: text, recognizer: link, mouseCursor: cursor),
      MarkdownBold(:final children) =>
        TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: _spans(context, children, link)),
      MarkdownItalic(:final children) =>
        TextSpan(style: const TextStyle(fontStyle: FontStyle.italic), children: _spans(context, children, link)),
      MarkdownCode(:final code) => TextSpan(
          text: code,
          recognizer: link,
          mouseCursor: cursor,
          style: context.textStyles.mono.copyWith(
            fontSize: (widget.style.fontSize ?? 14) * 0.92,
            backgroundColor: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
      MarkdownLink(:final url, :final children) => TextSpan(
          style: TextStyle(color: context.colors.mainAccent, decoration: TextDecoration.underline),
          children: _spans(context, children, _recognizerFor(context, url)),
        ),
      MarkdownLineBreak() => const TextSpan(text: '\n'),
    };
  }

  TapGestureRecognizer _recognizerFor(BuildContext context, String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(context, url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.trim());
    var opened = false;
    if (uri != null && uri.hasScheme && SafeLink.isAllowed(url)) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }
}
