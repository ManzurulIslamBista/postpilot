import '../../../../core/database/daos/collection_auth_dao.dart';
import '../../domain/repositories/collection_auth_repository.dart';

final class CollectionAuthRepositoryImpl implements CollectionAuthRepository {
  final CollectionAuthDao _dao;
  const CollectionAuthRepositoryImpl(this._dao);

  @override
  Future<String?> getAuthJson(int collectionId) async => (await _dao.findByCollection(collectionId))?.authJson;

  @override
  Future<void> setAuthJson(int collectionId, String json) => _dao.upsert(collectionId, json);

  @override
  Stream<String?> watchAuthJson(int collectionId) => _dao.watchByCollection(collectionId).map((r) => r?.authJson);
}
