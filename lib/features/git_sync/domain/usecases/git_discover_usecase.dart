import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../entities/sync_doc.dart';
import '../repositories/git_host_client.dart';
import '../services/repo_layout.dart';
import '../services/sync_engine.dart';

final class GitDiscoverParams {
  final RepoRef repo;
  final String branch;
  const GitDiscoverParams({required this.repo, required this.branch});
}

/// A collection found in a repository (a folder holding collection.json).
final class DiscoveredCollection {
  final String basePath;
  final String name;
  const DiscoveredCollection({required this.basePath, required this.name});
}

/// Scans the branch for collection.json files and returns one entry per collection (name read from the file). Empty list when the repository holds none.
final class GitDiscoverUseCase implements UseCase<List<DiscoveredCollection>, GitDiscoverParams> {
  final GitHostClient _host;
  final SyncEngine _engine;
  const GitDiscoverUseCase(this._host, this._engine);

  @override
  Future<List<DiscoveredCollection>> call(GitDiscoverParams params) async {
    final info = await _host.getRepo(params.repo);
    final head = await _host.getBranchHead(params.repo, params.branch);
    if (head == null) {
      if (info.isEmpty) return const [];
      throw GitBranchMissingException(params.branch);
    }

    const marker = RepoLayout.collectionFile;
    final tree = await _host.getTree(params.repo, head);
    final candidates = {
      for (final entry in tree.blobShaByPath.entries)
        if (entry.key == marker || entry.key.endsWith('/$marker')) entry.key: entry.value,
    };
    final texts = await _engine.downloadTexts(params.repo, candidates);

    final found = <DiscoveredCollection>[];
    for (final path in candidates.keys.toList()..sort()) {
      final doc = RepoLayout.tryParseDoc(texts[path]!);
      if (doc == null || doc.kind != SyncKind.collection) continue;
      final dir = path == marker ? '' : path.substring(0, path.length - marker.length - 1);
      found.add(DiscoveredCollection(basePath: dir, name: doc.name));
    }
    return found..sort((a, b) => a.basePath.compareTo(b.basePath));
  }
}
