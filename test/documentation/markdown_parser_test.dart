import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/domain/entities/markdown_node.dart';
import 'package:postpilot/features/documentation/domain/services/markdown_parser.dart';

import 'support/markdown_dump.dart';

void main() {
  group('headings', () {
    test('levels 1 to 6, with optional closing hashes', () {
      expect(parsed('# One\n## Two ##\n### Three\n#### Four\n##### Five\n###### Six'),
          'h1[One] h2[Two] h3[Three] h4[Four] h5[Five] h6[Six]');
    });

    test('need a space after the hashes and stop at six', () {
      expect(parsed('#nospace'), 'p[#nospace]');
      expect(parsed('####### seven'), 'p[####### seven]');
    });

    test('keep a hash that belongs to the text', () {
      expect(parsed('## Learning C#'), 'h2[Learning C#]');
      expect(parsed('## C# ##'), 'h2[C#]');
    });

    test('hold inline formatting', () {
      expect(parsed('# The *new* `API`'), 'h1[The <i>new</i> <code>API</code>]');
    });
  });

  group('paragraphs', () {
    test('join wrapped lines and split on blank lines', () {
      expect(parsed('one\ntwo\n\nthree'), 'p[one two] p[three]');
    });

    test('honour a hard break', () {
      expect(parsed('one  \ntwo'), 'p[one<br>two]');
      expect(parsed('one\\\ntwo'), 'p[one<br>two]');
    });

    test('are ended by a heading, a fence, a quote or a bullet', () {
      expect(parsed('text\n# Title'), 'p[text] h1[Title]');
      expect(parsed('text\n```\ncode\n```'), 'p[text] code[code]');
      expect(parsed('text\n> quote'), 'p[text] quote{p[quote]}');
      expect(parsed('text\n- item'), 'p[text] ul{p[item]}');
    });

    test('are not interrupted by an ordered marker that does not start at 1', () {
      expect(parsed('in\n2024. Big year'), 'p[in 2024. Big year]');
      expect(parsed('steps\n1. first'), 'p[steps] ol1{p[first]}');
    });

    test('ignore empty and whitespace-only input', () {
      expect(parsed(''), '');
      expect(parsed('  \n\n \n'), '');
    });

    test('accept Windows and old Mac line endings', () {
      expect(parsed('a\r\nb\r\n\r\nc\rd'), 'p[a b] p[c d]');
    });
  });

  group('fenced code', () {
    test('keeps the language and the exact content', () {
      expect(parsed('```json\n{"a": 1}\n\n  {"b": 2}\n```'), 'code(json)[{"a": 1}\n\n  {"b": 2}]');
    });

    test('supports tilde fences and an info string with extra words', () {
      expect(parsed('~~~yaml title="x"\na: 1\n~~~'), 'code(yaml)[a: 1]');
    });

    test('a longer fence can contain a shorter one', () {
      expect(parsed('````\n```\ninner\n```\n````'), 'code[```\ninner\n```]');
    });

    test('runs to the end of the input when it is never closed', () {
      expect(parsed('```\nx\ny\n\nz'), 'code[x\ny\n\nz]');
    });

    test('does not treat markdown inside as markup', () {
      expect(parsed('```\n# not a heading\n- not a list\n```'), 'code[# not a heading\n- not a list]');
    });

    test('resumes normal parsing after the closing fence', () {
      expect(parsed('```\nc\n```\nafter'), 'code[c] p[after]');
    });

    test('three backticks on one line are inline code, not a fence', () {
      expect(parsed('```code```'), 'p[<code>code</code>]');
    });

    test('removes the indentation of the opening fence from the content', () {
      expect(parsed('  ```\n  a\n    b\n  ```'), 'code[a\n  b]');
    });
  });

  group('block quotes', () {
    test('join their lines into one paragraph', () {
      expect(parsed('> a\n> b'), 'quote{p[a b]}');
    });

    test('nest and hold other blocks', () {
      expect(parsed('> > deep'), 'quote{quote{p[deep]}}');
      expect(parsed('> # Title\n> - a\n> - b'), 'quote{h1[Title] ul{p[a] ; p[b]}}');
    });

    test('continue lazily on an unmarked line', () {
      expect(parsed('> a\nb'), 'quote{p[a b]}');
    });

    test('end at a blank line', () {
      expect(parsed('> a\n\nb'), 'quote{p[a]} p[b]');
    });

    test('stop nesting instead of recursing without bound', () {
      final blocks = MarkdownParser.parse('${'>' * 500} bottom');
      expect(blocks, hasLength(1));
    });
  });

  group('lists', () {
    test('bullets with any of the three markers', () {
      expect(parsed('- a\n* b\n+ c'), 'ul{p[a] ; p[b] ; p[c]}');
    });

    test('ordered lists keep their first number', () {
      expect(parsed('3. a\n4) b'), 'ol3{p[a] ; p[b]}');
    });

    test('a marker needs a space and some text', () {
      expect(parsed('-a'), 'p[-a]');
      expect(parsed('-'), 'p[-]');
    });

    test('nested by indentation', () {
      expect(parsed('- a\n  - b\n    - c\n- d'), 'ul{p[a] ul{p[b] ul{p[c]}} ; p[d]}');
      expect(parsed('1. a\n    - b'), 'ol1{p[a] ul{p[b]}}');
    });

    test('blank lines between items keep one list', () {
      expect(parsed('- a\n\n- b'), 'ul{p[a] ; p[b]}');
    });

    test('an item can hold several paragraphs and code', () {
      expect(parsed('- a\n\n  more\n  ```\n  code\n  ```\n- b'), 'ul{p[a] p[more] code[code] ; p[b]}');
    });

    test('a wrapped item line continues the item', () {
      expect(parsed('- a\nb\n- c'), 'ul{p[a b] ; p[c]}');
    });

    test('switching between bullets and numbers starts a new list', () {
      expect(parsed('- a\n1. b'), 'ul{p[a]} ol1{p[b]}');
    });

    test('text after a blank line ends the list', () {
      expect(parsed('- a\n\nafter'), 'ul{p[a]} p[after]');
    });

    test('an item can start with a heading or a quote', () {
      expect(parsed('- # T\n- > q'), 'ul{h1[T] ; quote{p[q]}}');
    });

    test('a rule wins over a bullet', () {
      expect(parsed('* * *'), 'hr');
      expect(parsed('- a\n---\n- b'), 'ul{p[a]} hr ul{p[b]}');
    });
  });

  group('horizontal rules', () {
    test('three or more of -, * or _', () {
      for (final rule in ['---', '***', '___', '- - -', '_____', '  ***']) {
        expect(parsed(rule), 'hr', reason: rule);
      }
    });

    test('two are not enough', () {
      expect(parsed('--'), 'p[--]');
    });

    test('follow a paragraph line as their own block', () {
      expect(parsed('text\n---'), 'p[text] hr');
    });
  });

  group('tables', () {
    test('header, alignment and body rows', () {
      expect(parsed('| Name | Age | City |\n| :--- | :---: | ---: |\n| Ann | 30 | Oslo |\n| Bo | 41 | Rome |'),
          'table(left,center,right)[Name|Age|City / Ann|30|Oslo / Bo|41|Rome]');
    });

    test('work without outer pipes', () {
      expect(parsed('a | b\n--- | ---\n1 | 2'), 'table(none,none)[a|b / 1|2]');
    });

    test('an escaped pipe stays in the cell, even inside code', () {
      expect(parsed('| k | v |\n| - | - |\n| `a\\|b` | x\\|y |'), 'table(none,none)[k|v / <code>a|b</code>|x|y]');
    });

    test('short rows are padded and long rows trimmed to the header', () {
      expect(parsed('| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |'), 'table(none,none)[a|b / 1| / 1|2]');
    });

    test('cells hold inline formatting', () {
      expect(parsed('| a |\n|---|\n| **x** and `y` |'), 'table(none)[a / <b>x</b> and <code>y</code>]');
    });

    test('end at a blank line', () {
      expect(parsed('| a |\n|---|\n| 1 |\n\nafter'), 'table(none)[a / 1] p[after]');
    });

    test('a header and delimiter row of different width are just text', () {
      expect(parsed('| a | b |\n|---|'), 'p[| a | b | |---|]');
    });

    test('a pipe in a paragraph is not a table', () {
      expect(parsed('a | b'), 'p[a | b]');
    });
  });

  group('bold and italic', () {
    test('star and underscore forms', () {
      expect(parsed('**b** __b__ *i* _i_'), 'p[<b>b</b> <b>b</b> <i>i</i> <i>i</i>]');
    });

    test('bold italic with three markers', () {
      expect(parsed('***both***'), 'p[<b><i>both</i></b>]');
    });

    test('nest in both directions', () {
      expect(parsed('**bold *and italic* text**'), 'p[<b>bold <i>and italic</i> text</b>]');
      expect(parsed('*italic **and bold** text*'), 'p[<i>italic <b>and bold</b> text</i>]');
      expect(parsed('**bold *italic***'), 'p[<b>bold <i>italic</i></b>]');
      expect(parsed('*italic **bold***'), 'p[<i>italic <b>bold</b></i>]');
    });

    test('an opener followed by a space is literal', () {
      expect(parsed('2 * 3 * 4'), 'p[2 * 3 * 4]');
      expect(parsed('a ** b ** c'), 'p[a ** b ** c]');
    });

    test('underscores inside a word are literal', () {
      expect(parsed('snake_case_name and __init__.py'), 'p[snake_case_name and <b>init</b>.py]');
      expect(parsed('a_b_c'), 'p[a_b_c]');
    });

    test('stars inside a word still emphasise', () {
      expect(parsed('2*3*4'), 'p[2<i>3</i>4]');
    });

    test('an unmatched opener before a real pair does not swallow the pair', () {
      expect(parsed('Skips *.json files, but *this* is emphasised.'), 'p[Skips *.json files, but <i>this</i> is emphasised.]');
      expect(parsed('_private and _italic_'), 'p[_private and <i>italic</i>]');
      expect(parsed('*.md, *.txt and **bold**'), 'p[*.md, *.txt and <b>bold</b>]');
      expect(parsed('**a and **b** c'), 'p[**a and <b>b</b> c]');
    });

    test('unmatched markers stay as they are', () {
      expect(parsed('**open only'), 'p[**open only]');
      expect(parsed('close only**'), 'p[close only**]');
      expect(parsed('a **** b'), 'p[a **** b]');
      expect(parsed('*a **b'), 'p[*a **b]');
      expect(parsed('**a*'), 'p[**a*]');
    });

    test('can span a soft line break', () {
      expect(parsed('**a\nb**'), 'p[<b>a b</b>]');
    });

    test('an escaped marker is literal', () {
      expect(parsed(r'\*not italic\* and \_x\_'), 'p[*not italic* and _x_]');
    });

    test('markers inside code are left alone', () {
      expect(parsed('*a `b*` c*'), 'p[<i>a <code>b*</code> c</i>]');
    });
  });

  group('inline code', () {
    test('single and double backtick spans', () {
      expect(parsed('use `GET` or ``a ` b``'), 'p[use <code>GET</code> or <code>a ` b</code>]');
    });

    test('drops one padding space on each side', () {
      expect(parsed('`` `x` ``'), 'p[<code>`x`</code>]');
    });

    test('does not parse the inside', () {
      expect(parsed('`**not bold**`'), 'p[<code>**not bold**</code>]');
    });

    test('an unclosed backtick is literal', () {
      expect(parsed('a ` b'), 'p[a ` b]');
    });
  });

  group('links', () {
    test('inline link with optional title', () {
      expect(parsed('[docs](https://x.dev/a)'), 'p[<a https://x.dev/a>docs</a>]');
      expect(parsed('[docs](https://x.dev/a "Title")'), 'p[<a https://x.dev/a>docs</a>]');
      expect(parsed('[docs](<https://x.dev/a b>)'), 'p[<a https://x.dev/a b>docs</a>]');
    });

    test('link text can be formatted', () {
      expect(parsed('[**bold** `code`](/x)'), 'p[<a /x><b>bold</b> <code>code</code></a>]');
    });

    test('balanced parentheses stay in the url', () {
      expect(parsed('[w](https://en.wikipedia.org/wiki/A_(b)) end'),
          'p[<a https://en.wikipedia.org/wiki/A_(b)>w</a> end]');
    });

    test('an image becomes a link to it', () {
      expect(parsed('![logo](https://x.dev/l.png)'), 'p[<a https://x.dev/l.png>logo</a>]');
      expect(parsed('![](https://x.dev/l.png)'), 'p[<a https://x.dev/l.png>https://x.dev/l.png</a>]');
    });

    test('angle-bracket autolinks', () {
      expect(parsed('<https://x.dev> and <mailto:a@b.co>'),
          'p[<a https://x.dev>https://x.dev</a> and <a mailto:a@b.co>mailto:a@b.co</a>]');
    });

    test('bare urls become links without trailing punctuation', () {
      expect(parsed('See https://x.dev/a?b=1, then http://y.dev.'),
          'p[See <a https://x.dev/a?b=1>https://x.dev/a?b=1</a>, then <a http://y.dev>http://y.dev</a>.]');
      expect(parsed('(https://x.dev/p)'), 'p[(<a https://x.dev/p>https://x.dev/p</a>)]');
      expect(parsed('https://x.dev/a_(b)'), 'p[<a https://x.dev/a_(b)>https://x.dev/a_(b)</a>]');
    });

    test('a bare url inside link text is not linked twice', () {
      expect(parsed('[https://x.dev](https://x.dev)'), 'p[<a https://x.dev>https://x.dev</a>]');
    });

    test('a broken link is plain text', () {
      expect(parsed('[text] (url)'), 'p[[text] (url)]');
      expect(parsed('[text](url'), 'p[[text](url]');
      expect(parsed('[no close'), 'p[[no close]');
    });

    test('emphasis around a bare url does not swallow the markers', () {
      expect(parsed('**https://x.dev**'), 'p[<b><a https://x.dev>https://x.dev</a></b>]');
    });
  });

  group('escapes', () {
    test('a backslash before punctuation is dropped, before a letter kept', () {
      expect(parsed(r'\# \[ \` \\ \a'), r'p[# [ ` \ \a]');
    });
  });

  group('robustness', () {
    test('unmatched openers do not make parsing quadratic', () {
      final watch = Stopwatch()..start();
      MarkdownParser.parse('*a ' * 20000);
      MarkdownParser.parse('[a ' * 20000);
      MarkdownParser.parse('`a ' * 20000);
      MarkdownParser.parse('_a ' * 20000);
      MarkdownParser.parse('${'  ' * 50000}x | y\n${' ' * 50000}|');
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('unmatched openers followed by a real pair stay bounded', () {
      final watch = Stopwatch()..start();
      final blocks = MarkdownParser.parse('${'*a ' * 20000}*b*');
      MarkdownParser.parse('${'_a ' * 20000}_b_');
      expect(blocks, isNotEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('deeply nested emphasis is bounded', () {
      final source = '${'*a ' * 100}b${'* ' * 100}';
      expect(MarkdownParser.parse(source), isNotEmpty);
    });

    test('a very long line does not overflow the stack', () {
      final blocks = MarkdownParser.parse('- ' * 5000);
      expect(blocks, isNotEmpty);
    });

    test('every block type appears in a mixed document', () {
      final blocks = MarkdownParser.parse('# T\n\np\n\n> q\n\n- l\n\n---\n\n```\nc\n```\n\n| a |\n|---|\n| 1 |');
      expect(blocks.map((b) => b.runtimeType).toList(), [
        MarkdownHeading,
        MarkdownParagraph,
        MarkdownQuote,
        MarkdownList,
        MarkdownRule,
        MarkdownCodeBlock,
        MarkdownTable,
      ]);
    });
  });
}
