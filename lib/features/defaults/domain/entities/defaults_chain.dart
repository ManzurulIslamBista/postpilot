import '../../../collections/domain/entities/collection_entity.dart';
import 'defaults_origin.dart';
import 'level_defaults.dart';

/// One level of a [DefaultsChain] with where it is.
final class DefaultsScope {
  final DefaultsOrigin origin;
  final LevelDefaults defaults;
  const DefaultsScope(this.origin, this.defaults);
}

/// The levels a request inherits from, outermost first: the collection, then
/// each folder from the top-level one down to the folder the request is in.
/// A request with no folder has the collection alone; an empty chain (nothing
/// is known) inherits nothing.
final class DefaultsChain {
  final List<DefaultsScope> scopes;
  const DefaultsChain(this.scopes);

  static const empty = DefaultsChain([]);

  Iterable<DefaultsScope> get folders => scopes.where((s) => s.origin.isFolder);
}

/// Every level of one collection: its own defaults and those of each folder.
/// What the stores load in one go, and what a workspace file or a Git
/// snapshot is turned into, so a [chainFor] request answers the same wherever
/// the data came from.
final class DefaultsTree {
  static const _maxDepth = 64;

  final String collectionName;
  final int? collectionId;
  final LevelDefaults collection;
  final List<FolderEntity> folders;

  /// Defaults by folder id. A folder that sets nothing has no entry.
  final Map<int, LevelDefaults> folderDefaults;

  const DefaultsTree({
    required this.collectionName,
    this.collectionId,
    this.collection = LevelDefaults.empty,
    this.folders = const [],
    this.folderDefaults = const {},
  });

  static const none = DefaultsTree(collectionName: '');

  bool get isEmpty => collection.isEmpty && folderDefaults.values.every((d) => d.isEmpty);

  /// The chain for a request in [folderId] (null = the collection's top level).
  /// A folder that is not in the tree, or a parent loop in damaged data, ends
  /// the walk instead of failing: the request then inherits what could be reached.
  DefaultsChain chainFor(int? folderId) {
    final path = <FolderEntity>[];
    final byId = {for (final f in folders) f.id: f};
    var current = folderId == null ? null : byId[folderId];
    while (current != null && path.length < _maxDepth && !path.any((f) => f.id == current!.id)) {
      path.insert(0, current);
      current = current.parentFolderId == null ? null : byId[current.parentFolderId];
    }
    return DefaultsChain([
      DefaultsScope(DefaultsOrigin.collection(collectionName, id: collectionId), collection),
      for (final folder in path)
        DefaultsScope(
          DefaultsOrigin.folder(folder.name, id: folder.id),
          folderDefaults[folder.id] ?? LevelDefaults.empty,
        ),
    ]);
  }

  /// The chain for the folder [folderId] itself, [chainFor]'s levels without it:
  /// what the folder inherits from above.
  DefaultsChain chainAbove(int? folderId) {
    final scopes = chainFor(folderId).scopes;
    return DefaultsChain(scopes.sublist(0, scopes.length > 1 ? scopes.length - 1 : scopes.length));
  }
}
