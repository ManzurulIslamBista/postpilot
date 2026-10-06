import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/services/oauth2_token_service.dart';
import '../entities/auth_owner.dart';

/// Where a renewed token is kept so the next send, the next run and the Auth tab see it: back into the
/// auth of whoever owns it (the request, the folder or the collection), the place the Auth tab already
/// stores a token fetched by hand.
abstract interface class OAuth2TokenStore {
  /// Writes [token] (and its rotated refresh token) into the stored auth of [owner]. [source] is the auth
  /// the token was fetched for: when the stored auth has been changed since (another token URL, another
  /// client, another auth type) the token is not written, because it belongs to a configuration that is gone.
  Future<void> save(AuthOwner owner, RequestAuth source, OAuth2Token token);
}

/// Keeps nothing. For a run that has nowhere to write to (the command line in CI): the renewed token then
/// lives in the [OAuth2TokenManager]'s memory for as long as the run does.
final class MemoryOAuth2TokenStore implements OAuth2TokenStore {
  const MemoryOAuth2TokenStore();

  @override
  Future<void> save(AuthOwner owner, RequestAuth source, OAuth2Token token) async {}
}
