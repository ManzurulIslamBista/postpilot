// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or a CI job.
import '../../auth_renewal/domain/services/relogin_policy.dart';
import '../../cli/iterated_run.dart';
import '../../cli/workspace_runner.dart';
import '../../documentation/domain/services/secret_masker.dart';
import '../../import_export/domain/services/backup_codec.dart';
import '../../import_export/domain/services/backup_order.dart';
import '../../scripting/domain/entities/extractor_entity.dart';
import '../../settings/domain/entities/request_settings.dart';
import '../domain/entities/cleanup_entry.dart';
import '../domain/entities/cleanup_settings.dart';
import '../domain/services/cleanup_executor.dart';
import '../domain/services/cleanup_planner.dart';
import '../domain/services/delete_response_check.dart';

/// What `postpilot run --cleanup` did after the run, ready to print.
final class CliCleanupReport {
  /// The lines to print, none when nothing was made.
  final List<String> lines;

  /// Records deleted.
  final int deleted;

  /// Deletes that were tried and did not work (the server refused, the production lock refused, a variable was missing).
  final int failed;

  /// Creates whose records could not be cleaned up at all: no id in the answer, no way to undo. They are still on the
  /// server, so they count against the exit code like a failed delete.
  final int notCleaned;

  const CliCleanupReport(this.lines, {this.deleted = 0, this.failed = 0, this.notCleaned = 0});

  /// Whether something was left on the server that the cleanup was asked to remove.
  bool get hasFailures => failed > 0 || notCleaned > 0;

