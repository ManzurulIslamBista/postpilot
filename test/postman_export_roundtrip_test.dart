import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

void main() {
  test('export -> import round-trip preserves a request in a nested folder', () {
    const folder = FolderEntity(id: 1, collectionId: 10, parentFolderId: null, name: 'Users');
    final request = ApiRequestEntity(
      id: 100,
      collectionId: 10,
      folderId: 1,
      name: 'Create user',
      method: HttpMethod.post,
      url: 'https://api.example.com/users',
      headers: [KeyValueItem(key: 'Content-Type', value: 'application/json')],
      queryParams: const [],
      body: const RequestBody(type: BodyType.raw, rawText: '{"name":"John"}', rawContentType: RawContentType.json),
      auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'abc123'),
    );

    final json = PostmanCollectionExporter.export(
      collectionName: 'Round Trip',
      folders: const [folder],
      requests: [request],
    );

    final reimported = PostmanCollectionParser.parse(json);
    expect(reimported.name, 'Round Trip');

    final reimportedFolder = reimported.items.single as PostmanFolderItem;
    expect(reimportedFolder.name, 'Users');

    final reimportedRequest = reimportedFolder.children.single as PostmanRequestItem;
    expect(reimportedRequest.name, 'Create user');
    expect(reimportedRequest.method, HttpMethod.post);
    expect(reimportedRequest.url, 'https://api.example.com/users');
    expect(reimportedRequest.headers.single.key, 'Content-Type');
    expect(reimportedRequest.body.type, BodyType.raw);
    expect(reimportedRequest.body.rawText, '{"name":"John"}');
    expect(reimportedRequest.auth.type, AuthType.bearer);
    expect(reimportedRequest.auth.bearerToken, 'abc123');
  });

  test('export -> import round-trip preserves collection variables, including disabled ones', () {
    final json = PostmanCollectionExporter.export(
      collectionName: 'With Variables',
      folders: const [],
      requests: const [],
      variables: const [
        CollectionVariableEntity(id: 1, collectionId: 10, key: 'baseUrl', value: 'https://api.example.com', enabled: true),
        CollectionVariableEntity(id: 2, collectionId: 10, key: 'legacy', value: 'x', enabled: false),
      ],
    );

    final variables = PostmanCollectionParser.parse(json).variables;
    expect(variables.map((v) => v.key), ['baseUrl', 'legacy']);
    expect(variables.map((v) => v.value), ['https://api.example.com', 'x']);
    expect(variables.map((v) => v.enabled), [true, false]);
  });

  test('a collection without variables exports no variable array', () {
    final json = PostmanCollectionExporter.export(collectionName: 'Plain', folders: const [], requests: const []);

    expect(json, isNot(contains('"variable"')));
  });
}
