import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/services/postman_environment_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_environment_usecase.dart';
import 'support/in_memory_import_export_fakes.dart';

const _export = '''
{
  "id": "e1",
  "name": "Staging",
  "values": [
    {"key": "baseUrl", "value": "https://staging.test", "type": "default", "enabled": true},
    {"key": "apiKey", "value": "abc", "type": "default", "enabled": true},
    {"key": "pw", "value": "x", "type": "secret", "enabled": true},
    {"key": "unused", "value": "y", "type": "default", "enabled": false},
    {"key": "", "value": "z"},
    {"key": "baseUrl", "value": "dup"},
    {"key": "count", "value": 5},
    {"key": "flag", "value": true}
  ],
  "_postman_variable_scope": "environment",
  "_postman_exported_at": "2026-01-01T00:00:00.000Z"
}
''';

const _globals = '''
{"id": "g1", "name": "Workspace Globals", "_postman_variable_scope": "globals", "values": [
  {"key": "host", "value": "https://new.test", "enabled": true},
  {"key": "fresh", "value": "f", "enabled": true},
  {"key": "session_token", "value": "s", "enabled": true}
]}
''';

final class _Unused<Output, Params> implements UseCase<Output, Params> {
  @override
  Future<Output> call(Params params) => throw StateError('the wrong importer ran');
}

