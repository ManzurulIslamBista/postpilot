import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/services/collection_order.dart';
import '../entities/api_request_entity.dart';
import 'run_selection.dart';

/// A collection as a run sees it: its folders and requests and the canonical order they run in. The runner
/// dialog draws its checkbox tree from the same object the runner then sends from, so what is ticked is what runs.
final class CollectionRunPlan {
  final List<FolderEntity> folders;

  /// Every request of the collection, in the order the repository listed them.
  final List<RequestSummaryEntity> requests;

  /// The folders and requests in canonical order; entries index into [folders] and [requests].
  final CollectionOrder order;

  const CollectionRunPlan._(this.folders, this.requests, this.order);

  /// The tree the sidebar shows: depth-first, folders and requests interleaved by their order index.
  factory CollectionRunPlan.canonical({
    required List<FolderEntity> folders,
    required List<RequestSummaryEntity> requests,
  }) => CollectionRunPlan._(
    folders,
    requests,
    CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    ),
  );

  /// Without a source of folders the repository's own order stands, as listed.
  factory CollectionRunPlan.asListed(List<RequestSummaryEntity> requests) => CollectionRunPlan._(
    const [],
    requests,
    CollectionOrder.of(requests: [for (final (i, r) in requests.indexed) (id: r.id, folderId: null, orderIndex: i)]),
  );

  /// Every request in run order.
  List<RequestSummaryEntity> get ordered => [for (final i in order.requestIndexes) requests[i]];

  /// The requests [selection] picks, in run order.
  List<RequestSummaryEntity> select(RunSelection selection) => switch (selection) {
    RunAllRequests() => ordered,
    RunFolder(:final folderId) => [for (final i in order.requestIndexesIn(folderId)) requests[i]],
    RunRequests(:final requestIds) => [for (final r in ordered) if (requestIds.contains(r.id)) r],
  };

  /// The folder names from the top down to [folderId]'s parent and itself, e.g. `Auth / Admin`.
  String folderPath(int? folderId) {
    final names = <String>[];
    var current = folderId;
    for (var guard = 0; current != null && guard < 64; guard++) {
      final folder = folders.where((f) => f.id == current).firstOrNull;
      if (folder == null) break;
      names.insert(0, folder.name);
      current = folder.parentFolderId;
    }
    return names.join(' / ');
  }
}
