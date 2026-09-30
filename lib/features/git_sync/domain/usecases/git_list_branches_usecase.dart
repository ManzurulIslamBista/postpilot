import '../../../../core/usecases/usecase.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

/// Branch names of the linked repository (parameter: collection id).
final class GitListBranchesUseCase implements UseCase<List<String>, int> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  const GitListBranchesUseCase(this._links, this._host);

  @override
  Future<List<String>> call(int params) async => _host.listBranches((await _links.requireLink(params)).repo);
}
