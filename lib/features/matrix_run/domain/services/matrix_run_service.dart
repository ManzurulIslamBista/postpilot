import '../../../../core/network/api_http_response.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../request_builder/domain/services/collection_run_options.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../../../request_builder/domain/services/run_selection.dart';
import '../../../safety/domain/services/production_guard.dart';
import '../entities/matrix_column.dart';
import '../entities/matrix_grid.dart';
import 'matrix_read_only.dart';
import 'matrix_session_isolation.dart';

/// What a matrix run is asked to do.
final class MatrixRunSpec {
  final int collectionId;

  /// For the production confirmation ("Running "Shop" sends 2 data-changing requests").
  final String collectionName;
  final RunSelection selection;
  final List<MatrixColumn> columns;

  /// Send only GET, HEAD and OPTIONS requests (see [MatrixReadOnly]); on unless the person turned it off.
  final bool readOnlyOnly;

  const MatrixRunSpec({
    required this.collectionId,
    required this.collectionName,
    this.selection = RunSelection.all,
    required this.columns,
    this.readOnlyOnly = true,
  });
}

/// How a matrix run ended.
final class MatrixRunResult {
  final MatrixGrid grid;

  /// Why a column did not run, or ran only in part, by [MatrixColumn.key].
  final Map<String, String> columnNotes;

  /// Requests of the selection that were not sent because they change data and the run was read-only.
  final int leftOut;
  final bool cancelled;

  const MatrixRunResult(this.grid, this.columnNotes, this.leftOut, this.cancelled);
}

/// Asked once for a production column that would change data; returns whether to go ahead.
typedef ProductionConfirm = Future<bool> Function(ProductionWarning warning);

/// Called after every change to the grid, with the column being run.
typedef MatrixProgress = void Function(MatrixGrid grid, Map<String, String> columnNotes, int column);

/// What the screen and the tests drive; [MatrixRunService] is the real one.
abstract interface class MatrixRunner {
  Future<MatrixRunResult> run(
    MatrixRunSpec spec, {
    ApiCancelToken? cancelToken,
    ProductionConfirm? confirm,
    MatrixProgress? onProgress,
  });
}

/// Runs one collection, or a selection of it, once per column and collects what each column got.
///
/// Every column goes through the app's normal runner, one after the other: the production lock asks as usual
/// (`ProductionGuard`, once for a production column that would change data), an undefined variable stops the request
/// that holds it, tests and extractors run, and History records the sends. A column's environment is made the *active*
/// environment for the length of its run, because that is what the send, the guard and "Run if" all read; the person's
/// own active environment is put back when the run ends, however it ends. The column's identity goes on top as a run's
/// data row, so it beats the environment's variables.
final class MatrixRunService implements MatrixRunner {
  final CollectionRunnerService _runner;
  final EnvironmentRepository _environments;
  final ProductionGuard? _guard;
  final MatrixSessionIsolation? _sessions;

  const MatrixRunService(this._runner, this._environments, {this._guard, this._sessions});

