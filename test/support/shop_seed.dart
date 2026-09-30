import 'dart:convert';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'in_memory_import_export_fakes.dart';

const shopAssertions = '[{"type":"statusIn2xx","path":"","expected":""}]';
const shopExtractors = r'[{"source":"jsonPath","path":"$.id","scope":"environment","key":"orderId"}]';

Future<int> addRequest(
  RepositoryBundle repos,
  int collectionId,
  String name, {
  int? folderId,
  HttpMethod method = HttpMethod.get,
  String url = 'https://shop.test/x',
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> query = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(),
}) async {
  final id = await repos.requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: name);
  await repos.requestRepository.saveRequest(ApiRequestEntity(
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
  ));
  return id;
}

/// Everything a backup has to carry, written through the repositories: nested
/// folders, every body kind, secret auth, tests, saved examples, environments
/// and globals. Works on any [RepositoryBundle], in-memory or database-backed.
Future<void> seedShop(RepositoryBundle repos) async {
  final shop = await repos.collectionRepository.createCollection('Shop');
  await repos.collectionAuthRepository.setAuthJson(shop, const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}').toJsonString());
  for (final v in [('baseUrl', 'https://shop.test', true), ('currency', 'EUR', false)]) {
    await repos.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: v.$1, value: v.$2, enabled: v.$3));
  }
  final orders = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
  final archive = await repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: orders, name: 'Archive');
  final users = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Users');

  await addRequest(repos, shop, 'List orders',
      folderId: orders,
      url: '{{baseUrl}}/orders',
      headers: [KeyValueItem(key: 'X-Trace', value: 'on', enabled: false)],
      query: [KeyValueItem(key: 'limit', value: '10')]);
  await addRequest(repos, shop, 'Create order',
      folderId: orders,
      method: HttpMethod.post,
      body: const RequestBody(type: BodyType.raw, rawContentType: RawContentType.xml, rawText: '<order/>'),
      auth: RequestAuth(
        type: AuthType.oauth2,
        oauth2AccessTokenUrl: 'https://auth.test/token',
        oauth2ClientId: 'client',
        oauth2ClientSecret: 'client-secret',
        oauth2Scope: 'orders',
      ).withOAuth2Token('access-token', DateTime.utc(2030), refreshToken: 'refresh-token'));
  final old = await addRequest(repos, shop, 'Old order',
      folderId: archive,
      method: HttpMethod.put,
      body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [KeyValueItem(key: 'a', value: '1', enabled: false)]));
  await repos.scriptsRepository.save(RequestScriptsEntity(requestId: old, assertionsJson: shopAssertions, extractorsJson: shopExtractors));
  for (final example in [
    ResponseExampleEntity(
      id: 0,
      requestId: old,
      name: '200 OK',
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: '{"ok":true}',
      savedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    ),
    ResponseExampleEntity(id: 0, requestId: old, name: 'Gone', statusCode: 410, headers: const {}, body: '', savedAt: DateTime.utc(2026, 2, 3)),
  ]) {
    await repos.exampleRepository.add(example);
  }
  final ping = await addRequest(repos, shop, 'Ping',
      method: HttpMethod.post,
      body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ ping }', graphqlVariables: '{"a":1}'));
  await repos.scriptsRepository.save(RequestScriptsEntity(requestId: ping, extractorsJson: shopExtractors));
  await addRequest(repos, shop, 'Login',
      folderId: users,
      method: HttpMethod.post,
      body: RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'user', value: 'ann')]),
      auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: 'pw'));
  // A request with default (empty) tests must not clutter the file.
  final plain = await addRequest(repos, shop, 'Plain');
  await repos.scriptsRepository.save(RequestScriptsEntity(requestId: plain));

  await repos.collectionRepository.createCollection('Empty');

  final dev = await repos.environmentRepository.create('Dev');
  for (final v in [('host', 'dev.shop.test', false, true), ('password', 'p4ss', true, true), ('off', 'x', false, false)]) {
    await repos.environmentRepository
        .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: dev, key: v.$1, value: v.$2, isSecret: v.$3, enabled: v.$4));
  }
  await repos.environmentRepository.create('Prod');

  await repos.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'apiVersion', value: '2', isSecret: false, enabled: true));
  await repos.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'masterKey', value: 'k3y', isSecret: true, enabled: false));
}

/// A backup text with folder ids replaced by folder paths and the timestamp
/// removed, so the backups of two databases with different ids compare equal.
Map<String, dynamic> normalizedBackup(String backupText) {
  final doc = jsonDecode(backupText) as Map<String, dynamic>..remove('exportedAt');
  for (final collection in (doc['collections'] as List).cast<Map<String, dynamic>>()) {
    final folders = {for (final f in (collection['folders'] as List).cast<Map<String, dynamic>>()) f['id'] as int: f};
    String path(Map<String, dynamic> folder) =>
        folder['parentId'] == null ? '${folder['name']}' : '${path(folders[folder['parentId']]!)}/${folder['name']}';
    collection['folders'] = [for (final f in folders.values) path(f)];
    for (final request in (collection['requests'] as List).cast<Map<String, dynamic>>()) {
      final folderId = request['folderId'];
      request['folderId'] = folderId == null ? null : path(folders[folderId]!);
    }
  }
  return doc;
}
