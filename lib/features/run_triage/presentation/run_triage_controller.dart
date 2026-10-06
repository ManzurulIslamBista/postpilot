import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../../collections/presentation/view_models/collection_runner_view_model.dart';
import '../domain/entities/run_record_doc.dart';
import '../domain/repositories/run_record_repository.dart';
import '../domain/services/app_run_mapper.dart';
import '../domain/services/request_history_stats.dart';
import '../domain/services/triage_analysis.dart';

/// What a record needs to know about the run that the runner itself does not: names, the active environment, and
/// each request's address as written.
final class RunContext {
  final String collectionName;
  final String environmentName;
  final List<FolderEntity> folders;

  /// The address of a request as written (`{{baseUrl}}/orders`); null when it cannot be found any more.
  final Future<String?> Function(int requestId) urlOf;

  const RunContext({
    this.collectionName = '',
    this.environmentName = '',
    this.folders = const [],
    this.urlOf = _noUrl,
  });

  static Future<String?> _noUrl(int _) async => null;
}

/// Watches a collection runner and, when a run ends, makes its triage: the failures grouped by cause, the change since
/// the run before, the flaky and the slow requests. A run that finished is also stored in the run history; one the
/// person stopped, or that broke, is analysed but not stored (it is not a whole run to compare with later).
///
/// Storage trouble never stops the analysis: the triage is shown and says that the history could not be written.
final class RunTriageController with ChangeNotifier {
  final CollectionRunnerViewModel _runner;
  final int collectionId;
  final RunRecordRepository? _records;
  final Future<RunContext> Function() _context;
  final DateTime Function() _now;
  final String trigger;

  RunTriageController({
    required this._runner,
    required this.collectionId,
    this._records,
    Future<RunContext> Function()? context,
    DateTime Function()? now,
    this.trigger = 'manual',
  })  : _context = context ?? (() async => const RunContext()),
        _now = now ?? DateTime.now {
    _runner.addListener(_onRunnerChanged);
    _wasRunning = _runner.isRunning;
  }

  bool _wasRunning = false;
  bool _disposed = false;
  int _generation = 0;
  late DateTime _startedAt = _now();

  /// The triage of the last run that ended; null before one has, and while the next one is running.
  TriageAnalysis? analysis;

  /// The analysed run was stopped before its end, so it is partial and was not stored.
  bool isPartial = false;

  /// The id of the stored record of the analysed run.
  int? savedRecordId;

  /// Why the run could not be stored, when it could not.
  String? saveError;

  bool get isAnalysing => _runner.isRunning || _analysing;
  bool _analysing = false;

  void _onRunnerChanged() {
    final running = _runner.isRunning;
    if (running && !_wasRunning) {
      // A new run begins: the old triage no longer describes what is on screen.
      _startedAt = _now();
      _generation++;
      analysis = null;
      savedRecordId = null;
      saveError = null;
      isPartial = false;
      notifyListeners();
    } else if (!running && _wasRunning) {
      unawaited(_finish());
    }
    _wasRunning = running;
  }

  Future<void> _finish() async {
    final generation = ++_generation;
    final results = List.of(_runner.results);
    if (results.isEmpty) return;
    final stopped = _runner.wasStopped;
    final broke = _runner.runError != null;
    final iterations = _runner.totalIterations;
    final stoppedOnFailure = _runner.stoppedOnFailure;
    _analysing = true;
    notifyListeners();

    var context = const RunContext();
    try {
      context = await _context();
    } catch (_) {
      // Names and addresses are a nicety: the triage works without them.
    }
    final entries = <RunResultEntry>[];
    final urls = <int, String>{};
    for (final result in results) {
      final id = result.request.id;
      if (!urls.containsKey(id)) {
        try {
          urls[id] = await context.urlOf(id) ?? '';
        } catch (_) {
          urls[id] = '';
        }
      }
      entries.add(AppRunMapper.entryOf(result, folder: AppRunMapper.folderPath(context.folders, result.request.folderId), url: urls[id]!));
    }
    final doc = AppRunMapper.docOf(
      collection: context.collectionName,
      environment: context.environmentName,
      startedAt: _startedAt,
      duration: _now().difference(_startedAt),
      results: entries,
      trigger: trigger,
      iterations: iterations,
      stoppedOnFailure: stoppedOnFailure,
    );

    int? savedId;
    String? failure;
    final records = _records;
    if (records != null && !stopped && !broke) {
      try {
        savedId = await records.save(collectionId, doc);
      } catch (e) {
        failure = 'The run could not be added to the run history: $e';
      }
    }
    var earlier = <RunRecordDoc>[];
    if (records != null) {
      try {
        earlier = [
          for (final r in await records.recent(collectionId, limit: RequestHistoryStats.window + 1))
            if (r.id != savedId) r.doc,
        ];
      } catch (_) {
        // No history to compare with: the triage of this run alone still stands.
      }
    }
    if (_disposed || generation != _generation) return;
    analysis = TriageAnalysis.of(doc, earlier);
    savedRecordId = savedId;
    saveError = failure;
    isPartial = stopped;
    _analysing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runner.removeListener(_onRunnerChanged);
    super.dispose();
  }
}
