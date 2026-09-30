import '../entities/sync_doc.dart';

/// What [LocalCollectionStore.applySnapshot] changed, in local ids, so the
/// caller can refresh or close the open request tabs.
final class ApplyOutcome {
  final int collectionId;
  final int added;
  final int updated;
  final int deleted;
  final List<int> changedRequestIds;
  final List<int> deletedRequestIds;

  const ApplyOutcome({
    required this.collectionId,
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.changedRequestIds = const [],
    this.deletedRequestIds = const [],
  });
}

/// The local database side of Git sync: turns one collection into
/// [SyncSnapshot] docs and back. Maps local integer ids to the uids that
/// identify entities in the repository (creating a uid the first time an
/// entity is seen).
abstract interface class LocalCollectionStore {
  /// Every folder and request of [collectionId] plus the collection itself
  /// (its variables, auth, description and tags), as docs.
  ///
  /// With [includeSecrets] false, credential fields (tokens, passwords,
  /// secrets — see `SecretFields`) are stripped from the docs, so nothing
  /// secret is ever compared, committed or stored as base.
  Future<SyncSnapshot> readSnapshot(int collectionId, {required bool includeSecrets});

  /// Makes the local collection equal to [target]: creates missing entities
  /// (registering their uids), updates changed ones, deletes local entities
  /// whose uid is absent from [target]. With [collectionId] null a brand-new
  /// collection is created from [target]'s collection doc.
  ///
  /// Credential fields missing or empty in a [target] doc never erase a
  /// non-empty local value (docs read with `includeSecrets: false` carry none).
  /// Runs in one database transaction.
  Future<ApplyOutcome> applySnapshot(SyncSnapshot target, {int? collectionId});
}
