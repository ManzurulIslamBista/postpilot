// What the app's runner produced, as a run record keeps it.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/run_triage/domain/services/app_run_mapper.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_result.dart';
import 'package:postpilot/features/scripting/domain/entities/script_run_result.dart';
import 'dart:typed_data';

RequestSummaryEntity _summary(int id, String name, {HttpMethod method = HttpMethod.get, int? folderId}) =>
    RequestSummaryEntity(id: id, folderId: folderId, name: name, method: method);

ApiResponseEntity _response(int status, int ms) =>
    ApiResponseEntity(statusCode: status, statusMessage: '', headers: const {}, bodyBytes: Uint8List(0), duration: Duration(milliseconds: ms));

void main() {
  const folders = [
    FolderEntity(id: 1, collectionId: 1, parentFolderId: null, name: 'Orders'),
    FolderEntity(id: 2, collectionId: 1, parentFolderId: 1, name: 'Admin'),
    FolderEntity(id: 3, collectionId: 1, parentFolderId: 2, name: 'Deep'),
  ];

  group('folderPath', () {
    test('joins the folders from the top down with a slash', () {
      expect(AppRunMapper.folderPath(folders, 3), 'Orders/Admin/Deep');
      expect(AppRunMapper.folderPath(folders, 1), 'Orders');
      expect(AppRunMapper.folderPath(folders, null), '');
    });

    test('an unknown folder or a loop does not hang or throw', () {
      expect(AppRunMapper.folderPath(folders, 99), '');
      const loop = [
        FolderEntity(id: 1, collectionId: 1, parentFolderId: 2, name: 'A'),
        FolderEntity(id: 2, collectionId: 1, parentFolderId: 1, name: 'B'),
      ];
      expect(AppRunMapper.folderPath(loop, 1), isNotEmpty);
    });
  });

  group('entryOf', () {
    test('a passing request keeps its status and time', () {
      final e = AppRunMapper.entryOf(
        CollectionRunResult(request: _summary(7, 'Login', method: HttpMethod.post), response: _response(200, 41), scripts: ScriptRunResult.empty),
        folder: 'Auth',
        url: '{{baseUrl}}/login',
      );
      expect((e.requestId, e.name, e.folder, e.method, e.url, e.status, e.durationMs, e.passed, e.isFailed), (7, 'Login', 'Auth', 'POST', '{{baseUrl}}/login', 200, 41, true, false));
    });

    test('a failed check keeps its line, with where it was set', () {
      final e = AppRunMapper.entryOf(
        CollectionRunResult(
          request: _summary(1, 'Get'),
          response: _response(200, 10),
          scripts: const ScriptRunResult(assertions: [AssertionResult(name: 'Status equals 201', passed: false, actual: '200', origin: 'folder "Orders"')], extracted: []),
          iteration: 3,
        ),
        folder: '',
      );
      expect(e.isFailed, isTrue);
      expect(e.iteration, 3);
      expect(e.failures, ['Status equals 201 (from folder "Orders")']);
    });

    test('a request without an answer keeps its error and no status', () {
      final e = AppRunMapper.entryOf(CollectionRunResult(request: _summary(1, 'Get'), error: 'Timed out'), folder: '');
      expect((e.status, e.durationMs, e.error, e.isFailed), (null, null, 'Timed out', true));
    });

    test('a skipped request is neither failed nor counted as passed', () {
      final e = AppRunMapper.entryOf(CollectionRunResult(request: _summary(1, 'Get'), skipped: 'Run if did not hold'), folder: '');
      expect((e.isSkipped, e.isFailed, e.passed, e.skipped), (true, false, true, 'Run if did not hold'));
    });
  });

  test('docOf counts the way the runner counts', () {
    final results = [
      AppRunMapper.entryOf(CollectionRunResult(request: _summary(1, 'A'), response: _response(200, 1), scripts: ScriptRunResult.empty), folder: ''),
      AppRunMapper.entryOf(CollectionRunResult(request: _summary(2, 'B'), response: _response(500, 1), scripts: ScriptRunResult.empty), folder: ''),
      AppRunMapper.entryOf(CollectionRunResult(request: _summary(3, 'C'), skipped: 'Run if'), folder: ''),
    ];
    final doc = AppRunMapper.docOf(
      collection: 'Shop',
      environment: 'Staging',
      startedAt: DateTime.utc(2026, 10, 6),
      duration: const Duration(milliseconds: 1500),
      results: results,
      iterations: 2,
    );
    expect((doc.passed, doc.failed, doc.skipped, doc.durationMs, doc.iterations, doc.source, doc.trigger), (1, 1, 1, 1500, 2, 'app', 'manual'));
  });
}
