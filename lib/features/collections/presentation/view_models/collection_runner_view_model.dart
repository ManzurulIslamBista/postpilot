import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/utils/file_download.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/services/collection_run_options.dart';
import '../../../request_builder/domain/services/collection_run_plan.dart';
import '../../../request_builder/domain/services/collection_run_report.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../../../request_builder/domain/services/run_data_parser.dart';
import '../../../request_builder/domain/services/run_selection.dart';
import '../../domain/entities/collection_entity.dart';

typedef FileDownloader = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

/// One row of the runner's checkbox tree.
sealed class RunTreeRow {
  final int depth;
  const RunTreeRow(this.depth);
}

final class RunFolderRow extends RunTreeRow {
  final FolderEntity folder;

  /// True when every request below is ticked, false when none is, null when some are.
  final bool? checked;
  final bool expanded;
  final int selectedCount;
  final int requestCount;

  const RunFolderRow(
    super.depth,
    this.folder, {
    required this.checked,
    required this.expanded,
    required this.selectedCount,
    required this.requestCount,
  });
}

final class RunRequestRow extends RunTreeRow {
  final RequestSummaryEntity request;
  final bool checked;

  /// 1-based place among the requests that will run; null when it is not ticked.
  final int? runNumber;

  const RunRequestRow(super.depth, this.request, {required this.checked, required this.runNumber});
}

/// Holds a run's settings (iterations, delay, stop-on-failure, pasted data)
/// and its live results. A run only starts on [start] (the dialog's Run
/// button), never on opening — every request is really sent, so it must be an
/// explicit choice. [stop] aborts the request in flight and ends the run.
final class CollectionRunnerViewModel with ChangeNotifier {
  final CollectionRunnerService _collectionRunnerService;
  final RunDataParser _dataParser;
  final CollectionRunExporter _exporter;
  final FileDownloader _download;

  CollectionRunnerViewModel(
    this._collectionRunnerService, [
    this._dataParser = const RunDataParser(),
    this._exporter = const CollectionRunExporter(),
    this._download = downloadFile,
  ]);

  /// What a run would send, in the order it sends it: the requests that are ticked, filled by [load]
  /// and kept up to date by the selection methods.
  List<RequestSummaryEntity> requests = const [];
  bool isLoading = true;

  /// Every request and folder of the collection and the order a run takes through them; filled by [load].
  CollectionRunPlan? plan;
  final Set<int> _selectedIds = {};
  final Set<int> _collapsedFolderIds = {};

  /// Request ids below each folder, folders inside folders included.
  final Map<int, List<int>> _requestIdsByFolder = {};

  bool stopOnFailure = false;
  int? _iterations = 1;
  int? _delayMs = 0;
  RunData _data = RunData.empty;

  final List<CollectionRunResult> results = [];
  final List<RunIteration> _iterationList = [];
  CollectionRunSummary? _summary;
  CollectionRunOptions _options = const CollectionRunOptions();
  int _plannedRequests = 0;
  bool hasStarted = false;
  bool isRunning = false;
  bool wasStopped = false;

  /// The run ended before the last request because one failed.
  bool stoppedOnFailure = false;

  /// Set when the run itself broke (not when a request failed).
  String? runError;
  bool _disposed = false;
  ApiCancelToken? _cancelToken;
  StreamSubscription<CollectionRunResult>? _subscription;

  bool get usesData => _data.rows.isNotEmpty;
  int get dataRowCount => _data.rows.length;
  List<String> get dataColumns => _data.columns;
  String? get dataError => _data.error;

  /// Data rows replace the iteration count, so it is only checked without data.
  String? get iterationsError =>
      usesData || _iterations != null ? null : 'Enter 1-${CollectionRunOptions.maxIterations}';
  String? get delayError => _delayMs != null ? null : 'Enter 0-${CollectionRunOptions.maxDelay.inMilliseconds}';

  int get plannedIterations => usesData ? dataRowCount : (_iterations ?? 1);
  int get plannedRequestCount => requests.length * plannedIterations;

