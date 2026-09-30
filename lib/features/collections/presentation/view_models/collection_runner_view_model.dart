import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/utils/file_download.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/services/collection_run_options.dart';
import '../../../request_builder/domain/services/collection_run_report.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../../../request_builder/domain/services/run_data_parser.dart';

typedef FileDownloader = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

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

  /// What a run would send; filled by [load].
  List<RequestSummaryEntity> requests = const [];
  bool isLoading = true;

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

  Future<void> load(int collectionId) async {
    final found = await _collectionRunnerService.requestsIn(collectionId);
    if (_disposed) return;
    requests = found;
    isLoading = false;
    notifyListeners();
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
    _subscription = _collectionRunnerService.run(collectionId, options: _options, cancelToken: token).listen(
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
