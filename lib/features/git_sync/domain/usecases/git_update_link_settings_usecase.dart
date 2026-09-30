import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../repositories/git_link_repository.dart';
import '../services/git_hash.dart';
import '../services/secret_fields.dart';
import '../services/sync_engine.dart';

final class GitLinkSettingsParams {
  final int collectionId;
  final bool includeSecrets;
  const GitLinkSettingsParams({required this.collectionId, required this.includeSecrets});
}

/// Changes whether credential fields are committed for this link. The base is re-read under the new setting so toggling does not by itself create fake changes.
final class GitUpdateLinkSettingsUseCase implements UseCase<GitLink, GitLinkSettingsParams> {
  final GitLinkRepository _links;
  const GitUpdateLinkSettingsUseCase(this._links);

  @override
  Future<GitLink> call(GitLinkSettingsParams params) async {
    final link = await _links.requireLink(params.collectionId);
    if (link.includeSecrets == params.includeSecrets) return link;

    // Enabling needs nothing: credentials then show up as local edits ready to push.
    if (!params.includeSecrets) {
      final base = await _links.readBase(link.id);
      await _links.writeBase(link.id, {
        for (final entry in base.entries)
          entry.key: _stripped(entry.value),
      });
    }
    return _links.save(link.copyWith(includeSecrets: params.includeSecrets));
  }

  static BaseEntry _stripped(BaseEntry entry) {
    final doc = SecretFields.stripDoc(entry.doc);
    return BaseEntry(doc: doc, path: entry.path, blobSha: GitHash.blobSha(doc.canonicalText));
  }
}
