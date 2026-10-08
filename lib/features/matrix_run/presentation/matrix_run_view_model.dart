import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_http_response.dart';
import '../../../core/utils/file_download.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../collections/presentation/view_models/collection_runner_view_model.dart';
import '../../environments/domain/entities/environment_entity.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../request_builder/domain/entities/api_request_entity.dart';
import '../../safety/domain/services/production_detector.dart';
import '../domain/entities/matrix_column.dart';
import '../domain/entities/matrix_grid.dart';
import '../domain/entities/matrix_identity.dart';
import '../domain/repositories/matrix_identity_store.dart';
import '../domain/services/matrix_analysis.dart';
import '../domain/services/matrix_body.dart';
import '../domain/services/matrix_exporter.dart';
import '../domain/services/matrix_read_only.dart';
import '../domain/services/matrix_run_service.dart';

/// Where the dialog is in its life.
enum MatrixPhase { setup, running, done }

/// What a matrix export is saved as.
enum MatrixExportFormat {
  markdown('Markdown', 'matrix-run.md', 'text/markdown'),
  csv('CSV', 'matrix-run.csv', 'text/csv');

  final String label;
  final String fileName;
  final String mimeType;
  const MatrixExportFormat(this.label, this.fileName, this.mimeType);
}

/// The matrix run dialog's state: which collection and requests, which environments and identities make the columns,
/// the options, then the grid as it fills, the expectations set on it, and its export.
///
/// The requests are picked with the same tree as the Collection Runner (a [CollectionRunnerViewModel] used for its
/// selection only); the run itself goes through a [MatrixRunner].
final class MatrixRunViewModel extends ChangeNotifier {
  /// Most columns one run may have: every column sends the whole selection again.
  static const maxColumns = 8;

  final MatrixRunner _runner;
  final MatrixIdentityStore _identities;
  final EnvironmentRepository _environmentRepository;
  final CollectionRepository _collectionRepository;
  final FileDownloader _download;
  final bool Function(String environmentName) _isProduction;
  final String Function() _newId;

  /// The request tree and the choice of requests; filled by [setCollection].
  final CollectionRunnerViewModel picker;

  MatrixRunViewModel({
    required this._runner,
    required this._identities,
    required EnvironmentRepository environments,
    required CollectionRepository collections,
    required this.picker,
    this._download = downloadFile,
    bool Function(String environmentName)? isProduction,
    String Function()? newId,
  })  : _environmentRepository = environments,
        _collectionRepository = collections,
        _isProduction = isProduction ?? ((name) => ProductionDetector.isProduction(name)),
        _newId = newId ?? (() => 'i${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}') {
    picker.addListener(notifyListeners);
  }

  // --- setup ---------------------------------------------------------------------------------

  List<CollectionEntity> collections = const [];
  int? collectionId;
  List<EnvironmentEntity> environments = const [];
  List<MatrixIdentity> identities = const [];
  final Set<String> _environmentNames = {};
  final Set<String> _identityIds = {};
  bool readOnlyOnly = true;
  MatrixCompareMode mode = MatrixCompareMode.full;
  bool isLoading = true;

