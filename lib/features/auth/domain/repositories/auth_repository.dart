import '../entities/app_user_entity.dart';

abstract interface class AuthRepository {
  AppUserEntity? get currentUser;
  Stream<AppUserEntity?> get authStateChanges;
  Future<void> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

/// Thrown by [AuthRepository.signUp] when the Supabase project has email
/// confirmation enabled: the account was created but no session is active
/// until the user clicks the confirmation link sent to their email.
final class EmailConfirmationRequiredException implements Exception {
  const EmailConfirmationRequiredException();
}
