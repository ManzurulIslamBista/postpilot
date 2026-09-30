import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

ApiRequestEntity _request({
  String url = 'https://api.example.com/items',
  List<KeyValueItem> queryParams = const [],
  RequestAuth auth = const RequestAuth(),
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 10,
      folderId: null,
      name: 'List items',
      method: HttpMethod.get,
      url: url,
      headers: const [],
      queryParams: queryParams,
      body: RequestBody.empty,
      auth: auth,
    );

String _export(ApiRequestEntity request) =>
    PostmanCollectionExporter.export(collectionName: 'C', folders: const [], requests: [request]);

Map<String, dynamic> _exportedRequest(String json) =>
    ((jsonDecode(json)['item'] as List).single as Map<String, dynamic>)['request'] as Map<String, dynamic>;

void main() {
  test('enabled Params are appended to the exported URL and every param is listed under query', () {
    final json = _export(_request(queryParams: [
      KeyValueItem(key: 'page', value: '2'),
      KeyValueItem(key: 'debug', value: '1', enabled: false),
    ]));

    final url = _exportedRequest(json)['url'] as Map<String, dynamic>;
    expect(url['raw'], 'https://api.example.com/items?page=2');
    expect((url['query'] as List).map((q) => '${q['key']}:${q['disabled']}'), ['page:false', 'debug:true']);
  });

  test('Params join onto a query string the URL already has', () {
    final json = _export(_request(url: 'https://api.example.com/items?sort=asc', queryParams: [
      KeyValueItem(key: 'page', value: '2'),
    ]));

    expect((_exportedRequest(json)['url'] as Map)['raw'], 'https://api.example.com/items?sort=asc&page=2');
  });

  test('a request without Params keeps a plain url and no query array', () {
    final url = _exportedRequest(_export(_request()))['url'] as Map<String, dynamic>;

    expect(url['raw'], 'https://api.example.com/items');
    expect(url.containsKey('query'), isFalse);
  });

  test('re-importing keeps enabled Params in the URL and disabled ones as disabled Params', () {
    final json = _export(_request(queryParams: [
      KeyValueItem(key: 'page', value: '2'),
      KeyValueItem(key: 'debug', value: '1', enabled: false),
    ]));

    final reimported = PostmanCollectionParser.parse(json).items.single as PostmanRequestItem;
    expect(reimported.url, 'https://api.example.com/items?page=2');
    expect(reimported.queryParams.map((p) => p.key), ['debug']);
    expect(reimported.queryParams.single.enabled, isFalse);
  });

  test('a request that inherits its auth exports no auth block and re-imports as inherit', () {
    final json = _export(_request());

    expect(_exportedRequest(json).containsKey('auth'), isFalse);
    expect((PostmanCollectionParser.parse(json).items.single as PostmanRequestItem).auth.type, AuthType.inherit);
  });
}
