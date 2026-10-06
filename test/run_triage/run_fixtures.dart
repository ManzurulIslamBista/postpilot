import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';

/// A result of a run for a test: passes by default with a 200 in 20 ms.
RunResultEntry entry(
  String name, {
  String folder = '',
  String method = 'GET',
  String url = '',
  int iteration = 1,
  int? status = 200,
  int? ms = 20,
  bool? passed,
  String? skipped,
  String? error,
  List<String> failures = const [],
  int? requestId,
}) =>
    RunResultEntry(
      requestId: requestId,
      name: name,
      folder: folder,
      method: method,
      url: url.isEmpty ? 'https://api.shop.test/${name.toLowerCase().replaceAll(' ', '-')}' : url,
      iteration: iteration,
      status: status,
      durationMs: ms,
      passed: passed ?? (skipped != null || (error == null && failures.isEmpty && status != null && status >= 200 && status < 300)),
      skipped: skipped,
      error: error,
      failures: failures,
    );

/// A failed result with this status code.
RunResultEntry failedWith(String name, int status, {String folder = '', int iteration = 1, int? requestId}) =>
    entry(name, folder: folder, status: status, iteration: iteration, requestId: requestId, passed: false, failures: const []);

/// A run of [results] for a test.
RunRecordDoc run(
  List<RunResultEntry> results, {
  String environment = 'Staging',
  DateTime? at,
  String source = 'app',
  String trigger = 'manual',
  String collection = 'Shop',
  int durationMs = 1000,
}) =>
    RunRecordDoc(
      source: source,
      trigger: trigger,
      collection: collection,
      environment: environment,
      startedAt: at ?? DateTime.utc(2026, 10, 6, 10, 42),
      durationMs: durationMs,
      passed: results.where((r) => r.passed && !r.isSkipped).length,
      failed: results.where((r) => r.isFailed).length,
      skipped: results.where((r) => r.isSkipped).length,
      results: results,
    );
