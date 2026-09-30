import 'member_role.dart';

final class CollectionInviteEntity {
  final int id;
  final int collectionId;
  final String email;
  final MemberRole role;
  final String invitedBy;
  final DateTime createdAt;
  final bool accepted;

  const CollectionInviteEntity({
    required this.id,
    required this.collectionId,
    required this.email,
    required this.role,
    required this.invitedBy,
    required this.createdAt,
    required this.accepted,
  });
}
