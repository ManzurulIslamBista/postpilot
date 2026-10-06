import '../../../../core/network/api_http_response.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/services/collection_run_options.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../../../request_builder/domain/services/run_selection.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../../safety/domain/services/production_detector.dart';
import '../entities/monitor_config.dart';
import '../entities/run_record_doc.dart';
import '../repositories/run_record_repository.dart';
import 'app_run_mapper.dart';
import 'monitor_production_policy.dart';

/// What one monitored run did.
final class MonitorRunResult {
  final RunRecordDoc doc;
  final int? recordId;

  /// Requests left out by the production lock.
  final int skippedByLock;

  /// Every request was left out, so nothing was sent or checked.
  final bool ranNothing;

  const MonitorRunResult({required this.doc, required this.recordId, required this.skippedByLock, required this.ranNothing});

  int get failed => doc.failed;

  /// Something was sent and nothing failed.
  bool get isPassing => !ranNothing && doc.failed == 0;
}

/// Makes one monitored run. The monitor depends on this, so a test can stand in for the real requests.
abstract interface class MonitorRun {
  /// Runs [collectionId] with [config] and stores the run. Throws when the run cannot be made (the collection or the
  /// environment is gone); a failing request is a result, not an error.
  Future<MonitorRunResult> run(int collectionId, MonitorConfig config, {ApiCancelToken? cancelToken});
}

/// Runs a collection once for the monitor and stores the run: the same requests in the same order as the runner dialog,
/// minus whatever the production lock leaves out (see [MonitorProductionPolicy]).
///
/// A chosen environment is applied as the top scope of the run (like a data row), so the person's active environment is
/// never changed behind their back. Variables the active environment defines and the chosen one does not stay visible, so
/// the lock treats the run as production when either of them looks like production.
final class MonitorRunner implements MonitorRun {
  final CollectionRunnerService _runner;
  final CollectionRepository _collections;
  final EnvironmentRepository _environments;
  final BuildVariableResolverUseCase _resolver;
  final RunRecordRepository _records;

  /// The extra production words and production hosts of Settings > Safety, read at each run.
  final List<String> Function() _productionWords;
  final List<String> Function() _productionHosts;
  final DateTime Function() _now;

  MonitorRunner({
    required this._runner,
    required this._collections,
    required this._environments,
    required this._resolver,
    required this._records,
    List<String> Function()? productionWords,
    List<String> Function()? productionHosts,
    DateTime Function()? now,
  })  : _productionWords = productionWords ?? (() => const []),
        _productionHosts = productionHosts ?? (() => const []),
        _now = now ?? DateTime.now;

  /// Runs [collectionId] with [config]. [cancelToken] ends a run in flight (the app is closing).
  @override
  Future<MonitorRunResult> run(int collectionId, MonitorConfig config, {ApiCancelToken? cancelToken}) async {
    final startedAt = _now();
    final collection = (await _collections.watchCollections().first).where((c) => c.id == collectionId).firstOrNull;
    if (collection == null) throw StateError('The collection no longer exists.');
    final folders = await _collections.watchFolders(collectionId).first;

    final active = await _environments.watchActive().first;
    final chosen = config.environment == null ? null : await _environmentNamed(config.environment!);
    if (config.environment != null && chosen == null) {
      throw StateError('The environment "${config.environment}" no longer exists. Choose another one for the monitor.');
    }
    final environmentName = chosen?.name ?? active?.name ?? '';
    final data = chosen == null ? const <String, String>{} : await _variablesOf(chosen.id);

    final all = await _runner.fullRequestsIn(collectionId);
    final words = _productionWords();
    final productionEnvironment = [chosen?.name, active?.name].any((n) => n != null && ProductionDetector.isProduction(n, extraWords: words));
    final plan = MonitorProductionPolicy.plan(
      [for (final r in all) (request: r, resolvedUrl: await _resolve(collectionId, r, data))],
      productionEnvironment: productionEnvironment,
      productionHosts: _productionHosts(),
    );

    final results = <CollectionRunResult>[];
    if (plan.allowed.isNotEmpty) {
      await for (final result in _runner.run(
        collectionId,
        options: CollectionRunOptions(dataRows: data.isEmpty ? const [] : [data]),
        cancelToken: cancelToken,
        selection: RunSelection.requests([for (final r in plan.allowed) r.id]),
      )) {
        results.add(result);
      }
    }

    final urls = {for (final r in all) r.id: r.url};
    final entries = [
      for (final r in results)
        AppRunMapper.entryOf(r, folder: AppRunMapper.folderPath(folders, r.request.folderId), url: urls[r.request.id] ?? ''),
      for (final skip in plan.skipped)
        RunResultEntry(
          requestId: skip.request.id,
          name: skip.request.name,
          folder: AppRunMapper.folderPath(folders, skip.request.folderId),
          method: skip.request.method.label,
          url: skip.request.url,
          passed: true,
          skipped: skip.reason,
        ),
    ];
    final doc = AppRunMapper.docOf(
      collection: collection.name,
      environment: environmentName,
      startedAt: startedAt,
      duration: _now().difference(startedAt),
      results: entries,
      trigger: 'monitor',
    );
    final id = await _records.save(collectionId, doc);
    return MonitorRunResult(doc: doc, recordId: id, skippedByLock: plan.skipped.length, ranNothing: results.isEmpty);
  }

  Future<({int id, String name})?> _environmentNamed(String name) async {
    for (final e in await _environments.watchAll().first) {
      if (e.name == name) return (id: e.id, name: e.name);
    }
    return null;
  }

  Future<Map<String, String>> _variablesOf(int environmentId) async => {
        for (final v in await _environments.watchVariables(environmentId).first)
          if (v.enabled) v.key: v.value,
      };

  Future<String> _resolve(int collectionId, ApiRequestEntity request, Map<String, String> data) async {
    try {
      return (await _resolver(collectionId, dataVariables: data, folderId: request.folderId)).resolve(request.url);
    } catch (_) {
      return request.url; // a variable store that cannot be read must not stop the lock from judging
    }
  }
}
