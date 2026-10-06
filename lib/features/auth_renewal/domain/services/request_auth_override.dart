import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';

/// Puts a renewed [RequestAuth] in the place the request builder reads the auth in force from, so a
/// request is built again with the new token whoever owns the auth.
abstract final class RequestAuthOverride {
  /// The request and the inherited auth to build with so that [auth] is the one that applies: the
  /// inherited auth takes it for a request that inherits, the request itself for one that has its own.
  static (ApiRequestEntity, RequestAuth?) apply(ApiRequestEntity request, RequestAuth? inheritedAuth, RequestAuth auth) =>
      request.auth.type == AuthType.inherit ? (request, auth) : (request.copyWith(auth: auth), inheritedAuth);
}