  /// Why there is nothing to run, once a collection with requests is loaded and none of them is ticked.
  String? get selectionError =>
      isLoading || (plan?.requests.isEmpty ?? true) || requests.isNotEmpty ? null : 'Tick at least one request to run.';

  int get totalRequestCount => plan?.requests.length ?? 0;
  int get selectedCount => requests.length;
  bool get allSelected => totalRequestCount > 0 && selectedCount == totalRequestCount;

  bool isSelected(int requestId) => _selectedIds.contains(requestId);

  /// The ticked requests as a [RunSelection]: always the exact ids, so a request added to the collection while this
  /// is open does not join a run it was never shown in.
  RunSelection get selection => RunSelection.requests(_selectedIds);

  bool get canRun =>
      !isRunning &&
      requests.isNotEmpty &&
      iterationsError == null &&
      delayError == null &&
      dataError == null;

  bool get hasResults => results.isNotEmpty;

  /// The run's passes, each with the results it produced so far.
  List<RunIteration> get runIterations => UnmodifiableListView(_iterationList);
  int get totalIterations => _options.iterationCount;
  int get currentIteration => _iterationList.isEmpty ? 1 : _iterationList.last.number;

  CollectionRunSummary get summary => _summary ??= CollectionRunSummary.of(results);

  /// Full requests of the run, for the production lock: exactly the ticked ones.
  Future<List<ApiRequestEntity>> fullRequests(int collectionId) =>
      _collectionRunnerService.fullRequestsIn(collectionId, selection: selection);

  /// Loads the collection. Everything is ticked, or with [folderId] only what is in that folder and below.
  Future<void> load(int collectionId, {int? folderId}) async {
    final found = await _collectionRunnerService.planFor(collectionId);
    if (_disposed) return;
    plan = found;
    _indexFolders(found);
    _selectedIds
      ..clear()
      ..addAll([
        for (final r in found.select(folderId == null ? RunSelection.all : RunSelection.folder(folderId))) r.id,
      ]);
    _refreshSelected();
    isLoading = false;
    notifyListeners();
  }

  void _indexFolders(CollectionRunPlan found) {
    _requestIdsByFolder.clear();
    final parents = {for (final f in found.folders) f.id: f.parentFolderId};
    for (final request in found.ordered) {
      var folder = request.folderId;
      for (var guard = 0; folder != null && guard < 64; guard++) {
        (_requestIdsByFolder[folder] ??= []).add(request.id);
        folder = parents[folder];
      }
    }
  }

  void _refreshSelected() {
    final current = plan;
    requests = current == null ? const [] : current.select(RunSelection.requests(_selectedIds));
  }

  void toggleRequest(int requestId) {
    if (!_selectedIds.remove(requestId)) _selectedIds.add(requestId);
    _refreshSelected();
    notifyListeners();
  }

  /// Ticks every request below [folderId] unless they all are already, in which case it unticks them.
  void toggleFolderSelection(int folderId) {
    final ids = _requestIdsByFolder[folderId] ?? const <int>[];
    if (folderSelection(folderId) == true) {
      _selectedIds.removeAll(ids);
    } else {
      _selectedIds.addAll(ids);
    }
    _refreshSelected();
    notifyListeners();
  }

  /// True when every request below [folderId] is ticked, false when none is (or it holds none), null when some are.
  bool? folderSelection(int folderId) {
    final ids = _requestIdsByFolder[folderId] ?? const <int>[];
    final ticked = ids.where(_selectedIds.contains).length;
    if (ticked == 0) return false;
    return ticked == ids.length ? true : null;
  }

  void selectAll() {
    _selectedIds
      ..clear()
      ..addAll([for (final r in plan?.requests ?? const <RequestSummaryEntity>[]) r.id]);
    _refreshSelected();
    notifyListeners();
  }

  void selectNone() {
    _selectedIds.clear();
    _refreshSelected();
    notifyListeners();
  }

  bool isFolderExpanded(int folderId) => !_collapsedFolderIds.contains(folderId);

