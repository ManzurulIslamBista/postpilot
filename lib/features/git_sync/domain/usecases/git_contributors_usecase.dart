import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_results.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

/// Contributors of the linked repository (parameter: collection id) - the team, as far as Git knows it.
final class GitContributorsUseCase implements UseCase<List<GitContributor>, int> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  const GitContributorsUseCase(this._links, this._host);

  @override
  Future<List<GitContributor>> call(int params) async => _host.listContributors((await _links.requireLink(params)).repo);
}
