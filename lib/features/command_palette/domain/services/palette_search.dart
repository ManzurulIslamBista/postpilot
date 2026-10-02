import '../entities/palette_item.dart';
import 'fuzzy_matcher.dart';

final class PaletteHit {
  final PaletteItem item;
  final int score;

  /// Positions of the matched letters in [PaletteItem.title], or empty when the match was elsewhere.
  final List<int> titlePositions;
  const PaletteHit(this.item, this.score, this.titlePositions);
}

/// Ranks [items] for [query]: a hit in the title beats one in the subtitle or
/// keywords, which beats one in the hidden text (URL, body). With no query the
/// items come back in their given order.
abstract final class PaletteSearch {
  static List<PaletteHit> search(List<PaletteItem> items, String query, {int limit = 60}) {
    if (query.trim().isEmpty) return [for (final i in items.take(limit)) PaletteHit(i, 0, const [])];
    final hits = <PaletteHit>[];
    for (final item in items) {
      final title = FuzzyMatcher.match(query, item.title);
      var best = title == null ? null : title.score * 3;
      var positions = title?.positions ?? const <int>[];
      final side = FuzzyMatcher.match(query, '${item.subtitle} ${item.keywords.join(' ')}');
      if (side != null && (best == null || side.score * 2 > best)) {
        best = side.score * 2;
        positions = const [];
      }
      if (best == null && item.hiddenText.isNotEmpty && query.trim().length >= 2) {
        // Hidden text is only searched for a literal match: fuzzy matching a
        // whole request body would match nearly everything.
        if (item.hiddenText.toLowerCase().contains(query.trim().toLowerCase())) best = 300;
      }
      if (best != null) hits.add(PaletteHit(item, best, positions));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.item.category.index.compareTo(b.item.category.index);
    });
    return hits.take(limit).toList();
  }
}
