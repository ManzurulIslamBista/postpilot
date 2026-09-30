import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

final class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _client;
  const AuthRepositoryImpl(this._client);

  @override
  AppUserEntity? get currentUser => _toEntity(_client.auth.currentUser);

  @override
  Stream<AppUserEntity?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((state) => _toEntity(state.session?.user));

  @override
  Future<void> signUp(String email, String password) async {
    final response = await _client.auth.signUp(email: email, password: password);
    if (response.session == null) {
      throw const EmailConfirmationRequiredException();
    }
  }

  @override
  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() => _client.auth.signOut();

  AppUserEntity? _toEntity(User? user) => user == null ? null : AppUserEntity(id: user.id, email: user.email ?? '');
}
