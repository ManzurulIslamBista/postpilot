import '../entities/git_link.dart';

/// Persists which collections are linked to which repository, and the base
/// snapshot (last state shared with the remote) each link is merged against.
abstract interface class GitLinkRepository {
  Future<GitLink?> findByCollection(int collectionId);

  /// Every link on this device (one per linked collection).
  Future<List<GitLink>> findAll();

  /// Emits the link (or null) now and whenever it changes.
  Stream<GitLink?> watchByCollection(int collectionId);

  /// Collection ids that currently have a link, for sidebar badges.
  Stream<Set<int>> watchLinkedCollectionIds();

  /// Inserts when `link.id == 0`, otherwise updates; returns the saved link.
  Future<GitLink> save(GitLink link);

  /// Deletes the link and its base entries. The collection itself stays.
  Future<void> remove(int collectionId);

  /// Base entries by doc uid; empty before the first sync.
  Future<Map<String, BaseEntry>> readBase(int linkId);

  /// Replaces every base entry of [linkId] with [entries].
  Future<void> writeBase(int linkId, Map<String, BaseEntry> entries);
}
