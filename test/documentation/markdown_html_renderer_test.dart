import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/domain/services/markdown_embedder.dart';
import 'package:postpilot/features/documentation/domain/services/markdown_html_renderer.dart';
import 'package:postpilot/features/documentation/domain/services/safe_link.dart';

String _html(String markdown, {int shift = 0}) => MarkdownHtmlRenderer.render(markdown, shiftHeadings: shift);

void main() {
  group('blocks', () {
    test('headings, paragraphs and rules', () {
      expect(_html('# T\n\ntext\n\n---'), '<h1>T</h1>\n<p>text</p>\n<hr>\n');
    });

    test('heading levels can be shifted but stop at six', () {
      expect(_html('# A\n###### B', shift: 2), '<h3>A</h3>\n<h6>B</h6>\n');
    });

    test('code keeps its text and gets a language class', () {
      expect(_html('```json\n{"a": "<b>"}\n```'), '<pre><code class="language-json">{&quot;a&quot;: &quot;&lt;b&gt;&quot;}</code></pre>\n');
      expect(_html('```\nplain\n```'), '<pre><code>plain</code></pre>\n');
    });

    test('a hostile language is cut down to safe characters', () {
      final html = _html('```js"><script>alert(1)</script>\ncode\n```');
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('"><')));
    });

    test('quotes nest their blocks', () {
      expect(_html('> a\n>\n> - b'), '<blockquote>\n<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n</blockquote>\n');
    });

    test('lists: bullets, numbers with a start, nesting', () {
      expect(_html('- a\n  - b\n- c'), '<ul>\n<li>a<ul>\n<li>b</li>\n</ul>\n</li>\n<li>c</li>\n</ul>\n');
      expect(_html('3. a\n4. b'), '<ol start="3">\n<li>a</li>\n<li>b</li>\n</ol>\n');
      expect(_html('1. a'), '<ol>\n<li>a</li>\n</ol>\n');
    });

    test('tables with alignment', () {
      expect(_html('| a | b | c |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |'), '''
<table>
<thead><tr><th style="text-align:left">a</th><th style="text-align:center">b</th><th style="text-align:right">c</th></tr></thead>
<tbody>
<tr><td style="text-align:left">1</td><td style="text-align:center">2</td><td style="text-align:right">3</td></tr>
</tbody>
</table>
''');
      expect(_html('| a |\n|---|\n| 1 |'), contains('<th>a</th>'));
    });
  });

  group('inline', () {
    test('formatting and code', () {
      expect(_html('**b** *i* `c` a  \nb'), '<p><strong>b</strong> <em>i</em> <code>c</code> a<br>b</p>\n');
    });

    test('text is escaped, including in code', () {
      expect(_html('a <b> & "c" \'d\' `<x>`'), '<p>a &lt;b&gt; &amp; &quot;c&quot; &#39;d&#39; <code>&lt;x&gt;</code></p>\n');
    });

    test('raw html in the source stays text', () {
      final html = _html('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>');
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<img')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('safe links become anchors that cannot reach the opener', () {
      expect(_html('[a](https://x.dev/?q=1&r="2")'),
          '<p><a href="https://x.dev/?q=1&amp;r=&quot;2&quot;" rel="noopener noreferrer" target="_blank">a</a></p>\n');
      expect(_html('[m](mailto:a@b.co) [h](#top)'), contains('href="mailto:a@b.co"'));
      expect(_html('[m](mailto:a@b.co) [h](#top)'), contains('href="#top"'));
    });

    test('unsafe links keep their text and lose the link', () {
      for (final url in ['javascript:alert(1)', 'data:text/html,x', 'vbscript:x', 'file:///etc/passwd', '//evil.dev/x', '/relative']) {
        final html = _html('[click]($url)');
        expect(html, '<p>click</p>\n', reason: url);
      }
    });

    test('a bare url is linked, an autolink too', () {
      expect(_html('see https://x.dev.'), contains('<a href="https://x.dev" rel="noopener noreferrer" target="_blank">https://x.dev</a>.'));
      expect(_html('<https://x.dev>'), contains('href="https://x.dev"'));
      expect(_html('<javascript:alert(1)>'), isNot(contains('href')));
    });
  });

  group('SafeLink', () {
    test('allows web, mail and in-page links only', () {
      for (final url in ['http://a.dev', 'HTTPS://a.dev', 'mailto:a@b.co', '#section', '  https://a.dev']) {
        expect(SafeLink.isAllowed(url), isTrue, reason: url);
      }
      for (final url in ['javascript:x', 'JaVaScRiPt:x', 'java\tscript:x', 'java\nscript:x', ' \u0001javascript:x', 'data:x', 'file:///x', 'ftp://x', '/x', '//x', '']) {
        expect(SafeLink.isAllowed(url), isFalse, reason: url);
      }
    });
  });

  group('MarkdownEmbedder', () {
    test('moves headings down and stops at level six', () {
      expect(MarkdownEmbedder.prepare('# A\n## B\n###### C', shiftHeadings: 2), '### A\n#### B\n###### C');
      expect(MarkdownEmbedder.prepare('# A', shiftHeadings: 0), '# A');
    });

    test('leaves lines that are not headings', () {
      expect(MarkdownEmbedder.prepare('#tag\n####### seven\n    # indented\ntext # not', shiftHeadings: 1),
          '#tag\n####### seven\n    # indented\ntext # not');
    });

    test('allows up to three spaces before a heading', () {
      expect(MarkdownEmbedder.prepare('text\n   # A', shiftHeadings: 1), 'text\n   ## A');
    });

    test('does not touch what is inside a code fence', () {
      expect(MarkdownEmbedder.prepare('# A\n```sh\n# comment\n```\n# B', shiftHeadings: 1), '## A\n```sh\n# comment\n```\n## B');
      expect(MarkdownEmbedder.prepare('~~~\n# c\n~~~\n# B', shiftHeadings: 1), '~~~\n# c\n~~~\n## B');
      expect(MarkdownEmbedder.prepare('````\n```\n# c\n```\n````\n# B', shiftHeadings: 1), '````\n```\n# c\n```\n````\n## B');
    });

    test('closes a fence that was left open', () {
      expect(MarkdownEmbedder.prepare('a\n```\ncode', shiftHeadings: 1), 'a\n```\ncode\n```');
      expect(MarkdownEmbedder.prepare('~~~~\ncode', shiftHeadings: 1), '~~~~\ncode\n~~~~');
    });

    test('normalises line endings and trims blank edges', () {
      expect(MarkdownEmbedder.prepare('\r\n\r\n# A\r\ntext\r\n\r\n', shiftHeadings: 1), '## A\ntext');
      expect(MarkdownEmbedder.prepare('   ', shiftHeadings: 1), '');
      expect(MarkdownEmbedder.prepare('', shiftHeadings: 1), '');
    });
  });
}
