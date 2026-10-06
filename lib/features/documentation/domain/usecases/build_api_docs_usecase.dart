import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/entities/collection_entity.dart' show FolderEntity;
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../defaults/domain/entities/defaults_chain.dart';
import '../../../defaults/domain/entities/inherited_defaults.dart';
import '../../../defaults/domain/repositories/defaults_repository.dart';
import '../../../defaults/domain/services/defaults_resolver.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../entities/api_docs_model.dart';
import '../entities/entity_kind.dart';
import '../repositories/documentation_repository.dart';
import '../repositories/tag_repository.dart';

/// Reads one collection through the repositories and assembles what the docs
/// generator needs. Disabled headers, parameters and variables are left out and
/// authentication becomes a type label: no credential is ever copied.
final class BuildApiDocsUseCase implements UseCase<ApiDocsModel, int> {
  final CollectionRepository _collections;
  final RequestRepository _requests;
  final ResponseExampleRepository _examples;
  final CollectionVariableRepository _variables;
  final CollectionAuthRepository _auth;
  final DocumentationRepository _docs;
  final TagRepository _tags;

  /// What the collection and its folders pass down: the headers a request inherits are listed with it,
  /// and its authorization says which folder it comes from. Without it only a request's own are shown.
  final DefaultsRepository? _defaults;

  const BuildApiDocsUseCase(
    this._collections,
    this._requests,
    this._examples,
    this._variables,
    this._auth,
    this._docs,
    this._tags, [
    this._defaults,
  ]);

  @override
  Future<ApiDocsModel> call(int collectionId) async {
    final collection = (await _collections.watchCollections().first).where((c) => c.id == collectionId).firstOrNull;
    if (collection == null) throw const NotFoundException('Collection not found.');

    final requests = <ApiRequestEntity>[];
    for (final summary in await _requests.watchByCollection(collectionId).first) {
      final full = await _requests.findById(summary.id);
      if (full != null) requests.add(full);
    }
    final context = _Context(
      folders: await _collections.watchFolders(collectionId).first,
      requests: requests,
      examples: {
        for (final request in requests) request.id: (await _examples.watchByRequest(request.id).first).reversed.toList(),
      },
      collectionAuth: _decodeAuth(await _auth.getAuthJson(collectionId)),
      docs: {for (final kind in EntityKind.values) kind: await _docs.markdownByLocalId(kind)},
      tags: {for (final kind in EntityKind.values) kind: await _tags.tagsByLocalId(kind)},
      defaults: await _defaults?.loadTree(collectionId),
    );

    final folders = _foldersUnder(null, context);
    final topLevel = [
      for (final request in requests)
        if (!context.placed.contains(request.id)) _request(request, context),
    ];
    final variables = await _variables.watchByCollection(collectionId).first;
    return ApiDocsModel(
      name: collection.name,
      description: context.description(EntityKind.collection, collection.id),
      tags: context.tagsOf(EntityKind.collection, collection.id),
      authSummary: _authSummary(context.collectionAuth, null),
      variables: [
        for (final variable in variables)
          if (variable.enabled && variable.key.trim().isNotEmpty) ApiDocsField(variable.key, variable.value),
      ],
      folders: folders,
      requests: topLevel,
    );
  }

  List<ApiDocsFolder> _foldersUnder(int? parentId, _Context context) => [
        for (final folder in context.folders.where((f) => f.parentFolderId == parentId))
          if (context.visited.add(folder.id)) _folder(folder, context),
      ];

  ApiDocsFolder _folder(FolderEntity folder, _Context context) {
    final folders = _foldersUnder(folder.id, context);
    return ApiDocsFolder(
      name: folder.name,
      description: context.description(EntityKind.folder, folder.id),
      tags: context.tagsOf(EntityKind.folder, folder.id),
      folders: folders,
      requests: [
        for (final request in context.requests.where((r) => r.folderId == folder.id))
          if (context.placed.add(request.id)) _request(request, context),
      ],
    );
  }

