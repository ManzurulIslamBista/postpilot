import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import '../../../core/network/api_http_response.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../domain/entities/monitor_config.dart';
import '../domain/repositories/monitor_config_store.dart';
import '../domain/repositories/run_record_repository.dart';
import '../domain/services/monitor_runner.dart';

/// A timer the service can cancel; tests replace the real one with a clock they advance by hand.
abstract interface class MonitorTimer {
  void cancel();
}

typedef MonitorTimerFactory = MonitorTimer Function(Duration delay, void Function() callback);

final class _RealTimer implements MonitorTimer {
  final Timer _timer;
  _RealTimer(Duration delay, void Function() callback) : _timer = Timer(delay, callback);

  @override
  void cancel() => _timer.cancel();
}

MonitorTimer _realTimer(Duration delay, void Function() callback) => _RealTimer(delay, callback);

/// Runs the monitored collections again and again while the app is open, and keeps what the person sees: which
/// collections are monitored, how each last run went, and a banner when one starts failing.
///
/// Rules it keeps:
///  * a run never overlaps the one before it (a slow run delays the next, it does not pile up);
///  * the next run starts [MonitorConfig.interval] after the start of the last, but never sooner than [minimumGap]
///    after its end;
///  * every timer is cancelled when the app goes away (`detached`), when a collection stops being monitored or is
///    deleted, and on [dispose], and a run in flight is cancelled with them: nothing outlives the app;
///  * a restored monitor waits [startupDelay] before its first run, so it does not send requests while the workspace is
///    still loading.
final class MonitorService with ChangeNotifier {
  /// How long a monitor restored at start-up waits before it first runs.
  final Duration startupDelay;

  /// The shortest time between the end of a run and the start of the next, whatever the interval says.
  final Duration minimumGap;

  final MonitorConfigStore _store;
  final CollectionRepository _collections;
  final RunRecordRepository _records;
  final MonitorRun _runner;
  final DateTime Function() _now;
  final MonitorTimerFactory _timerFactory;

  MonitorService({
    required this._store,
    required this._collections,
    required this._records,
    required this._runner,
    DateTime Function()? now,
    MonitorTimerFactory? timerFactory,
    this.startupDelay = const Duration(seconds: 30),
    this.minimumGap = const Duration(seconds: 15),
  })  : _now = now ?? DateTime.now,
        _timerFactory = timerFactory ?? _realTimer;

  final Map<int, MonitorConfig> _configs = {};
  final Map<int, MonitorStatus> _statuses = {};
  final Map<int, MonitorTimer> _timers = {};
  final Map<int, DateTime> _lastStart = {};
  final Map<int, ApiCancelToken> _tokens = {};
  final Set<int> _running = {};

  /// Whether the last run of a collection passed; absent while unknown.
  final Map<int, bool> _lastPassed = {};
  Map<int, String> _names = {};
  StreamSubscription<List<CollectionEntity>>? _namesSubscription;
  Future<void>? _starting;
  bool _paused = false;
  bool _disposed = false;

  /// The banners for runs that went from passing to failing, oldest first; [dismissAlert] removes one.
  final List<MonitorAlert> _alerts = [];
  List<MonitorAlert> get alerts => List.unmodifiable(_alerts);

