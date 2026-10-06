import '../../../request_builder/domain/entities/key_value_item.dart';

/// How headers pile up from the collection down to a request. The same rule
/// everywhere: the request builder, the code snippets, the CLI, the exports.
///
///  * Levels apply outermost first: the collection, each folder from the top
///    one down, then the request. The result lists them in that order.
///  * A header name is compared without regard to case (and ignoring spaces
///    around it). The most specific level that mentions a name decides it: its
///    enabled rows are sent, and the same name from a level above is dropped.
///  * A disabled row only ever takes headers away: when it is the most specific
///    mention of its name, the name is not sent at all. That is how an inner
///    folder or a request switches off a header it inherits. A disabled row
///    with nothing above it to switch off changes nothing.
///
/// A level may repeat a name (several `Set-Cookie`-style rows); all of its
/// enabled rows are kept, only other levels' rows of that name are replaced.
abstract final class HeaderInheritance {
  /// The enabled rows that survive, outermost level first, each with the index
  /// (into [levels]) of the level it comes from. [nameOf] turns a row's key into
  /// the name compared (the request builder passes the key with its
  /// `{{variables}}` resolved); a row whose name is empty is skipped.
  static List<({int level, KeyValueItem item})> mergeWithLevels(
    List<List<KeyValueItem>> levels, {
    String Function(String key)? nameOf,
  }) {
    final name = nameOf ?? _same;
    final kept = List.generate(levels.length, (_) => <KeyValueItem>[]);
    final claimed = <String>{};
    for (var level = levels.length - 1; level >= 0; level--) {
      final mentioned = <String>{};
      for (final item in levels[level]) {
        final raw = name(item.key);
        if (raw.isEmpty) continue;
        final normal = _normal(raw);
        mentioned.add(normal);
        if (item.enabled && !claimed.contains(normal)) kept[level].add(item);
      }
      claimed.addAll(mentioned);
    }
    return [
      for (var level = 0; level < levels.length; level++)
        for (final item in kept[level]) (level: level, item: item),
    ];
  }

  /// [mergeWithLevels] without the level indexes.
  static List<KeyValueItem> merge(List<List<KeyValueItem>> levels, {String Function(String key)? nameOf}) => [
        for (final row in mergeWithLevels(levels, nameOf: nameOf)) row.item,
      ];

  /// The rows a request effectively carries once what it [inherited] (already
  /// merged, see [merge]) is combined with its [own]: written out, for the
  /// exports that have no header inheritance of their own. Own rows keep their
  /// enabled flag, so a request that switches an inherited header off still
  /// shows its disabled row.
  static List<KeyValueItem> materialize(List<KeyValueItem> inherited, List<KeyValueItem> own) {
    final ownNames = {
      for (final item in own)
        if (item.key.isNotEmpty) _normal(item.key),
    };
    return [
      for (final item in inherited)
        if (!ownNames.contains(_normal(item.key))) item,
      ...own,
    ];
  }

  static String _same(String key) => key;

  static String _normal(String name) => name.trim().toLowerCase();
}
