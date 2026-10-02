import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/enums/auth_type.dart';
import '../../../core/enums/body_type.dart';
import '../../../core/enums/http_method.dart';
import '../../import_export/domain/entities/imported_collection.dart';
import '../../odoo/domain/services/odoo_json2.dart';
import '../../request_builder/domain/entities/key_value_item.dart';
import '../../request_builder/domain/entities/request_auth.dart';
import '../../request_builder/domain/entities/request_body.dart';

/// A ready-made collection (and the environment it uses) a person can add with one click.
final class StarterTemplate {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<String> tags;
  final ImportedCollection collection;

  /// An environment created beside the collection; null when none is needed.
  final String? environmentName;
  final List<TemplateVariable> environmentVariables;

  const StarterTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.tags,
    required this.collection,
    this.environmentName,
    this.environmentVariables = const [],
  });

  int get requestCount => collection.requestCount;
}

final class TemplateVariable {
  final String key;
  final String value;
  final bool secret;
  const TemplateVariable(this.key, this.value, {this.secret = false});
}

/// The templates offered in the gallery. They point at free public sandboxes
/// (JSONPlaceholder, httpbin, a public GraphQL API), so each one works the
/// moment it is added, with no account or key.
abstract final class StarterTemplates {
  static List<StarterTemplate> all() => [_rest(), _httpbin(), _graphql(), _odoo()];

