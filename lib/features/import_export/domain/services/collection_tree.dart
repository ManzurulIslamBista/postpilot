import '../../../collections/domain/entities/collection_entity.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';

/// A request together with the "Parent / Child" path of the folder it is in
/// (null at the collection's top level).
typedef PlacedRequest = ({String? folder, ApiRequestEntity request});

abstract final class CollectionTree {
  static const _separator = ' / ';
  static const _maxDepth = 32;

  /// Every request in tree order: folders (recursively) before the requests
  /// beside them, as the sidebar and the Postman export order them. A request
  /// whose folder no longer exists comes last, at the top level.
  static List<PlacedRequest> ordered(List<FolderEntity> folders, List<ApiRequestEntity> requests) {
    final labels = _labels(folders);
    final ordered = <PlacedRequest>[];
    final placed = <ApiRequestEntity>{};
    final visited = <int>{};

    void walk(int? parentId, int depth) {
      if (depth > _maxDepth) return;
      for (final folder in folders.where((f) => f.parentFolderId == parentId)) {
        if (visited.add(folder.id)) walk(folder.id, depth + 1);
      }
      for (final request in requests.where((r) => r.folderId == parentId)) {
        if (placed.add(request)) ordered.add((folder: labels[parentId], request: request));
      }
    }

    walk(null, 0);
    for (final request in requests) {
      if (placed.add(request)) ordered.add((folder: null, request: request));
    }
    return ordered;
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
