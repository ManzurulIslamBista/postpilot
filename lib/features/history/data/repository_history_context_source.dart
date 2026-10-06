import '../../collections/domain/repositories/collection_auth_repository.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../environments/domain/repositories/global_variable_repository.dart';
import '../../git_sync/domain/services/secret_fields.dart';
import '../../git_sync/domain/services/secret_names.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../request_builder/domain/entities/request_auth.dart';
import '../domain/repositories/history_store.dart';

/// Reads the collection name, the active environment and what is secret
/// around a request from the app's own repositories. Each lookup fails on its
/// own and quietly: History is a convenience and a send must not depend on it.
final class RepositoryHistoryContextSource implements HistoryContextSource {
  final CollectionRepository _collections;
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;
  final CollectionAuthRepository _collectionAuth;

  const RepositoryHistoryContextSource({
    required this._collections,
    required this._environments,
    required this._globals,
    required this._collectionAuth,
  });

  @override
  Future<HistoryContext> of(ApiRequestEntity request) async {
    String? collectionName;
    String? environmentName;
    final flagged = <String>{};
    final secrets = <String>[];

    try {
      for (final collection in await _collections.watchCollections().first) {
        if (collection.id == request.collectionId) collectionName = collection.name;
      }
    } catch (_) {}

    try {
      final active = await _environments.watchActive().first;
      if (active != null) {
        environmentName = active.name;
        for (final v in await _environments.watchVariables(active.id).first) {
          if (v.isSecret && v.enabled) flagged.add(v.key);
        }
      }
    } catch (_) {}

    try {
      for (final g in await _globals.watchAll().first) {
        if (g.isSecret && g.enabled) flagged.add(g.key);
      }
    } catch (_) {}

    try {
      // A request that inherits its auth sends the collection's credentials, which a server may echo back.
      final auth = RequestAuth.fromJsonString(await _collectionAuth.getAuthJson(request.collectionId));
      if (auth != null) {
        for (final entry in auth.toJson().entries) {
          final value = entry.value;
          if (SecretFields.authKeys.contains(entry.key) && value is String && SecretNames.hasLiteralSecret(value)) {
            secrets.add(value);
          }
        }
      }
    } catch (_) {}

    return HistoryContext(
      collectionName: collectionName,
      environmentName: environmentName,
      flaggedSecretKeys: flagged,
      secretValues: secrets,
    );
  }
}
