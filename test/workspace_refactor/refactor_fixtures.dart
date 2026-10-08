// Plain objects for the workspace refactoring tests: units built by hand, so the engine is tested without a database.
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/level_units.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/request_unit.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/variable_units.dart';

RequestUnit req(
  int id,
  String name, {
  String url = '',
  int collectionId = 1,
  int? folderId,
  List<String> parent = const ['Shop'],
  HttpMethod method = HttpMethod.get,
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> query = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(),
  List<AssertionEntity> assertions = const [],
  List<ExtractorEntity> extractors = const [],
  String description = '',
  List<String> tags = const [],
  List<ResponseExampleEntity> examples = const [],
}) => RequestUnit(
  request: ApiRequestEntity(
    id: id,
    collectionId: collectionId,
    folderId: folderId,
    name: name,
    method: method,
    url: url,
    headers: headers,
    queryParams: query,
    body: body,
    auth: auth,
  ),
  parentTrail: parent,
  assertions: assertions,
  extractors: extractors,
  hasScripts: assertions.isNotEmpty || extractors.isNotEmpty,
  description: description,
  tags: tags,
  examples: examples,
);

CollectionUnit collection(int id, String name, {String description = '', List<String> tags = const [], RequestAuth? auth, LevelDefaults defaults = LevelDefaults.empty}) =>
    CollectionUnit(collection: CollectionEntity(id: id, name: name), description: description, tags: tags, auth: auth, defaults: defaults);

FolderUnit folder(
  int id,
  String name, {
  int collectionId = 1,
  int? parentId,
  List<String> parent = const ['Shop'],
  String description = '',
  List<String> tags = const [],
  LevelDefaults defaults = LevelDefaults.empty,
}) => FolderUnit(
  folder: FolderEntity(id: id, collectionId: collectionId, parentFolderId: parentId, name: name),
  parentTrail: parent,
  description: description,
  tags: tags,
  defaults: defaults,
);

EnvironmentVariableUnit envVar(int id, String env, String key, String value, {int envId = 1, bool secret = false, bool enabled = true}) =>
    EnvironmentVariableUnit(
      variable: EnvironmentVariableEntity(id: id, environmentId: envId, key: key, value: value, isSecret: secret, enabled: enabled),
      environmentName: env,
    );

GlobalVariableUnit globalVar(int id, String key, String value, {bool secret = false, bool enabled = true}) =>
    GlobalVariableUnit(variable: GlobalVariableEntity(id: id, key: key, value: value, isSecret: secret, enabled: enabled));

CollectionVariableUnit collectionVar(int id, String key, String value, {int collectionId = 1, String collectionName = 'Shop', bool enabled = true}) =>
    CollectionVariableUnit(
      variable: CollectionVariableEntity(id: id, collectionId: collectionId, key: key, value: value, enabled: enabled),
      collectionName: collectionName,
    );

KeyValueItem row(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

/// One occurrence of "acme" in every part of a workspace the tool can search: twelve, one per scope.
WorkspaceSnapshot acmeWorkspace() => WorkspaceSnapshot([
  collection(
    1,
    'Shop',
    defaults: LevelDefaults(headers: [row('X-Owner', 'acme')]),
  ),
  req(
    100,
    'Acme list',
    url: 'https://acme.test/orders',
    query: [row('owner', 'acme')],
    headers: [row('X-Key', 'acme-key')],
    body: const RequestBody(type: BodyType.raw, rawText: '{"owner":"acme"}'),
    auth: const RequestAuth(type: AuthType.basic, basicUsername: 'acme-user'),
    assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: 'acme')],
    description: 'About acme',
    tags: ['acme'],
    examples: [
      ResponseExampleEntity(id: 7, requestId: 100, name: '200', statusCode: 200, headers: const {}, body: '{"vendor":"acme"}', savedAt: DateTime.utc(2026)),
    ],
  ),
  envVar(500, 'Dev', 'host', 'acme.example'),
]);
