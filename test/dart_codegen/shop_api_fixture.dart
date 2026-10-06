// A small shop API as a collection would hold it: two folders, a loose request, saved examples with
// nested objects, lists, dates, integers and decimals, a nullable field, secrets, and error examples.
// The expectations in the test generator tests are worked out by hand from this data.
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';

const shopSecretToken = 'sk_live_abcdefghijklmnopqrstuv';
const shopSecretPin = 4321;

const _usersList = '''
{
  "data": [
    {
      "id": 1,
      "name": "Ann",
      "email": "ann@example.com",
      "created_at": "2026-10-02T10:00:00Z",
      "balance": 12.5,
      "role": "admin",
      "active": true,
      "manager": null,
      "tags": ["vip", "beta"],
      "api_token": "$shopSecretToken",
      "pin": $shopSecretPin
    },
    {
      "id": 2,
      "name": "Bob",
      "email": "bob@example.com",
      "created_at": "2026-10-03T08:30:00+02:00",
      "balance": 7,
      "role": "member",
      "active": false,
      "manager": null,
      "tags": [],
      "api_token": "$shopSecretToken",
      "pin": $shopSecretPin
    }
  ],
  "total": 2,
  "next_cursor": null
}
''';

const _user = '''
{
  "id": 42,
  "name": "Ann",
  "address": {"city": "Oslo", "zip": "0150", "geo": {"lat": 59.91, "lng": 10.75}},
  "orders": [{"id": 10, "total": 9.99}, {"id": 11, "total": 20}],
  "joined": "2026-01-15"
}
''';

List<ApiSpecRequest> shopApiRequests() => const [
      ApiSpecRequest(
        name: 'List users',
        method: 'GET',
        url: '{{baseUrl}}/users',
        query: [('page', '{{page}}'), ('limit', '20'), ('status', 'active')],
        folders: ['Users'],
        exampleResponse: _usersList,
        examples: [
          ApiSpecExample(name: 'OK', statusCode: 200, body: _usersList),
          ApiSpecExample(name: 'Unauthorized', statusCode: 401, body: '{"message":"Unauthorized","code":401}'),
          ApiSpecExample(name: 'Gateway', statusCode: 502, body: '<html>Bad Gateway</html>'),
        ],
      ),
      ApiSpecRequest(
        name: 'Get user',
        method: 'GET',
        url: '{{baseUrl}}/users/{{userId}}',
        folders: ['Users'],
        exampleResponse: _user,
        examples: [
          ApiSpecExample(name: 'Found', statusCode: 200, body: _user),
          ApiSpecExample(name: 'Not found', statusCode: 404, body: '{"error":"not_found"}'),
        ],
      ),
      ApiSpecRequest(
        name: 'Create user',
        method: 'POST',
        url: '{{baseUrl}}/users',
        headers: [('X-Tenant', '{{tenant}}'), ('Authorization', 'Bearer {{token}}')],
        bodyKind: ApiBodyKind.json,
        bodyText: '{"name":"Ann","email":"ann@example.com","age":{{age}},"password":"hunter2-secret"}',
        folders: ['Users'],
        exampleResponse: '{"id":3,"name":"Ann"}',
        examples: [
          ApiSpecExample(name: 'Created', statusCode: 201, body: '{"id":3,"name":"Ann"}'),
          ApiSpecExample(name: 'Invalid', statusCode: 422, body: '{"errors":[{"field":"email","message":"invalid"}]}'),
        ],
      ),
      ApiSpecRequest(
        name: 'Rename user',
        method: 'PATCH',
        url: '{{baseUrl}}/users/:id',
        bodyKind: ApiBodyKind.json,
        bodyText: '[{"op":"replace","path":"/name","value":"Ann"}]',
        folders: ['Users'],
        exampleResponse: '[1, 2, 3]',
      ),
      ApiSpecRequest(name: 'Delete user', method: 'DELETE', url: '{{baseUrl}}/users/:id', folders: ['Users']),
      ApiSpecRequest(
        name: 'List orders',
        method: 'GET',
        url: '{{baseUrl}}/orders',
        folders: ['Orders'],
        exampleResponse: '[{"id":10,"total":9.99,"items":[{"sku":"a-1","qty":2}],"placed_at":"2026-10-03"},'
            '{"id":11,"total":20,"items":[],"placed_at":"2026-10-04","note":"gift"}]',
      ),
      ApiSpecRequest(
        name: 'Upload receipt',
        method: 'POST',
        url: '{{baseUrl}}/orders/{{orderId}}/receipt',
        bodyKind: ApiBodyKind.form,
        folders: ['Orders'],
      ),
      ApiSpecRequest(
        name: 'Search',
        method: 'POST',
        url: '{{baseUrl}}/graphql',
        bodyKind: ApiBodyKind.graphql,
        bodyText: 'query { me { id } }',
        folders: ['Orders'],
      ),
      ApiSpecRequest(
        name: 'Health',
        method: 'GET',
        url: '{{baseUrl}}/health',
        exampleResponse: 'ok',
        examples: [ApiSpecExample(name: 'Up', statusCode: 200, body: 'ok')],
      ),
    ];
