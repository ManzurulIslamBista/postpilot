import 'package:flutter/foundation.dart' show compute;
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../services/import_names.dart';
import '../services/openapi_parser.dart';
import '../services/openapi_refresh_planner.dart';

/// Brings an existing collection up to date with a newer version of the API
/// spec it was imported from, without touching anything the person edited:
/// new endpoints are added (in their tag's folder), endpoints that left the
/// spec can be marked, and every other request stays as it is.
final class RefreshOpenApiUseCase {
  static const removedMarker = '⚠ ';

  final CollectionRepository _collections;
  final RequestRepository _requests;

  const RefreshOpenApiUseCase(this._collections, this._requests);

  Future<OpenApiRefreshPlan> plan(int collectionId, String specText) async {
    // Off the UI isolate, like a first import: a large spec would freeze the window.
    final spec = await compute(OpenApiParser.parse, specText);
    final summaries = await _requests.watchByCollection(collectionId).first;
    final existing = <ExistingRequest>[];
    for (final s in summaries) {
      final full = await _requests.findById(s.id);
      if (full != null) {
        existing.add(ExistingRequest(id: full.id, name: full.name, method: full.method, url: full.url, folderId: full.folderId));
      }
    }
    return OpenApiRefreshPlanner.plan(spec, existing);
  }

  /// Applies [plan]. Returns how many requests were added.
  Future<int> apply(int collectionId, OpenApiRefreshPlan plan, {bool markRemoved = true}) async {
    final folders = await _collections.watchFolders(collectionId).first;
    final folderIds = <String, int>{
      for (final f in folders)
        if (f.parentFolderId == null) f.name: f.id,
    };

    var added = 0;
    for (final endpoint in plan.added) {
      int? folderId;
      final folder = endpoint.folder;
      if (folder != null) {
        final name = ImportNames.folder(folder);
        folderId = folderIds[name] ?? (folderIds[name] = await _collections.createFolder(collectionId: collectionId, name: name));
      }
      final item = endpoint.item;
      final id = await _requests.createRequest(collectionId: collectionId, folderId: folderId, name: item.name);
      await _requests.saveRequest(ApiRequestEntity(
        id: id,
        collectionId: collectionId,
        folderId: folderId,
        name: item.name,
        method: item.method,
        url: item.url,
        headers: item.headers,
        queryParams: item.queryParams,
        body: item.body,
        auth: item.auth,
      ));
      added++;
    }

    if (markRemoved) {
      for (final gone in plan.removed) {
        if (gone.name.startsWith(removedMarker)) continue;
        final full = await _requests.findById(gone.id);
        if (full != null) await _requests.saveRequest(full.copyWith(name: '$removedMarker${full.name}'));
      }
    }
    return added;
  }

  /// The collections to choose from.
  Future<List<CollectionEntity>> collections() => _collections.watchCollections().first;
}
