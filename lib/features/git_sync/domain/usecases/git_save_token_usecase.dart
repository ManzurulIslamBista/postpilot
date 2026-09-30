import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../repositories/git_credentials_store.dart';
import '../repositories/git_host_client.dart';

final class GitTokenParams {
  final GitProvider provider;
  final String token;
  const GitTokenParams({required this.provider, required this.token});
}

/// Stores the token in secure storage, asks the host who it belongs to and returns that login; if the host rejects the token it is deleted again and a GitAuthException is thrown.
final class GitSaveTokenUseCase implements UseCase<String, GitTokenParams> {
  final GitCredentialsStore _credentials;
  final GitHostClient _host;
  const GitSaveTokenUseCase(this._credentials, this._host);

  @override
  Future<String> call(GitTokenParams params) async {
    final token = params.token.trim();
    if (token.isEmpty) throw const GitAuthException('Enter an access token.');
    final previous = await _credentials.readToken(params.provider);
    await _credentials.saveToken(params.provider, token);
    try {
      return await _host.getAuthenticatedLogin();
    } catch (_) {
      if (previous == null) {
        await _credentials.deleteToken(params.provider);
      } else {
        await _credentials.saveToken(params.provider, previous);
      }
      rethrow;
    }
  }
}
