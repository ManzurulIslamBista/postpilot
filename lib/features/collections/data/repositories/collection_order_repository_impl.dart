import '../../../../core/database/daos/collections_dao.dart';
import '../../domain/entities/move_receipt.dart';
import '../../domain/repositories/collection_order_repository.dart';
import '../../domain/services/collection_order.dart';

final class CollectionOrderRepositoryImpl implements CollectionOrderRepository {
  final CollectionsDao _dao;
  const CollectionOrderRepositoryImpl(this._dao);

  @override
  Future<MoveReceipt> moveRequest(int requestId, {required int collectionId, int? folderId, OrderRef? before}) async {
    final replaced = await _dao.moveRequest(requestId, collectionId: collectionId, folderId: folderId, before: before);
    return _receipt(replaced, OrderRef.request(requestId), collectionId);
  }

  @override
  Future<MoveReceipt> moveFolder(int folderId, {required int collectionId, int? parentFolderId, OrderRef? before}) async {
    final replaced = await _dao.moveFolder(
      folderId,
      collectionId: collectionId,
      parentFolderId: parentFolderId,
      before: before,
    );
    return _receipt(replaced, OrderRef.folder(folderId), collectionId);
  }

  @override
  Future<void> undo(MoveReceipt receipt) => _dao.restorePlacements(receipt.replaced);

  @override
  Future<int> normalize(int collectionId) => _dao.normalizeOrder(collectionId);

  MoveReceipt _receipt(List<Placement> replaced, OrderRef moved, int collectionId) => MoveReceipt(
        replaced: replaced,
        changedCollection: replaced.any((p) => p.ref == moved && p.collectionId != collectionId),
      );
}
