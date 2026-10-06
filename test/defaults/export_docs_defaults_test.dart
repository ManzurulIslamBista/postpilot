// The OpenAPI export and the generated docs show what a request inherits: its security, its headers.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_chain.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/documentation/domain/services/api_docs_generator.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_exporter.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

ApiRequestEntity _request(
  String name,
  String path, {
  int? folderId,
  HttpMethod method = HttpMethod.get,
  List<KeyValueItem> headers = const [],
  RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  RequestBody body = RequestBody.empty,
}) =>
    ApiRequestEntity(
      id: 0,
      collectionId: 0,
      folderId: folderId,
      name: name,
      method: method,
      url: 'https://shop.test$path',
      headers: headers,
      queryParams: const [],
      body: body,
      auth: auth,
    );

void main() {
  group('OpenAPI export', () {
    const folders = [
      FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Admin'),
      FolderEntity(id: 2, collectionId: 0, parentFolderId: null, name: 'Public'),
      FolderEntity(id: 3, collectionId: 0, parentFolderId: 1, name: 'Deep'),
    ];
    final tree = DefaultsTree(
      collectionName: 'Shop',
      collection: LevelDefaults(
        headers: [_h('X-Tenant', 'acme'), _h('X-Trace', 'on')],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'secret'),
      ),
      folders: folders,
      folderDefaults: {
        1: const LevelDefaults(auth: RequestAuth(type: AuthType.basic, basicUsername: 'a', basicPassword: 'b')),
        2: const LevelDefaults(auth: RequestAuth(type: AuthType.none)),
        3: LevelDefaults(headers: [_h('X-Trace', '', enabled: false), _h('Content-Type', 'application/vnd.api+json')]),
      },
    );

    Map<String, dynamic> export(List<ApiRequestEntity> requests, {DefaultsTree? defaults}) => jsonDecode(OpenApiExporter.export(
          collectionName: 'Shop',
          folders: folders,
          requests: requests,
          collectionAuth: const RequestAuth(type: AuthType.bearer, bearerToken: 'secret'),
          defaults: defaults,
        ).text) as Map<String, dynamic>;

    Map<String, dynamic> operation(Map<String, dynamic> doc, String path) => (doc['paths'][path] as Map).values.single as Map<String, dynamic>;

    test('a request that inherits from a folder is secured by the folder\'s auth, not the document-wide one', () {
      final doc = export([
        _request('Top', '/top'),
        _request('Admin only', '/admin', folderId: 1),
        _request('Public', '/public', folderId: 2),
        _request('Deeper', '/deep', folderId: 3),
      ], defaults: tree);

      expect(doc['security'], [
        {'bearerAuth': []},
      ]);
      expect(operation(doc, '/top').containsKey('security'), isFalse, reason: 'follows the document-wide security');
      expect(operation(doc, '/admin')['security'], [
        {'basicAuth': []},
      ]);
      expect(operation(doc, '/public')['security'], isEmpty, reason: 'Public sets No Auth: an explicit "no security"');
      expect(operation(doc, '/deep')['security'], [
        {'basicAuth': []},
      ], reason: 'Deep sets none, so Admin\'s applies');
    });

    test('inherited headers are parameters of every operation below, minus the ones switched off or replaced', () {
      final doc = export([
        _request('Top', '/top'),
        _request('Deeper', '/deep', folderId: 3),
        _request('Overrides', '/own', headers: [_h('x-tenant', 'globex')]),
      ], defaults: tree);

      List<String> headers(String path) => [
            for (final p in (operation(doc, path)['parameters'] as List).cast<Map>())
              if (p['in'] == 'header') '${p['name']}=${p['example']}',
          ];

      expect(headers('/top'), ['X-Tenant=acme', 'X-Trace=on']);
      expect(headers('/deep'), ['X-Tenant=acme'], reason: 'Deep switches X-Trace off; Content-Type is never a parameter');
      expect(headers('/own'), ['X-Trace=on', 'x-tenant=globex'], reason: 'what is inherited first, then the request\'s own');
    });

    test('an inherited Content-Type decides the media type of the request body', () {
      final doc = export([
        _request(
          'Create',
          '/create',
          folderId: 3,
          method: HttpMethod.post,
          body: const RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '{"a":1}'),
        ),
      ], defaults: tree);

      expect(((operation(doc, '/create')['requestBody'] as Map)['content'] as Map).keys, ['application/vnd.api+json']);
    });

    test('without defaults the export is what it was', () {
      final doc = export([_request('Admin only', '/admin', folderId: 1)]);

      expect(operation(doc, '/admin').containsKey('security'), isFalse);
      expect(operation(doc, '/admin').containsKey('parameters'), isFalse);
    });
  });

  group('generated docs', () {
    late InMemoryDb db;
    late int shop;

    setUp(() async {
      db = InMemoryDb();
      shop = await db.collectionRepository.createCollection('Shop');
    });

    BuildApiDocsUseCase build() => BuildApiDocsUseCase(
          db.collectionRepository,
          db.requestRepository,
          db.exampleRepository,
          db.collectionVariableRepository,
          db.collectionAuthRepository,
          db.documentationRepository,
          db.tagRepository,
          db.defaultsRepository,
        );

    test('a request lists the headers it inherits with where each comes from, its own after them', () async {
      final orders = await db.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
      await db.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme'), _h('Accept-Language', 'en')]));
      await db.defaultsRepository.saveFolder(orders, LevelDefaults(headers: [_h('accept-language', 'bn'), _h('X-Api-Version', '2')]));
      await addRequest(db, shop, 'List', folderId: orders, headers: [_h('X-Own', '1')]);

      final model = await build()(shop);

      final request = model.folders.single.requests.single;
      expect([for (final h in request.headers) '${h.key}=${h.value}@${h.origin}'], [
        'X-Tenant=acme@collection "Shop"',
        'accept-language=bn@folder "Orders"',
        'X-Api-Version=2@folder "Orders"',
        'X-Own=1@',
      ]);
      final markdown = ApiDocsGenerator.toMarkdown(model);
      expect(markdown, contains('| Key | Value | Inherited from |'));
      expect(markdown, contains('folder "Orders"'));
      final html = ApiDocsGenerator.toHtml(model);
      expect(html, contains('<th>Inherited from</th>'));
      expect(html, contains('collection &quot;Shop&quot;'));
    });

    test('a header the request sets, or switches off, replaces the inherited one', () async {
      await db.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme'), _h('X-Trace', 'on')]));
      await addRequest(db, shop, 'Get', headers: [_h('x-tenant', 'globex'), _h('X-TRACE', '', enabled: false)]);

      final request = (await build()(shop)).requests.single;

      expect([for (final h in request.headers) '${h.key}=${h.value}@${h.origin}'], ['x-tenant=globex@']);
    });

    test('a secret in an inherited header is masked like one in the request\'s own', () async {
      await db.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('Authorization', 'Bearer abcdefghijklmnop123456')]));
      await addRequest(db, shop, 'Get');

      final markdown = ApiDocsGenerator.toMarkdown(await build()(shop));

      expect(markdown, contains('Authorization'));
      expect(markdown, isNot(contains('abcdefghijklmnop123456')));
    });

    test('the authorization says which folder it is inherited from', () async {
      final auth = await db.collectionRepository.createFolder(collectionId: shop, name: 'Auth');
      await db.collectionAuthRepository.setAuthJson(shop, const RequestAuth(type: AuthType.basic, basicUsername: 'a').toJsonString());
      await db.defaultsRepository.saveFolder(auth, const LevelDefaults(auth: RequestAuth(type: AuthType.bearer, bearerToken: 't')));
      await addRequest(db, shop, 'In folder', folderId: auth);
      await addRequest(db, shop, 'At top');

      final model = await build()(shop);

      expect(model.folders.single.requests.single.authSummary, 'Bearer Token (inherited from folder "Auth")');
      expect(model.requests.single.authSummary, 'Basic Auth (inherited from the collection)');
      expect(model.authSummary, 'Basic Auth');
    });

    test('without a defaults repository the docs are what they were', () async {
      await db.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme')]));
      await addRequest(db, shop, 'Get', headers: [_h('X-Own', '1')]);
      final plain = BuildApiDocsUseCase(
        db.collectionRepository,
        db.requestRepository,
        db.exampleRepository,
        db.collectionVariableRepository,
        db.collectionAuthRepository,
        db.documentationRepository,
        db.tagRepository,
      );

      final request = (await plain(shop)).requests.single;

      expect(request.headers.map((h) => h.key), ['X-Own']);
    });
  });
}
