/// "Did you mean ...": the names (fields, models, selection values) closest to one that does not exist.
abstract final class OdooNames {
  /// The edit distance between [a] and [b] counting an insertion, a deletion, a substitution and the swap of two
  /// neighbouring letters (`parnter_id`) as one step each.
  static int distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var beforePrevious = List<int>.filled(b.length + 1, 0);
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var best = [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost].reduce((x, y) => x < y ? x : y);
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          final swap = beforePrevious[j - 2] + 1;
          if (swap < best) best = swap;
        }
        current[j] = best;
      }
      beforePrevious = previous;
      previous = current;
    }
    return previous[b.length];
  }

  /// Up to [limit] of [candidates] that [name] is probably a misspelling of, nearest first, and among equally near ones
  /// in the order given. A candidate counts when it is within a third of the name's length in edit steps (at least
  /// one, at most three; none for a single character, which is close to everything), or contains the name (`partner`
  /// finds `partner_id`) or is contained in it. Case is ignored.
  static List<String> suggest(String name, Iterable<String> candidates, {int limit = 3}) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final allowed = needle.length <= 1 ? 0 : (needle.length / 3).ceil().clamp(1, 3);
    final scored = <(int, int, String)>[];
    var index = 0;
    for (final candidate in candidates) {
      final order = index++;
      final hay = candidate.toLowerCase();
      if (hay == needle) continue;
      final d = distance(needle, hay);
      if (d <= allowed) {
        scored.add((d, order, candidate));
      } else if (needle.length >= 3 && (hay.contains(needle) || (hay.length >= 3 && needle.contains(hay)))) {
        // A containment is weaker than a near miss, so it ranks after every one of them.
        scored.add((allowed + 1 + (hay.length - needle.length).abs(), order, candidate));
      }
    }
    scored.sort((x, y) {
      final byDistance = x.$1.compareTo(y.$1);
      return byDistance != 0 ? byDistance : x.$2.compareTo(y.$2);
    });
    return [for (final s in scored.take(limit)) s.$3];
  }
}
