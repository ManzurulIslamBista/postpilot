// Pure decision logic for where the web database is stored, kept free of any
// drift or browser import so it runs (and is tested) on the VM. The web
// connection translates drift's types to these by name.

/// Storage implementations, declared from most to least preferable. The names
/// match drift's `WasmStorageImplementation`.
enum WebStorage {
  opfsShared(WebStorageKind.opfs, runsInSharedWorker: true),
  opfsLocks(WebStorageKind.opfs),
  sharedIndexedDb(WebStorageKind.indexedDb, runsInSharedWorker: true),
  unsafeIndexedDb(WebStorageKind.indexedDb),
  inMemory(null);

  /// Where the data is kept; null when it is not persisted at all.
  final WebStorageKind? kind;

  /// Whether a *shared* worker hosts the database, which is the part of the
  /// browser [chooseWebStorage] may have to distrust.
  final bool runsInSharedWorker;

  const WebStorage(this.kind, {this.runsInSharedWorker = false});
}

/// The browser storage API that holds a database's files. The names match
/// drift's `WebStorageApi`.
enum WebStorageKind { indexedDb, opfs }

/// A database already present in the browser: where it lives and its name.
typedef ExistingWebDatabase = (WebStorageKind, String);

/// Picks where the database lives, the way drift's `WasmDatabase.open` does,
/// with one addition: when [sharedWorkersUsable] is false the shared storages
/// are never chosen.
///
/// A browser can offer shared workers yet stop them from making network
/// requests (some embedded browsers and managed-browser policies). The
/// database would then fail on its first query, when the worker tries to fetch
/// `sqlite3.wasm`, so the dedicated-worker storages are used instead.
///
/// An existing database keeps the storage API it was created with (IndexedDB
/// or OPFS), so data written earlier stays readable: `sharedIndexedDb` and
/// `unsafeIndexedDb` read the same IndexedDB files.
WebStorage chooseWebStorage({
  required String databaseName,
  required Iterable<WebStorage> available,
  required Iterable<ExistingWebDatabase> existingDatabases,
  required bool sharedWorkersUsable,
}) {
  final candidates = available.where((s) => sharedWorkersUsable || !s.runsInSharedWorker).toSet().toList()
    ..sort((a, b) => a.index.compareTo(b.index));

  final best = candidates.isEmpty ? WebStorage.inMemory : candidates.first;
  final existing = _kindOfExistingDatabase(databaseName, candidates, existingDatabases);
  if (existing == null || existing == best.kind) return best;
  return candidates.firstWhere((candidate) => candidate.kind == existing, orElse: () => best);
}

WebStorageKind? _kindOfExistingDatabase(
  String databaseName,
  List<WebStorage> candidates,
  Iterable<ExistingWebDatabase> existingDatabases,
) {
  for (final (kind, name) in existingDatabases) {
    if (name == databaseName && candidates.any((candidate) => candidate.kind == kind)) return kind;
  }
  return null;
}
