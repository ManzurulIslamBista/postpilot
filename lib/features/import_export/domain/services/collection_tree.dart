import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/services/collection_order.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';

/// A request together with the "Parent / Child" path of the folder it is in
/// (null at the collection's top level).
typedef PlacedRequest = ({String? folder, ApiRequestEntity request});

abstract final class CollectionTree {
  static const _separator = ' / ';
  static const _maxDepth = 32;

  /// Every request in the collection's canonical order (see `CollectionOrder`): depth-first, the folders and
  /// requests of a level interleaved by their order index, as the sidebar shows them and the runner sends them.
  /// A request whose folder no longer exists counts as top level.
  static List<PlacedRequest> ordered(List<FolderEntity> folders, List<ApiRequestEntity> requests) {
    final labels = _labels(folders);
    final order = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    );
    return [
      for (final entry in order.entries)
        if (!entry.isFolder) (folder: labels[entry.parentId], request: requests[entry.index]),
    ];
  }

  static Map<int, String> _labels(List<FolderEntity> folders) {
    final byId = {for (final f in folders) f.id: f};
    String label(FolderEntity folder, int depth) {
      final parent = byId[folder.parentFolderId];
      if (parent == null || depth > _maxDepth) return folder.name;
      return '${label(parent, depth + 1)}$_separator${folder.name}';
    }

    return {for (final f in folders) f.id: label(f, 0)};
  }
}
