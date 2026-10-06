import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/import_export/domain/services/import_format_detector.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/summarizing_importer.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';
import 'support/in_memory_import_export_fakes.dart';

ImportFormat detect(String text) => ImportFormatDetector.detect(text);

void main() {
  group('JSON formats', () {
    test('a Postman collection', () {
      expect(
        detect('''
        {"info": {"_postman_id": "1", "name": "API", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item": [{"name": "Get", "request": {"method": "GET", "url": "https://x.io"}}]}
        '''),
        ImportFormat.postman,
      );
    });

    test('a Postman collection with no requests yet', () {
      expect(detect('{"info": {"name": "Empty"}, "item": []}'), ImportFormat.postman);
    });

    test('a Postman environment export, with or without its scope marker', () {
      expect(
        detect('{"id": "1", "name": "Dev", "values": [{"key": "a", "value": "b", "enabled": true}]}'),
        ImportFormat.postmanEnvironment,
      );
      expect(
        detect(
          '{"id":"2","name":"Dev","values":[{"key":"a","value":"b","type":"default","enabled":true}],'
          '"_postman_variable_scope":"environment","_postman_exported_at":"2026-01-01T00:00:00.000Z"}',
        ),
        ImportFormat.postmanEnvironment,
      );
    });

    test('a Postman globals file and an environment with no variables yet', () {
      expect(
        detect('{"id":"3","name":"Globals","values":[{"key":"a","value":"1"}],"_postman_variable_scope":"globals"}'),
        ImportFormat.postmanEnvironment,
      );
      expect(detect('{"name": "Empty", "values": []}'), ImportFormat.postmanEnvironment);
    });

    test('an Insomnia v4 export', () {
      expect(
        detect('{"_type": "export", "__export_format": 4, "resources": [{"_id": "wrk_1", "_type": "workspace", "name": "W"}]}'),
        ImportFormat.insomnia,
      );
    });

    test('an Insomnia v5 document written as JSON', () {
      expect(detect('{"type": "collection.insomnia.rest/5.0", "name": "W", "collection": []}'), ImportFormat.insomnia);
    });

    test('a HAR file', () {
      expect(
        detect('{"log": {"version": "1.2", "creator": {"name": "WebInspector"}, "entries": [{"request": {"method": "GET", "url": "https://x.io"}}]}}'),
        ImportFormat.har,
      );
    });

    test('OpenAPI 3 and Swagger 2 documents', () {
      expect(detect('{"openapi": "3.0.3", "info": {"title": "T"}, "paths": {}}'), ImportFormat.openApi);
      expect(detect('{"swagger": "2.0", "info": {"title": "T"}, "paths": {}}'), ImportFormat.openApi);
    });

    test('a PostPilot backup, as the codec writes it', () {
      final text = BackupCodec.encode(BackupSnapshot(exportedAt: DateTime.utc(2026)));
      expect(detect(text), ImportFormat.backup);
    });

    test('a byte-order mark and surrounding whitespace are ignored', () {
      expect(detect('﻿\n  {"openapi": "3.1.0", "paths": {}}  \n'), ImportFormat.openApi);
    });
  });

  group('YAML formats', () {
    test('OpenAPI 3 YAML', () {
      expect(detect('openapi: 3.0.0\ninfo:\n  title: T\n  version: "1"\npaths: {}\n'), ImportFormat.openApi);
    });

    test('Swagger 2 YAML with a quoted version', () {
      expect(detect('swagger: "2.0"\ninfo:\n  title: T\npaths: {}\n'), ImportFormat.openApi);
    });

    test('an Insomnia v5 collection', () {
      const yaml = '''
type: collection.insomnia.rest/5.0
name: My API
meta:
  id: wrk_1
collection:
  - url: https://example.com
    name: Ping
    method: GET
''';
      expect(detect(yaml), ImportFormat.insomnia);
    });

    test('a nested "openapi" key is not a document marker', () {
      expect(detect('info:\n  notes:\n    openapi: 3.0.0\n'), ImportFormat.unknown);
    });
  });

  group('cURL', () {
    test('a plain command, in any letter case', () {
      expect(detect("curl -X POST https://api.example.com/users -d '{\"a\":1}'"), ImportFormat.curl);
      expect(detect('CURL https://example.com'), ImportFormat.curl);
    });

    test('a shell prompt, curl.exe and multi-line commands', () {
      expect(detect(r'$ curl https://example.com'), ImportFormat.curl);
      expect(detect('curl.exe https://example.com'), ImportFormat.curl);
      expect(detect("curl --location 'https://example.com' \\\n--header 'A: b'"), ImportFormat.curl);
    });

    test('a script that opens with a shebang and comments', () {
      expect(detect('#!/usr/bin/env bash\n# my calls\n\n# Get users\ncurl https://example.com/users\n'), ImportFormat.curl);
    });

    test('other words that merely start with curl are not commands', () {
      expect(detect('curling is a sport'), ImportFormat.unknown);
      expect(detect('curl'), ImportFormat.unknown);
    });
  });

  group('unknown', () {
    test('empty and blank text', () {
      expect(detect(''), ImportFormat.unknown);
      expect(detect('  \n\t '), ImportFormat.unknown);
    });

    test('prose and unmarked YAML', () {
      expect(detect('hello world'), ImportFormat.unknown);
      expect(detect('name: foo\nvalues:\n  - a\n'), ImportFormat.unknown);
    });

    test('JSON without any known marker', () {
      expect(detect('{"hello": "world"}'), ImportFormat.unknown);
      expect(detect('[1, 2, 3]'), ImportFormat.unknown);
      expect(detect('{"info": {"name": "x"}}'), ImportFormat.unknown);
    });

    test('values lists that are not Postman variables stay unknown', () {
      expect(detect('{"name": "Dev", "values": [1, 2]}'), ImportFormat.unknown);
      expect(detect('{"values": [{"key": "a"}]}'), ImportFormat.unknown);
    });

    test('truncated JSON', () {
      expect(detect('{"info": {"name": "x"}, "item": ['), ImportFormat.unknown);
    });

    test('a HAR-looking object without an entries array', () {
      expect(detect('{"log": {"version": "1.2"}}'), ImportFormat.unknown);
    });
  });

  group('routing to the right importer', () {
    late _Routes routes;

    setUp(() => routes = _Routes());

    const samples = {
      ImportFormat.postman: '{"info": {"name": "P"}, "item": []}',
      ImportFormat.postmanEnvironment: '{"name": "Dev", "values": [], "_postman_variable_scope": "environment"}',
      ImportFormat.insomnia: '{"_type": "export", "resources": []}',
      ImportFormat.har: '{"log": {"entries": []}}',
      ImportFormat.openApi: '{"openapi": "3.0.0", "paths": {}}',
      ImportFormat.curl: 'curl https://a.test',
      ImportFormat.backup: '{"format": "postpilot-backup", "version": 1}',
    };

    for (final entry in samples.entries) {
      test('${entry.key.name} goes only to its own importer', () async {
        await routes.useCase(ImportAnyParams(text: entry.value));

        expect(routes.called, [entry.key]);
      });
    }

    test('cURL commands are told where to go', () async {
      await routes.useCase(const ImportAnyParams(text: 'curl https://a.test', collectionId: 4, folderId: 9));

      final params = routes.curl.calls.single;
      expect((params.script, params.collectionId, params.folderId), ('curl https://a.test', 4, 9));
    });

    test('a forced format wins over what the text looks like', () async {
      await routes.useCase(const ImportAnyParams(text: '{"openapi": "3.0.0"}', format: ImportFormat.postman));

      expect(routes.called, [ImportFormat.postman]);
    });

    test('Postman and OpenAPI imports are described by reading the new collection back', () async {
      routes.onCollectionImport = (db) async {
        final id = await db.collectionRepository.createCollection('Pet Store');
        final folder = await db.collectionRepository.createFolder(collectionId: id, name: 'Pets');
        await db.requestRepository.createRequest(collectionId: id, folderId: folder, name: 'List');
        await db.requestRepository.createRequest(collectionId: id, name: 'Health');
        return id;
      };

      final summary = await routes.useCase(ImportAnyParams(text: samples[ImportFormat.openApi]!));

      expect(summary.format, ImportFormat.openApi);
      expect(summary.collectionName, 'Pet Store');
      expect((summary.folders, summary.requests), (1, 2));
      expect(summary.description, 'Imported "Pet Store": 1 folder, 2 requests');
    });

    test('a Postman importer that can summarise itself is asked to, so its notes reach the dialog', () async {
      final summarizing = _SummarizingPostman();
      final useCase = ImportAnyUseCase(
        summarizing,
        routes.openApi,
        routes.insomnia,
        routes.har,
        routes.curl,
        routes.backup,
        routes.db.collectionRepository,
        routes.db.requestRepository,
        importPostmanEnvironment: routes.postmanEnvironment,
      );

      final summary = await useCase(ImportAnyParams(text: samples[ImportFormat.postman]!));

      expect(summary.skipped, 1);
      expect(summary.notes, ['left out: scripts']);
      expect(summarizing.plainCalls, 0, reason: 'the bare collection-id importer must not run as well');
      expect(routes.called, isEmpty);
    });

    test('unrecognised text is an error naming the supported formats', () async {
      await expectLater(
        routes.useCase(const ImportAnyParams(text: 'hello')),
        throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('Postman'))),
      );
      expect(routes.called, isEmpty);
    });
  });

  group('ImportAnyViewModel', () {
    late _Routes routes;
    late ImportAnyViewModel vm;
    late int notifications;

    setUp(() {
      routes = _Routes();
      vm = ImportAnyViewModel(routes.useCase);
      notifications = 0;
      vm.addListener(() => notifications++);
    });

    tearDown(() => vm.dispose());

    test('detects the format as text arrives and only allows importing a recognised one', () {
      expect(vm.canImport, isFalse);

      vm.setText('{"info": {"name": "P"}, "item": []}');
      expect(vm.detected, ImportFormat.postman);
      expect(vm.canImport, isTrue);

      vm.setText('some words');
      expect(vm.detected, ImportFormat.unknown);
      expect(vm.hasText, isTrue);
      expect(vm.canImport, isFalse);
      expect(notifications, 2);
    });

    test('a hand-picked format replaces detection and unlocks importing', () {
      vm.setText('some words');

      vm.selectFormat(ImportFormat.har);

      expect(vm.format, ImportFormat.har);
      expect(vm.canImport, isTrue);
      vm.selectFormat(null);
      expect(vm.format, ImportFormat.unknown);
    });

    test('text too long to detect on the UI isolate is detected in the background', () async {
      final items = [for (var i = 0; i < 4000; i++) '{"name":"r$i","request":{"method":"GET","url":"https://x.io/$i"}}'];
      final big = '{"info":{"name":"Big"},"item":[${items.join(',')}]}';
      expect(big.length, greaterThan(200000));
      final detected = Completer<void>();
      vm.addListener(() {
        if (vm.detected == ImportFormat.postman && !detected.isCompleted) detected.complete();
      });

      vm.setText(big);
      expect(vm.detected, ImportFormat.unknown);
      await detected.future.timeout(const Duration(seconds: 20));

      expect(vm.canImport, isTrue);
    });

    test('a slow detection of older text never overwrites the newer text\'s result', () async {
      final items = [for (var i = 0; i < 4000; i++) '{"name":"r$i","request":{"method":"GET","url":"https://x.io/$i"}}'];
      vm.setText('{"info":{"name":"Big"},"item":[${items.join(',')}]}');

      vm.setText('curl https://a.test');
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(vm.detected, ImportFormat.curl);
    });

    test('a successful import returns the summary and clears the busy state', () async {
      vm.setText('curl https://a.test');

      final summary = await vm.import(collectionId: 3, folderId: null);

      expect(summary, isNotNull);
      expect(vm.isImporting, isFalse);
      expect(vm.error, isNull);
      expect(routes.curl.calls.single.collectionId, 3);
    });

    test('a failed import keeps the dialog open with a friendly message', () async {
      routes.failWith = const ImportException('the export holds no workspace.');
      vm.setText('{"_type": "export", "resources": []}');

      final summary = await vm.import();

      expect(summary, isNull);
      expect(vm.isImporting, isFalse);
      expect(vm.error, 'Could not import as Insomnia export: the export holds no workspace.');
    });

    test('a forced format is passed on to the use case', () async {
      vm.setText('whatever');
      vm.selectFormat(ImportFormat.har);

      await vm.import();

      expect(routes.called, [ImportFormat.har]);
    });

    test('changing the text clears an old error', () async {
      routes.failWith = const ImportException('nope');
      vm.setText('curl https://a.test');
      await vm.import();
      expect(vm.error, isNotNull);

      vm.setText('curl https://b.test');

      expect(vm.error, isNull);
    });

    test('error texts: our own message, a JSON syntax error, and anything else shortened', () {
      expect(ImportAnyViewModel.describeError(const ImportException('bad'), ImportFormat.postman), 'Could not import as Postman collection: bad');
      expect(
        ImportAnyViewModel.describeError(const FormatException('Unexpected character'), ImportFormat.openApi),
        'Could not import as OpenAPI / Swagger document: the text is not valid JSON or YAML (Unexpected character)',
      );
      expect(ImportAnyViewModel.describeError(const ImportException('x'), ImportFormat.unknown), 'Could not import: x');
      final long = ImportAnyViewModel.describeError(StateError('e' * 300), ImportFormat.har);
      expect(long, endsWith('...'));
      expect(long.length, lessThan(200));
    });

    test('a second import while one is running is ignored', () async {
      routes.hold = Completer<void>();
      vm.setText('curl https://a.test');

      final first = vm.import();
      final second = await vm.import();
      routes.hold!.complete();
      await first;

      expect(second, isNull);
      expect(routes.curl.calls, hasLength(1));
    });
  });
}

