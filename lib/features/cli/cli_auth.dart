// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or a CI job.
import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_http_response.dart';
import '../auth_renewal/domain/entities/auth_owner.dart';
import '../defaults/domain/entities/defaults_origin.dart';
import 'workspace_runner.dart';

/// The command line's HTTP sender as an [ApiClient], so the token requests of OAuth 2.0 go out through
/// the same sender, with the same timeout and TLS choice, as the requests of the run, and the token logic
/// of the app (`OAuth2TokenService`, `OAuth2TokenManager`) is the code that runs here too.
final class CliApiClient implements ApiClient {
  final CliSend _send;
  final Duration timeout;
  final bool verifySsl;

  const CliApiClient(this._send, {required this.timeout, required this.verifySsl});

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final body = spec.body;
    final CliResponse response;
    try {
      response = await _send(CliRequest(
        method: spec.method,
        url: spec.url,
        headers: spec.headers,
        body: body is List<int> ? body : null,
        timeout: timeout,
        verifySsl: verifySsl,
      ));
    } on NetworkException {
      rethrow;
    } catch (e) {
      // The sender throws a sentence ("Can't reach the server: ...", "Timed out after 30s").
      throw NetworkException('$e', kind: NetworkErrorKind.connectionError, summary: '$e');
    }
    return ApiHttpResponse(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers,
      bodyBytes: response.bodyBytes,
      duration: response.duration,
    );
  }
}

/// Whose auth a token belongs to in a workspace file, where ids mean nothing: the collection's name, a
/// folder's file-local id, or the request's place in its collection. Told apart so that two collections
/// (or two requests) with the same name in different places never share a token.
abstract final class CliAuthOwners {
  static AuthOwner of({
    required bool ownsAuth,
    required String collection,
    required String requestPath,
    DefaultsOrigin? origin,
  }) {
    if (ownsAuth) return AuthOwner.named(AuthOwnerKind.request, '$collection/$requestPath', 'request "$requestPath"');
    if (origin != null && origin.isFolder && origin.id != null) {
      return AuthOwner.named(AuthOwnerKind.folder, '$collection:${origin.id}', origin.label);
    }
    return AuthOwner.named(AuthOwnerKind.collection, collection, 'collection "$collection"');
  }
}
