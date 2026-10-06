// Pure Dart (no Flutter, no Drift): the sidebar, the collection runner, the CLI, the exports and the
// backup all ask this one file "in what order?", so they cannot disagree.

/// A folder as the ordering sees it.
typedef OrderFolder = ({int id, int? parentId, int orderIndex});

/// A request as the ordering sees it.
typedef OrderRequest = ({int id, int? folderId, int orderIndex});

/// Identifies a folder or a request (their ids come from different tables, so the kind is part of the identity).
final class OrderRef {
  final bool isFolder;
  final int id;

  const OrderRef.folder(this.id) : isFolder = true;
  const OrderRef.request(this.id) : isFolder = false;

  @override
  bool operator ==(Object other) => other is OrderRef && other.isFolder == isFolder && other.id == id;

  @override
  int get hashCode => Object.hash(isFolder, id);

  @override
  String toString() => '${isFolder ? 'folder' : 'request'}#$id';
}

/// One folder or request of a level, with the position the database stores for it.
typedef LevelItem = ({OrderRef ref, int orderIndex});

/// Where one folder or request is stored: its collection, the folder it sits in (null = top level) and its
/// index there. A move remembers the placements it replaced, so undoing it can put every one of them back.
final class Placement {
  final OrderRef ref;
  final int collectionId;
  final int? parentId;
  final int orderIndex;

  const Placement({required this.ref, required this.collectionId, required this.parentId, required this.orderIndex});

  bool sameAs(Placement other) =>
      other.ref == ref &&
      other.collectionId == collectionId &&
      other.parentId == parentId &&
      other.orderIndex == orderIndex;

  @override
  String toString() => '$ref in $collectionId/${parentId ?? '-'} at $orderIndex';
}

/// One folder or request in its canonical place.
final class OrderEntry {
  final bool isFolder;

  /// Position in the `folders` or `requests` list [CollectionOrder.of] was given, so a caller that has richer
  /// objects than [OrderFolder] / [OrderRequest] can map straight back to them.
  final int index;
  final int id;

  /// The folder this entry sits in; null at the top level. A folder or request whose folder is not in the
  /// collection (or that is caught in a parent cycle) counts as top level, which is where a restore puts it.
  final int? parentId;

  /// 0 for the top level.
  final int depth;

  const OrderEntry({
    required this.isFolder,
    required this.index,
    required this.id,
    required this.parentId,
    required this.depth,
  });

  OrderRef get ref => isFolder ? OrderRef.folder(id) : OrderRef.request(id);

  @override
  String toString() => '${isFolder ? 'folder' : 'request'}#$id@$depth';
}

/// The canonical order of a collection: a depth-first walk in which, at every level, folders and requests are
/// interleaved by their `order_index` (equal indexes: folders before requests, then the lower id, then the
/// earlier in the input) and a folder's content is listed right after it.
///
/// This is what the sidebar shows, what the collection runner and the CLI run, and what the exports write.
final class CollectionOrder {
  /// Every folder and request, depth-first.
  final List<OrderEntry> entries;

  final Map<int?, List<OrderEntry>> _children;

  const CollectionOrder._(this.entries, this._children);

  /// The empty collection.
  static const empty = CollectionOrder._([], {});

  factory CollectionOrder.of({Iterable<OrderFolder> folders = const [], Iterable<OrderRequest> requests = const []}) {
    final folderList = folders.toList();
    final requestList = requests.toList();
    final folderIds = {for (final f in folderList) f.id};

    // A parent that is not in the collection (or the folder itself) is no parent at all.
    int? parentKey(int? parent, {int? self}) => parent != null && parent != self && folderIds.contains(parent) ? parent : null;

    final children = <int?, List<_Node>>{};
    for (var i = 0; i < folderList.length; i++) {
      final f = folderList[i];
      (children[parentKey(f.parentId, self: f.id)] ??= []).add(_Node(true, i, f.id, f.orderIndex));
    }
    for (var i = 0; i < requestList.length; i++) {
      final r = requestList[i];
      (children[parentKey(r.folderId)] ??= []).add(_Node(false, i, r.id, r.orderIndex));
    }
    for (final level in children.values) {
      level.sort(_compareNodes);
    }

    final entries = <OrderEntry>[];
    final byParent = <int?, List<OrderEntry>>{};
    final placed = <(bool, int)>{};
    final expanded = <int?>{};

    void walk(int? parent, int depth) {
      // Folders sharing an id would otherwise list the same children twice.
      if (!expanded.add(parent)) return;
      for (final node in children[parent] ?? const <_Node>[]) {
        if (!placed.add((node.isFolder, node.index))) continue;
        final entry = OrderEntry(isFolder: node.isFolder, index: node.index, id: node.id, parentId: parent, depth: depth);
        entries.add(entry);
        (byParent[parent] ??= []).add(entry);
        if (node.isFolder) walk(node.id, depth + 1);
      }
    }

    walk(null, 0);

    // Folders in a parent cycle (and the ones hanging off them) are not reachable from the top. They are listed
    // there, each on its own, rather than lost; a restore has always put them at the top level too.
    final stranded = [
      for (final node in [for (final level in children.values) ...level])
        if (node.isFolder && !placed.contains((true, node.index))) node,
    ]..sort(_compareNodes);
    for (final node in stranded) {
      placed.add((true, node.index));
      final entry = OrderEntry(isFolder: true, index: node.index, id: node.id, parentId: null, depth: 0);
      entries.add(entry);
      (byParent[null] ??= []).add(entry);
    }
    for (final node in stranded) {
      walk(node.id, 1);
    }

    return CollectionOrder._(List.unmodifiable(entries), {for (final e in byParent.entries) e.key: List.unmodifiable(e.value)});
  }

