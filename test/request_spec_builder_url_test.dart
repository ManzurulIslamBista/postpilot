import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';

String _urlOf(
  String url, {
  List<KeyValueItem> params = const [],
  Map<String, String> variables = const {},
  RequestAuth auth = const RequestAuth(type: AuthType.none),
}) =>
    const RequestSpecBuilder()
        .build(
          ApiRequestEntity(
            id: 1,
            collectionId: 10,
            folderId: null,
            name: 'r',
            method: HttpMethod.get,
            url: url,
            headers: const [],
            queryParams: params,
            body: RequestBody.empty,
            auth: auth,
          ),
          VariableResolver(variables),
        )
        .url;

void main() {
  group('scheme', () {
    test('a URL without one defaults to http://, host:port included', () {
      expect(_urlOf('localhost:3000/api/users'), 'http://localhost:3000/api/users');
      expect(_urlOf('api.example.com/v1/users'), 'http://api.example.com/v1/users');
      expect(_urlOf('  api.example.com  '), 'http://api.example.com');
    });

    test('an explicit scheme is left alone, whatever its case', () {
      expect(_urlOf('https://api.example.com/users'), 'https://api.example.com/users');
      expect(_urlOf('HTTPS://api.example.com/users'), 'HTTPS://api.example.com/users');
    });

    test('a :// further along (a redirect target in the query) is not mistaken for the scheme', () {
      expect(_urlOf('example.com/go?to=https://other.com'), 'http://example.com/go?to=https://other.com');
    });

    test('is applied after variables resolve, so a variable can carry the scheme', () {
      expect(_urlOf('{{host}}/users', variables: {'host': 'api.example.com'}), 'http://api.example.com/users');
      expect(_urlOf('{{base}}/users', variables: {'base': 'https://api.example.com'}), 'https://api.example.com/users');
    });

    test('an empty URL stays empty', () {
      expect(_urlOf(''), '');
    });
  });

  group('query params', () {
    test('a repeated key is sent once per row', () {
      final url = _urlOf('https://api.example.com/items', params: [
        KeyValueItem(key: 'tag', value: 'a'),
        KeyValueItem(key: 'tag', value: 'b'),
      ]);

      expect(url, 'https://api.example.com/items?tag=a&tag=b');
    });

    test('keeps every entry of the URL\'s own query, repeats included', () {
      final url = _urlOf('https://api.example.com/items?ids=1&ids=2', params: [KeyValueItem(key: 'page', value: '1')]);

      expect(url, 'https://api.example.com/items?ids=1&ids=2&page=1');
    });

    test('a param replaces the same-named entry in the URL\'s own query', () {
      final url = _urlOf('https://api.example.com/items?page=9&sort=asc', params: [KeyValueItem(key: 'page', value: '1')]);

      expect(Uri.parse(url).queryParametersAll, {'sort': ['asc'], 'page': ['1']});
    });

    test('disabled and blank-keyed rows are skipped, values are resolved and encoded', () {
      final url = _urlOf(
        'https://api.example.com/items',
        variables: {'q': 'a b'},
        params: [
          KeyValueItem(key: 'q', value: '{{q}}'),
          KeyValueItem(key: 'off', value: '1', enabled: false),
          KeyValueItem(key: '', value: 'x'),
        ],
      );

      expect(url, 'https://api.example.com/items?q=a+b');
    });

    test('an API key sent in the query replaces a same-named param', () {
      final url = _urlOf(
        'https://api.example.com/items',
        params: [KeyValueItem(key: 'key', value: 'old')],
        auth: const RequestAuth(
          type: AuthType.apiKey,
          apiKeyName: 'key',
          apiKeyValue: 'secret',
          apiKeyLocation: ApiKeyLocation.query,
        ),
      );

      expect(url, 'https://api.example.com/items?key=secret');
    });
  });
}
