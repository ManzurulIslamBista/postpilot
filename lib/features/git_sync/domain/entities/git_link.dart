import 'sync_doc.dart';

/// Git hosts PostPilot can talk to. Each one needs a `GitHostClient`.
enum GitProvider {
  github;

  String get label => switch (this) {
        github => 'GitHub',
      };

  String get host => switch (this) {
        github => 'github.com',
      };
}

/// A repository on a Git host.
final class RepoRef {
  final GitProvider provider;
  final String owner;
  final String repo;

  const RepoRef({required this.provider, required this.owner, required this.repo});

  String get fullName => '$owner/$repo';

  /// Browser URL of the repository's home page.
  String get webUrl => 'https://${provider.host}/$owner/$repo';

  /// Where repository collaborators are managed on the host.
  String get accessSettingsUrl => '$webUrl/settings/access';

  String commitUrl(String sha) => '$webUrl/commit/$sha';

  /// Accepts `owner/repo`, `https://github.com/owner/repo(.git)` and
  /// `git@github.com:owner/repo.git`; null when [input] is none of them.
  static RepoRef? parse(String input, {GitProvider provider = GitProvider.github}) {
    var text = input.trim();
    if (text.isEmpty) return null;
    text = text.replaceFirst(RegExp(r'\.git$'), '').replaceFirst(RegExp(r'/+$'), '');
    final ssh = RegExp(r'^git@[^:]+:(.+)$').firstMatch(text);
    if (ssh != null) text = ssh.group(1)!;
    final http = RegExp(r'^https?://[^/]+/(.+)$').firstMatch(text);
    if (http != null) text = http.group(1)!;
    final parts = text.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1];
    if (!RegExp(r'^[\w.-]+$').hasMatch(owner) || !RegExp(r'^[\w.-]+$').hasMatch(repo)) return null;
    return RepoRef(provider: provider, owner: owner, repo: repo);
  }

  @override
  bool operator ==(Object other) =>
      other is RepoRef && other.provider == provider && other.owner == owner && other.repo == repo;

  @override
  int get hashCode => Object.hash(provider, owner, repo);
}

/// A local collection tied to a folder of a Git repository branch.
final class GitLink {
  /// 0 until first saved.
  final int id;
  final int collectionId;
  final RepoRef repo;
  final String branch;

  /// Folder inside the repository that holds this collection's files; ''
  /// means the repository root. No leading or trailing slash.
  final String basePath;

  /// Commit the local base snapshot corresponds to; null before the first
  /// sync (nothing pulled or pushed yet).
  final String? lastSyncedSha;
  final DateTime? lastSyncedAt;

  /// Commit credential fields (tokens, passwords, secrets) to the repository.
  /// Off by default: repositories are shared and often public.
  final bool includeSecrets;

  const GitLink({
    required this.id,
    required this.collectionId,
    required this.repo,
    required this.branch,
    required this.basePath,
    this.lastSyncedSha,
    this.lastSyncedAt,
    this.includeSecrets = false,
  });

  GitLink copyWith({
    String? branch,
    String? basePath,
    String? lastSyncedSha,
    DateTime? lastSyncedAt,
    bool? includeSecrets,
  }) =>
      GitLink(
        id: id,
        collectionId: collectionId,
        repo: repo,
        branch: branch ?? this.branch,
        basePath: basePath ?? this.basePath,
        lastSyncedSha: lastSyncedSha ?? this.lastSyncedSha,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        includeSecrets: includeSecrets ?? this.includeSecrets,
      );
}

/// What the local store remembers about the last state it shared with the
/// repository, per doc: the doc itself plus where it lived and the Git blob
/// sha of its file (lets a pull skip downloading files that did not change).
final class BaseEntry {
  final SyncDoc doc;
  final String path;
  final String blobSha;

  const BaseEntry({required this.doc, required this.path, required this.blobSha});
}