  /// The folders and requests that sit directly in [folderId] (null = top level), in order.
  List<OrderEntry> childrenOf(int? folderId) => _children[folderId] ?? const [];

  Iterable<OrderEntry> get folders => entries.where((e) => e.isFolder);
  Iterable<OrderEntry> get requests => entries.where((e) => !e.isFolder);

  /// Indexes into the `requests` list given to [CollectionOrder.of], in run order.
  List<int> get requestIndexes => [for (final e in entries) if (!e.isFolder) e.index];

  /// Indexes into the `folders` list given to [CollectionOrder.of], in tree order.
  List<int> get folderIndexes => [for (final e in entries) if (e.isFolder) e.index];

  /// [folderId] and every folder nested under it, at any depth; empty when there is no such folder.
  Set<int> folderSubtree(int folderId) {
    final ids = <int>{};
    void collect(int id) {
      if (!ids.add(id)) return;
      for (final child in childrenOf(id)) {
        if (child.isFolder) collect(child.id);
      }
    }

    if (!entries.any((e) => e.isFolder && e.id == folderId)) return ids;
    collect(folderId);
    return ids;
  }

  /// Indexes (into the `requests` list given to [CollectionOrder.of]) of the requests in [folderId] or any folder
  /// under it, in run order.
  List<int> requestIndexesIn(int folderId) {
    final subtree = folderSubtree(folderId);
    return [for (final e in entries) if (!e.isFolder && e.parentId != null && subtree.contains(e.parentId)) e.index];
  }

  /// The position of [ref] among its siblings, or -1.
  int positionOf(OrderRef ref) {
    for (final level in _children.values) {
      final at = level.indexWhere((e) => e.ref == ref);
      if (at >= 0) return at;
    }
    return -1;
  }

  /// The siblings of [ref] (itself included), in order; empty when [ref] is not in the collection.
  List<OrderEntry> siblingsOf(OrderRef ref) {
    for (final level in _children.values) {
      if (level.any((e) => e.ref == ref)) return level;
    }
    return const [];
  }

  /// Equal indexes: folders before requests, then the lower id, then the one that came first.
  static int _compareNodes(_Node a, _Node b) {
    final byIndex = a.orderIndex.compareTo(b.orderIndex);
    if (byIndex != 0) return byIndex;
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    final byId = a.id.compareTo(b.id);
    return byId != 0 ? byId : a.index.compareTo(b.index);
  }

  // ---- one level, for the code that changes the stored indexes ----

  /// [items] of one level in canonical order.
  static List<LevelItem> sortLevel(Iterable<LevelItem> items) {
    final indexed = [for (final (i, item) in items.indexed) (i, item)];
    indexed.sort((a, b) {
      final x = a.$2;
      final y = b.$2;
      final byIndex = x.orderIndex.compareTo(y.orderIndex);
      if (byIndex != 0) return byIndex;
      if (x.ref.isFolder != y.ref.isFolder) return x.ref.isFolder ? -1 : 1;
      final byId = x.ref.id.compareTo(y.ref.id);
      return byId != 0 ? byId : a.$1.compareTo(b.$1);
    });
    return [for (final (_, item) in indexed) item];
  }

  /// Whether two siblings of [level] share an index, which leaves their order resting on the tie-break alone.
  static bool hasTies(Iterable<LevelItem> level) {
    final seen = <int>{};
    return level.any((item) => !seen.add(item.orderIndex));
  }

  /// The level's refs once [moved] sits immediately before [before] (at the end when [before] is null or is no
  /// longer in the level; untouched when it is [moved] itself). [moved] may come from another level: it is simply
  /// inserted.
  static List<OrderRef> placed(Iterable<LevelItem> level, OrderRef moved, {OrderRef? before}) {
    final sorted = [for (final item in sortLevel(level)) item.ref];
    // Dropped in front of itself: it stays where it is.
    if (before == moved && sorted.contains(moved)) return sorted;
    final rest = [for (final ref in sorted) if (ref != moved) ref];
    final at = before == null ? -1 : rest.indexOf(before);
    return [...rest]..insert(at < 0 ? rest.length : at, moved);
  }

  /// Where [item] has to go to move one step ([delta] -1 up, +1 down) among [siblings] (canonical order):
  /// `before` is the sibling to place it in front of (null = the end). `canMove` is false at either end.
  static ({bool canMove, OrderRef? before}) step(List<OrderRef> siblings, OrderRef item, int delta) {
    final at = siblings.indexOf(item);
    if (at < 0) return (canMove: false, before: null);
    if (delta < 0) return at == 0 ? (canMove: false, before: null) : (canMove: true, before: siblings[at - 1]);
    if (at >= siblings.length - 1) return (canMove: false, before: null);
    return (canMove: true, before: at + 2 < siblings.length ? siblings[at + 2] : null);
  }
}

final class _Node {
  final bool isFolder;
  final int index;
  final int id;
  final int orderIndex;
  const _Node(this.isFolder, this.index, this.id, this.orderIndex);
}