  @override
  Future<MatrixRunResult> run(
    MatrixRunSpec spec, {
    ApiCancelToken? cancelToken,
    ProductionConfirm? confirm,
    MatrixProgress? onProgress,
  }) async {
    final plan = await _runner.planFor(spec.collectionId);
    final selected = plan.select(spec.selection);
    final sendable = spec.readOnlyOnly ? [for (final r in selected) if (MatrixReadOnly.allows(r.method)) r] : selected;
    final grid = MatrixGrid(spec.columns, [
      for (final r in sendable)
        MatrixRow(
          key: rowKey(r.id),
          name: r.name,
          method: r.method.label,
          folder: plan.folderPath(r.folderId),
          columns: spec.columns.length,
        ),
    ]);
    final notes = <String, String>{};
    final leftOut = selected.length - sendable.length;
    if (sendable.isEmpty) return MatrixRunResult(grid, notes, leftOut, false);
    final ids = RunSelection.requests([for (final r in sendable) r.id]);

    final original = (await _environments.watchActive().first);
    final environments = await _environments.watchAll().first;
    var cancelled = false;
    try {
      for (final (index, column) in spec.columns.indexed) {
        if (cancelToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        onProgress?.call(grid, notes, index);
        try {
          await _runColumn(
            spec: spec,
            ids: ids,
            grid: grid,
            notes: notes,
            index: index,
            column: column,
            original: original,
            environments: environments,
            cancelToken: cancelToken,
            confirm: confirm,
            onProgress: onProgress,
          );
        } catch (e) {
          // One column failing (a broken store, an environment gone) must not end the others.
          _fail(grid, notes, index, column, SecretMasker.maskMessage('The column could not run: $e'));
          onProgress?.call(grid, notes, index);
        }
        if (cancelToken?.isCancelled ?? false) cancelled = true;
      }
    } finally {
      await _restore(original);
    }
    return MatrixRunResult(grid, notes, leftOut, cancelled);
  }

  /// The key of a request's row.
  static String rowKey(int requestId) => 'r$requestId';

  Future<void> _runColumn({
    required MatrixRunSpec spec,
    required RunSelection ids,
    required MatrixGrid grid,
    required Map<String, String> notes,
    required int index,
    required MatrixColumn column,
    required EnvironmentEntity? original,
    required List<EnvironmentEntity> environments,
    required ApiCancelToken? cancelToken,
    required ProductionConfirm? confirm,
    required MatrixProgress? onProgress,
  }) async {
    final named = column.environment;
    final target = named == null ? original : environments.where((e) => e.name == named).firstOrNull;
    if (named != null && target == null) {
      _fail(grid, notes, index, column, 'The environment "$named" no longer exists.');
      return;
    }
    await _activate(target);

    // The requests as this environment sees them ("Run if" can leave some out), judged by the production lock before
    // anything is sent.
    final guard = _guard;
    if (guard != null) {
      final requests = await _runner.fullRequestsIn(spec.collectionId, selection: ids);
      final warning = await guard.checkRunRequests(requests, spec.collectionName);
      if (warning != null) {
        final go = confirm == null ? false : await confirm(warning);
        if (!go) {
          _fail(grid, notes, index, column, 'Not sent: the production confirmation for ${warning.environmentName} was declined.');
          onProgress?.call(grid, notes, index);
          return;
        }
      }
    }

    final answers = <int, ApiResponseEntity>{};
    Future<void> work() async {
      final overrides = column.overrides;
      await for (final result in _runner.run(
        spec.collectionId,
        options: CollectionRunOptions(dataRows: overrides.isEmpty ? const [] : [overrides]),
        cancelToken: cancelToken,
        selection: ids,
        onResponse: (request, response) => answers[request.id] = response,
      )) {
        grid.setCell(rowKey(result.request.id), index, _cellOf(result, answers.remove(result.request.id)));
        onProgress?.call(grid, notes, index);
      }
    }

    final sessions = _sessions;
    if (column.identity != null && sessions != null) {
      await sessions.isolated(work);
    } else {
      await work();
    }
  }

  MatrixCell _cellOf(CollectionRunResult result, ApiResponseEntity? answer) {
    if (result.skipped != null) return MatrixCell.notSent(result.skipped!);
    final error = result.error;
    if (error != null) return MatrixCell.failed(error);
    final response = result.response;
    if (response == null) return const MatrixCell.failed('No answer.');
    return MatrixCell.response(
      status: response.statusCode,
      duration: response.duration,
      bodyBytes: answer?.bodyBytes,
      truncated: response.truncated,
      contentType: _header(response.headers, 'content-type'),
    );
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  /// Every cell of a column that did not run (or did not finish) says why, so the grid has no silent gap.
  void _fail(MatrixGrid grid, Map<String, String> notes, int index, MatrixColumn column, String reason) {
    notes[column.key] = reason;
    for (final row in grid.rows) {
      row.cells[index] ??= MatrixCell.notSent(reason);
    }
  }

  Future<void> _activate(EnvironmentEntity? target) async {
    final now = await _environments.watchActive().first;
    if (now?.id == target?.id) return;
    if (target == null) {
      await _environments.clearActive();
    } else {
      await _environments.setActive(target.id);
    }
  }

  /// The person's own active environment, or "No Environment", back as it was. An environment deleted meanwhile cannot
  /// come back, and that must not hide how the run ended.
  Future<void> _restore(EnvironmentEntity? original) async {
    try {
      await _activate(original);
    } catch (_) {
      // nothing left to restore
    }
  }
}