void main() {
  group('PostmanEnvironmentParser', () {
    test('reads keys, values, enabled flags and secrets; skips unusable entries with a reason', () {
      final parsed = PostmanEnvironmentParser.parse(_export);

      expect((parsed.name, parsed.isGlobals), ('Staging', false));
      expect(parsed.variables.map((v) => (v.key, v.value, v.enabled, v.isSecret)), [
        ('baseUrl', 'https://staging.test', true, false),
        // `apiKey` is a credential by its name even though the export calls it a plain variable.
        ('apiKey', 'abc', true, true),
        // type "secret" is a secret whatever the name.
        ('pw', 'x', true, true),
        ('unused', 'y', false, false),
        // A hand-edited file may hold numbers and booleans.
        ('count', '5', true, false),
        ('flag', 'true', true, false),
      ]);
      expect(parsed.skipped, [
        'Entry 5 has no variable name, so it was not imported.',
        'Variable "baseUrl" appears more than once; only its first value was imported.',
      ]);
    });

    test('a globals file is marked as such, and a missing name falls back', () {
      final parsed = PostmanEnvironmentParser.parse('{"_postman_variable_scope": "globals", "values": []}');
      expect((parsed.isGlobals, parsed.name), (true, 'Imported environment'));
      expect(parsed.variables, isEmpty);
    });

    test('a leading byte-order mark is ignored', () {
      expect(PostmanEnvironmentParser.parse('﻿{"name": "E", "values": []}').name, 'E');
    });

    test('anything that is not an environment is an ImportException, invalid JSON stays a FormatException', () {
      for (final text in ['[1]', '{"info": {"name": "x"}, "item": []}', '{"values": "no"}']) {
        expect(() => PostmanEnvironmentParser.parse(text), throwsA(isA<ImportException>()), reason: text);
      }
      expect(() => PostmanEnvironmentParser.parse('{"values": ['), throwsA(isA<FormatException>()));
    });
  });

  group('ImportPostmanEnvironmentUseCase', () {
    late InMemoryDb db;
    late ImportPostmanEnvironmentUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportPostmanEnvironmentUseCase(db.environmentRepository, db.globalVariableRepository);
    });

    test('creates one environment with the variables, secret and disabled flags kept', () async {
      final summary = await useCase(_export);

      final environment = db.environments.single;
      expect(environment.name, 'Staging');
      expect(db.environmentVariables.map((v) => (v.environmentId, v.key, v.value, v.isSecret, v.enabled)), [
        (environment.id, 'baseUrl', 'https://staging.test', false, true),
        (environment.id, 'apiKey', 'abc', true, true),
        (environment.id, 'pw', 'x', true, true),
        (environment.id, 'unused', 'y', false, false),
        (environment.id, 'count', '5', false, true),
        (environment.id, 'flag', 'true', false, true),
      ]);
      expect(db.globals, isEmpty);
      expect(summary.format, ImportFormat.postmanEnvironment);
      expect((summary.environments, summary.variables, summary.skipped), (1, 6, 2));
      expect(summary.description, 'Imported "Staging": 1 environment, 6 variables (2 skipped)');
      expect(summary.notes, [
        'Entry 5 has no variable name, so it was not imported.',
        'Variable "baseUrl" appears more than once; only its first value was imported.',
        '1 variable is disabled, as in the export; switch it on to use it.',
        '2 variables were marked secret (type "secret", or a name that looks like a credential).',
      ]);
    });

    test('an existing environment of the same name is never touched: the new one gets a suffix', () async {
      await useCase('{"name": "Staging", "values": [{"key": "a", "value": "1"}]}');
      await useCase('{"name": "Staging", "values": []}');
      await useCase('{"name": "Staging", "values": []}');

      expect(db.environments.map((e) => e.name), ['Staging', 'Staging (imported)', 'Staging (imported 2)']);
      expect(db.environmentVariables, hasLength(1));
    });

    test('a clean import has nothing to list', () async {
      final summary = await useCase('{"name": "Dev", "values": [{"key": "a", "value": "1", "enabled": true}]}');
      expect(summary.skipped, 0);
      expect(summary.notes, isEmpty);
      expect(summary.description, 'Imported "Dev": 1 environment, 1 variable');
    });

    test('a globals file adds new globals, keeps existing ones and says so', () async {
      await db.globalVariableRepository.upsert(
        const GlobalVariableEntity(id: 0, key: 'host', value: 'https://old.test', isSecret: false, enabled: true),
      );

      final summary = await useCase(_globals);

      expect(db.environments, isEmpty);
      expect(db.globals.map((g) => (g.key, g.value, g.isSecret)), [
        ('host', 'https://old.test', false),
        ('fresh', 'f', false),
        // A name that looks like a credential is marked secret.
        ('session_token', 's', true),
      ]);
      expect((summary.globalVariables, summary.skipped, summary.environments), (2, 1, 0));
      expect(summary.description, 'Imported: 2 global variables (1 skipped)');
      expect(summary.notes, [
        'Global variable "host" already exists, so its current value was kept.',
        '1 variable was marked secret (type "secret", or a name that looks like a credential).',
      ]);
    });

    test('a failure while saving globals removes what this import added and keeps what was there', () async {
      await db.globalVariableRepository.upsert(
        const GlobalVariableEntity(id: 0, key: 'keep', value: 'k', isSecret: false, enabled: true),
      );
      db.failUpsertGlobalOnCall = 3; // the first call was the setup above; the import's own second global fails

      await expectLater(useCase(_globals), throwsA(isA<StateError>()));

      expect(db.globals.map((g) => g.key), ['keep']);
    });
  });

  group('through ImportAnyUseCase', () {
    test('a pasted environment goes to the environment importer and nowhere else', () async {
      final db = InMemoryDb();
      final any = ImportAnyUseCase(
        _Unused<int, String>(),
        _Unused<int, String>(),
        _Unused<ImportSummary, String>(),
        _Unused<ImportSummary, String>(),
        _Unused<ImportSummary, ImportCurlScriptParams>(),
        _Unused<ImportSummary, String>(),
        db.collectionRepository,
        db.requestRepository,
        importPostmanEnvironment: ImportPostmanEnvironmentUseCase(db.environmentRepository, db.globalVariableRepository),
      );

      final summary = await any(const ImportAnyParams(text: _export));

      expect(summary.format, ImportFormat.postmanEnvironment);
      expect(db.environments.single.name, 'Staging');
    });
  });
}
