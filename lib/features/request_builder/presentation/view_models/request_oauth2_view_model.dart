import 'package:flutter/foundation.dart';
import '../../domain/entities/request_auth.dart';
import '../../domain/services/oauth2_token_service.dart';
import '../../domain/usecases/build_variable_resolver_usecase.dart';

/// Drives the "Get new access token" flow for the OAuth 2.0 auth editor.
/// It never owns the [RequestAuth]: the freshly fetched token is handed back
/// through the `onToken` callback so the request (or collection) that owns
/// the auth can apply it to its own current auth and persist it.
final class RequestOAuth2ViewModel with ChangeNotifier {
  final OAuth2TokenService _tokenService;
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;

  RequestOAuth2ViewModel(this._tokenService, this._buildVariableResolverUseCase);

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

  String describeTokenStatus(RequestAuth auth) {
    if (!auth.hasOAuth2Token) return 'No token yet';
    final expiry = auth.oauth2TokenExpiry;
    if (expiry == null) return 'Token present (no expiry reported)';
    final now = DateTime.now();
    if (auth.isOAuth2TokenExpiredAt(now)) return 'Token expired';
    return 'Token valid for ${_describeDuration(expiry.difference(now))}';
  }

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
      errorMessage = e.toString();
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
    final resolver = await _buildVariableResolverUseCase(collectionId ?? 0);
    return auth.copyWith(
      oauth2AccessTokenUrl: resolver.resolve(auth.oauth2AccessTokenUrl),
      oauth2AuthorizationUrl: resolver.resolve(auth.oauth2AuthorizationUrl),
      oauth2RedirectUri: resolver.resolve(auth.oauth2RedirectUri),
      oauth2ClientId: resolver.resolve(auth.oauth2ClientId),
      oauth2ClientSecret: resolver.resolve(auth.oauth2ClientSecret),
      oauth2Scope: resolver.resolve(auth.oauth2Scope),
      oauth2Username: resolver.resolve(auth.oauth2Username),
      oauth2Password: resolver.resolve(auth.oauth2Password),
      oauth2Audience: resolver.resolve(auth.oauth2Audience),
    );
  }

  static String _describeDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
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
