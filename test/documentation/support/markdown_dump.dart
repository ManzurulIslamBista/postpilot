import 'package:postpilot/features/documentation/domain/entities/markdown_node.dart';
import 'package:postpilot/features/documentation/domain/services/markdown_parser.dart';

/// A compact, readable rendering of a parsed tree for assertions.
String parsed(String markdown) => dump(MarkdownParser.parse(markdown));

String dump(List<MarkdownBlock> blocks) => blocks.map(_block).join(' ');

String inlines(List<MarkdownInline> nodes) => nodes.map(_inline).join();

String _block(MarkdownBlock block) => switch (block) {
      MarkdownHeading() => 'h${block.level}[${inlines(block.content)}]',
      MarkdownParagraph() => 'p[${inlines(block.content)}]',
      MarkdownCodeBlock() => 'code${block.language.isEmpty ? '' : '(${block.language})'}[${block.code}]',
      MarkdownQuote() => 'quote{${dump(block.children)}}',
      MarkdownList() => '${block.ordered ? 'ol${block.start}' : 'ul'}{${block.items.map(dump).join(' ; ')}}',
      MarkdownRule() => 'hr',
      MarkdownTable() => 'table(${block.alignments.map((a) => a.name).join(',')})'
          '[${block.header.map(inlines).join('|')}${block.rows.map((r) => ' / ${r.map(inlines).join('|')}').join()}]',
    };

String _inline(MarkdownInline node) => switch (node) {
      MarkdownText() => node.text,
      MarkdownBold() => '<b>${inlines(node.children)}</b>',
      MarkdownItalic() => '<i>${inlines(node.children)}</i>',
      MarkdownCode() => '<code>${node.code}</code>',
      MarkdownLink() => '<a ${node.url}>${inlines(node.children)}</a>',
      MarkdownLineBreak() => '<br>',
    };
