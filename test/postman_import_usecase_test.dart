import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'support/in_memory_import_export_fakes.dart';

Map<String, Object?> _script(List<String> lines) => {
  'event': [
    {
      'listen': 'test',
      'script': {'type': 'text/javascript', 'exec': lines},
    },
  ],
};

final _shop = jsonEncode({
  'info': {'name': 'Shop'},
  'variable': [
    {'key': 'baseUrl', 'value': 'https://shop.test'},
  ],
  'item': [
    {
      'name': 'Auth',
      'variable': [
        {'key': 'role', 'value': 'admin'},
      ],
      'item': [
        {
          'name': 'Login',
          'request': {
            'method': 'POST',
            'url': {'raw': '{{baseUrl}}/login'},
          },
          ..._script([
            'var jsonData = pm.response.json();',
            'pm.test("ok", function () { pm.response.to.have.status(200); });',
            'pm.environment.set("token", jsonData.token);',
            'console.log(jsonData);',
          ]),
        },
      ],
    },
    {
      'name': 'Get order',
      'request': {
        'method': 'GET',
        'url': {
          'raw': '{{baseUrl}}/orders/:id',
          'variable': [
            {'key': 'id', 'value': '7'},
          ],
        },
        'auth': {'type': 'hawk'},
      },
      ..._script(['pm.expect(pm.response.responseTime).to.be.below(300);', "tests['x'] = true;"]),
    },
  ],
});

void main() {
  late InMemoryDb db;
  late ImportPostmanCollectionUseCase useCase;

  setUp(() {
    db = InMemoryDb();
    useCase = ImportPostmanCollectionUseCase(
      db.collectionRepository,
      db.requestRepository,
      db.collectionVariableRepository,
      db.collectionAuthRepository,
      db.scriptsRepository,
    );
  });

  test('importWithSummary stores the requests, the translated scripts and the merged variables', () async {
    final summary = await useCase.importWithSummary(_shop);

    final collectionId = summary.collectionIds.single;
    expect(db.collections.single.name, 'Shop');
    expect(db.folders.map((f) => f.name), ['Auth']);
    final login = db.requests.firstWhere((r) => r.name == 'Login');
    final order = db.requests.firstWhere((r) => r.name == 'Get order');
    expect(order.url, '{{baseUrl}}/orders/7');
    expect(order.auth.type, AuthType.none, reason: 'hawk is not supported');

    // The folder variable joined the collection's.
    expect(db.variables.where((v) => v.collectionId == collectionId).map((v) => (v.key, v.value)), [
      ('baseUrl', 'https://shop.test'),
      ('role', 'admin'),
    ]);

    final loginAssertions = ScriptsJsonCodec.decodeAssertions(db.scripts[login.id]!.assertionsJson);
    expect(loginAssertions.map((a) => (a.type, a.expected)), [(AssertionType.statusEquals, '200')]);
    final loginExtractors = ScriptsJsonCodec.decodeExtractors(db.scripts[login.id]!.extractorsJson);
    expect(loginExtractors.map((x) => (x.source, x.path, x.scope, x.variableKey)), [
      (ExtractorSource.jsonPath, 'token', ExtractorScope.environment, 'token'),
    ]);
    final orderAssertions = ScriptsJsonCodec.decodeAssertions(db.scripts[order.id]!.assertionsJson);
    expect(orderAssertions.map((a) => (a.type, a.expected)), [(AssertionType.responseTimeBelowMs, '300')]);
    expect(ScriptsJsonCodec.decodeExtractors(db.scripts[order.id]!.extractorsJson), isEmpty);
  });

  test('the summary counts what was imported and lists what was left out, skipped items before changes', () async {
    final summary = await useCase.importWithSummary(_shop);

    expect(summary.format, ImportFormat.postman);
    expect(summary.collectionName, 'Shop');
    expect((summary.folders, summary.requests, summary.skipped), (1, 2, 2));
    expect(summary.description, 'Imported "Shop": 1 folder, 2 requests (2 skipped)');
    expect(summary.notesHeading, 'Imported with 2 skipped items');
    expect(summary.notes, [
      "Test scripts were converted to 2 checks and 1 variable extractor on the requests' Tests tab.",
      "Request \"Get order\": test script statement not converted: tests['x'] = true",
      'Request "Get order": "hawk" authentication is not supported, so it was imported without authentication.',
      'Folder "Auth": 1 variable imported as collection variable (PostPilot has no folder-level variables).',
      'Request "Get order": path variable :id was written into the URL (PostPilot has no :path variables).',
    ]);
  });

  test('call() keeps returning just the new collection id', () async {
    final id = await useCase(_shop);
    expect(db.collections.single.id, id);
  });

  test('an export with nothing to report has no notes, so the dialog can close at once', () async {
    final summary = await useCase.importWithSummary(
      jsonEncode({
        'info': {'name': 'Plain'},
        'item': [
          {'name': 'Ping', 'request': 'https://a.test/ping'},
        ],
      }),
    );
    expect(summary.skipped, 0);
    expect(summary.notes, isEmpty);
    expect(db.scripts, isEmpty, reason: 'no row for a request without scripts');
    expect(db.requests.single.url, 'https://a.test/ping');
  });

  test('a failure while saving removes the half-built collection, scripts included', () async {
    db.failSaveRequestOnCall = 2;

    await expectLater(useCase.importWithSummary(_shop), throwsA(isA<StateError>()));

    expect(db.collections, isEmpty);
    expect(db.requests, isEmpty);
    expect(db.scripts, isEmpty);
  });
}
