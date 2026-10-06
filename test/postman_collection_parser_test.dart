import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

void main() {
  test('parses collection name and a flat list of requests', () {
    const json = '''
    {
      "info": { "name": "My API" },
      "item": [
        {
          "name": "Get user",
          "request": {
            "method": "GET",
            "header": [{"key": "Accept", "value": "application/json"}],
            "url": { "raw": "https://api.example.com/users/1" }
          }
        }
      ]
    }
    ''';

    final parsed = PostmanCollectionParser.parse(json);
    expect(parsed.name, 'My API');
    expect(parsed.items, hasLength(1));

    final request = parsed.items.single as PostmanRequestItem;
    expect(request.name, 'Get user');
    expect(request.method, HttpMethod.get);
    expect(request.url, 'https://api.example.com/users/1');
    expect(request.headers.single.key, 'Accept');
  });

  test('nested folders become PostmanFolderItem with children', () {
    const json = '''
    {
      "info": { "name": "Nested" },
      "item": [
        {
          "name": "Users",
          "item": [
            { "name": "List", "request": { "method": "GET", "url": "https://api.example.com/users" } }
          ]
        }
      ]
    }
    ''';

    final parsed = PostmanCollectionParser.parse(json);
    final folder = parsed.items.single as PostmanFolderItem;
    expect(folder.name, 'Users');
    expect(folder.children, hasLength(1));
    expect((folder.children.single as PostmanRequestItem).name, 'List');
  });

  test('raw JSON body maps to BodyType.raw with the right content type', () {
    const json = '''
    {
      "info": { "name": "C" },
      "item": [{
        "name": "Create",
        "request": {
          "method": "POST",
          "url": "https://api.example.com/users",
          "body": { "mode": "raw", "raw": "{\\"name\\":\\"John\\"}", "options": { "raw": { "language": "json" } } }
        }
      }]
    }
    ''';

    final request = PostmanCollectionParser.parse(json).items.single as PostmanRequestItem;
    expect(request.body.type, BodyType.raw);
    expect(request.body.rawContentType, RawContentType.json);
    expect(request.body.rawText, '{"name":"John"}');
  });

  test('bearer auth maps to AuthType.bearer with the token', () {
    const json = '''
    {
      "info": { "name": "C" },
      "item": [{
        "name": "Get",
        "request": {
          "method": "GET",
          "url": "https://api.example.com",
          "auth": { "type": "bearer", "bearer": [{ "key": "token", "value": "abc123" }] }
        }
      }]
    }
    ''';

    final request = PostmanCollectionParser.parse(json).items.single as PostmanRequestItem;
    expect(request.auth.type, AuthType.bearer);
    expect(request.auth.bearerToken, 'abc123');
  });

  test('graphql body maps query and variables', () {
    const json = r'''
    {
      "info": { "name": "C" },
      "item": [{
        "name": "Query",
        "request": {
          "method": "POST",
          "url": "https://api.example.com/graphql",
          "body": { "mode": "graphql", "graphql": { "query": "{ me { id } }", "variables": "{}" } }
        }
      }]
    }
    ''';

    final request = PostmanCollectionParser.parse(json).items.single as PostmanRequestItem;
    expect(request.body.type, BodyType.graphql);
    expect(request.body.graphqlQuery, '{ me { id } }');
  });

  test('file-type form fields come in as file rows rather than crashing or being dropped', () {
    const json = '''
    {
      "info": { "name": "C" },
      "item": [{
        "name": "Upload",
        "request": {
          "method": "POST",
          "url": "https://api.example.com/upload",
          "body": { "mode": "formdata", "formdata": [
            { "key": "title", "value": "hello", "type": "text" },
            { "key": "file", "type": "file", "src": "/some/local/path.png" }
          ]}
        }
      }]
    }
    ''';

    final request = PostmanCollectionParser.parse(json).items.single as PostmanRequestItem;
    expect(request.body.type, BodyType.formData);
    expect(request.body.formFields.map((f) => (f.key, f.value, f.isFile)), [('title', 'hello', false), ('file', '/some/local/path.png', true)]);
  });

  test('collection-level variables are parsed, tolerating disabled and non-string values', () {
    const json = '''
    {
      "info": { "name": "C" },
      "item": [],
      "variable": [
        { "id": "1", "key": "baseUrl", "value": "https://api.example.com", "type": "string" },
        { "key": "retries", "value": 3 },
        { "key": "off", "value": "x", "disabled": true },
        { "value": "no key, skipped" }
      ]
    }
    ''';

    final variables = PostmanCollectionParser.parse(json).variables;
    expect(variables.map((v) => v.key), ['baseUrl', 'retries', 'off']);
    expect(variables.map((v) => v.value), ['https://api.example.com', '3', 'x']);
    expect(variables.map((v) => v.enabled), [true, true, false]);
  });

  test('a collection without a variable array has no variables', () {
    final parsed = PostmanCollectionParser.parse('{ "info": { "name": "C" }, "item": [] }');
    expect(parsed.variables, isEmpty);
  });
}
