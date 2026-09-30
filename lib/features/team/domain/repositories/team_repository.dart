import '../entities/cloud_collection_entity.dart';
import '../entities/cloud_folder_entity.dart';
import '../entities/cloud_request_entity.dart';
import '../entities/collection_invite_entity.dart';
import '../entities/collection_member_entity.dart';
import '../entities/member_role.dart';

abstract interface class TeamRepository {
  /// Collections the current user is a member of (owner, editor or viewer).
  Future<List<CloudCollectionEntity>> listMyCollections();
  Future<CloudCollectionEntity> createCollection(String name);
  Future<void> renameCollection(int collectionId, String name);
  Future<void> deleteCollection(int collectionId);

  Stream<List<CollectionMemberEntity>> watchMembers(int collectionId);
  Future<void> inviteMember(int collectionId, String email, MemberRole role);
  Future<void> removeMember(int collectionId, String userId);
  Future<void> updateMemberRole(int collectionId, String userId, MemberRole role);

  /// Pending invites addressed to the current user's own email.
  Future<List<CollectionInviteEntity>> listMyPendingInvites();
  Future<void> acceptInvite(int inviteId);

  /// Every invite sent for [collectionId]. RLS only grants this to the
  /// collection owner; other members get an empty list, not an error.
  Future<List<CollectionInviteEntity>> listCollectionInvites(int collectionId);

  Stream<List<CloudFolderEntity>> watchFolders(int collectionId);
  Future<void> createFolder(int collectionId, String name, {int? parentFolderId});

  /// The folder and request writes below ([renameFolder], [deleteFolder],
  /// [updateRequest], [moveRequest], [deleteRequest]) throw a
  /// `NotFoundException` when no row was affected: PostgREST answers 2xx for a
  /// row that is gone or that RLS hides, so a missing error isn't success.
  Future<void> renameFolder(int folderId, String name);

  /// Also deletes every sub-folder and request inside it (FK cascade).
  Future<void> deleteFolder(int folderId);

  Stream<List<CloudRequestEntity>> watchRequests(int collectionId);

  /// Creates a request with just a [name] — method/url/headers/body all get
  /// the schema's own empty defaults ('GET', '', `[]`, `{"type":"none"}`).
  /// Returns the stored row so the caller can start editing it right away.
  Future<CloudRequestEntity> createRequest(int collectionId, String name, {int? folderId});

  /// Writes only the columns of [request] that differ from [base] (every
  /// column when [base] is null), so an editor working from a stale snapshot
  /// can't overwrite a teammate's edit to a field it never touched.
  Future<void> updateRequest(CloudRequestEntity request, {CloudRequestEntity? base});
  Future<void> moveRequest(int requestId, int? folderId);
  Future<void> deleteRequest(int requestId);
}
