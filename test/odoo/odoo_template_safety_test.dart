import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/templates/domain/starter_templates.dart';
import '../support/drift_repos.dart';

void main() {
  final templates = OdooJson2.templatesFor('res.partner', sampleFields: const ['name']);
  OdooRequestDraft named(String name) => templates.firstWhere((d) => d.name == name);

  group('ready-made Odoo requests', () {
    test('write and unlink take the record id from an undefined variable, not a literal 1', () {
      for (final name in ['Update res.partner', 'Delete res.partner']) {
        final d = named(name);
        expect(d.bodyText, contains('"ids": [{{recordId}}]'), reason: name);
        expect(d.bodyText, isNot(contains('[1]')), reason: name);
        expect(d.bodyText, isNot(contains('"1"')), reason: name);
        expect(d.note, contains('{{recordId}}'), reason: name);
        expect(d.note, contains('undefined'), reason: name);
      }
      // Until the variable is set the body is not JSON, so Odoo rejects it instead of acting on a record.
      expect(() => jsonDecode(named('Delete res.partner').bodyText), throwsFormatException);
      // With a value the id is a number, not a string, and nothing else changed.
      expect(jsonDecode(named('Delete res.partner').bodyText.replaceAll('{{recordId}}', '42')), {'ids': [42]});
      expect(jsonDecode(named('Update res.partner').bodyText.replaceAll('{{recordId}}', '42')), {
        'ids': [42],
        'vals': {'name': 'Updated'},
      });
    });

    test('read-only and model-level requests are unchanged', () {
      expect(jsonDecode(named('Read res.partner by id').bodyText), containsPair('ids', [1]));
      for (final d in templates) {
        if (d.name.startsWith('Update') || d.name.startsWith('Delete')) continue;
        expect(d.bodyText, isNot(contains('{{')), reason: d.name);
      }
    });

    test('the id variable never leaks into the body a direct call sends', () {
      const call = OdooCall(model: 'm', method: 'unlink', ids: [5], idsVariable: 'recordId');
      expect(call.body, {'ids': [5]});
      expect(call.bodyText, contains('{{recordId}}'));
      expect(OdooVars.recordId, 'recordId');
    });

    test('the recordId variable is not part of any starter environment', () {
      final odoo = StarterTemplates.all().firstWhere((t) => t.id == 'odoo');
      expect(odoo.environmentVariables.map((v) => v.key), isNot(contains('recordId')));
      expect(odoo.description, contains('recordId'));
      expect(odoo.description, contains('on purpose'));
    });
  });

  group('saved requests', () {
    late AppDatabase db;
    late DriftRepos repos;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = DriftRepos(db);
    });
    tearDown(() => db.close());

    test('the collection keeps the note of each request as its description', () async {
      final useCase = CreateOdooWorkspaceUseCase(
        repos.environmentRepository,
        repos.collectionRepository,
        repos.requestRepository,
        repos.documentationRepository,
      );
      final result = await useCase.createCollection(name: 'Odoo', models: ['res.partner']);
      final loader = CollectionLoader(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      final loaded = await loader.load(result.collectionId!);
      final delete = loaded.requests.firstWhere((r) => r.name == 'Delete res.partner');
      expect(delete.body.rawText, contains('"ids": [{{recordId}}]'));
      final docs = await repos.documentationRepository.markdownOf(EntityKind.request, delete.id);
      expect(docs, contains('Set the variable {{recordId}}'));
      final list = loaded.requests.firstWhere((r) => r.name == 'List res.partner');
      expect(await repos.documentationRepository.markdownOf(EntityKind.request, list.id), contains('newest first'));
    });

    test('without a documentation store the requests are still created', () async {
      final useCase = CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository);
      final result = await useCase.createCollection(name: 'Odoo', models: ['res.partner']);
      expect(result.requestCount, 10);
    });

    test('the starter collection says which requests wait for the id', () async {
      final odoo = StarterTemplates.all().firstWhere((t) => t.id == 'odoo');
      final names = [for (final item in odoo.collection.items) item.name];
      expect(names, containsAll(['Update res.partner (set recordId first)', 'Delete res.partner (set recordId first)']));
      expect(names.where((n) => n.contains('recordId')), hasLength(2));
    });
  });
}
