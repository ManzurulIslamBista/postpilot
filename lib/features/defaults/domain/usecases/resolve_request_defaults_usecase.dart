import '../../../../core/usecases/usecase.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../entities/inherited_defaults.dart';
import '../repositories/defaults_repository.dart';
import '../services/defaults_resolver.dart';

/// What a request inherits from its collection and the folders above it, right now.
///
/// The folder is read from the stored request, not from the entity in hand: a tab opened before the
/// request was moved still has the old folder, and the request must follow its new one (the entity's
/// folder is used only when the request is not stored). Everything a send, a code snippet and the
/// editor tabs show goes through here, so they agree.
final class ResolveRequestDefaultsUseCase implements UseCase<InheritedDefaults, ApiRequestEntity> {
  final DefaultsRepository _repository;
  const ResolveRequestDefaultsUseCase(this._repository);

  @override
  Future<InheritedDefaults> call(ApiRequestEntity request) =>
      forRequest(requestId: request.id, collectionId: request.collectionId, folderId: request.folderId);

  /// [call] for a caller that has the ids but not the entity; [folderId] is where the request was last seen.
  Future<InheritedDefaults> forRequest({required int requestId, required int collectionId, int? folderId}) async {
    final current = await _repository.currentFolderId(requestId, fallback: folderId);
    return forFolder(collectionId, current);
  }

  /// What a request in [folderId] (null = the collection's top level) would inherit.
  Future<InheritedDefaults> forFolder(int collectionId, int? folderId) async =>
      DefaultsResolver.resolve((await _repository.loadTree(collectionId)).chainFor(folderId));

  /// The [repository]'s change stream for [collectionId], for editors that keep what [forFolder] says on screen.
  Stream<void> changes(int collectionId) => _repository.changes(collectionId);
}
