import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_openapi_usecase.dart';
import 'support/in_memory_import_export_fakes.dart';

const _secured = '''
{
  "openapi": "3.0.3",
  "info": { "title": "Pet Store" },
  "servers": [{ "url": "https://api.example.com/v1" }],
  "components": {
    "securitySchemes": {
      "bearerAuth": { "type": "http", "scheme": "bearer" },
      "keyAuth": { "type": "apiKey", "in": "header", "name": "X-Api-Key" }
    }
  },
  "paths": {
    "/pets/{petId}": {
      "get": {
        "summary": "Get pet",
        "security": [{ "bearerAuth": [] }],
        "parameters": [{ "name": "petId", "in": "path", "required": true, "schema": { "type": "string" } }]
      }
    },
    "/keyed": { "get": { "summary": "Keyed", "security": [{ "keyAuth": [] }] } }
  }
}
''';

void main() {
  late InMemoryDb db;
  late ImportOpenApiUseCase useCase;

  setUp(() {
    db = InMemoryDb();
    useCase = ImportOpenApiUseCase(
      db.collectionRepository,
      db.requestRepository,
      db.collectionVariableRepository,
      db.environmentRepository,
    );
  });

  test('every variable the requests reference gets an empty environment entry, secrets marked by name', () async {
    final summary = await useCase.importWithSummary(_secured);

    // `baseUrl` is the collection's own variable, so it is not repeated in the environment.
    final collectionId = summary.collectionIds.single;
    expect(db.variables.where((v) => v.collectionId == collectionId).map((v) => (v.key, v.value)), [
      ('baseUrl', 'https://api.example.com/v1'),
    ]);
    final environment = db.environments.single;
    expect(environment.name, 'Pet Store');
    expect(environment.isActive, isFalse, reason: 'switching the active environment is the user\'s call');
    expect(db.environmentVariables.map((v) => (v.environmentId, v.key, v.value, v.isSecret, v.enabled)), [
      (environment.id, 'petId', '', false, true),
      (environment.id, 'token', '', true, true),
      (environment.id, 'apiKey', '', true, true),
    ]);

    expect(summary.format, ImportFormat.openApi);
    expect((summary.requests, summary.folders, summary.environments), (2, 0, 1));
    expect(summary.description, 'Imported "Pet Store": 2 requests, 1 environment');
    expect(summary.notes, [
      'Created the environment "Pet Store" with 3 empty variables the requests use (petId; token, secret; apiKey, secret). '
          'Select it and fill in the values.',
    ]);
  });

  test('every {{variable}} of the imported requests is defined by the collection or the new environment', () async {
    final summary = await useCase.importWithSummary(_secured);

    final defined = {
      for (final v in db.variables) v.key,
      for (final v in db.environmentVariables) v.key,
    };
    final pattern = RegExp(r'\{\{([\w.$-]+)\}\}');
    for (final request in db.requestsOf(summary.collectionIds.single)) {
      final text = [request.url, request.auth.bearerToken, request.auth.apiKeyValue].join(' ');
      for (final match in pattern.allMatches(text)) {
        expect(defined, contains(match.group(1)), reason: '${request.name} uses ${match.group(0)}');
      }
    }
  });

  test('a document that needs nothing beyond its server creates no environment and no note', () async {
    final summary = await useCase.importWithSummary(
      '{"openapi":"3.0.3","info":{"title":"Plain"},"servers":[{"url":"https://p.test"}],"paths":{"/ping":{"get":{"summary":"Ping"}}}}',
    );

    expect(db.environments, isEmpty);
    expect(summary.environments, 0);
    expect(summary.notes, isEmpty);
    expect(summary.description, 'Imported "Plain": 1 request');
  });

  test('without a server, baseUrl itself is left to the environment', () async {
    final summary = await useCase.importWithSummary(
      '{"openapi":"3.0.3","info":{"title":"No server"},"paths":{"/ping":{"get":{"summary":"Ping"}}}}',
    );

    expect(db.variables, isEmpty);
    expect(db.environmentVariables.map((v) => (v.key, v.isSecret)), [('baseUrl', false)]);
    expect(summary.notes.single, startsWith('Created the environment "No server" with 1 empty variable the requests use (baseUrl).'));
  });

  test('an existing environment of the same name is left alone', () async {
    await db.environmentRepository.create('Pet Store');

    await useCase.importWithSummary(_secured);

    expect(db.environments.map((e) => e.name), ['Pet Store', 'Pet Store (imported)']);
    expect(db.environmentVariables.map((v) => v.environmentId).toSet(), {db.environments.last.id});
  });

  test('call() still returns the collection id', () async {
    final id = await useCase(_secured);
    expect(db.collections.single.id, id);
  });

  test('a failure while creating the environment removes the collection as well', () async {
    db.failCreateEnvironmentOnCall = 1;

    await expectLater(useCase.importWithSummary(_secured), throwsA(isA<StateError>()));

    expect(db.collections, isEmpty);
    expect(db.requests, isEmpty);
    expect(db.environments, isEmpty);
  });
}
