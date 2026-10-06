import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

PostmanRequestItem _request(PostmanItem item) => item as PostmanRequestItem;
PostmanFolderItem _folder(PostmanItem item) => item as PostmanFolderItem;

ApiRequestEntity _apiRequest(String name, RequestAuth auth) => ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: name,
      method: HttpMethod.get,
      url: 'https://api.example.com/$name',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: auth,
    );

void main() {
  group('import', () {
    test('the collection-level auth is kept and requests without auth still inherit', () {
      const json = '''
      {
        "info": {"name": "C"},
        "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "root-tok"}]},
        "item": [
          {"name": "inherits", "request": {"method": "GET", "url": "https://x/a"}},
          {"name": "own", "request": {"method": "GET", "url": "https://x/b",
            "auth": {"type": "basic", "basic": [{"key": "username", "value": "u"}, {"key": "password", "value": "p"}]}}},
          {"name": "off", "request": {"method": "GET", "url": "https://x/c", "auth": {"type": "noauth"}}}
        ]
      }
      ''';

      final parsed = PostmanCollectionParser.parse(json);
      expect(parsed.auth?.type, AuthType.bearer);
      expect(parsed.auth?.bearerToken, 'root-tok');
      expect(_request(parsed.items[0]).auth.type, AuthType.inherit);
      expect(_request(parsed.items[1]).auth.type, AuthType.basic);
      expect(_request(parsed.items[2]).auth.type, AuthType.none);
    });

    test('a collection-level OAuth 2.0 config is parsed', () {
      const json = '''
      {
        "info": {"name": "C"},
        "auth": {"type": "oauth2", "oauth2": [
          {"key": "grant_type", "value": "client_credentials"},
          {"key": "accessTokenUrl", "value": "https://auth.example.com/token"},
          {"key": "clientId", "value": "cid"},
          {"key": "clientSecret", "value": "sec"},
          {"key": "scope", "value": "read"}
        ]},
        "item": [{"name": "r", "request": {"method": "GET", "url": "https://x"}}]
      }
      ''';

      final parsed = PostmanCollectionParser.parse(json);
      expect(parsed.auth?.type, AuthType.oauth2);
      expect(parsed.auth?.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(parsed.auth?.oauth2ClientId, 'cid');
      expect(parsed.auth?.oauth2Scope, 'read');
      expect(_request(parsed.items.single).auth.type, AuthType.inherit);
    });

    test('an export without collection-level auth has none to import', () {
      const json = '{"info":{"name":"C"},"item":[{"name":"r","request":{"method":"GET","url":"u"}}]}';

      final parsed = PostmanCollectionParser.parse(json);
      expect(parsed.auth, isNull);
      expect(_request(parsed.items.single).auth.type, AuthType.inherit);
    });

    // A folder's auth stays on the folder (it becomes the folder's default auth): requests below it that set
    // none of their own stay on "inherit" and take the nearest folder's at send time, as in Postman.
    test('a folder auth stays on the folder, and the requests below it that set none of their own inherit it', () {
      const json = '''
      {
        "info": {"name": "C"},
        "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "root"}]},
        "item": [
          {"name": "top", "request": {"method": "GET", "url": "u"}},
          {"name": "Admin",
           "auth": {"type": "apikey", "apikey": [{"key": "key", "value": "X-Admin"}, {"key": "value", "value": "k"}]},
           "item": [
             {"name": "a1", "request": {"method": "GET", "url": "u"}},
             {"name": "a2-own", "request": {"method": "GET", "url": "u", "auth": {"type": "noauth"}}},
             {"name": "Deep", "item": [{"name": "d1", "request": {"method": "GET", "url": "u"}}]},
             {"name": "Deep2",
              "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "deep2"}]},
              "item": [{"name": "d2", "request": {"method": "GET", "url": "u"}}]}
           ]},
          {"name": "Plain", "item": [{"name": "p1", "request": {"method": "GET", "url": "u"}}]}
        ]
      }
      ''';

      final parsed = PostmanCollectionParser.parse(json);
      expect(_request(parsed.items[0]).auth.type, AuthType.inherit);

      final admin = _folder(parsed.items[1]);
      expect(admin.auth?.type, AuthType.apiKey);
      expect(admin.auth?.apiKeyName, 'X-Admin');
      expect(_request(admin.children[0]).auth.type, AuthType.inherit, reason: 'no copy of the folder\'s auth');
      expect(_request(admin.children[1]).auth.type, AuthType.none, reason: 'a request\'s own noauth is its own');
      final deep = _folder(admin.children[2]);
      expect(deep.auth, isNull, reason: 'a folder without an auth block inherits from the folder above');
      expect(_request(deep.children.single).auth.type, AuthType.inherit);
      final deep2 = _folder(admin.children[3]);
      expect(deep2.auth?.bearerToken, 'deep2');
      expect(_request(deep2.children.single).auth.type, AuthType.inherit);

      final plain = _folder(parsed.items[2]);
      expect(plain.auth, isNull);
      expect(_request(plain.children.single).auth.type, AuthType.inherit);
    });
  });

  group('export', () {
    const oauth = RequestAuth(
      type: AuthType.oauth2,
      oauth2AccessTokenUrl: 'https://auth.example.com/token',
      oauth2ClientId: 'cid',
      oauth2ClientSecret: 'sec',
      oauth2Scope: 'read write',
      oauth2AccessToken: 'cached-access-token',
      oauth2RefreshToken: 'cached-refresh-token',
    );

    test('a request that inherits is written without an auth block, not as an explicit noauth', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [
          _apiRequest('inherits', const RequestAuth(type: AuthType.inherit)),
          _apiRequest('none', RequestAuth.none),
          _apiRequest('bearer', const RequestAuth(type: AuthType.bearer, bearerToken: 'abc')),
        ],
      );

      final items = (jsonDecode(json) as Map<String, dynamic>)['item'] as List;
      Map<String, dynamic> requestOf(int index) => (items[index] as Map<String, dynamic>)['request'] as Map<String, dynamic>;
      expect(requestOf(0).containsKey('auth'), isFalse);
      expect((requestOf(1)['auth'] as Map)['type'], 'noauth');
      expect((requestOf(2)['auth'] as Map)['type'], 'bearer');
    });

    test('the collection auth is written at the root, without its cached tokens', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [_apiRequest('inherits', const RequestAuth(type: AuthType.inherit))],
        collectionAuth: oauth,
      );

      expect((jsonDecode(json) as Map<String, dynamic>)['auth']['type'], 'oauth2');
      expect(json, isNot(contains('cached-access-token')));
      expect(json, isNot(contains('cached-refresh-token')));
    });

    test('no collection auth means no root auth block', () {
      final json = PostmanCollectionExporter.export(collectionName: 'X', folders: const [], requests: const []);

      expect((jsonDecode(json) as Map<String, dynamic>).containsKey('auth'), isFalse);
    });

    test('export -> import keeps inherit, none and the collection auth', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [
          _apiRequest('inherits', const RequestAuth(type: AuthType.inherit)),
          _apiRequest('none', RequestAuth.none),
          _apiRequest('bearer', const RequestAuth(type: AuthType.bearer, bearerToken: 'abc')),
        ],
        collectionAuth: oauth,
      );

      final reimported = PostmanCollectionParser.parse(json);
      expect(reimported.auth?.type, AuthType.oauth2);
      expect(reimported.auth?.oauth2AccessTokenUrl, 'https://auth.example.com/token');
      expect(reimported.auth?.oauth2ClientId, 'cid');
      expect(reimported.auth?.oauth2ClientSecret, 'sec');
      expect(reimported.auth?.oauth2Scope, 'read write');
      expect(_request(reimported.items[0]).auth.type, AuthType.inherit);
      expect(_request(reimported.items[1]).auth.type, AuthType.none);
      expect(_request(reimported.items[2]).auth.bearerToken, 'abc');
    });

    test('a collection without stored auth re-imports without one', () {
      final json = PostmanCollectionExporter.export(
        collectionName: 'X',
        folders: const [],
        requests: [_apiRequest('inherits', const RequestAuth(type: AuthType.inherit))],
      );

      expect(PostmanCollectionParser.parse(json).auth, isNull);
    });
  });
}
