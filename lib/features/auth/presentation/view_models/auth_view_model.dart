import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

final class AuthViewModel with ChangeNotifier {
  final AuthRepository _authRepository;
  late final StreamSubscription<AppUserEntity?> _authSubscription;

  AuthViewModel(this._authRepository) {
    currentUser = _authRepository.currentUser;
    _authSubscription = _authRepository.authStateChanges.listen((user) {
      currentUser = user;
      notifyListeners();
    });
  }

  AppUserEntity? currentUser;
  bool isLoading = false;
  String? errorMessage;

  /// One-off status text for a successful [signUp]/[signIn] (e.g. "Signed
  /// in" or "Check your email to confirm your account"), meant to be shown
  /// once — via a SnackBar — right after the call resolves. `null` when the
  /// call failed; check [errorMessage] in that case.
  String? infoMessage;

  Future<void> signUp(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _authRepository.signUp(email, password);
      infoMessage = 'Signed in';
    } on EmailConfirmationRequiredException {
      infoMessage = 'Check your email to confirm your account';
    } catch (e) {
      errorMessage = _describeError(e);
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _authRepository.signIn(email, password);
      infoMessage = 'Signed in';
    } catch (e) {
      errorMessage = _describeError(e);
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    isLoading = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _authRepository.signOut();
    } catch (e) {
      errorMessage = _describeError(e);
    }
    isLoading = false;
    notifyListeners();
  }

  /// Translates the exceptions [AuthRepositoryImpl] lets through (Supabase's
  /// own [AuthException] hierarchy) into short, human-readable text.
  String _describeError(Object error) {
    if (error is AuthApiException) {
      switch (error.code) {
        case 'invalid_credentials':
          return 'Incorrect email or password';
        case 'email_not_confirmed':
          return 'Check your email to confirm your account before signing in';
        case 'user_already_exists':
        case 'email_exists':
          return 'An account with this email already exists';
        case 'weak_password':
          return 'Password is too weak — use at least 6 characters';
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
          return 'Too many attempts — please wait a moment and try again';
        default:
          return error.message;
      }
    }
    if (error is AuthException) {
      return error.message;
    }
    return 'Something went wrong — please try again';
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