  /// Loads what the dialog offers. [initialCollectionId] is the collection to open on; without it, the first one.
  Future<void> load({int? initialCollectionId}) async {
    collections = await _collectionRepository.watchCollections().first;
    environments = await _environmentRepository.watchAll().first;
    identities = await _identities.load();
    if (_disposed) return;
    final wanted = collections.where((c) => c.id == initialCollectionId).firstOrNull ?? collections.firstOrNull;
    if (wanted != null) await setCollection(wanted.id);
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  String get collectionName => collections.where((c) => c.id == collectionId).firstOrNull?.name ?? '';

  Future<void> setCollection(int id) async {
    collectionId = id;
    await picker.load(id);
    if (!_disposed) notifyListeners();
  }

  bool isProduction(String environmentName) => _isProduction(environmentName);
  bool isEnvironmentSelected(String name) => _environmentNames.contains(name);
  bool isIdentitySelected(String id) => _identityIds.contains(id);

  void toggleEnvironment(String name) {
    if (!_environmentNames.remove(name)) _environmentNames.add(name);
    notifyListeners();
  }

  void toggleIdentity(String id) {
    if (!_identityIds.remove(id)) _identityIds.add(id);
    notifyListeners();
  }

  /// Adds the identity, or replaces the one with the same id, and ticks it.
  Future<void> saveIdentity(MatrixIdentity identity) async {
    final index = identities.indexWhere((i) => i.id == identity.id);
    identities = [
      for (final (i, existing) in identities.indexed)
        if (i == index) identity else existing,
      if (index < 0) identity,
    ];
    _identityIds.add(identity.id);
    notifyListeners();
    await _identities.save(identities);
  }

  Future<void> deleteIdentity(String id) async {
    identities = [for (final i in identities) if (i.id != id) i];
    _identityIds.remove(id);
    notifyListeners();
    await _identities.save(identities);
  }

  /// A new identity's id.
  String newIdentityId() => _newId();

  void setReadOnly(bool value) {
    readOnlyOnly = value;
    notifyListeners();
  }

  void setMode(MatrixCompareMode value) {
    mode = value;
    notifyListeners();
  }

  /// The ticked environments in the order the app lists them, with the ticked identities: every pair is a column.
  List<MatrixColumn> get columns => MatrixColumn.product(
        [for (final e in environments) if (_environmentNames.contains(e.name)) e.name],
        [for (final i in identities) if (_identityIds.contains(i.id)) i],
      );

  /// The selected requests that will be sent: all of them, or the reads among them.
  List<RequestSummaryEntity> get sendable => [
        for (final r in picker.requests)
          if (!readOnlyOnly || MatrixReadOnly.allows(r.method)) r,
      ];

  /// Selected requests that are not sent because they change data and the run is read-only.
  int get leftOutCount => picker.requests.length - sendable.length;

  /// What stops the run from starting; null when it can.
  String? get setupError {
    if (isLoading) return null;
    if (collectionId == null) return 'There is no collection to run.';
    final count = columns.length;
    if (count < 2) return 'Tick at least two columns to compare: environments, identities, or both.';
    if (count > maxColumns) return 'That makes $count columns; the most is $maxColumns. Every column sends the whole selection again.';
    if (picker.requests.isEmpty) return 'Tick at least one request.';
    if (sendable.isEmpty) return 'Only data-changing requests are ticked, and the run is read-only. Untick "Read-only requests only" or tick a read.';
    return null;
  }

  bool get canRun => phase != MatrixPhase.running && !isLoading && setupError == null;

  // --- the run -------------------------------------------------------------------------------

  MatrixPhase phase = MatrixPhase.setup;
  MatrixGrid? grid;
  Map<String, String> notes = const {};
  int? runningColumn;
  int leftOut = 0;
  bool wasStopped = false;
  String? runError;
  ApiCancelToken? _cancelToken;
  bool _disposed = false;

  /// Runs every column in turn. [confirm] is asked once for a production column that would change data.
  Future<void> start({required ProductionConfirm confirm}) async {
    if (!canRun) return;
    final id = collectionId!;
    final spec = MatrixRunSpec(
      collectionId: id,
      collectionName: collectionName,
      selection: picker.selection,
      columns: columns,
      readOnlyOnly: readOnlyOnly,
    );
    phase = MatrixPhase.running;
    grid = null;
    notes = const {};
    runningColumn = null;
    wasStopped = false;
    runError = null;
    final token = _cancelToken = ApiCancelToken();
    notifyListeners();
    try {
      final result = await _runner.run(
        spec,
        cancelToken: token,
        confirm: confirm,
        onProgress: (g, n, column) {
          grid = g;
          notes = n;
          runningColumn = column;
          if (!_disposed) notifyListeners();
        },
      );
      grid = result.grid;
      notes = result.columnNotes;
      leftOut = result.leftOut;
      wasStopped = result.cancelled;
    } catch (e) {
      runError = '$e';
    } finally {
      runningColumn = null;
      phase = MatrixPhase.done;
      _cancelToken = null;
      if (!_disposed) notifyListeners();
    }
  }

  void stop() {
    if (phase != MatrixPhase.running) return;
    _cancelToken?.cancel();
    notifyListeners();
  }

  /// Back to the setup, keeping the grid and expectations until the next run replaces them.
  void editSetup() {
    if (phase == MatrixPhase.running) return;
    phase = MatrixPhase.setup;
    notifyListeners();
  }

  void showResults() {
    if (grid == null || phase == MatrixPhase.running) return;
    phase = MatrixPhase.done;
    notifyListeners();
  }

  // --- expectations --------------------------------------------------------------------------

  /// What a whole column is expected to get ("anonymous is denied everywhere"), set before a run or from the grid.
  final Map<String, MatrixExpect> _columnExpectations = {};

  /// What is expected of one request in one column, which beats the column's: row key, then column key.
  final Map<String, Map<String, MatrixExpect>> _expectations = {};

  MatrixExpect columnExpectationOf(String columnKey) => _columnExpectations[columnKey] ?? MatrixExpect.none;

  /// What is expected of the request in the column: its own expectation, else the column's, else nothing.
  MatrixExpect expectationOf(String rowKey, String columnKey) =>
      _expectations[rowKey]?[columnKey] ?? _columnExpectations[columnKey] ?? MatrixExpect.none;

  /// Expects [expect] of one request in one column, whatever the column as a whole is expected to get.
  void setExpectation(String rowKey, String columnKey, MatrixExpect expect) {
    _expectations.putIfAbsent(rowKey, () => {})[columnKey] = expect;
    notifyListeners();
  }

  /// Expects [expect] of every request in a column, replacing what was set on single requests.
  void setColumnExpectation(String columnKey, MatrixExpect expect) {
    for (final row in _expectations.values) {
      row.remove(columnKey);
    }
    if (expect == MatrixExpect.none) {
      _columnExpectations.remove(columnKey);
    } else {
      _columnExpectations[columnKey] = expect;
    }
    notifyListeners();
  }

  // --- results and export --------------------------------------------------------------------

  /// The grid judged: derived on every read, so a changed mode or expectation shows at once.
  MatrixAnalysis? get analysis {
    final g = grid;
    if (g == null) return null;
    return MatrixAnalysis.of(
      g,
      mode: mode,
      expectations: {
        for (final row in g.rows) row.key: {for (final c in g.columns) c.key: expectationOf(row.key, c.key)},
      },
    );
  }

  String get _title => collectionName.isEmpty ? 'Matrix run' : '$collectionName: matrix run';

  String export(MatrixExportFormat format) {
    final a = analysis;
    if (a == null) return '';
    return switch (format) {
      MatrixExportFormat.markdown => MatrixExporter.markdown(a, title: _title),
      MatrixExportFormat.csv => MatrixExporter.csv(a),
    };
  }

  /// The written path, or null where the browser owns the download (web).
  Future<String?> downloadExport(MatrixExportFormat format) => _download(
        fileName: format.fileName,
        bytes: Uint8List.fromList(utf8.encode(export(format))),
        mimeType: format.mimeType,
      );

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    picker
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
