import '../entities/move_receipt.dart';
import '../services/collection_order.dart';

/// Changes where folders and requests sit. Kept apart from `CollectionRepository` so that stays what it was
/// for everything that already implements it.
abstract interface class CollectionOrderRepository {
  /// Moves a request into [folderId] of [collectionId] (null = that collection's top level), immediately before
  /// [before] among the folders and requests there (at the end when null or no longer there). Both levels it
  /// touches are renumbered densely, in one transaction.
  Future<MoveReceipt> moveRequest(int requestId, {required int collectionId, int? folderId, OrderRef? before});

  /// Moves a folder with its sub-folders and requests; see [moveRequest]. Throws [MoveRefusedException] for a
  /// destination inside the folder itself.
  Future<MoveReceipt> moveFolder(int folderId, {required int collectionId, int? parentFolderId, OrderRef? before});

  /// Puts back what [receipt] replaced.
  Future<void> undo(MoveReceipt receipt);

  /// Gives levels whose siblings share an index distinct ones, in the order they are already shown in. Returns
  /// how many rows it wrote (0 when there was nothing to do).
  Future<int> normalize(int collectionId);
}
