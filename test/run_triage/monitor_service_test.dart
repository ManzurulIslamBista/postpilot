// The monitor's schedule, driven by a clock the test moves by hand: when runs start, that they never overlap, what is
// remembered across a restart, when a banner is raised, and that no timer outlives the app.
import 'dart:async';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/run_triage/domain/entities/monitor_config.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/repositories/monitor_config_store.dart';
import 'package:postpilot/features/run_triage/domain/repositories/run_record_repository.dart';
import 'package:postpilot/features/run_triage/domain/services/monitor_runner.dart';
import 'package:postpilot/features/run_triage/presentation/monitor_service.dart';
import 'run_fixtures.dart';

/// A clock and its timers: nothing happens until [advance] moves time forward, and then every timer that came due
/// fires, in order.
final class _Clock {
  DateTime now = DateTime.utc(2026, 10, 6, 10);
  final _timers = <_Timer>[];

  MonitorTimer timer(Duration delay, void Function() callback) {
    final t = _Timer(now.add(delay), callback);
    _timers.add(t);
    return t;
  }

  int get pending => _timers.where((t) => t.active).length;

  Future<void> advance(Duration by) async {
    final target = now.add(by);
    while (true) {
      final due = _timers.where((t) => t.active && !t.at.isAfter(target)).toList()..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      if (next.at.isAfter(now)) now = next.at;
      next.fired = true;
      next.callback();
      await pumpEventQueue();
    }
    now = target;
    await pumpEventQueue();
  }
}

final class _Timer implements MonitorTimer {
  final DateTime at;
  final void Function() callback;
  bool fired = false;
  bool cancelled = false;
  _Timer(this.at, this.callback);

  bool get active => !fired && !cancelled;

  @override
  void cancel() => cancelled = true;
}

final class _Store implements MonitorConfigStore {
  Map<int, MonitorConfig> saved = {};
  int saves = 0;

  @override
  Future<Map<int, MonitorConfig>> load() async => Map.of(saved);

  @override
  Future<void> save(Map<int, MonitorConfig> configs) async {
    saved = Map.of(configs);
    saves++;
  }
}

final class _Collections implements CollectionRepository {
  final controller = StreamController<List<CollectionEntity>>.broadcast();
  List<CollectionEntity> current = const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Billing')];

  @override
  Stream<List<CollectionEntity>> watchCollections() async* {
    yield current;
    yield* controller.stream;
  }

