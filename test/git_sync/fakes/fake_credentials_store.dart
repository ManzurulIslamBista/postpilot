import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_credentials_store.dart';

class FakeCredentialsStore implements GitCredentialsStore {
  final tokens = <GitProvider, String>{};

  @override
  Future<String?> readToken(GitProvider provider) async => tokens[provider];

  @override
  Future<void> saveToken(GitProvider provider, String token) async => tokens[provider] = token;

  @override
  Future<void> deleteToken(GitProvider provider) async => tokens.remove(provider);
}
