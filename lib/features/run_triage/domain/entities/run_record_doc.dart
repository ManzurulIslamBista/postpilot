// Pure Dart (no Flutter, no database): the command line writes this document and the app stores and reads it.

/// One request of a finished run, as it is kept for triage: what was sent where (a masked address without its
/// query), what came back, and why it failed. Free text is masked by `RunRecordCodec` before it is stored.
final class RunResultEntry {
  /// The request's id in the app's database. Null for a result that came from the command line until it has been
  /// matched with a request of the collection (see `CliRunImporter`).
  final int? requestId;
  final String name;

  /// The folders above the request, `Auth/Admin`; empty at the top level.
  final String folder;
  final String method;

  /// Scheme, host and path only: no credentials and no query string.
  final String url;

  /// The 1-based pass over the collection (data row) this result belongs to.
  final int iteration;
  final int? status;
  final int? durationMs;

  /// A skipped request counts as passed, like everywhere else; [skipped] tells it apart.
  final bool passed;
  final String? skipped;
  final String? error;

  /// What the checks and variable saves said, one line each.
  final List<String> failures;

  const RunResultEntry({
    this.requestId,
    required this.name,
    this.folder = '',
    required this.method,
    this.url = '',
    this.iteration = 1,
    this.status,
    this.durationMs,
    required this.passed,
    this.skipped,
    this.error,
    this.failures = const [],
  });

  bool get isSkipped => skipped != null;
  bool get isFailed => !passed && skipped == null;

  /// The same request in two runs: where it sits and how it is called, not its database id (a workspace pulled on
  /// another machine has other ids).
  String get requestKey => '$folder\u0001$method\u0001$name';

  /// One result of one pass: [requestKey] and the iteration.
  String get resultKey => '$requestKey\u0001$iteration';

  /// `Auth / Login`, for a list.
  String get label => folder.isEmpty ? name : '${folder.replaceAll('/', ' / ')} / $name';

  RunResultEntry copyWith({int? requestId, bool clearRequestId = false}) => RunResultEntry(
        requestId: clearRequestId ? null : requestId ?? this.requestId,
        name: name,
        folder: folder,
        method: method,
        url: url,
        iteration: iteration,
        status: status,
        durationMs: durationMs,
        passed: passed,
        skipped: skipped,
        error: error,
        failures: failures,
      );

  Map<String, Object?> toJson() => {
        if (requestId != null) 'requestId': requestId,
        'name': name,
        if (folder.isNotEmpty) 'folder': folder,
        'method': method,
        if (url.isNotEmpty) 'url': url,
        if (iteration != 1) 'iteration': iteration,
        if (status != null) 'status': status,
        if (durationMs != null) 'durationMs': durationMs,
        'passed': passed,
        if (skipped != null) 'skipped': skipped,
        if (error != null) 'error': error,
        if (failures.isNotEmpty) 'failures': failures,
      };

  /// Tolerant of a hand-edited or older file: a missing field takes its default, a wrongly typed one is ignored.
  factory RunResultEntry.fromJson(Map<String, Object?> json) => RunResultEntry(
        requestId: _int(json['requestId']),
        name: _string(json['name']) ?? '(unnamed)',
        folder: _string(json['folder']) ?? '',
        method: _string(json['method']) ?? 'GET',
        url: _string(json['url']) ?? '',
        iteration: _int(json['iteration']) ?? 1,
        status: _int(json['status']),
        durationMs: _int(json['durationMs']),
        passed: json['passed'] is bool ? json['passed'] as bool : false,
        skipped: _string(json['skipped']),
        error: _string(json['error']),
        failures: [
          if (json['failures'] case final List<Object?> list)
            for (final f in list)
              if (f is String) f,
        ],
      );
}

/// A whole run of one collection: the totals and every result.
final class RunRecordDoc {
  static const format = 'postpilot-run-record';
  static const version = 1;

  /// `app` or `cli`.
  final String source;

  /// What started it: `manual` (the runner dialog), `monitor` or `cli`.
  final String trigger;
  final String collection;
  final String environment;
  final DateTime startedAt;
  final int durationMs;

