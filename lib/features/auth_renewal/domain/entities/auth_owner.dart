import '../../../defaults/domain/entities/defaults_origin.dart';

enum AuthOwnerKind { request, folder, collection }

/// Whose auth a token belongs to: the request that holds an OAuth 2.0 auth of its own, or the folder or
/// collection a request inherits it from. It says where a renewed token is written back, and which
/// requests share one renewal (every request below a collection's auth shares that one token).
final class AuthOwner {
  final AuthOwnerKind kind;

  /// The request's, folder's or collection's id; null in a workspace file, where ids mean nothing.
  final int? id;

  /// Identifies the owner for as long as the process lives: `request:12`, `folder:3`, `collection:Shop`.
  final String key;

  /// For messages: `collection "Shop"`.
  final String label;

  const AuthOwner._(this.kind, this.id, this.key, this.label);

  factory AuthOwner.request(int id, String name) =>
      AuthOwner._(AuthOwnerKind.request, id, 'request:$id', 'request "$name"');

  factory AuthOwner.folder(int id, String name) =>
      AuthOwner._(AuthOwnerKind.folder, id, 'folder:$id', name.trim().isEmpty ? 'folder' : 'folder "$name"');

  factory AuthOwner.collection(int id, String name) => AuthOwner._(
        AuthOwnerKind.collection,
        id,
        'collection:$id',
        name.trim().isEmpty ? 'collection' : 'collection "$name"',
      );

  /// An owner of a workspace file, told apart by [scope] (the collection's name plus a folder's file-local id).
  factory AuthOwner.named(AuthOwnerKind kind, String scope, String label) => AuthOwner._(kind, null, '${kind.name}:$scope', label);

  /// The owner of the auth a request is sent with: its own when it sets one, else the level that
  /// [origin] says set the inherited one. [collectionId] is where an inherited auth comes from when
  /// the defaults are not known (the collection's auth is then the only one that can apply).
  static AuthOwner of({
    required bool ownsAuth,
    required int requestId,
    required String requestName,
    required int collectionId,
    required String collectionName,
    DefaultsOrigin? origin,
  }) {
    if (ownsAuth) return AuthOwner.request(requestId, requestName);
    if (origin != null && origin.isFolder && origin.id != null) return AuthOwner.folder(origin.id!, origin.name);
    return AuthOwner.collection(origin?.id ?? collectionId, origin?.name ?? collectionName);
  }

  @override
  bool operator ==(Object other) => other is AuthOwner && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
