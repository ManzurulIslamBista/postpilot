import '../entities/api_request_entity.dart';

abstract interface class RequestRepository {
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId);
  Stream<ApiRequestEntity?> watchById(int id);
  Future<ApiRequestEntity?> findById(int id);
  Future<int> createRequest({required int collectionId, int? folderId, required String name});
  Future<void> saveRequest(ApiRequestEntity request);
  Future<void> deleteRequest(int id);
}