  /// How many passes the run made (one per data row).
  final int iterations;
  final int passed;
  final int failed;
  final int skipped;

  /// The run ended at the first failure, so later requests never ran.
  final bool stoppedOnFailure;

  /// Results were left out to keep the record small; the totals still count every request.
  final bool truncated;
  final List<RunResultEntry> results;

  const RunRecordDoc({
    this.source = 'app',
    this.trigger = 'manual',
    required this.collection,
    this.environment = '',
    required this.startedAt,
    this.durationMs = 0,
    this.iterations = 1,
    required this.passed,
    required this.failed,
    this.skipped = 0,
    this.stoppedOnFailure = false,
    this.truncated = false,
    this.results = const [],
  });

  int get total => passed + failed + skipped;

  /// A run that sent something and saw nothing fail.
  bool get isPassing => failed == 0;

  RunRecordDoc copyWith({List<RunResultEntry>? results, bool? truncated, String? environment, String? source}) =>
      RunRecordDoc(
        source: source ?? this.source,
        trigger: trigger,
        collection: collection,
        environment: environment ?? this.environment,
        startedAt: startedAt,
        durationMs: durationMs,
        iterations: iterations,
        passed: passed,
        failed: failed,
        skipped: skipped,
        stoppedOnFailure: stoppedOnFailure,
        truncated: truncated ?? this.truncated,
        results: results ?? this.results,
      );

  /// Everything but the results: what the `summaryJson` column holds.
  Map<String, Object?> summaryJson() => {
        'trigger': trigger,
        'collection': collection,
        'iterations': iterations,
        if (stoppedOnFailure) 'stoppedOnFailure': true,
        if (truncated) 'truncated': true,
      };

  /// The file the command line writes (`--records-dir`) and the app imports.
  Map<String, Object?> toJson() => {
        'format': format,
        'version': version,
        'source': source,
        'trigger': trigger,
        'collection': collection,
        'environment': environment,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'iterations': iterations,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        if (stoppedOnFailure) 'stoppedOnFailure': true,
        if (truncated) 'truncated': true,
        'results': [for (final r in results) r.toJson()],
      };

  /// Reads a document written by [toJson]. Throws a [FormatException] whose message says what is wrong when [json]
  /// is not a run record.
  factory RunRecordDoc.fromJson(Object? json) {
    if (json is! Map || json['format'] != format) {
      throw const FormatException('This file is not a PostPilot run record (it has no "format": "$format" marker).');
    }
    final fileVersion = _int(json['version']);
    if (fileVersion == null || fileVersion > version) {
      throw FormatException(
        'This run record has version ${json['version']}, a newer format than this PostPilot reads (version $version). '
        'Update PostPilot to import it.',
      );
    }
    final results = json['results'];
    if (results is! List) throw const FormatException('The run record has no "results" list.');
    final entries = [
      for (final r in results)
        if (r is Map) RunResultEntry.fromJson(Map<String, Object?>.from(r)),
    ];
    final started = DateTime.tryParse(_string(json['startedAt']) ?? '');
    return RunRecordDoc(
      source: _string(json['source']) ?? 'cli',
      trigger: _string(json['trigger']) ?? 'cli',
      collection: _string(json['collection']) ?? '',
      environment: _string(json['environment']) ?? '',
      startedAt: started ?? DateTime.now().toUtc(),
      durationMs: _int(json['durationMs']) ?? 0,
      iterations: _int(json['iterations']) ?? 1,
      passed: _int(json['passed']) ?? entries.where((e) => e.passed && !e.isSkipped).length,
      failed: _int(json['failed']) ?? entries.where((e) => e.isFailed).length,
      skipped: _int(json['skipped']) ?? entries.where((e) => e.isSkipped).length,
      stoppedOnFailure: json['stoppedOnFailure'] == true,
      truncated: json['truncated'] == true,
      results: entries,
    );
  }
}

int? _int(Object? value) => value is int ? value : (value is num && value == value.roundToDouble() ? value.toInt() : null);

String? _string(Object? value) => value is String ? value : null;
