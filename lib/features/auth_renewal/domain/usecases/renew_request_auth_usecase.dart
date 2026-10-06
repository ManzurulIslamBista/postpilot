import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/usecases/prepare_request_usecase.dart';
import '../entities/auth_owner.dart';
import '../services/oauth2_token_manager.dart';

/// The step between "the request is prepared" and "the request is sent": when it is sent with OAuth 2.0,
/// make sure the token is there and not about to expire (see [OAuth2TokenManager]). The auth it returns
/// replaces the one the request was prepared with.
final class RenewRequestAuthUseCase {
  final OAuth2TokenManager _manager;
  const RenewRequestAuthUseCase(this._manager);

  /// Throws [OAuth2RenewalException] when a token is needed and cannot be had; the request must not be sent.
  Future<TokenRenewal> call(ApiRequestEntity request, PreparedRequest prepared) {
    final auth = prepared.auth;
    if (auth.type != AuthType.oauth2) return Future.value(TokenRenewal.none(auth));
    final scopes = prepared.inherited?.chain.scopes ?? const [];
    final owner = AuthOwner.of(
      ownsAuth: request.auth.type != AuthType.inherit,
      requestId: request.id,
      requestName: request.name,
      collectionId: request.collectionId,
      collectionName: scopes.isEmpty ? '' : scopes.first.origin.name,
      origin: prepared.inherited?.authOrigin,
    );
    return _manager.ensureFresh(auth, owner: owner, resolver: prepared.resolver);
  }
}
