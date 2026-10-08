// The matching and replacing engine on its own: plain text and regular expressions, case, whole words, `$1` groups.
// Every expected value was worked out by hand from the text, by counting characters.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_plan.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/text_finder.dart';

/// [text] with every match of [options] replaced by [replacement], the way a plan splices it.
String replaceAll(String text, FindOptions options, String replacement) {
  final finder = TextFinder(options);
  var out = '';
  var cursor = 0;
  for (final m in finder.matches(text)) {
    out += text.substring(cursor, m.start) + finder.replacement(m, replacement);
    cursor = m.end;
  }
  return out + text.substring(cursor);
}

List<(int, int)> spans(String text, FindOptions options) => [for (final m in TextFinder(options).matches(text)) (m.start, m.end)];

void main() {
  group('plain text is literal', () {
    test('regex characters in the query mean themselves', () {
      // x0 a1 .2 b3 *4 c5 y6 _7 a8 .9 b10 *11 c12 _13 a14 X15 b16
      const text = 'xa.b*cy a.b*c aXb';
      expect(spans(text, const FindOptions(query: 'a.b*c')), [(1, 6), (8, 13)]);
      expect(replaceAll(text, const FindOptions(query: 'a.b*c'), 'Z'), 'xZy Z aXb');
    });

    test('brackets, parentheses, plus and the dollar sign are literal too', () {
      const text = r'cost (a+b) = $5 [x]';
      expect(replaceAll(text, const FindOptions(query: '(a+b)'), 'sum'), r'cost sum = $5 [x]');
      expect(replaceAll(text, const FindOptions(query: r'$5'), 'five'), 'cost (a+b) = five [x]');
      expect(replaceAll(text, const FindOptions(query: '[x]'), 'y'), r'cost (a+b) = $5 y');
    });

    test('the replacement is literal as well: a dollar and digits are not a group', () {
      expect(replaceAll('foo', const FindOptions(query: 'foo'), r'$1 and $&'), r'$1 and $&');
    });

    test('an empty query is refused with a message', () {
      expect(() => TextFinder(const FindOptions(query: '')), throwsA(isA<FormatException>()));
    });
  });

  group('case', () {
    const text = 'Token TOKEN token';
    test('ignored by default', () {
      expect(spans(text, const FindOptions(query: 'token')), [(0, 5), (6, 11), (12, 17)]);
    });

    test('kept when asked: only the lower-case word matches', () {
      expect(spans(text, const FindOptions(query: 'token', caseSensitive: true)), [(12, 17)]);
    });

    test('accented letters fold too', () {
      expect(spans('Café CAFÉ cafe', const FindOptions(query: 'café')), [(0, 4), (5, 9)]);
    });
  });

  group('whole word', () {
    // i0 d1 _2 u3 s4 e5 r6 _7 i8 d9 _10 i11 d12 x13 _14 i15 d16 .17
    const text = 'id user_id idx id.';

    test('does not match inside a longer word, after an underscore or before a letter', () {
      expect(spans(text, const FindOptions(query: 'id', wholeWord: true)), [(0, 2), (15, 17)]);
    });

    test('without it every occurrence matches', () {
      expect(spans(text, const FindOptions(query: 'id')), hasLength(4));
    });

    test('a query that starts with a brace is still bounded by its neighbours', () {
      expect(spans('x{{id}}y', const FindOptions(query: '{{id}}', wholeWord: true)), isEmpty);
      expect(spans('x {{id}} y', const FindOptions(query: '{{id}}', wholeWord: true)), [(2, 8)]);
    });

    test('works with a regular expression that has an alternation', () {
      // Without the wrapping group the word boundary would only bind the first alternative.
      expect(spans('cat concat dog', const FindOptions(query: 'cat|dog', regex: true, wholeWord: true)), [(0, 3), (11, 14)]);
    });
  });

  group('regular expressions', () {
    test(r'$1 and $2 are the captured groups', () {
      const options = FindOptions(query: r'(\w+)@(\w+)\.com', regex: true);
      expect(replaceAll('ann@shop.com bob@x.com', options, r'$2:$1'), 'shop:ann x:bob');
    });

    test(r'$& and $0 are the whole match, $$ is a dollar sign', () {
      const options = FindOptions(query: r'\d+', regex: true);
      expect(replaceAll('a1b22', options, r'[$&]'), 'a[1]b[22]');
      expect(replaceAll('a1b22', options, r'<$0>'), 'a<1>b<22>');
      expect(replaceAll('a1b22', options, r'$$'), r'a$b$');
    });

    test(r'$12 is group 12 only when the expression has twelve groups, else group 1 and a "2"', () {
      expect(replaceAll('a', const FindOptions(query: '(a)', regex: true), r'$12'), 'a2');
      final twelve = List.filled(12, '(a)').join();
      expect(replaceAll('a' * 12, FindOptions(query: twelve, regex: true), r'$12!'), 'a!');
    });

    test('a group the expression does not have stays as typed', () {
      expect(replaceAll('a', const FindOptions(query: '(a)', regex: true), r'$5'), r'$5');
    });

    test('a named group is reached with <name>', () {
      const options = FindOptions(query: r'(?<k>\w+)=(?<v>\w+)', regex: true);
      expect(replaceAll('a=1 b=2', options, r'$<v>=$<k>'), '1=a 2=b');
    });

    test('a group that did not take part becomes nothing', () {
      expect(replaceAll('ac', const FindOptions(query: r'a(b)?c', regex: true), r'[$1]'), '[]');
    });

    test('^ and \$ match at every line of a body', () {
      expect(spans('id\nid', const FindOptions(query: '^id', regex: true)), [(0, 2), (3, 5)]);
      expect(spans('a;\nb;', const FindOptions(query: r';$', regex: true)), [(1, 2), (4, 5)]);
    });

    test('an occurrence of no characters is not a match', () {
      // "x*" is empty before the a, after the xx and at the end; only "xx" is something to replace.
      expect(spans('axxb', const FindOptions(query: 'x*', regex: true)), [(1, 3)]);
    });

    test('an expression that does not compile says so', () {
      expect(
        () => TextFinder(const FindOptions(query: '(', regex: true)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', startsWith('Not a valid regular expression'))),
      );
    });

    test('case-insensitive by default, and exact when asked', () {
      expect(spans('Abc abc', const FindOptions(query: 'a.c', regex: true)), [(0, 3), (4, 7)]);
      expect(spans('Abc abc', const FindOptions(query: 'a.c', regex: true, caseSensitive: true)), [(4, 7)]);
    });
  });

  group('JSON text', () {
    // A body as it is stored: quotes escaped inside a string, an escaped unicode letter (backslash, u, 00e9), a real one.
    const bs = r'\';
    const escaped = '${bs}u00e9';
    const body = '{"msg":"say $bs"hi$bs" café","code":"$escaped","ok":true}';

    test('an escaped quote is found as the two characters it is', () {
      expect(
        replaceAll(body, FindOptions(query: '$bs"hi$bs"'), '$bs"yo$bs"'),
        '{"msg":"say $bs"yo$bs" café","code":"$escaped","ok":true}',
      );
    });

    test('a unicode escape is plain text, not the letter it stands for', () {
      // The letter itself is at 22; the escape further on is six other characters, starting at 33.
      expect(spans(body, const FindOptions(query: 'é')), [(22, 23)]);
      expect(spans(body, FindOptions(query: escaped)), [(33, 39)]);
    });

    test('a regular expression can reach into the quotes', () {
      expect(
        replaceAll(body, const FindOptions(query: r'"(\w+)":', regex: true), r'$1:'),
        '{msg:"say $bs"hi$bs" café",code:"$escaped",ok:true}',
      );
    });

    test('an emoji and a non-latin word are found whole', () {
      expect(spans('a😀b', const FindOptions(query: '😀')), [(1, 3)]);
      expect(spans('x 日本語 y', const FindOptions(query: '日本語')), [(2, 5)]);
    });
  });

  group('expand', () {
    test('a template without a dollar sign is returned as it is', () {
      final match = RegExp('a').firstMatch('a')!;
      expect(TextFinder.expand('plain', match), 'plain');
    });

    test('a lone dollar sign at the end stays', () {
      final match = RegExp('a').firstMatch('a')!;
      expect(TextFinder.expand(r'cost$', match), r'cost$');
    });
  });
}
