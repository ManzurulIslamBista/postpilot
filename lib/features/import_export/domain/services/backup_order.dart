import '../../../collections/domain/services/collection_order.dart';
import 'backup_codec.dart';

/// A collection read from a backup or workspace file, in the canonical order the app shows and runs it in.
/// Pure Dart: the CLI uses it too.
extension BackupCollectionOrder on BackupCollection {
  /// The file's folders and requests in canonical order. Entries index into [folders] and [requests]. The
  /// requests have no ids in a file, so their position in [requests] is what breaks a tie.
  CollectionOrder get canonicalOrder => CollectionOrder.of(
    folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
    requests: [
      for (final (i, r) in requests.indexed) (id: i, folderId: r.request.folderId, orderIndex: r.request.orderIndex),
    ],
  );

  /// The requests in the order a run sends them.
  List<BackupRequest> get orderedRequests => [for (final i in canonicalOrder.requestIndexes) requests[i]];
}
