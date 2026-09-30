import '../entities/sync_doc.dart';

/// Field-level comparison helpers shared by the diff and the three-way merge.
abstract final class DocFields {
  static const _leading = ['name', 'parentUid', 'order'];

  /// Deep equality through canonical JSON.
  static bool sameValue(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);

  /// An absent key is different from a key holding null.
  static bool sameEntry(Map<String, Object?> a, Map<String, Object?> b, String key) =>
      a.containsKey(key) == b.containsKey(key) && sameValue(a[key], b[key]);

  /// `name`, `parentUid`, `order` first, then the data keys alphabetically.
  static List<String> ordered(Iterable<String> keys) {
    final rest = keys.toSet();
    return [
      for (final key in _leading)
        if (rest.remove(key)) key,
      ...(rest.toList()..sort()),
    ];
  }

  /// Collection first, then folders, then requests; alphabetical inside each.
  static int compareEntries(SyncKind aKind, String aName, String aUid, SyncKind bKind, String bName, String bUid) {
    final byKind = aKind.index.compareTo(bKind.index);
    if (byKind != 0) return byKind;
    final byName = aName.toLowerCase().compareTo(bName.toLowerCase());
    if (byName != 0) return byName;
    final exact = aName.compareTo(bName);
    return exact != 0 ? exact : aUid.compareTo(bUid);
  }
}
