import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_link_repository.dart';
import 'repo_layout.dart';

/// Keeps two local collections from syncing the same files of one repository branch.
abstract final class LinkOverlapGuard {
  /// Throws [GitPathOverlapException] when another link ([exceptCollectionId] is
  /// the collection being (re)connected, which may overlap its own old link) would
  /// share files with [basePath] of [repo] on [branch].
  static Future<void> requireFree(
    GitLinkRepository links, {
    required RepoRef repo,
    required String branch,
    required String basePath,
    int? exceptCollectionId,
  }) async {
    for (final other in await links.findAll()) {
      if (other.collectionId == exceptCollectionId) continue;
      final sameRepo = other.repo == repo || other.repo.fullName.toLowerCase() == repo.fullName.toLowerCase();
      if (sameRepo && other.branch == branch && RepoLayout.overlaps(other.basePath, basePath)) {
        throw GitPathOverlapException(RepoLayout.describe(basePath), RepoLayout.describe(other.basePath));
      }
    }
  }
}
