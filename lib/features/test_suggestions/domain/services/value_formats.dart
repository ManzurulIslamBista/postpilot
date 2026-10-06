/// The recognisable kinds of string a response holds, used to turn "this is a UUID" into a pattern check and to
/// tell values that change by themselves (ids, tokens, timestamps) from values worth comparing exactly.
enum ValueFormat {
  uuid('a UUID', 'uuid'),
  email('an email address', 'email'),
  url('a URL', 'uri'),
  dateTime('a date and time', 'date-time'),
  date('a date', 'date'),
  jwt('a JWT', null),
  opaqueId('an opaque id', null);

  /// How the kind reads in a sentence.
  final String phrase;

  /// The JSON Schema `format` that checks it, when the validator knows one.
  final String? schemaFormat;

  const ValueFormat(this.phrase, this.schemaFormat);
}

abstract final class ValueFormats {
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _url = RegExp(r'^https?://[^\s/$.?#][^\s]*$', caseSensitive: false);
  static final _dateTime = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$');
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _jwt = RegExp(r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');
  static final _hex = RegExp(r'^[0-9a-fA-F]{20,}$');
  static final _ulid = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');
  static final _opaque = RegExp(r'^[A-Za-z0-9+/_\-=.]{32,}$');

  /// The kind [text] is, or null when it is ordinary text.
  static ValueFormat? of(String text) {
    if (text.isEmpty || text.length > 2048) return null;
    if (_uuid.hasMatch(text)) return ValueFormat.uuid;
    if (_jwt.hasMatch(text)) return ValueFormat.jwt;
    if (_dateTime.hasMatch(text) && _onCalendar(text)) return ValueFormat.dateTime;
    if (_date.hasMatch(text) && _onCalendar(text)) return ValueFormat.date;
    if (_email.hasMatch(text)) return ValueFormat.email;
    if (_url.hasMatch(text)) return ValueFormat.url;
    if (_hex.hasMatch(text) || _ulid.hasMatch(text)) return ValueFormat.opaqueId;
    // A long run of letters, digits and a few symbols that mixes both is a token, not a word.
    if (_opaque.hasMatch(text) && text.contains(RegExp(r'[A-Za-z]')) && text.contains(RegExp(r'\d'))) {
      return ValueFormat.opaqueId;
    }
    return null;
  }

  /// The date (and time) at the start of [text] exists: Dart reads `2026-13-45` as a day in 2027, so the parts are
  /// checked against the calendar here instead.
  static bool _onCalendar(String text) {
    final year = int.parse(text.substring(0, 4));
    final month = int.parse(text.substring(5, 7));
    final day = int.parse(text.substring(8, 10));
    if (month < 1 || month > 12 || day < 1) return false;
    if (day > DateTime.utc(year, month + 1, 0).day) return false;
    if (text.length < 16) return true;
    final hour = int.parse(text.substring(11, 13));
    final minute = int.parse(text.substring(14, 16));
    final second = text.length >= 19 && text[16] == ':' ? int.parse(text.substring(17, 19)) : 0;
    return hour <= 23 && minute <= 59 && second <= 60;
  }

  /// The kind every one of [values] is; null when they are not all strings of one kind.
  static ValueFormat? commonFormat(Iterable<Object> values) {
    ValueFormat? found;
    for (final value in values) {
      if (value is! String) return null;
      final kind = of(value);
      if (kind == null || (found != null && kind != found)) return null;
      found = kind;
    }
    return found;
  }

  /// A regular expression every one of [values] matches and that says something about how an id is built, with the
  /// same thing in words; null when they share no shape worth checking: all digits, one prefix then a code
  /// (`usr_8f3a`), or lower-case hex of one length.
  static ({String regex, String phrase})? idPattern(List<String> values) {
    if (values.isEmpty) return null;
    if (values.every((v) => RegExp(r'^\d+$').hasMatch(v))) return (regex: r'^\d+$', phrase: 'is made of digits only');
    final prefixed = RegExp(r'^([A-Za-z]{1,12}[_-])([A-Za-z0-9]{4,})$');
    final prefixes = <String>{};
    for (final v in values) {
      final m = prefixed.firstMatch(v);
      if (m == null) {
        prefixes.clear();
        break;
      }
      prefixes.add(m.group(1)!);
    }
    if (prefixes.length == 1) {
      final prefix = prefixes.single;
      return (regex: '^${RegExp.escape(prefix)}[A-Za-z0-9]+\$', phrase: 'starts with "$prefix" and ends in letters or digits');
    }
    final lengths = <int>{};
    final hex = values.every((v) {
      lengths.add(v.length);
      return RegExp(r'^[0-9a-f]+$').hasMatch(v) && v.length >= 12;
    });
    if (hex && lengths.length == 1) {
      return (regex: '^[0-9a-f]{${lengths.single}}\$', phrase: 'is ${lengths.single} lower-case hex characters');
    }
    return null;
  }
}
