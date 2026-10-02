/// Subsequence matching for the command palette: "dsm" finds "Dart Studio:
/// models", "ord" finds "Create order". Letters must appear in order but not
/// next to each other; consecutive letters and word starts score higher, so the
/// result a person expects comes first.
final class FuzzyMatch {
  final int score;

  /// Indices in the matched text of each query letter, for highlighting.
  final List<int> positions;
  const FuzzyMatch(this.score, this.positions);
}

abstract final class FuzzyMatcher {
  /// `null` when [query] is not a subsequence of [text]. An empty query
  /// matches everything with score 0.
  static FuzzyMatch? match(String query, String text) {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (q.isEmpty) return const FuzzyMatch(0, []);
    final t = text.toLowerCase();
    if (q.length > t.length) return null;

    // A plain substring is the best kind of match.
    final at = t.indexOf(q);
    if (at >= 0) {
      final startsWord = at == 0 || !_isAlnum(t.codeUnitAt(at - 1));
      return FuzzyMatch(1000 + (startsWord ? 200 : 0) - at, [for (var i = 0; i < q.length; i++) at + i]);
    }

    final positions = <int>[];
    var score = 0;
    var ti = 0;
    var previous = -2;
    for (var qi = 0; qi < q.length; qi++) {
      final found = t.indexOf(q[qi], ti);
      if (found < 0) return null;
      positions.add(found);
      score += 10;
      if (found == previous + 1) score += 15; // consecutive
      if (found == 0 || !_isAlnum(t.codeUnitAt(found - 1))) score += 12; // word start
      score -= (found - ti).clamp(0, 6); // gaps cost a little
      previous = found;
      ti = found + 1;
    }
    return FuzzyMatch(score, positions);
  }

  static bool _isAlnum(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A) || c > 0x7F;
}
