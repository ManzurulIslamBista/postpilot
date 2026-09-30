import 'git_link.dart';
import 'sync_doc.dart';

enum DocChangeType { added, modified, deleted }

/// One entity that differs between the local working state and the last
/// state shared with the repository.
final class DocChange {
  final String uid;
  final SyncKind kind;
  final String name;
  final DocChangeType type;

  /// Field names that differ (`name`, `url`, `headers`, ...); empty for
  /// added/deleted.
  final List<String> changedFields;

  const DocChange({
    required this.uid,
    required this.kind,
    required this.name,
    required this.type,
    this.changedFields = const [],
  });
}

/// Basic facts about a repository the token can see.
final class GitRepoInfo {
  final String defaultBranch;

  /// The token may push to it. False = read-only (viewer).
  final bool canPush;
  final bool isPrivate;

  /// No commits yet (has no branches).
  final bool isEmpty;

  const GitRepoInfo({
    required this.defaultBranch,
    required this.canPush,
    required this.isPrivate,
    required this.isEmpty,
  });
}

final class GitCommitInfo {
  final String sha;
  final String message;
  final String authorName;
  final DateTime date;
  final String? url;

  const GitCommitInfo({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.date,
    this.url,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  /// First line of the message.
  String get title => message.split('\n').first;
}

final class GitContributor {
  final String login;
  final int contributions;
  final String? avatarUrl;
  final String? profileUrl;

  const GitContributor({required this.login, required this.contributions, this.avatarUrl, this.profileUrl});
}

/// Files of a commit under a path prefix, as Git blob shas (no contents).
final class RemoteTree {
  final String commitSha;

  /// Full repository path -> blob sha.
  final Map<String, String> blobShaByPath;

  const RemoteTree({required this.commitSha, required this.blobShaByPath});
}

/// Local working state vs the last synced state, plus (optionally) whether
/// the remote branch has moved on.
final class GitStatus {
  final GitLink link;
  final GitRepoInfo? repoInfo;
  final List<DocChange> localChanges;

  /// Head of the remote branch; null when the remote was not checked.
  final String? remoteHeadSha;

  /// True when [remoteHeadSha] differs from `link.lastSyncedSha`; null when
  /// the remote was not checked.
  final bool? behind;

  const GitStatus({
    required this.link,
    required this.localChanges,
    this.repoInfo,
    this.remoteHeadSha,
    this.behind,
  });

  bool get hasLocalChanges => localChanges.isNotEmpty;

  /// Unknown access counts as writable so the UI only blocks on a known "no".
  bool get canPush => repoInfo?.canPush ?? true;
}

enum ConflictKind { bothModified, deletedLocallyModifiedRemotely, modifiedLocallyDeletedRemotely }

enum ConflictChoice { local, remote }

/// One field both sides changed differently since the last sync.
final class FieldConflict {
  final String field;
  final Object? base;
  final Object? local;
  final Object? remote;

  const FieldConflict({required this.field, this.base, this.local, this.remote});
}

/// One entity the merge could not settle on its own.
final class SyncConflict {
  final String uid;
  final SyncKind kind;
  final String name;
  final ConflictKind type;

  /// The clashing fields; empty for the delete-vs-modify kinds.
  final List<FieldConflict> fields;

  const SyncConflict({
    required this.uid,
    required this.kind,
    required this.name,
    required this.type,
    this.fields = const [],
  });
}

/// The user's decision per conflicting entity uid: keep the local or the
/// remote version of every clashing field (for delete-vs-modify: keep the
/// side that has the entity).
typedef ConflictResolutions = Map<String, ConflictChoice>;

sealed class PullResult {
  const PullResult();
}

final class PullUpToDate extends PullResult {
  const PullUpToDate();
}

/// Remote changes were merged into the local collection.
final class PullApplied extends PullResult {
  final int added;
  final int updated;
  final int deleted;

  /// Local request ids the caller should reload / close in open tabs.
  final List<int> changedRequestIds;
  final List<int> deletedRequestIds;

  const PullApplied({
    required this.added,
    required this.updated,
    required this.deleted,
    this.changedRequestIds = const [],
    this.deletedRequestIds = const [],
  });
}

/// The merge needs decisions; call the pull again with `resolutions`.
final class PullConflicts extends PullResult {
  final List<SyncConflict> conflicts;
  const PullConflicts(this.conflicts);
}

final class PushResult {
  final String commitSha;
  final String commitUrl;
  final int changedFiles;

  const PushResult({required this.commitSha, required this.commitUrl, required this.changedFiles});
}
