import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import '../services/sync_engine.dart';

/// Throws away all local changes: the local collection is reset to the base snapshot (parameter: collection id).
final class GitDiscardUseCase implements UseCase<ApplyOutcome, int> {
  final GitLinkRepository _links;
  final LocalCollectionStore _store;
  final SyncEngine _engine;
  const GitDiscardUseCase(this._links, this._store, this._engine);

  @override
  Future<ApplyOutcome> call(int params) async {
    final link = await _links.requireLink(params);
    final base = _engine.baseSnapshot(await _links.readBase(link.id));
    // Before the first push the base is empty; resetting to it would delete the whole collection.
    if (base.root == null) throw const GitSyncException('Nothing to discard - this collection has not been synced yet.');
    return _store.applySnapshot(base, collectionId: link.collectionId);
  }
}