  void emit(List<CollectionEntity> list) {
    current = list;
    controller.add(list);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Records implements RunRecordRepository {
  final stored = <int, List<StoredRun>>{};

  void add(int collectionId, RunRecordDoc doc) => (stored[collectionId] ??= []).insert(0, StoredRun(id: stored.length * 100 + (stored[collectionId]?.length ?? 0), collectionId: collectionId, doc: doc));

  @override
  Future<List<StoredRun>> recent(int collectionId, {int limit = 50}) async => (stored[collectionId] ?? const []).take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// A monitor run record for a test; a top-level function because `_Run.run` hides the fixture's `run`.
RunRecordDoc _monitorDoc(List<RunResultEntry> results) => run(results, trigger: 'monitor');

/// Answers each run from a queue, and can hold one run open.
final class _Run implements MonitorRun {
  _Run(this.clock);

  final _Clock clock;
  final calls = <({int id, DateTime at, ApiCancelToken? token})>[];
  final results = <MonitorRunResult>[];
  Object? failWith;
  Completer<void>? gate;

  MonitorRunResult passing() => MonitorRunResult(doc: _monitorDoc([entry('A')]), recordId: 1, skippedByLock: 0, ranNothing: false);
  MonitorRunResult failing([int failed = 2]) => MonitorRunResult(
        doc: _monitorDoc([for (var i = 0; i < failed; i++) failedWith('R$i', 500)]),
        recordId: 2,
        skippedByLock: 0,
        ranNothing: false,
      );

  @override
  Future<MonitorRunResult> run(int collectionId, MonitorConfig config, {ApiCancelToken? cancelToken}) async {
    calls.add((id: collectionId, at: clock.now, token: cancelToken));
    final hold = gate;
    if (hold != null) await hold.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return results.isEmpty ? passing() : results.removeAt(0);
  }
}

void main() {
  late _Clock clock;
  late _Store store;
  late _Collections collections;
  late _Records records;
  late _Run runner;
  late MonitorService service;

  MonitorService build({Duration startup = const Duration(seconds: 30), Duration gap = const Duration(seconds: 15)}) => MonitorService(
        store: store,
        collections: collections,
        records: records,
        runner: runner,
        now: () => clock.now,
        timerFactory: clock.timer,
        startupDelay: startup,
        minimumGap: gap,
      );

  setUp(() {
    clock = _Clock();
    store = _Store();
    collections = _Collections();
    records = _Records();
    runner = _Run(clock);
    service = build();
  });

  tearDown(() {
    service.dispose();
    collections.controller.close();
  });

  const everyTen = MonitorConfig(enabled: true, everyMinutes: 10);
  final t0 = DateTime.utc(2026, 10, 6, 10);

  group('schedule', () {
    test('a restored monitor waits for the start-up delay, then runs every interval counted from the start of each run', () async {
      store.saved = {1: everyTen};
      await service.start();
      expect(runner.calls, isEmpty);
      await clock.advance(const Duration(seconds: 29));
      expect(runner.calls, isEmpty);
      await clock.advance(const Duration(seconds: 1));
      expect(runner.calls.map((c) => c.at), [t0.add(const Duration(seconds: 30))]);

      await clock.advance(const Duration(minutes: 10));
      await clock.advance(const Duration(minutes: 10));
      expect(runner.calls.map((c) => c.at.difference(t0).inSeconds), [30, 30 + 600, 30 + 1200]);
      expect(runner.calls.every((c) => c.id == 1), isTrue);
    });

    test('a collection that is not monitored is never run', () async {
      store.saved = {1: everyTen, 2: const MonitorConfig(enabled: false)};
      await service.start();
      await clock.advance(const Duration(hours: 1));
      expect(runner.calls.map((c) => c.id).toSet(), {1});
      expect(service.configOf(2), isNull);
    });

    test('turning a monitor on runs the collection soon, saves the choice and schedules the next run', () async {
      await service.start();
      await service.setConfig(1, everyTen);
      await clock.advance(Duration.zero);
      expect(runner.calls.map((c) => c.at), [t0]);
      expect(store.saved, {1: everyTen});
      expect(service.isActive, isTrue);
      await clock.advance(const Duration(minutes: 10));
      expect(runner.calls, hasLength(2));
    });

    test('turning it off cancels the timer and forgets the choice', () async {
      await service.start();
      await service.setConfig(1, everyTen);
      await clock.advance(const Duration(seconds: 1));
      expect(clock.pending, 1);
      await service.setConfig(1, const MonitorConfig());
      expect(clock.pending, 0);
      expect(store.saved, isEmpty);
      expect(service.isActive, isFalse);
      await clock.advance(const Duration(hours: 2));
      expect(runner.calls, hasLength(1));
    });

    test('a changed interval takes effect from the next run', () async {
      await service.start();
      await service.setConfig(1, everyTen);
      await clock.advance(const Duration(seconds: 1));
      await service.setConfig(1, everyTen.copyWith(everyMinutes: 30));
      await clock.advance(Duration.zero);
      // The change itself runs the collection again, then every 30 minutes.
      final afterChange = runner.calls.length;
      await clock.advance(const Duration(minutes: 29));
      expect(runner.calls, hasLength(afterChange));
      await clock.advance(const Duration(minutes: 1));
      expect(runner.calls, hasLength(afterChange + 1));
    });

    test('runNow runs at once and the next run follows an interval after it', () async {
      store.saved = {1: everyTen};
      await service.start();
      await service.runNow(1);
      expect(runner.calls.map((c) => c.at), [t0]);
      await clock.advance(const Duration(minutes: 10));
      expect(runner.calls.map((c) => c.at.difference(t0).inMinutes), [0, 10]);
    });
  });

  group('no overlap and no hammering', () {
    test('a run in flight is never started again, and a slow run delays the next by the minimum gap only', () async {
      store.saved = {1: const MonitorConfig(enabled: true, everyMinutes: 1)};
      runner.gate = Completer<void>();
      await service.start();
      await clock.advance(const Duration(seconds: 30));
      expect(runner.calls, hasLength(1));
      // Three minutes pass with the first run still open: no second run starts.
      await clock.advance(const Duration(minutes: 3));
      expect(runner.calls, hasLength(1));
      expect(service.statusOf(1).state, MonitorState.running);

      runner.gate!.complete();
      await pumpEventQueue();
      runner.gate = null;
      // The interval is long past, but the next run waits the minimum gap after the end of this one.
      await clock.advance(const Duration(seconds: 14));
      expect(runner.calls, hasLength(1));
      await clock.advance(const Duration(seconds: 1));
      expect(runner.calls, hasLength(2));
    });

    test('runNow while a run is in flight does not start a second one', () async {
      store.saved = {1: everyTen};
      runner.gate = Completer<void>();
      await service.start();
      final first = service.runNow(1);
      await pumpEventQueue();
      await service.runNow(1);
      expect(runner.calls, hasLength(1));
      runner.gate!.complete();
      await first;
    });
  });

  group('status and the banner', () {
    test('passing, failing, and the count the chip shows', () async {
      store.saved = {1: everyTen, 2: everyTen};
      await service.start();
      runner.results.addAll([runner.passing(), runner.failing(3)]);
      await clock.advance(const Duration(seconds: 30));
      expect(service.statusOf(1).state, MonitorState.passing);
      expect(service.statusOf(2).state, MonitorState.failing);
      expect(service.statusOf(2).failed, 3);
      expect(service.failingCount, 1);
      expect([for (final m in service.monitored) (m.name, m.status.state)], [('Shop', MonitorState.passing), ('Billing', MonitorState.failing)]);
    });

    test('a run that goes from passing to failing raises one banner; staying failing does not repeat it; passing clears it', () async {
      store.saved = {1: everyTen};
      await service.start();
      runner.results.addAll([runner.passing(), runner.failing(2), runner.failing(5), runner.passing()]);

      await clock.advance(const Duration(seconds: 30));
      expect(service.alerts, isEmpty);
      await clock.advance(const Duration(minutes: 10));
      expect(service.alerts.map((a) => (a.collectionName, a.failed)), [('Shop', 2)]);
      await clock.advance(const Duration(minutes: 10));
      expect(service.alerts, hasLength(1), reason: 'still failing: the same banner');
      expect(service.alerts.single.failed, 2);
      await clock.advance(const Duration(minutes: 10));
      expect(service.alerts, isEmpty, reason: 'passing again clears it');
      expect(service.statusOf(1).state, MonitorState.passing);
    });

    test('a banner can be dismissed, and comes back when the collection fails again after passing', () async {
      store.saved = {1: everyTen};
      await service.start();
      runner.results.addAll([runner.failing(), runner.passing(), runner.failing()]);
      await clock.advance(const Duration(seconds: 30));
      expect(service.alerts, hasLength(1), reason: 'failing on the very first run is news too');
      service.dismissAlert(1);
      expect(service.alerts, isEmpty);
      await clock.advance(const Duration(minutes: 10));
      await clock.advance(const Duration(minutes: 10));
      expect(service.alerts, hasLength(1));
    });

    test('a restart remembers that a collection was failing: no new banner, the chip is right at once', () async {
      store.saved = {1: everyTen};
      records.add(1, run([failedWith('A', 500), failedWith('B', 500)], trigger: 'monitor', at: t0.subtract(const Duration(hours: 1))));
      await service.start();
      expect(service.statusOf(1).state, MonitorState.failing);
      expect(service.statusOf(1).failed, 2);
      expect(service.failingCount, 1);
      runner.results.add(runner.failing());
      await clock.advance(const Duration(seconds: 30));
      expect(service.alerts, isEmpty);
    });

    test('a manual run in the app is not mistaken for a monitor run when restoring', () async {
      store.saved = {1: everyTen};
      records.add(1, run([failedWith('A', 500)], trigger: 'manual'));
      await service.start();
      expect(service.statusOf(1).state, MonitorState.waiting);
    });

    test('a run that could not be made says why and is tried again at the next interval', () async {
      store.saved = {1: everyTen};
      await service.start();
      runner.failWith = StateError('The environment "Gone" no longer exists. Choose another one for the monitor.');
      await clock.advance(const Duration(seconds: 30));
      expect(service.statusOf(1).state, MonitorState.error);
      expect(service.statusOf(1).error, contains('"Gone" no longer exists'));
      expect(service.alerts, isEmpty);
      runner.failWith = null;
      await clock.advance(const Duration(minutes: 10));
      expect(service.statusOf(1).state, MonitorState.passing);
    });

    test('a run that left everything out is not a pass and not a failure, and says so', () async {
      store.saved = {1: everyTen};
      await service.start();
      runner.results.add(MonitorRunResult(doc: run([entry('A', skipped: 'Left out', status: null)], trigger: 'monitor'), recordId: 3, skippedByLock: 1, ranNothing: true));
      await clock.advance(const Duration(seconds: 30));
      final s = service.statusOf(1);
      expect((s.state, s.ranNothing, s.skippedByLock), (MonitorState.error, true, 1));
      expect(s.error, contains('Nothing was sent'));
      expect(service.alerts, isEmpty);
      expect(service.failingCount, 0);
    });

    test('the production lock count of the last run is kept for the dialog', () async {
      store.saved = {1: everyTen};
      await service.start();
      runner.results.add(MonitorRunResult(doc: run([entry('A')], trigger: 'monitor'), recordId: 3, skippedByLock: 2, ranNothing: false));
      await clock.advance(const Duration(seconds: 30));
      expect(service.statusOf(1).skippedByLock, 2);
      expect(service.statusOf(1).state, MonitorState.passing);
    });
  });

  group('timers do not outlive the app', () {
    test('detached cancels every timer and the run in flight; resumed sets them again and an overdue run goes soon', () async {
      store.saved = {1: everyTen, 2: everyTen};
      await service.start();
      await clock.advance(const Duration(seconds: 30));
      expect(runner.calls, hasLength(2));
      expect(clock.pending, 2);

      service.onLifecycle(AppLifecycleState.detached);
      expect(clock.pending, 0);
      await clock.advance(const Duration(hours: 1));
      expect(runner.calls, hasLength(2), reason: 'nothing runs while the app is gone');

      service.onLifecycle(AppLifecycleState.resumed);
      expect(clock.pending, 2);
      await clock.advance(Duration.zero);
      expect(runner.calls, hasLength(4), reason: 'the runs that fell due while it was gone run now');
      // And then the usual rhythm again.
      await clock.advance(const Duration(minutes: 10));
      expect(runner.calls, hasLength(6));
    });

    test('a run in flight is cancelled when the app goes away, and its answer is ignored', () async {
      store.saved = {1: everyTen};
      runner.gate = Completer<void>();
      await service.start();
      await clock.advance(const Duration(seconds: 30));
      final token = runner.calls.single.token!;
      expect(token.isCancelled, isFalse);
      service.onLifecycle(AppLifecycleState.detached);
      expect(token.isCancelled, isTrue);
      runner.gate!.complete();
      await pumpEventQueue();
      expect(clock.pending, 0, reason: 'a cancelled run schedules nothing');
      expect(service.statusOf(1).state, isNot(MonitorState.passing));
    });

    test('other lifecycle states leave the monitor running (a minimised desktop window still monitors)', () async {
      store.saved = {1: everyTen};
      await service.start();
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        service.onLifecycle(state);
      }
      expect(clock.pending, 1);
      await clock.advance(const Duration(seconds: 30));
      expect(runner.calls, hasLength(1));
    });

    test('dispose cancels every timer and the run in flight, and nothing fires afterwards', () async {
      store.saved = {1: everyTen, 2: everyTen};
      await service.start();
      await clock.advance(const Duration(seconds: 30));
      runner.gate = Completer<void>();
      await clock.advance(const Duration(minutes: 10));
      final inFlight = runner.calls.last.token!;
      service.dispose();
      expect(inFlight.isCancelled, isTrue);
      expect(clock.pending, 0);
      runner.gate!.complete();
      await clock.advance(const Duration(hours: 5));
      expect(runner.calls, hasLength(4));
      // A stale call after dispose is harmless.
      await service.setConfig(1, everyTen);
      expect(clock.pending, 0);
      service = build(); // so tearDown has something to dispose
    });

    test('a deleted collection stops being monitored: its timer is cancelled and the choice forgotten', () async {
      store.saved = {1: everyTen, 2: everyTen};
      await service.start();
      await pumpEventQueue();
      expect(clock.pending, 2);
      collections.emit(const [CollectionEntity(id: 1, name: 'Shop')]);
      await pumpEventQueue();
      expect(clock.pending, 1);
      expect(service.configOf(2), isNull);
      expect(store.saved.keys, [1]);
      await clock.advance(const Duration(hours: 1));
      expect(runner.calls.every((c) => c.id == 1), isTrue);
    });

    test('start twice starts once', () async {
      store.saved = {1: everyTen};
      await Future.wait([service.start(), service.start()]);
      expect(clock.pending, 1);
    });
  });

  group('settings', () {
    test('the interval has to be from 1 to 1440 minutes', () {
      for (final good in ['1', '15', '1440', ' 60 ']) {
        expect(MonitorConfig.intervalError(good), isNull, reason: good);
      }
      for (final bad in ['', '0', '1441', '-5', 'abc', '1.5']) {
        expect(MonitorConfig.intervalError(bad), contains('from 1 to 1440'), reason: bad);
      }
    });

    test('a saved choice survives the round trip through JSON, and a damaged one takes defaults', () {
      const config = MonitorConfig(enabled: true, everyMinutes: 45, environment: 'Staging');
      expect(MonitorConfig.fromJson(config.toJson()), config);
      final odd = MonitorConfig.fromJson({'enabled': 'yes', 'every': 99999, 'env': ''});
      expect((odd.enabled, odd.everyMinutes, odd.environment), (false, MonitorConfig.defaultMinutes, null));
    });
  });
}
