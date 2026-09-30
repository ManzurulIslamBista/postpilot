import '../entities/git_link.dart';

/// Where the personal access token for each Git host lives (secure storage,
/// never the database and never a repository file).
abstract interface class GitCredentialsStore {
  Future<String?> readToken(GitProvider provider);
  Future<void> saveToken(GitProvider provider, String token);
  Future<void> deleteToken(GitProvider provider);
}
