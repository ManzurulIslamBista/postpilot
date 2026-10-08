import '../../../documentation/domain/services/secret_masker.dart';
import '../entities/refactor_plan.dart';

/// Finds [FindOptions.query] in text and works out what each occurrence becomes.
///
/// Plain text is searched literally. A regular expression is compiled with `multiLine` on (`^` and `$` match at each
/// line of a body) and its replacement may use `$1`..`$99`, `$&` (the whole match), `$0`, `$<name>` and `$$` (a
/// dollar). In plain mode the replacement is always literal, `$` included. Whole-word matching refuses a match that
/// touches a letter, digit or underscore. An occurrence of no characters (what `a*` finds between letters) is not a
/// match, since there is nothing to replace.
final class TextFinder {
  final RegExp _pattern;
  final bool _regex;

  TextFinder._(this._pattern, this._regex);

  /// Throws a [FormatException] whose message is safe to show when the query is empty or not a valid expression.
  factory TextFinder(FindOptions options) {
    if (options.query.isEmpty) throw const FormatException('Type something to look for.');
    var source = options.regex ? options.query : RegExp.escape(options.query);
    if (options.wholeWord) source = '(?<![A-Za-z0-9_])(?:$source)(?![A-Za-z0-9_])';
    try {
      return TextFinder._(RegExp(source, caseSensitive: options.caseSensitive, multiLine: true), options.regex);
    } on FormatException catch (e) {
      throw FormatException('Not a valid regular expression: ${e.message}');
    }
  }

  /// Every non-empty occurrence in [text], in order.
  Iterable<RegExpMatch> matches(String text) => _pattern.allMatches(text).where((m) => m.end > m.start);

  /// What [match] becomes with [template].
  String replacement(RegExpMatch match, String template) => _regex ? expand(template, match) : template;

  /// [template] with `$1`, `$&`, `$<name>` and `$$` filled in from [match]. A reference to a group the expression does
  /// not have stays as written.
  static String expand(String template, RegExpMatch match) {
    if (!template.contains(r'$')) return template;
    final out = StringBuffer();
    for (var i = 0; i < template.length; i++) {
      final c = template[i];
      if (c != r'$' || i + 1 >= template.length) {
        out.write(c);
        continue;
      }
      final next = template[i + 1];
      if (next == r'$') {
        out.write(r'$');
        i++;
      } else if (next == '&') {
        out.write(match[0]);
        i++;
      } else if (_isDigit(next)) {
        var group = int.parse(next);
        var used = 1;
        // $12 is group 12 when the expression has one, else group 1 followed by a "2".
        if (i + 2 < template.length && _isDigit(template[i + 2])) {
          final two = group * 10 + int.parse(template[i + 2]);
          if (two <= match.groupCount) {
            group = two;
            used = 2;
          }
        }
        if (group <= match.groupCount) {
          out.write(match[group] ?? '');
          i += used;
        } else {
          out.write(c);
        }
      } else if (next == '<') {
        final close = template.indexOf('>', i + 2);
        final name = close == -1 ? null : template.substring(i + 2, close);
        if (name != null && match.groupNames.contains(name)) {
          out.write(match.namedGroup(name) ?? '');
          i = close;
        } else {
          out.write(c);
        }
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}

/// Builds the [RefactorEdit]s of a plan: the span, the new text and the few words around it the preview shows.
abstract final class EditSnippets {
  /// How many characters of the text before and after an occurrence the preview shows.
  static const _context = 26;

  /// The longest old or new text the preview shows in one piece.
  static const _longest = 80;

  /// The edit for the occurrence of [text] at [start]..[end] of the field [fieldKey], becoming [after]. A [secret]
  /// field's preview is the mask, never any of its text.
  static RefactorEdit edit({
    required String fieldKey,
    required String text,
    required int start,
    required int end,
    required String after,
    required bool secret,
  }) {
    final before = text.substring(start, end);
    return RefactorEdit(
      id: '$fieldKey@$start',
      start: start,
      end: end,
      before: before,
      after: after,
      lead: secret ? '' : _lead(text, start),
      shownBefore: secret ? SecretMasker.mask : _clip(before),
      shownAfter: secret ? SecretMasker.mask : _clip(after),
      tail: secret ? '' : _tail(text, end),
    );
  }

  static String _lead(String text, int start) {
    final from = start > _context ? start - _context : 0;
    return '${from > 0 ? '…' : ''}${_flat(text.substring(from, start))}';
  }

  static String _tail(String text, int end) {
    final to = end + _context < text.length ? end + _context : text.length;
    return '${_flat(text.substring(end, to))}${to < text.length ? '…' : ''}';
  }

  static String _clip(String text) => _flat(text.length <= _longest ? text : '${text.substring(0, _longest - 1)}…');

  /// One line: a line break would stretch a row of the preview over the whole screen.
  static String _flat(String text) => text.replaceAll(RegExp(r'\r\n|\r|\n'), '↵').replaceAll('\t', ' ');
}