/// Records which importer ran, standing in for all six.
final class _Recorder<Output, Params> implements UseCase<Output, Params> {
  final ImportFormat format;
  final _Routes _routes;
  final Future<Output> Function(Params params) _respond;
  final calls = <Params>[];

  _Recorder(this.format, this._routes, this._respond);

  @override
  Future<Output> call(Params params) async {
    calls.add(params);
    _routes.called.add(format);
    final hold = _routes.hold;
    if (hold != null) await hold.future;
    final failure = _routes.failWith;
    if (failure != null) throw failure;
    return _respond(params);
  }
}

final class _Routes {
  final db = InMemoryDb();
  final called = <ImportFormat>[];
  Object? failWith;
  Completer<void>? hold;
  Future<int> Function(InMemoryDb db) onCollectionImport = (db) async => db.collectionRepository.createCollection('Imported');

  late final _Recorder<int, String> postman = _Recorder(ImportFormat.postman, this, (_) => onCollectionImport(db));
  late final _Recorder<int, String> openApi = _Recorder(ImportFormat.openApi, this, (_) => onCollectionImport(db));
  late final _Recorder<ImportSummary, String> insomnia = _Recorder(ImportFormat.insomnia, this, (_) async => _summary(ImportFormat.insomnia));
  late final _Recorder<ImportSummary, String> har = _Recorder(ImportFormat.har, this, (_) async => _summary(ImportFormat.har));
  late final _Recorder<ImportSummary, String> backup = _Recorder(ImportFormat.backup, this, (_) async => _summary(ImportFormat.backup));
  late final _Recorder<ImportSummary, String> postmanEnvironment =
      _Recorder(ImportFormat.postmanEnvironment, this, (_) async => _summary(ImportFormat.postmanEnvironment));
  late final _Recorder<ImportSummary, ImportCurlScriptParams> curl =
      _Recorder(ImportFormat.curl, this, (_) async => _summary(ImportFormat.curl));

  late final ImportAnyUseCase useCase =
      ImportAnyUseCase(
        postman,
        openApi,
        insomnia,
        har,
        curl,
        backup,
        db.collectionRepository,
        db.requestRepository,
        importPostmanEnvironment: postmanEnvironment,
      );

  static ImportSummary _summary(ImportFormat format) => ImportSummary(format: format, requests: 1);
}

/// A Postman importer that answers both ways: the bare collection id and a full summary with notes.
final class _SummarizingPostman implements UseCase<int, String>, SummarizingImporter {
  int plainCalls = 0;

  @override
  Future<int> call(String params) async {
    plainCalls++;
    return 1;
  }

  @override
  Future<ImportSummary> importWithSummary(String text) async => const ImportSummary(
    format: ImportFormat.postman,
    collectionIds: [1],
    collectionName: 'P',
    requests: 1,
    skipped: 1,
    notes: ['left out: scripts'],
  );
}
