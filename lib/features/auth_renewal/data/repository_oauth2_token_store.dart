import '../../collections/domain/repositories/collection_auth_repository.dart';
import '../../defaults/domain/repositories/defaults_repository.dart';
import '../../request_builder/domain/entities/request_auth.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../../request_builder/domain/services/oauth2_token_service.dart';
import '../domain/entities/auth_owner.dart';
import '../domain/repositories/oauth2_token_store.dart';
import '../domain/services/oauth2_token_manager.dart';

/// Writes a renewed token back where the Auth tab keeps one it fetched by hand: into the auth of the
/// collection (`collection_auth`), of the folder (`folder_defaults`) or of the request. The stored auth is
/// read again first and only its token fields change, so an edit made since the renewal began survives.
final class RepositoryOAuth2TokenStore implements OAuth2TokenStore {
  final RequestRepository _requests;
  final CollectionAuthRepository _collectionAuth;
  final DefaultsRepository _defaults;

  const RepositoryOAuth2TokenStore(this._requests, this._collectionAuth, this._defaults);

  @override
  Future<void> save(AuthOwner owner, RequestAuth source, OAuth2Token token) async {
    final id = owner.id;
    if (id == null) return;
    RequestAuth withToken(RequestAuth stored) =>
        stored.withOAuth2Token(token.accessToken, token.expiresAt, refreshToken: token.refreshToken ?? '');

    switch (owner.kind) {
      case AuthOwnerKind.collection:
        final stored = RequestAuth.fromJsonString(await _collectionAuth.getAuthJson(id));
        if (stored == null || !OAuth2TokenManager.sameConfig(stored, source)) return;
        await _collectionAuth.setAuthJson(id, withToken(stored).toJsonString());
      case AuthOwnerKind.folder:
        final level = await _defaults.getFolder(id);
        final stored = level.auth;
        if (stored == null || !OAuth2TokenManager.sameConfig(stored, source)) return;
        await _defaults.saveFolder(id, level.withAuth(withToken(stored)));
      case AuthOwnerKind.request:
        final request = await _requests.findById(id);
        if (request == null || !OAuth2TokenManager.sameConfig(request.auth, source)) return;
        await _requests.saveRequest(request.copyWith(auth: withToken(request.auth)));
    }
  }
}
