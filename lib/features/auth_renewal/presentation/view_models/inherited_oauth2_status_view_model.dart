import 'package:flutter/foundation.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../domain/entities/auth_owner.dart';
import '../../domain/services/oauth2_token_manager.dart';

/// Behind the OAuth 2.0 status line of a request that inherits its auth: the "Renew now" button renews the
/// token of the level that owns the auth (the collection or a folder) and writes it back there.
final class InheritedOAuth2StatusViewModel with ChangeNotifier {
  final OAuth2TokenManager _manager;
  final BuildVariableResolverUseCase _buildVariableResolver;

  InheritedOAuth2StatusViewModel(this._manager, this._buildVariableResolver);

  bool isRenewing = false;
  String? errorMessage;
  bool _disposed = false;

  /// [auth] is the inherited auth as stored; [owner] says where the renewed token is written back.
  Future<void> renew(RequestAuth auth, AuthOwner owner, {required int collectionId, int? folderId}) async {
    if (isRenewing) return;
    isRenewing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final resolver = await _buildVariableResolver(collectionId, folderId: folderId);
      await _manager.ensureFresh(auth, owner: owner, resolver: resolver, force: true);
    } on Exception catch (e) {
      errorMessage = SecretMasker.maskMessage(e.toString());
    }
    isRenewing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
