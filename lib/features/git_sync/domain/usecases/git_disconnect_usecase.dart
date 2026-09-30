import '../../../../core/usecases/usecase.dart';
import '../repositories/git_link_repository.dart';

/// Removes the link (parameter: collection id). The local collection and the repository stay untouched.
final class GitDisconnectUseCase implements UseCase<void, int> {
  final GitLinkRepository _links;
  const GitDisconnectUseCase(this._links);

  @override
  Future<void> call(int params) => _links.remove(params);
}