  ApiDocsRequest _request(ApiRequestEntity request, _Context context) {
    final inherited = context.defaults == null
        ? null
        : DefaultsResolver.resolve(context.defaults!.chainFor(request.folderId));
    // A header the request sets itself (or switches off) takes the place of the inherited one.
    final ownNames = {
      for (final item in request.headers)
        if (item.key.trim().isNotEmpty) item.key.trim().toLowerCase(),
    };
    return ApiDocsRequest(
      name: request.name,
      method: request.method.label,
      url: request.url,
      description: context.description(EntityKind.request, request.id),
      tags: context.tagsOf(EntityKind.request, request.id),
      queryParams: _fields(request.queryParams),
      headers: [
        for (final header in inherited?.headers ?? const <InheritedHeader>[])
          if (header.item.key.trim().isNotEmpty && !ownNames.contains(header.item.key.trim().toLowerCase()))
            ApiDocsField(header.item.key, header.item.value, origin: header.origin.label),
        ..._fields(request.headers),
      ],
      body: _body(request.body),
      authSummary: _authSummary(
        request.auth,
        inherited?.auth ?? context.collectionAuth,
        inheritedFrom: inherited?.authOrigin?.isFolder == true ? inherited!.authOrigin!.label : 'the collection',
      ),
      examples: [
        for (final example in context.examples[request.id] ?? const <ResponseExampleEntity>[])
          ApiDocsExample(name: example.name, statusCode: example.statusCode, body: example.body),
      ],
    );
  }

  static List<ApiDocsField> _fields(List<KeyValueItem> items) => [
        for (final item in items)
          if (item.enabled && item.key.trim().isNotEmpty) ApiDocsField(item.key, item.value),
      ];

  static ApiDocsBody? _body(RequestBody body) {
    switch (body.type) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        if (body.rawText.trim().isEmpty) return null;
        final (label, language) = switch (body.rawContentType) {
          RawContentType.json => ('JSON', 'json'),
          RawContentType.text => ('Text', ''),
          RawContentType.xml => ('XML', 'xml'),
          RawContentType.html => ('HTML', 'html'),
          RawContentType.javascript => ('JavaScript', 'javascript'),
        };
        return ApiDocsBody(typeLabel: label, language: language, text: body.rawText);
      case BodyType.formData:
        final fields = _fields(body.formFields);
        return fields.isEmpty ? null : ApiDocsBody(typeLabel: BodyType.formData.label, fields: fields);
      case BodyType.urlEncoded:
        final fields = _fields(body.urlEncodedFields);
        return fields.isEmpty ? null : ApiDocsBody(typeLabel: BodyType.urlEncoded.label, fields: fields);
      case BodyType.graphql:
        if (body.graphqlQuery.trim().isEmpty) return null;
        final variables = body.graphqlVariables.trim();
        return ApiDocsBody(
          typeLabel: BodyType.graphql.label,
          language: 'graphql',
          text: body.graphqlQuery,
          variablesText: variables == '{}' ? '' : variables,
        );
    }
  }

  /// Only the type ever leaves this method. A request that inherits shows what
  /// it inherits and where from ([inheritedFrom]: `the collection`, or `folder "Auth"`),
  /// and nothing when no default is set.
  static String _authSummary(RequestAuth? auth, RequestAuth? collectionAuth, {String inheritedFrom = 'the collection'}) {
    if (auth == null) return '';
    final inherited = auth.type == AuthType.inherit;
    final effective = auth.resolveInherited(collectionAuth);
    if (effective.type == AuthType.none || effective.type == AuthType.inherit) return '';
    return inherited ? '${effective.type.label} (inherited from $inheritedFrom)' : effective.type.label;
  }

  /// A corrupt stored value must not stop the docs from being generated.
  static RequestAuth? _decodeAuth(String? json) {
    try {
      return RequestAuth.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }
}

final class _Context {
  final List<FolderEntity> folders;
  final List<ApiRequestEntity> requests;
  final Map<int, List<ResponseExampleEntity>> examples;
  final RequestAuth? collectionAuth;
  final Map<EntityKind, Map<int, String>> docs;
  final Map<EntityKind, Map<int, List<String>>> tags;
  final DefaultsTree? defaults;
  final Set<int> visited = {};
  final Set<int> placed = {};

  _Context({
    required this.folders,
    required this.requests,
    required this.examples,
    required this.collectionAuth,
    required this.docs,
    required this.tags,
    this.defaults,
  });

  String description(EntityKind kind, int id) => docs[kind]?[id] ?? '';

  List<String> tagsOf(EntityKind kind, int id) => tags[kind]?[id] ?? const [];
}
