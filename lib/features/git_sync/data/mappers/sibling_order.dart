import '../../domain/entities/sync_doc.dart';

/// How the position of a folder or request among its siblings (`SyncDoc.order`)
/// relates to the `order_index` column.
///
/// The app never assigns `order_index`: siblings tie at 0 and are listed in the
/// order they were created (row id). A doc that copied the column would carry
/// no order at all, so a clone on another device would list the siblings
/// alphabetically. Instead a doc's order is derived from the whole sibling
/// group, and applying docs keeps the column at 0 wherever creation order
/// already says the same, so a request added later on a clone still lands at
/// the end.
abstract final class SiblingOrder {
  /// The order every entity of one sibling group gets as a doc: its
  /// `order_index`, raised where needed so that no two siblings share an order.
  /// Ties are ranked by row id (creation order). Distinct explicit values stay
  /// as they are.
  static Map<int, int> positions(Iterable<({int id, int orderIndex})> siblings) {
    final sorted = [...siblings]..sort((a, b) {
        final byColumn = a.orderIndex.compareTo(b.orderIndex);
        return byColumn != 0 ? byColumn : a.id.compareTo(b.id);
      });
    final positions = <int, int>{};
    int? previous;
    for (final sibling in sorted) {
      final position = previous == null || sibling.orderIndex > previous ? sibling.orderIndex : previous + 1;
      positions[sibling.id] = position;
      previous = position;
    }
    return positions;
  }

  /// The `order_index` to write for each of [siblings] (docs of one sibling
  /// group): 0 for the leading docs whose order is just their place in the
  /// list, which rows created in that order already have; the doc's own order
  /// from the first doc that is not in its place on.
  static Map<String, int> columnValues(Iterable<SyncDoc> siblings) {
    final sorted = [...siblings]..sort(compare);
    final values = <String, int>{};
    var inPlace = true;
    for (var i = 0; i < sorted.length; i++) {
      inPlace = inPlace && sorted[i].order == i;
      values[sorted[i].uid] = inPlace ? 0 : sorted[i].order;
    }
    return values;
  }

  /// Siblings by order; equal orders by name, then uid, so every device lists
  /// (and creates) them the same way.
  static int compare(SyncDoc a, SyncDoc b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.uid.compareTo(b.uid);
  }
}
