import 'package:flutter/foundation.dart' show compute;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../services/import_names.dart';
import '../services/openapi_parser.dart';
import 'summarizing_importer.dart';

/// Recreates an OpenAPI 3.x / Swagger 2.0 document (JSON or YAML) as a
/// brand-new local collection, one folder per tag, with the document's server
/// stored once as the collection's `baseUrl` variable. Returns the new
/// collection's id, or with [importWithSummary] a summary too.
///
/// The requests also reference variables the document cannot supply: the
/// `{{token}}` of a bearer scheme, the `{{apiKey}}`, `{{clientId}}` and
/// `{{password}}` of the other schemes, a path parameter's `{{petId}}`. Left
/// alone they show up as "Undefined" on every request, so they are created
/// empty in a new environment named after the API (a name that looks like a
/// credential is marked secret). The environment is not activated: that is the
/// user's switch to make.
final class ImportOpenApiUseCase implements UseCase<int, String>, SummarizingImporter {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final EnvironmentRepository _environmentRepository;

  const ImportOpenApiUseCase(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._environmentRepository,
  );

  @override
  Future<int> call(String text) async => (await importWithSummary(text)).collectionIds.single;

  @override
  Future<ImportSummary> importWithSummary(String text) async {
    // Off the UI isolate: a multi-MB document would otherwise freeze the
    // window before the import spinner ever paints.
    final parsed = await compute(OpenApiParser.parse, text);
    final collectionId = await _collectionRepository.createCollection(parsed.name);
    int? environmentId;
    String? environmentName;
    final missing = _missingVariables(parsed);
    try {
      if (parsed.baseUrl.isNotEmpty) {
        await _collectionVariableRepository.upsert(CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: OpenApiParser.baseUrlVariable,
          value: parsed.baseUrl,
          enabled: true,
        ));
      }
      for (final request in parsed.rootRequests) {
        await _persist(request, collectionId, null);
      }
      for (final folder in parsed.folders) {
        final folderId =
            await _collectionRepository.createFolder(collectionId: collectionId, name: ImportNames.folder(folder.name));
        for (final request in folder.requests) {
          await _persist(request, collectionId, folderId);
        }
      }
      if (missing.isNotEmpty) {
        environmentName = await _freeEnvironmentName(parsed.name);
        environmentId = await _environmentRepository.create(environmentName);
        for (final name in missing) {
          await _environmentRepository.upsertVariable(EnvironmentVariableEntity(
            id: 0,
            environmentId: environmentId,
            key: name,
            value: '',
            isSecret: SecretNames.looksSecretKey(name),
            enabled: true,
          ));
        }
      }
    } catch (_) {
      // A half-imported collection would sit in the sidebar and a retry would
      // create a duplicate next to it; the cascade removes its contents too.
      if (environmentId != null) {
        try {
          await _environmentRepository.delete(environmentId);
        } catch (_) {}
      }
      await _collectionRepository.deleteCollection(collectionId);
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.openApi,
      collectionIds: [collectionId],
      collectionName: parsed.name,
      folders: parsed.folders.length,
      requests: parsed.rootRequests.length + parsed.folders.fold(0, (sum, f) => sum + f.requests.length),
      environments: environmentId == null ? 0 : 1,
      notes: [
        if (environmentName != null)
          'Created the environment "$environmentName" with ${missing.length} empty variable${missing.length == 1 ? '' : 's'} '
              'the requests use (${missing.map((n) => SecretNames.looksSecretKey(n) ? '$n, secret' : n).join('; ')}). '
              'Select it and fill in the values.',
      ],
    );
  }

  /// The `{{variables}}` the imported requests use that nothing defines yet: every one except the dynamic
  /// `{{$...}}` ones and the `baseUrl` the collection gets from the document's server.
  static List<String> _missingVariables(ParsedOpenApiDocument parsed) {
    final names = <String>{};
    void scan(String text) {
      for (final match in AppConstants.variablePattern.allMatches(text)) {
        names.add(match.group(1)!);
      }
    }

    for (final request in [
      ...parsed.rootRequests,
      for (final folder in parsed.folders) ...folder.requests,
    ]) {
      scan(request.url);
      for (final item in [...request.headers, ...request.queryParams, ...request.body.formFields, ...request.body.urlEncodedFields]) {
        scan(item.key);
        scan(item.value);
      }
      scan(request.body.rawText);
      scan(request.body.graphqlQuery);
      scan(request.body.graphqlVariables);
      scan(request.auth.toJsonString());
    }
    if (parsed.baseUrl.isNotEmpty) names.remove(OpenApiParser.baseUrlVariable);
    return names.where((name) => !name.startsWith(r'$')).toList();
  }

  Future<String> _freeEnvironmentName(String wanted) async {
    final taken = {for (final e in await _environmentRepository.watchAll().first) e.name};
    var name = wanted;
    for (var n = 1; taken.contains(name); n++) {
      name = n == 1 ? '$wanted (imported)' : '$wanted (imported $n)';
    }
    return name;
  }

  Future<void> _persist(OpenApiRequestItem item, int collectionId, int? folderId) async {
    final requestId = await _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: item.name);
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
  }
}
