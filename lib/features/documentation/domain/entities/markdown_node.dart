sealed class MarkdownBlock {
  const MarkdownBlock();
}

final class MarkdownHeading extends MarkdownBlock {
  final int level;
  final List<MarkdownInline> content;
  const MarkdownHeading(this.level, this.content);
}

final class MarkdownParagraph extends MarkdownBlock {
  final List<MarkdownInline> content;
  const MarkdownParagraph(this.content);
}

final class MarkdownCodeBlock extends MarkdownBlock {
  final String code;
  final String language;
  const MarkdownCodeBlock(this.code, {this.language = ''});
}

final class MarkdownQuote extends MarkdownBlock {
  final List<MarkdownBlock> children;
  const MarkdownQuote(this.children);
}

final class MarkdownList extends MarkdownBlock {
  final bool ordered;
  final int start;
  final List<List<MarkdownBlock>> items;
  const MarkdownList({required this.ordered, required this.start, required this.items});
}

final class MarkdownRule extends MarkdownBlock {
  const MarkdownRule();
}

enum MarkdownColumnAlign { none, left, center, right }

final class MarkdownTable extends MarkdownBlock {
  final List<MarkdownColumnAlign> alignments;
  final List<List<MarkdownInline>> header;
  final List<List<List<MarkdownInline>>> rows;
  const MarkdownTable({required this.alignments, required this.header, required this.rows});
}

sealed class MarkdownInline {
  const MarkdownInline();
}

final class MarkdownText extends MarkdownInline {
  final String text;
  const MarkdownText(this.text);
}

final class MarkdownBold extends MarkdownInline {
  final List<MarkdownInline> children;
  const MarkdownBold(this.children);
}

final class MarkdownItalic extends MarkdownInline {
  final List<MarkdownInline> children;
  const MarkdownItalic(this.children);
}

final class MarkdownCode extends MarkdownInline {
  final String code;
  const MarkdownCode(this.code);
}

final class MarkdownLink extends MarkdownInline {
  final String url;
  final List<MarkdownInline> children;
  const MarkdownLink(this.url, this.children);
}

final class MarkdownLineBreak extends MarkdownInline {
  const MarkdownLineBreak();
}