  String get text => lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// Deletes what the requests of a finished command-line run created, newest first, through the runner itself: each
/// delete is a request of the workspace's collection, sent with the same environment, variables, authentication,
/// cookies and production lock as the run (so `--allow-production` is needed to delete in production, exactly as it was
/// to create there, and an MCP agent has no way to ask for it).
///
/// Only a request with "Clean up what this request creates" switched on is looked at. Every pass of an `--iterations` or
/// `--data` run is cleaned with the variables that pass ended with.
Future<CliCleanupReport> runCliCleanup({
  required WorkspaceRunner runner,
  required IteratedRun run,
  required RunOptions Function(Map<String, String> row) optionsFor,
  required Map<String, String> processVariables,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final index = _Index(runner.snapshot);
  final entries = <CleanupEntry>[];
  final contexts = <int, _Context>{};
  final collections = <int, BackupCollection>{};
  final targets = <int, BackupRequest>{};
  var lastId = 0;
  var configured = false;

  for (final (pass, summary) in run.passes.indexed) {
    final row = pass < run.rows.length ? run.rows[pass] : const <String, String>{};
    final options = optionsFor(row);
    _Context? context;
    for (final outcome in summary.outcomes) {
      if (outcome.skipped != null || outcome.error != null || outcome.blocked != null || !outcome.isSuccess) continue;
      final found = index.find(outcome.collection, outcome.folder, outcome.name);
      final settings = found?.item.settings?.flow.cleanup ?? CleanupSettings.none;
      if (found == null || !settings.enabled) continue;
      configured = true;
      final drafts = CleanupPlanner.plan(
        request: found.item.request,
        settings: settings,
        statusCode: outcome.status!,
        responseBody: outcome.responseBody ?? '',
        environment: options.environment,
        now: clock(),
        dataVariables: row,
      );
      for (final draft in drafts) {
        final entry = CleanupEntry(
          id: ++lastId,
          requestName: [outcome.collection, if (outcome.folder.isNotEmpty) outcome.folder, outcome.name].join(' / '),
          environment: draft.environment,
          createdAt: draft.createdAt,
          ids: draft.ids,
          plan: draft.plan,
          variables: draft.variables,
          state: draft.state,
          reason: draft.reason,
        );
        entries.add(entry);
        context ??= _Context(options, runner.newState(options, processVariables: processVariables))..replay(summary.outcomes);
        contexts[entry.id] = context;
        collections[entry.id] = found.collection;
        // The request that undoes it when it is another request of the collection, found now while the workspace is at hand.
        if (entry.state == CleanupState.pending && draft.plan.kind == CleanupUndo.request) {
          final target = index.target(found.collection, draft.plan.undoRequest);
          if (target != null) targets[entry.id] = target;
        }
      }
    }
  }

  if (entries.isEmpty) {
    return CliCleanupReport([
      configured
          ? 'Cleanup: the run created no record that could be cleaned up.'
          : 'Cleanup: no request has "Clean up what this request creates" switched on, so there was nothing to delete.',
    ]);
  }

  final sender = _CliSender(runner, contexts, collections, targets);
  final result = await CleanupExecutor.run(entries, sender);
  final byId = {for (final r in result.results) r.entry.id: r};
  final lines = <String>[];
  var deleted = 0;
  var failed = 0;
  var notCleaned = 0;
  final created = entries.where((e) => e.state != CleanupState.skipped).fold<int>(0, (sum, e) => sum + e.recordCount);
  lines.add('Cleanup: $created ${created == 1 ? 'record was' : 'records were'} created by this run, deleting the newest first.');
  for (final entry in entries.reversed) {
    if (entry.state == CleanupState.skipped) {
      notCleaned++;
      lines.add('  not cleaned up  ${entry.requestName}: ${entry.reason}');
      continue;
    }
    final outcome = byId[entry.id];
    if (outcome != null && outcome.ok) {
      deleted += entry.recordCount;
      lines.add('  deleted  ${entry.requestName}  ${entry.plan.summary}');
    } else {
      failed++;
      lines.add('  FAILED   ${entry.requestName}  ${entry.plan.summary}');
      lines.add('           ${outcome?.reason ?? 'It was not tried.'}');
    }
  }
  lines.add(
    'Cleanup: $deleted ${deleted == 1 ? 'record' : 'records'} deleted'
    '${failed == 0 ? '' : ', $failed ${failed == 1 ? 'delete' : 'deletes'} failed'}'
    '${notCleaned == 0 ? '' : ', $notCleaned ${notCleaned == 1 ? 'create' : 'creates'} could not be cleaned up'}.',
  );
  return CliCleanupReport(lines, deleted: deleted, failed: failed, notCleaned: notCleaned);
}

/// The variables a pass ended with, and the options it ran under: what a delete of one of its records is sent with.
final class _Context {
  final RunOptions options;
  final RunState state;

  _Context(this.options, this.state);

  /// What the requests of the pass saved with their extractors (a token, an id): the state a run ends with, which the
  /// runner keeps to itself, rebuilt from the values it reported.
  void replay(List<RequestOutcome> outcomes) {
    for (final outcome in outcomes) {
      for (final extracted in outcome.scripts.extracted) {
        final value = extracted.value;
        if (!extracted.ok || value == null) continue;
        (extracted.scope == ExtractorScope.environment ? state.environment : state.globals)[extracted.key] = value;
      }
    }
  }
}

/// Finds a request of the workspace by where it sits.
final class _Index {
  final BackupSnapshot snapshot;
  const _Index(this.snapshot);

  ({BackupCollection collection, BackupRequest item})? find(String collection, String folder, String name) {
    for (final c in snapshot.collections) {
      if (c.name != collection) continue;
      for (final item in c.orderedRequests) {
        if (item.request.name == name && _folderPath(c, item.request.folderId) == folder) return (collection: c, item: item);
      }
    }
    return null;
  }

  /// The request [selector] (`Name`, or `Folder/Name`) names in [collection]; null when none or more than one does.
  BackupRequest? target(BackupCollection collection, String selector) {
    final candidates = [
      for (final r in collection.orderedRequests)
        ReloginCandidate<BackupRequest>(folderPath: _folderPath(collection, r.request.folderId), name: r.request.name, method: r.request.method, value: r),
    ];
    return switch (ReloginPolicy.find(selector, candidates)) {
      ReloginFound(:final candidate) => candidate.value,
      _ => null,
    };
  }

  static String _folderPath(BackupCollection collection, int? folderId) {
    final names = <String>[];
    var current = folderId;
    var guard = 0;
    while (current != null && guard++ < 50) {
      final folder = collection.folders.where((f) => f.id == current).firstOrNull;
      if (folder == null) break;
      names.insert(0, folder.name);
      current = folder.parentFolderId;
    }
    return names.join('/');
  }
}

final class _CliSender implements CleanupSender {
  final WorkspaceRunner _runner;
  final Map<int, _Context> _contexts;
  final Map<int, BackupCollection> _collections;
  final Map<int, BackupRequest> _targets;

  const _CliSender(this._runner, this._contexts, this._collections, this._targets);

  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) async {
    if (entry.plan.kind != CleanupUndo.request) {
      final planned = entry.plan.request;
      return planned == null ? CleanupPrepared.failed(entry, 'There is no request to undo this with.') : CleanupPrepared.ready(entry, planned);
    }
    final target = _targets[entry.id];
    if (target != null) return CleanupPrepared.ready(entry, target.request);
    return CleanupPrepared.failed(
      entry,
      'No single request of the collection is called "${entry.plan.undoRequest}" (give its name, or Folder/Name).',
    );
  }

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) async {
    final entry = prepared.entry;
    final context = _contexts[entry.id]!;
    final BackupRequest item = entry.plan.kind == CleanupUndo.request
        ? _targets[entry.id]!
        : BackupRequest(request: prepared.request!, settings: RequestSettings.none);
    // The created id and the fields of the answer sit above everything else for this one request, like a data row.
    final overrides = context.state.overrides;
    final replaced = {for (final key in entry.variables.keys) key: overrides[key]};
    overrides.addAll(entry.variables);
    final RequestOutcome outcome;
    try {
      outcome = await _runner.runRequest(_collections[entry.id]!, item, context.state, context.options, runScripts: false);
    } finally {
      for (final key in entry.variables.keys) {
        final before = replaced[key];
        before == null ? overrides.remove(key) : overrides[key] = before;
      }
    }
    // The production lock, an unresolved variable or an unreachable server are all reported on the outcome itself.
    final stopped = outcome.blocked ?? outcome.error ?? (outcome.skipped == null ? null : 'Skipped: ${outcome.skipped}');
    if (stopped != null) return CleanupResult(entry, CleanupState.failed, SecretMasker.maskMessage(stopped));
    final problem = DeleteResponseCheck.failureOf(
      statusCode: outcome.status ?? 0,
      statusMessage: outcome.statusMessage ?? '',
      body: outcome.responseBody ?? '',
    );
    return problem == null ? CleanupResult(entry, CleanupState.deleted) : CleanupResult(entry, CleanupState.failed, problem);
  }
}
