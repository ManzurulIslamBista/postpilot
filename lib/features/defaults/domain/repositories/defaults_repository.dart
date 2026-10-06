import '../entities/defaults_chain.dart';
import '../entities/level_defaults.dart';

/// Reads and writes what a collection and its folders pass down to their requests.
abstract interface class DefaultsRepository {
  /// Every level of [collectionId] in one read: the collection's headers and tests (and its auth,
  /// from `collection_auth`), and each folder's defaults with the folder tree that orders them. A
  /// collection or folder that never had any defaults is simply empty; there is nothing to create first.
  Future<DefaultsTree> loadTree(int collectionId);

  /// The collection's own headers and tests, without its auth and variables, which have their own
  /// repositories (see [LevelDefaults]).
  Future<LevelDefaults> getCollection(int collectionId);

  /// Saves the collection's headers and tests; its auth and variables are not touched. A collection
  /// with neither keeps no row.
  Future<void> saveCollection(int collectionId, LevelDefaults defaults);

  Future<LevelDefaults> getFolder(int folderId);

  /// Saves everything a folder holds. A folder that sets nothing keeps no row.
  Future<void> saveFolder(int folderId, LevelDefaults defaults);

  /// The folder [requestId] is in right now: what is stored, which differs from what an open tab
  /// remembers once the request has been moved. [fallback] when the request is not stored.
  Future<int?> currentFolderId(int requestId, {int? fallback});

  /// Fires whenever what [loadTree] returns for [collectionId] may have changed: a default of the
  /// collection or one of its folders, its auth, or the folder tree. A listener may get several
  /// events for one edit and should coalesce.
  Stream<void> changes(int collectionId);
}