  /// Loads the saved choices and starts the timers. Safe to call again.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final saved = await _store.load();
    if (_disposed) return;
    _configs
      ..clear()
      ..addAll({for (final e in saved.entries) if (e.value.enabled) e.key: e.value});
    _namesSubscription = _collections.watchCollections().listen(_onCollections, onError: (_) {});
    for (final id in _configs.keys.toList()) {
      await _restoreStatus(id);
      _schedule(id, delay: startupDelay);
    }
    notifyListeners();
  }

  /// What the last stored monitor run of [collectionId] said, so a restart does not forget that a collection is
  /// failing (and does not announce it as news again); unknown when there is no such run.
  Future<void> _restoreStatus(int collectionId) async {
    StoredRun? last;
    try {
      last = (await _records.recent(collectionId, limit: 5)).where((r) => r.doc.trigger == 'monitor').firstOrNull;
    } catch (_) {
      last = null;
    }
    if (last == null) {
      _statuses[collectionId] = const MonitorStatus(state: MonitorState.waiting);
      return;
    }
    final passing = last.doc.failed == 0;
    _lastPassed[collectionId] = passing;
    _statuses[collectionId] = MonitorStatus(
      state: passing ? MonitorState.passing : MonitorState.failing,
      lastRunAt: last.startedAt,
      failed: last.doc.failed,
    );
  }

  void _onCollections(List<CollectionEntity> collections) {
    _names = {for (final c in collections) c.id: c.name};
    final gone = [for (final id in _configs.keys) if (!_names.containsKey(id)) id];
    for (final id in gone) {
      _forget(id);
    }
    if (gone.isNotEmpty) unawaited(_persist());
    notifyListeners();
  }

  void _forget(int id) {
    _cancel(id);
    _configs.remove(id);
    _statuses.remove(id);
    _lastStart.remove(id);
    _lastPassed.remove(id);
    _alerts.removeWhere((a) => a.collectionId == id);
  }

  MonitorConfig? configOf(int collectionId) => _configs[collectionId];

  MonitorStatus statusOf(int collectionId) => _statuses[collectionId] ?? const MonitorStatus();

  /// The monitored collections and their last state, for the status chip.
  List<({int collectionId, String name, MonitorStatus status})> get monitored => [
        for (final id in _configs.keys) (collectionId: id, name: _names[id] ?? 'Collection $id', status: statusOf(id)),
      ];

  bool get isActive => _configs.isNotEmpty;
  int get failingCount => _statuses.values.where((s) => s.isFailing).length;

  /// Turns monitoring of [collectionId] on, off or changes it. Turning it on runs it soon; the choice is saved.
  Future<void> setConfig(int collectionId, MonitorConfig config) async {
    if (_disposed) return;
    final wasEnabled = _configs.containsKey(collectionId);
    if (!config.enabled) {
      _forget(collectionId);
    } else {
      final changed = _configs[collectionId] != config;
      _configs[collectionId] = config;
      if (!wasEnabled) await _restoreStatus(collectionId);
      if (_disposed) return;
      _statuses.putIfAbsent(collectionId, () => const MonitorStatus(state: MonitorState.waiting));
      if (!wasEnabled || (changed && !_running.contains(collectionId))) _schedule(collectionId, delay: Duration.zero);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _store.save(Map.of(_configs));
    } catch (_) {
      // The monitor still runs this session; the choice is only not remembered.
    }
  }

  /// Runs [collectionId] now, whatever the schedule says. The next run follows an interval after this one.
  Future<void> runNow(int collectionId) => _run(collectionId);

  void _schedule(int id, {required Duration delay}) {
    _cancelTimer(id);
    if (_paused || _disposed || !_configs.containsKey(id)) return;
    final wait = delay.isNegative ? Duration.zero : delay;
    _statuses[id] = _statusWith(id, nextRunAt: _now().add(wait), state: _running.contains(id) ? MonitorState.running : null);
    _timers[id] = _timerFactory(wait, () {
      _timers.remove(id);
      unawaited(_run(id));
    });
  }

  Future<void> _run(int id) async {
    final config = _configs[id];
    if (_disposed || config == null) return;
    // Never two runs of one collection at once: the next is scheduled when this one ends.
    if (_running.contains(id)) return;
    _cancelTimer(id);
    _running.add(id);
    final started = _now();
    _lastStart[id] = started;
    final token = _tokens[id] = ApiCancelToken();
    _statuses[id] = _statusWith(id, state: MonitorState.running);
    notifyListeners();

    MonitorRunResult? result;
    String? failure;
    try {
      result = await _runner.run(id, config, cancelToken: token);
    } catch (e) {
      failure = _clean(e);
    }
    _running.remove(id);
    _tokens.remove(id);
    if (_disposed || !_configs.containsKey(id) || token.isCancelled) return;

    final previous = _lastPassed[id];
    if (result != null) {
      final passing = result.isPassing;
      _statuses[id] = MonitorStatus(
        state: result.ranNothing ? MonitorState.error : (passing ? MonitorState.passing : MonitorState.failing),
        lastRunAt: started,
        failed: result.failed,
        skippedByLock: result.skippedByLock,
        ranNothing: result.ranNothing,
        error: result.ranNothing
            ? 'Nothing was sent: every request changes data and the environment looks like production, so the monitor left them all out.'
            : null,
      );
      if (!result.ranNothing) {
        _lastPassed[id] = passing;
        if (passing) {
          _alerts.removeWhere((a) => a.collectionId == id);
        } else if (previous != false) {
          // Passing (or unknown) before, failing now: say so once.
          _alerts
            ..removeWhere((a) => a.collectionId == id)
            ..add(MonitorAlert(collectionId: id, collectionName: _names[id] ?? 'Collection $id', failed: result.failed, at: started));
        }
      }
    } else {
      _statuses[id] = MonitorStatus(state: MonitorState.error, lastRunAt: started, error: failure);
    }
    // An interval after the start of this run, but never hammering: at least the minimum gap after its end.
    final due = started.add((_configs[id] ?? config).interval).difference(_now());
    _schedule(id, delay: due < minimumGap ? minimumGap : due);
    notifyListeners();
  }

  MonitorStatus _statusWith(int id, {MonitorState? state, DateTime? nextRunAt}) {
    final s = statusOf(id);
    return MonitorStatus(
      state: state ?? (s.state == MonitorState.off ? MonitorState.waiting : s.state),
      lastRunAt: s.lastRunAt,
      nextRunAt: nextRunAt ?? s.nextRunAt,
      failed: s.failed,
      skippedByLock: s.skippedByLock,
      ranNothing: s.ranNothing,
      error: s.error,
    );
  }

  String _clean(Object e) {
    final text = e is StateError ? e.message : '$e';
    return text.length <= 240 ? text : '${text.substring(0, 239)}…';
  }

  void dismissAlert(int collectionId) {
    _alerts.removeWhere((a) => a.collectionId == collectionId);
    notifyListeners();
  }

  /// The app goes away (`detached`): every timer and run in flight ends, so nothing keeps sending requests behind a
  /// closed window. When it comes back (`resumed`) the timers are set again, a run that fell due runs soon.
  void onLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.detached) {
      _pause();
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      for (final id in _configs.keys) {
        final last = _lastStart[id];
        final due = last == null ? startupDelay : last.add(_configs[id]!.interval).difference(_now());
        _schedule(id, delay: due);
      }
      notifyListeners();
    }
  }

  void _pause() {
    _paused = true;
    for (final id in _timers.keys.toList()) {
      _cancelTimer(id);
    }
    for (final token in _tokens.values) {
      token.cancel();
    }
  }

  void _cancel(int id) {
    _cancelTimer(id);
    _tokens.remove(id)?.cancel();
  }

  void _cancelTimer(int id) => _timers.remove(id)?.cancel();

  @override
  void dispose() {
    _disposed = true;
    _namesSubscription?.cancel();
    for (final id in _timers.keys.toList()) {
      _cancelTimer(id);
    }
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    super.dispose();
  }
}
