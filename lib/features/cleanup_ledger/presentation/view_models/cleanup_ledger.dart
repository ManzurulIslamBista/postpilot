import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_flow/domain/entities/sent_request.dart';
import '../../domain/entities/cleanup_entry.dart';
import '../../domain/services/cleanup_executor.dart';
import '../../domain/services/cleanup_planner.dart';

/// What the records created in this session are, and the way to delete them again. Fed by every send that got an answer
/// (`RequestFlowService` tells it, so a send by hand and a collection run both arrive), kept in memory only: nothing
/// is written to the database, a backup or Git, and it is gone when PostPilot closes.
///
/// Only a request with "Clean up what this request creates" switched on leaves an entry. A delete goes through the app's
/// normal send path (see `AppCleanupSender`), newest record first, and one that fails does not stop the others.
class CleanupLedger with ChangeNotifier {
  /// The most entries kept unless asked otherwise. Past it the oldest settled one goes first, then the oldest of all: a
  /// monitor that creates a record every minute must not grow the list for ever. A run of a thousand passes still fits.
  static const defaultMaxEntries = 5000;

  final CleanupSender _sender;
  final DateTime Function() _now;

  final List<CleanupEntry> _entries = [];

  /// Entries a delete has taken hold of: from the moment it is asked for until it is done, so a second one cannot start
  /// on the same records while the production warning is still open.
  final Set<int> _claimed = {};

  /// The claimed entries that are really being sent now (the person has agreed, if they had to).
  final Set<int> _working = {};

  /// The undo requests being sent: a send of one of them must not leave an entry of its own.
  final Set<ApiRequestEntity> _undoing = HashSet<ApiRequestEntity>.identity();
  int _lastId = 0;
  bool _autoCleanup = false;

  /// How many entries are kept at most.
  final int maxEntries;

  CleanupLedger(this._sender, {DateTime Function()? now, this.maxEntries = defaultMaxEntries}) : _now = now ?? DateTime.now;

  /// Every entry, in the order the records were created (the oldest first).
  List<CleanupEntry> get entries => UnmodifiableListView(_entries);

  /// A number that marks "now": [since] gives the entries made after it. A collection run takes one when it starts.
  int get mark => _lastId;

  /// The entries made after [mark], in creation order.
  List<CleanupEntry> since(int mark) => [for (final e in _entries) if (e.id > mark) e];

  CleanupEntry? byId(int id) => _entries.where((e) => e.id == id).firstOrNull;

  /// How many entries a delete could still be tried for.
  int get deletableCount => _entries.where((e) => e.canDelete).length;

  /// Whether a delete of this entry is under way.
  bool isWorking(int id) => _working.contains(id);

  bool get isBusy => _working.isNotEmpty;

  /// "Auto clean up after the run": a collection run deletes what it made when it is done. A choice for this session.
  bool get autoCleanup => _autoCleanup;

  set autoCleanup(bool value) {
    if (value == _autoCleanup) return;
    _autoCleanup = value;
    notifyListeners();
  }

  /// Called for every send that got an answer. Records what a request with cleanup switched on created.
  Future<void> recordSend(SentRequest sent) async {
    final settings = sent.settings.flow.cleanup;
    if (!settings.enabled || _undoing.contains(sent.request)) return;
    final drafts = CleanupPlanner.plan(
      request: sent.request,
      settings: settings,
      statusCode: sent.response.statusCode,
      responseBody: utf8.decode(sent.response.bodyBytes, allowMalformed: true),
      environment: sent.environment,
      now: _now(),
      dataVariables: sent.dataVariables,
    );
    if (drafts.isEmpty) return;
    for (final draft in drafts) {
      _entries.add(CleanupEntry(
        id: ++_lastId,
        requestName: draft.requestName,
        environment: draft.environment,
        createdAt: draft.createdAt,
        ids: draft.ids,
        plan: draft.plan,
        variables: draft.variables,
        state: draft.state,
        reason: draft.reason,
      ));
    }
    _trim();
    notifyListeners();
  }

  /// Deletes [chosen] (the ones that are not deleted yet), newest first. [gate] is asked once with every request about
  /// to go out, and is where the production lock gets its confirmation; without one the lock cannot be asked, so a
  /// caller that has none must not be used for production (see `productionGate`).
  Future<CleanupRun> cleanup(Iterable<CleanupEntry> chosen, {CleanupGate? gate}) async {
    final todo = [
      for (final e in chosen)
        if (byId(e.id) case final current? when current.canDelete && !_claimed.contains(current.id)) current,
    ];
    if (todo.isEmpty) return const CleanupRun([]);
    final ids = {for (final e in todo) e.id};
    _claimed.addAll(ids);
    // Nothing shows as "deleting" while a question is open: the person has not said yes yet.
    final asked = gate == null
        ? null
        : (List<ApiRequestEntity> requests) async {
            final go = await gate(requests);
            if (go) {
              _working.addAll(ids);
              notifyListeners();
            }
            return go;
          };
    if (gate == null) {
      _working.addAll(ids);
      notifyListeners();
    }
    try {
      return await CleanupExecutor.run(todo, _UndoGuard(_sender, _undoing), gate: asked, onResult: _settle);
    } finally {
      _claimed.removeAll(ids);
      _working.removeAll(ids);
      notifyListeners();
    }
  }

  /// Deletes every record that is still there.
  Future<CleanupRun> cleanupAll({CleanupGate? gate}) => cleanup(_entries.where((e) => e.canDelete).toList(), gate: gate);

  /// Takes an entry off the list without deleting anything (a record that was removed by hand, or is meant to stay).
  void forget(int id) {
    if (_claimed.contains(id)) return;
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  /// Takes every entry that needs nothing more (deleted, or never deletable) off the list.
  void clearFinished() {
    final before = _entries.length;
    _entries.removeWhere((e) => e.state == CleanupState.deleted || e.state == CleanupState.skipped);
    if (_entries.length != before) notifyListeners();
  }

  void _settle(CleanupResult result) {
    final index = _entries.indexWhere((e) => e.id == result.entry.id);
    if (index == -1) return; // forgotten while it was being deleted
    _entries[index] = _entries[index].settled(result.state, reason: result.reason, at: _now());
    notifyListeners();
  }

  void _trim() {
    while (_entries.length > maxEntries) {
      final settled = _entries.indexWhere((e) => !e.canDelete && !_claimed.contains(e.id));
      _entries.removeAt(settled == -1 ? 0 : settled);
    }
  }
}

/// Marks the request about to be sent as an undo, so the ledger does not take its answer for a create.
final class _UndoGuard implements CleanupSender {
  final CleanupSender _inner;
  final Set<ApiRequestEntity> _undoing;

  const _UndoGuard(this._inner, this._undoing);

  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) => _inner.prepare(entry);

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) async {
    final request = prepared.request;
    if (request != null) _undoing.add(request);
    try {
      return await _inner.send(prepared);
    } finally {
      if (request != null) _undoing.remove(request);
    }
  }
}
