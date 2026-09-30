import 'member_role.dart';

final class CollectionMemberEntity {
  final int collectionId;
  final String userId;
  final MemberRole role;

  const CollectionMemberEntity({required this.collectionId, required this.userId, required this.role});
}
