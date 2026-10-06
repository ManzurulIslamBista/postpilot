/// What a "Status equals" check accepts as the expected value: one status code (`200`), a class of them (`4xx`),
/// or several of either separated by commas or blanks (`401, 403`, `200 204`, `2xx, 404`). A single code behaves
/// exactly as it always did; the other forms let a test say "any client error" or "401 or 403" where the exact
/// code is not known or not fixed.
abstract final class StatusMatcher {
  static final _separator = RegExp(r'[\s,;]+');
  static final _statusClass = RegExp(r'^[1-5]xx$', caseSensitive: false);

  static bool matches(String expected, int status) {
    for (final part in expected.trim().split(_separator)) {
      if (part == '$status') return true;
      if (_statusClass.hasMatch(part) && int.parse(part[0]) == status ~/ 100) return true;
    }
    return false;
  }
}