  void toggleFolderExpanded(int folderId) {
    if (!_collapsedFolderIds.remove(folderId)) _collapsedFolderIds.add(folderId);
    notifyListeners();
  }

  /// The collection as a checkbox tree, depth-first in run order; a collapsed folder hides what is in it.
  List<RunTreeRow> get treeRows {
    final current = plan;
    if (current == null) return const [];
    final number = {for (final (i, r) in requests.indexed) r.id: i + 1};
    final rows = <RunTreeRow>[];
    void add(int? parent) {
      for (final entry in current.order.childrenOf(parent)) {
        if (!entry.isFolder) {
          final request = current.requests[entry.index];
          rows.add(RunRequestRow(entry.depth, request, checked: _selectedIds.contains(request.id), runNumber: number[request.id]));
          continue;
        }
        final folder = current.folders[entry.index];
        final ids = _requestIdsByFolder[folder.id] ?? const <int>[];
        final expanded = isFolderExpanded(folder.id);
        rows.add(
          RunFolderRow(
            entry.depth,
            folder,
            checked: folderSelection(folder.id),
            expanded: expanded,
            selectedCount: ids.where(_selectedIds.contains).length,
            requestCount: ids.length,
          ),
        );
        if (expanded) add(folder.id);
      }
    }

    add(null);
    return rows;
  }

  void setIterations(String text) {
    final count = int.tryParse(text.trim());
    _iterations = count != null && count >= 1 && count <= CollectionRunOptions.maxIterations ? count : null;
    notifyListeners();
  }

  /// Blank means no delay.
  void setDelayMs(String text) {
    final trimmed = text.trim();
    final ms = trimmed.isEmpty ? 0 : int.tryParse(trimmed);
    _delayMs = ms != null && ms >= 0 && ms <= CollectionRunOptions.maxDelay.inMilliseconds ? ms : null;
    notifyListeners();
  }

  void setStopOnFailure(bool value) {
    stopOnFailure = value;
    notifyListeners();
  }

  void setDataText(String text) {
    _data = _dataParser.parse(text);
    notifyListeners();
  }

  void start(int collectionId) {
    if (!canRun) return;
    _options = CollectionRunOptions(
      iterations: _iterations ?? 1,
      delay: Duration(milliseconds: _delayMs ?? 0),
      stopOnFailure: stopOnFailure,
      dataRows: _data.rows,
    );
    _plannedRequests = requests.length * _options.iterationCount;
    final chosen = selection;
    results.clear();
    _iterationList.clear();
    _summary = null;
    hasStarted = true;
    isRunning = true;
    wasStopped = false;
    stoppedOnFailure = false;
    runError = null;
    notifyListeners();

    _subscription?.cancel();
    final token = _cancelToken = ApiCancelToken();
    _subscription = _collectionRunnerService
        .run(collectionId, options: _options, cancelToken: token, selection: chosen)
        .listen(
      _onResult,
      onError: (Object error) => runError = error.toString(),
      onDone: _onDone,
    );
  }

  void stop() {
    if (!isRunning) return;
    _cancelToken?.cancel();
    _subscription?.cancel();
    _subscription = null;
    isRunning = false;
    wasStopped = true;
    notifyListeners();
  }

  String export(RunExportFormat format) => _exporter.export(format, _iterationList);

  /// The written path, or null where the browser owns the download (web).
  Future<String?> downloadExport(RunExportFormat format) => _download(
        fileName: format.fileName,
        bytes: Uint8List.fromList(utf8.encode(export(format))),
        mimeType: format.mimeType,
      );

  void _onResult(CollectionRunResult result) {
    results.add(result);
    if (_iterationList.isEmpty || _iterationList.last.number != result.iteration) {
      _iterationList.add(RunIteration(result.iteration, _options.dataFor(result.iteration)));
    }
    _iterationList.last.results.add(result);
    _summary = null;
    notifyListeners();
  }

  void _onDone() {
    isRunning = false;
    stoppedOnFailure =
        _options.stopOnFailure && results.isNotEmpty && !results.last.passed && results.length < _plannedRequests;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
