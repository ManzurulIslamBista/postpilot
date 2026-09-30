/// The tag rules the tag store applies (trim, drop blanks, ignore case, sort),
/// so a screen can show exactly what a save will store before it is stored.
abstract final class TagNormalizer {
  /// Duplicates ignoring case collapse to the spelling that came first.
  static List<String> normalise(Iterable<String> tags) {
    final seen = <String>{};
    return [
      for (final raw in tags)
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase())) raw.trim(),
    ]..sort((a, b) {
        final byLower = a.toLowerCase().compareTo(b.toLowerCase());
        return byLower != 0 ? byLower : a.compareTo(b);
      });
  }

  static bool same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
}
