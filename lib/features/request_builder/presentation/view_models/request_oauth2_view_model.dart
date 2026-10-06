import 'package:flutter/foundation.dart';
import '../../../auth_renewal/domain/services/oauth2_token_manager.dart';
import '../../../auth_renewal/domain/services/token_status.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../domain/entities/request_auth.dart';
import '../../domain/services/oauth2_token_service.dart';
import '../../domain/usecases/build_variable_resolver_usecase.dart';

/// Drives the "Get new access token" flow for the OAuth 2.0 auth editor.
/// It never owns the [RequestAuth]: the freshly fetched token is handed back
/// through the `onToken` callback so the request (or collection) that owns
/// the auth can apply it to its own current auth and persist it.
///
/// [_manager] is what keeps tokens valid on every send (see [OAuth2TokenManager]); here it serves the
/// "Renew now" button, which picks the grant the same way (the refresh token when there is one, else the
/// configured grant) and says specifically what went wrong.
final class RequestOAuth2ViewModel with ChangeNotifier {
  final OAuth2TokenService _tokenService;
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;
  final OAuth2TokenManager? _manager;

  RequestOAuth2ViewModel(this._tokenService, this._buildVariableResolverUseCase, [this._manager]);

  /// The folder the auth being edited belongs to; its variables (and those of the folders above it)
  /// resolve in the token request as they do when the auth is used in a send. Set by the editor.
  int? folderId;

  bool isFetching = false;
  String? errorMessage;

  /// Set once the PKCE flow has started; the UI opens it in a browser.
  Uri? authorizationUrl;
  String? _codeVerifier;
  String? _state;
  bool _disposed = false;

  Future<void> fetchToken(RequestAuth auth, ValueChanged<OAuth2Token> onToken, {int? collectionId}) =>
      _run(onToken, () async => _tokenService.fetchToken(await _resolved(auth, collectionId)));

  Future<void> refreshToken(RequestAuth auth, ValueChanged<OAuth2Token> onToken, {int? collectionId}) =>
      _run(onToken, () async => _tokenService.refreshToken(await _resolved(auth, collectionId)));

  /// "Renew now": a new token from the refresh token when there is one, else from the configured grant.
  /// Without the manager (a test wiring) it falls back to the refresh grant.
  Future<void> renewNow(RequestAuth auth, ValueChanged<OAuth2Token> onToken, {int? collectionId}) {
    final manager = _manager;
    if (manager == null) return refreshToken(auth, onToken, collectionId: collectionId);
    return _run(onToken, () async {
      final resolver = await _buildVariableResolverUseCase(collectionId ?? 0, folderId: folderId);
      return manager.obtainNow(auth, resolver);
    });
  }

  /// Called when the token is cleared by hand: a token the app renewed and still remembers must not come back
  /// on the next send in place of the fresh one the person asked for.
  void forgetRenewedTokens() => _manager?.forgetAll();

  /// What the Auth tab shows about [auth]'s token: whether there is one, when it ends, whether it renews itself.
  TokenStatus statusOf(RequestAuth auth) => TokenStatus.of(auth, DateTime.now());

  Future<void> startAuthorizationCodeFlow(RequestAuth auth, {int? collectionId}) async {
    final pkce = _tokenService.generatePkcePair();
    final state = _tokenService.generateState();
    _codeVerifier = pkce.verifier;
    _state = state;
    errorMessage = null;
    try {
      authorizationUrl = _tokenService.buildAuthorizationUrl(
        await _resolved(auth, collectionId),
        codeChallenge: pkce.challenge,
        state: state,
      );
    } on FormatException {
      authorizationUrl = null;
      errorMessage = 'Authorization URL is not a valid URL';
    }
    notifyListeners();
  }

  /// [pasted] is what the user copied back from the browser: the bare code or
  /// the whole redirect URL.
  Future<void> exchangeAuthorizationCode(
    RequestAuth auth,
    String pasted,
    ValueChanged<OAuth2Token> onToken, {
    int? collectionId,
  }) async {
    final verifier = _codeVerifier;
    if (verifier == null) {
      _fail('Open the authorization URL first');
      return;
    }
    final response = OAuth2TokenService.parseAuthorizationInput(pasted);
    if (response.code.isEmpty) {
      _fail('No authorization code found in what was pasted');
      return;
    }
    if (response.state != null && response.state != _state) {
      _fail('That redirect is from a different sign-in attempt — open the authorization URL again');
      return;
    }
    await _run(
      onToken,
      () async => _tokenService.exchangeAuthorizationCode(
        await _resolved(auth, collectionId),
        code: response.code,
        codeVerifier: verifier,
      ),
    );
  }

  String describeTokenStatus(RequestAuth auth) => statusOf(auth).headline;

  Future<void> _run(ValueChanged<OAuth2Token> onToken, Future<OAuth2Token> Function() fetch) async {
    if (isFetching) return;
    isFetching = true;
    errorMessage = null;
    notifyListeners();

    try {
      final token = await fetch();
      // The editor that asked for this token is gone (tab left, dialog closed,
      // auth type switched), so there is no auth left to apply it to.
      if (_disposed) return;
      onToken(token);
      authorizationUrl = null;
      _codeVerifier = null;
      _state = null;
    } on Exception catch (e) {
      // A server's error text can echo what was sent to it.
      errorMessage = SecretMasker.maskMessage(e.toString());
    }

    isFetching = false;
    notifyListeners();
  }

  void _fail(String message) {
    errorMessage = message;
    notifyListeners();
  }

  /// The token request bypasses [RequestSpecBuilder], so `{{variables}}` in
  /// the OAuth fields are resolved here with the same scopes a request gets.
  /// The unresolved auth is what gets persisted. Without a collection
  /// (a request not yet saved anywhere) only environment + globals apply.
  Future<RequestAuth> _resolved(RequestAuth auth, int? collectionId) async {
    final resolver = await _buildVariableResolverUseCase(collectionId ?? 0, folderId: folderId);
    return OAuth2TokenService.resolveFields(auth, resolver);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A token request can outlive the editor that started it, and notifying a
  /// disposed [ChangeNotifier] asserts.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
