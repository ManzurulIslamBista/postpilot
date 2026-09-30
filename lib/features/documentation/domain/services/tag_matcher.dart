import '../../../collections/domain/entities/collection_entity.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';

/// Decides which requests a tag filter shows.
abstract final class TagMatcher {
  /// Ids of the requests that carry one of [selected] (lower-case tag names),
  /// themselves or through an enclosing folder or their collection: tagging a
  /// folder tags everything inside it.
  static Set<int> matchingRequestIds({
    required Set<String> selected,
    required Map<int, List<String>> requestTags,
    required Map<int, List<String>> folderTags,
    required Map<int, List<String>> collectionTags,
    required Map<int, List<FolderEntity>> foldersByCollection,
    required Map<int, List<RequestSummaryEntity>> requestsByCollection,
  }) {
    bool hit(List<String>? tags) => tags != null && tags.any((tag) => selected.contains(tag.toLowerCase()));

    final matches = <int>{};
    for (final entry in requestsByCollection.entries) {
      final collectionHit = hit(collectionTags[entry.key]);
      final folders = {for (final folder in foldersByCollection[entry.key] ?? const <FolderEntity>[]) folder.id: folder};

      bool folderHit(int? folderId) {
        final visited = <int>{};
        for (var id = folderId; id != null && visited.add(id); id = folders[id]?.parentFolderId) {
          if (hit(folderTags[id])) return true;
        }
        return false;
      }

      for (final request in entry.value) {
        if (collectionHit || hit(requestTags[request.id]) || folderHit(request.folderId)) matches.add(request.id);
      }
    }
    return matches;
  }
}