  static RequestBody _json(Object value) =>
      RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: const JsonEncoder.withIndent('  ').convert(value));

  static final _jsonHeader = [KeyValueItem(key: 'Content-Type', value: 'application/json; charset=UTF-8')];

  static StarterTemplate _rest() => StarterTemplate(
        id: 'rest',
        title: 'REST basics',
        description: 'A full CRUD set against JSONPlaceholder: list, read, create, update, delete, plus nested resources.',
        icon: Icons.api_outlined,
        tags: const ['REST', 'beginner'],
        environmentName: 'JSONPlaceholder',
        environmentVariables: const [TemplateVariable('baseUrl', 'https://jsonplaceholder.typicode.com')],
        collection: ImportedCollection('REST basics', [
          ImportedFolder('Posts', [
            const ImportedRequest('List posts', method: HttpMethod.get, url: '{{baseUrl}}/posts'),
            const ImportedRequest('Get a post', method: HttpMethod.get, url: '{{baseUrl}}/posts/1'),
            ImportedRequest('Create a post', method: HttpMethod.post, url: '{{baseUrl}}/posts', headers: _jsonHeader, body: _json({'title': 'Hello', 'body': 'From PostPilot', 'userId': 1})),
            ImportedRequest('Update a post', method: HttpMethod.put, url: '{{baseUrl}}/posts/1', headers: _jsonHeader, body: _json({'id': 1, 'title': 'Updated', 'body': 'New text', 'userId': 1})),
            ImportedRequest('Patch a post', method: HttpMethod.patch, url: '{{baseUrl}}/posts/1', headers: _jsonHeader, body: _json({'title': 'Only the title'})),
            const ImportedRequest('Delete a post', method: HttpMethod.delete, url: '{{baseUrl}}/posts/1'),
            ImportedRequest('Posts of a user', method: HttpMethod.get, url: '{{baseUrl}}/posts', queryParams: [KeyValueItem(key: 'userId', value: '1')]),
          ]),
          const ImportedFolder('Users', [
            ImportedRequest('List users', method: HttpMethod.get, url: '{{baseUrl}}/users'),
            ImportedRequest('Get a user', method: HttpMethod.get, url: '{{baseUrl}}/users/1'),
            ImportedRequest('Comments of a post', method: HttpMethod.get, url: '{{baseUrl}}/posts/1/comments'),
          ]),
        ]),
      );

  static StarterTemplate _httpbin() => StarterTemplate(
        id: 'httpbin',
        title: 'Auth, headers and status codes',
        description: 'httpbin requests for the things that trip people up: every auth type, echoed headers, status codes and slow responses.',
        icon: Icons.lock_outline,
        tags: const ['auth', 'testing'],
        environmentName: 'httpbin',
        environmentVariables: const [
          TemplateVariable('baseUrl', 'https://httpbin.org'),
          TemplateVariable('token', 'my-secret-token', secret: true),
        ],
        collection: ImportedCollection('Auth, headers and status codes', [
          ImportedFolder('Auth', [
            ImportedRequest('Bearer token', method: HttpMethod.get, url: '{{baseUrl}}/bearer', auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}')),
            ImportedRequest('Basic auth', method: HttpMethod.get, url: '{{baseUrl}}/basic-auth/user/passwd', auth: const RequestAuth(type: AuthType.basic, basicUsername: 'user', basicPassword: 'passwd')),
            ImportedRequest('API key header', method: HttpMethod.get, url: '{{baseUrl}}/headers', headers: [KeyValueItem(key: 'X-Api-Key', value: '{{token}}')]),
          ]),
          ImportedFolder('Inspect your request', [
            ImportedRequest('Echo headers', method: HttpMethod.get, url: '{{baseUrl}}/headers'),
            ImportedRequest('Echo query', method: HttpMethod.get, url: '{{baseUrl}}/get', queryParams: [KeyValueItem(key: 'hello', value: 'world')]),
            ImportedRequest('Echo JSON body', method: HttpMethod.post, url: '{{baseUrl}}/post', body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '{\n  "name": "PostPilot"\n}')),
            ImportedRequest('Your IP', method: HttpMethod.get, url: '{{baseUrl}}/ip'),
          ]),
          ImportedFolder('Behaviour', [
            ImportedRequest('Status 404', method: HttpMethod.get, url: '{{baseUrl}}/status/404'),
            ImportedRequest('Status 500', method: HttpMethod.get, url: '{{baseUrl}}/status/500'),
            ImportedRequest('Delay 3 seconds', method: HttpMethod.get, url: '{{baseUrl}}/delay/3'),
            ImportedRequest('Redirect', method: HttpMethod.get, url: '{{baseUrl}}/redirect/2'),
            ImportedRequest('Set a cookie', method: HttpMethod.get, url: '{{baseUrl}}/cookies/set', queryParams: [KeyValueItem(key: 'session', value: 'abc123')]),
          ]),
        ]),
      );

  static StarterTemplate _graphql() => StarterTemplate(
        id: 'graphql',
        title: 'GraphQL basics',
        description: 'Queries with variables against a public countries API. Open the GraphQL explorer from the body editor to browse its schema.',
        icon: Icons.hexagon_outlined,
        tags: const ['GraphQL'],
        environmentName: 'Countries GraphQL',
        environmentVariables: const [TemplateVariable('graphqlUrl', 'https://countries.trevorblades.com/graphql')],
        collection: ImportedCollection('GraphQL basics', [
          ImportedRequest(
            'All countries',
            method: HttpMethod.post,
            url: '{{graphqlUrl}}',
            body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'query Countries {\n  countries {\n    code\n    name\n    emoji\n  }\n}', graphqlVariables: '{}'),
          ),
          ImportedRequest(
            'One country',
            method: HttpMethod.post,
            url: '{{graphqlUrl}}',
            body: const RequestBody(
              type: BodyType.graphql,
              graphqlQuery: 'query Country(\$code: ID!) {\n  country(code: \$code) {\n    name\n    capital\n    currency\n    languages {\n      name\n    }\n  }\n}',
              graphqlVariables: '{\n  "code": "BD"\n}',
            ),
          ),
          ImportedRequest(
            'Continents',
            method: HttpMethod.post,
            url: '{{graphqlUrl}}',
            body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'query Continents {\n  continents {\n    code\n    name\n  }\n}', graphqlVariables: '{}'),
          ),
        ]),
      );

  static StarterTemplate _odoo() {
    final requests = OdooJson2.templatesFor('res.partner', sampleFields: const ['name', 'email', 'phone']);
    return StarterTemplate(
      id: 'odoo',
      title: 'Odoo JSON-2',
      description: 'Search, read, create, update and delete contacts on an Odoo 19+ server. Fill in the URL, database and API key in the environment.',
      icon: Icons.hub_outlined,
      tags: const ['Odoo', 'JSON-2'],
      environmentName: 'Odoo',
      environmentVariables: const [
        TemplateVariable(OdooVars.url, 'https://your-company.odoo.com'),
        TemplateVariable(OdooVars.database, ''),
        TemplateVariable(OdooVars.apiKey, '', secret: true),
      ],
      collection: ImportedCollection('Odoo · res.partner', [
        for (final d in requests)
          ImportedRequest(
            d.name,
            method: HttpMethod.post,
            url: d.url,
            headers: [for (final e in d.headers.entries) KeyValueItem(key: e.key, value: e.value)],
            body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: d.bodyText),
          ),
      ]),
    );
  }
}
