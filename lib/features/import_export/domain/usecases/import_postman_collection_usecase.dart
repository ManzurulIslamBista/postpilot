import 'package:flutter/foundation.dart' show compute;
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/services/importers/postman_collection_parser.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../services/import_names.dart';
import 'summarizing_importer.dart';

/// Recreates an entire Postman collection export (folders, requests,
/// collection variables, collection auth and the test scripts that translate
/// to assertions and extractors) inside a brand-new local collection. Returns
/// the new collection's id, or with [importWithSummary] a summary that also
/// lists what the export held that PostPilot could not take over. If saving
/// fails midway the half-built collection is deleted again, so a retry doesn't
/// add a duplicate.
final class ImportPostmanCollectionUseCase implements UseCase<int, String>, SummarizingImporter {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;
  final RequestScriptsRepository _scriptsRepository;

  const ImportPostmanCollectionUseCase(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
    this._scriptsRepository,
  );

  @override
  Future<int> call(String json) async => (await importWithSummary(json)).collectionIds.single;

  @override
  Future<ImportSummary> importWithSummary(String json) async {
    // Off the UI isolate: a multi-MB collection would otherwise freeze the
    // window before the import spinner ever paints. The BOM some editors and
    // exporters prepend is not JSON (the format detector already ignores it).
    final parsed = await compute(PostmanCollectionParser.parse, json.replaceFirst('﻿', '').trim());
    final collectionId = await _collectionRepository.createCollection(parsed.name);
    try {
      final auth = parsed.auth;
      if (auth != null) await _collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());
      for (final variable in parsed.variables) {
        await _collectionVariableRepository.upsert(CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: variable.key,
          value: variable.value,
          enabled: variable.enabled,
        ));
      }
      for (final item in parsed.items) {
        await _persist(item, collectionId, null);
      }
    } catch (_) {
      // The cascade removes the collection's contents too. Best effort: the
      // original failure is what the user needs to see.
      try {
        await _collectionRepository.deleteCollection(collectionId);
      } catch (_) {}
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.postman,
      collectionIds: [collectionId],
      collectionName: parsed.name,
      folders: parsed.folderCount,
      requests: parsed.requestCount,
      skipped: parsed.skippedCount,
      notes: _notesOf(parsed),
    );
  }

  /// What the dialog lists: a line on the converted scripts, then what was left out, then what changed.
  static List<String> _notesOf(ParsedPostmanCollection parsed) {
    final checks = parsed.assertionCount;
    final extractors = parsed.extractorCount;
    return [
      if (checks + extractors > 0)
        'Test scripts were converted to ${_plural(checks, 'check')} and ${_plural(extractors, 'variable extractor')} '
            'on the requests\' Tests tab.',
      for (final note in parsed.notes)
        if (note.skipped) note.message,
      for (final note in parsed.notes)
        if (!note.skipped) note.message,
    ];
  }

  static String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

  Future<void> _persist(PostmanItem item, int collectionId, int? folderId) async {
    switch (item) {
      case PostmanFolderItem():
        final newFolderId =
            await _collectionRepository.createFolder(collectionId: collectionId, parentFolderId: folderId, name: ImportNames.folder(item.name));
        for (final child in item.children) {
          await _persist(child, collectionId, newFolderId);
        }
      case PostmanRequestItem():
        final requestId =
            await _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: item.name);
        await _requestRepository.saveRequest(ApiRequestEntity(
          id: requestId,
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
        if (item.assertions.isNotEmpty || item.extractors.isNotEmpty) {
          await _scriptsRepository.save(RequestScriptsEntity(
            requestId: requestId,
            assertionsJson: ScriptsJsonCodec.encodeAssertions(item.assertions),
            extractorsJson: ScriptsJsonCodec.encodeExtractors(item.extractors),
          ));
        }
    }
  }
}
