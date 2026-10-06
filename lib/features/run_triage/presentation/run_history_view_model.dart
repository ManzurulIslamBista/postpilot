import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../domain/repositories/run_record_repository.dart';
import '../domain/services/cli_run_importer.dart';
import '../domain/services/request_history_stats.dart';
import '../domain/services/triage_analysis.dart';

/// State of a collection's run history: the stored runs, the one being looked at, importing a command-line run.
final class RunHistoryViewModel with ChangeNotifier {
  final RunRecordRepository _records;
  final int collectionId;
  final String collectionName;

  /// The collection's requests and folders, to match an imported run with them.
  final Future<List<RequestSummaryEntity>> Function() _loadRequests;
  final Future<List<FolderEntity>> Function() _loadFolders;

  RunHistoryViewModel({
    required this._records,
    required this.collectionId,
    required this.collectionName,
    required this._loadRequests,
    required this._loadFolders,
  });

  StreamSubscription<List<StoredRun>>? _subscription;
  bool _disposed = false;

  bool isLoading = true;

  /// Newest first.
  List<StoredRun> runs = const [];
  int? selectedId;
  bool isImporting = false;

  /// What the last import or clear said, and whether it is bad news.
  String? message;
  bool messageIsError = false;

  void load() {
    _subscription?.cancel();
    _subscription = _records.watch(collectionId).listen(
      (list) {
        runs = list;
        isLoading = false;
        // The run on screen was removed (history cleared, or pruned): show the list again.
        if (selectedId != null && !list.any((r) => r.id == selectedId)) selectedId = null;
        notifyListeners();
      },
      onError: (Object e) {
        isLoading = false;
        message = 'The run history could not be read: $e';
        messageIsError = true;
        notifyListeners();
      },
    );
  }

  StoredRun? get selected => runs.where((r) => r.id == selectedId).firstOrNull;

  /// The triage of the selected run against the runs before it.
  TriageAnalysis? get analysis {
    final index = runs.indexWhere((r) => r.id == selectedId);
    if (index < 0) return null;
    final doc = runs[index].doc;
    return TriageAnalysis.of(doc, [for (final r in runs.skip(index + 1).take(RequestHistoryStats.window + 1)) r.doc]);
  }

  void select(int? id) {
    selectedId = id;
    notifyListeners();
  }

  /// Adds the run in [text], a file written by `postpilot run --records-dir`.
  Future<void> importText(String text) async {
    isImporting = true;
    message = null;
    notifyListeners();
    try {
      final result = await CliRunImporter.import(
        text: text,
        collectionId: collectionId,
        requests: await _loadRequests(),
        folders: await _loadFolders(),
        records: _records,
      );
      if (_disposed) return;
      messageIsError = false;
      if (result.duplicateOf != null) {
        selectedId = result.duplicateOf;
        message = 'This run was imported before; it is in the list.';
      } else {
        selectedId = result.id;
        final unmatched = result.doc.results.length - result.matched;
        message = 'Imported the run: ${result.doc.failed} ${result.doc.failed == 1 ? 'failure' : 'failures'} in ${result.doc.results.length} results'
            '${unmatched == 0 ? '' : ', $unmatched not found among the requests of this collection (they cannot be re-run from here)'}.'
            '${result.differsFrom(collectionName) ? ' It was recorded for the collection "${result.doc.collection}".' : ''}';
      }
    } on FormatException catch (e) {
      messageIsError = true;
      message = 'Could not import the file: ${e.message}';
    } catch (e) {
      messageIsError = true;
      message = 'Could not import the file: $e';
    }
    if (_disposed) return;
    isImporting = false;
    notifyListeners();
  }

  Future<void> clear() async {
    await _records.clear(collectionId);
    if (_disposed) return;
    selectedId = null;
    messageIsError = false;
    message = 'The run history of this collection was cleared.';
    notifyListeners();
  }

  void dismissMessage() {
    message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
