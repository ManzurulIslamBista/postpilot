/// Helpers for the `Set-Cookie` lines of a response.
///
/// HTTP clients join repeated headers with `, `, which `Set-Cookie` does not
/// survive: a cookie's `Expires` date holds a comma of its own. Where the
/// separate lines are known they are used as they are; [split] is the fallback
/// for a response that only kept the joined text (an imported example, the
/// command-line runner).
abstract final class SetCookies {
  /// A comma that ends one cookie and starts the next: followed by a
  /// `name=` with no space before the `=`. The comma inside
  /// `Expires=Wed, 21 Oct 2015 ...` is followed by a date, which has one.
  static final _between = RegExp(r',\s*(?=[^\s=;,]+=)');

  /// The cookies of a header value that [lines] were joined into with `, `.
  static List<String> split(String joined) => [
        for (final part in joined.split(_between))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  /// The value of the cookie called [name] in [lines] (the first one, when a
  /// response sets it twice), or null when no line sets it.
  static String? valueOf(Iterable<String> lines, String name) {
    final wanted = name.trim();
    if (wanted.isEmpty) return null;
    for (final line in lines) {
      final pair = line.split(';').first;
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      if (pair.substring(0, equals).trim() == wanted) return pair.substring(equals + 1).trim();
    }
    return null;
  }
}
