/// Collection-level default auth, kept as a raw JSON string: request_builder
/// owns the `RequestAuth` (de)serialization, so this layer stays format-agnostic.
abstract interface class CollectionAuthRepository {
  /// `null` when the collection has no auth configured yet.
  Future<String?> getAuthJson(int collectionId);
  Future<void> setAuthJson(int collectionId, String json);
  Stream<String?> watchAuthJson(int collectionId);
}
