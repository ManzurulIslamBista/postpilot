// What changed since the last run, and which requests are flaky or slower than usual. The medians and counts are worked
// out by hand next to each case.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/services/request_history_stats.dart';
import 'package:postpilot/features/run_triage/domain/services/run_comparison.dart';
import 'package:postpilot/features/run_triage/domain/services/triage_analysis.dart';
import 'run_fixtures.dart';

void main() {
  group('comparison with the earlier run', () {
    test('new failures, fixed and still failing, by request and pass', () {
      final before = [
        entry('Login'), // passed, still passes
        failedWith('Orders', 500), // failed, still fails
        failedWith('Invoices', 401), // failed, fixed
        entry('Profile'), // passed, now fails: new
        entry('Gone'), // passed, not part of this run
      ];
      final now = [
        entry('Login'),
        failedWith('Orders', 500),
        entry('Invoices'),
        failedWith('Profile', 404),
        failedWith('Brand new', 500), // not in the earlier run at all: new
      ];
      final c = RunComparison.compare(previous: before, current: now);
      expect(c.newFailures.map((r) => r.name), ['Profile', 'Brand new']);
      expect(c.fixed.map((r) => r.name), ['Invoices']);
      expect(c.stillFailing.map((r) => r.name), ['Orders']);
      expect(c.notRunNow, 0);
      expect(c.summary, '2 new failures, 1 fixed, 1 still failing');
      expect(c.isUnchanged, isFalse);
    });

    test('the same request in another pass (data row) is another result', () {
      final before = [entry('Login', iteration: 1), failedWith('Login', 401, iteration: 2)];
      final now = [failedWith('Login', 401, iteration: 1), entry('Login', iteration: 2)];
      final c = RunComparison.compare(previous: before, current: now);
      expect(c.newFailures.map((r) => r.iteration), [1]);
      expect(c.fixed.map((r) => r.iteration), [2]);
    });

    test('a request in a folder is not the request of the same name elsewhere', () {
      final before = [entry('List', folder: 'Orders'), failedWith('List', 500, folder: 'Invoices')];
      final now = [failedWith('List', 500, folder: 'Orders'), entry('List', folder: 'Invoices')];
      final c = RunComparison.compare(previous: before, current: now);
      expect(c.newFailures.single.folder, 'Orders');
      expect(c.fixed.single.folder, 'Invoices');
    });

    test('a request that failed before and was skipped or left out now is counted as not run', () {
      final before = [failedWith('A', 500), failedWith('B', 500), failedWith('C', 500)];
      final now = [entry('A', skipped: 'Run if', status: null), entry('B', status: 200)];
      final c = RunComparison.compare(previous: before, current: now);
      // A was skipped, B passes (fixed), C is absent.
      expect(c.fixed.map((r) => r.name), ['B']);
      expect(c.notRunNow, 2);
      expect(c.newFailures, isEmpty);
    });

    test('a skipped request is neither a new failure nor a fix', () {
      final c = RunComparison.compare(
        previous: [entry('A', skipped: 'Run if', status: null)],
        current: [entry('A', skipped: 'Run if', status: null)],
      );
      expect(c.newFailures, isEmpty);
      expect(c.fixed, isEmpty);
      expect(c.stillFailing, isEmpty);
      expect(c.summary, 'Same as the earlier run');
      expect(c.isUnchanged, isTrue);
    });

    test('identical runs are unchanged, with their failures still failing', () {
      final results = [entry('A'), failedWith('B', 500)];
      final c = RunComparison.compare(previous: results, current: results);
      expect(c.stillFailing, hasLength(1));
      expect(c.isUnchanged, isTrue);
      expect(c.summary, '1 still failing');
    });
  });

  group('flaky requests', () {
    // Each run is one request's outcome; newest first.
    Map<String, RequestStats> stats(List<List<bool>> perRun) => RequestHistoryStats.analyse([
          for (final outcomes in perRun) [for (final ok in outcomes) ok ? entry('A') : failedWith('A', 500)],
        ]);

    test('passed in some of the last runs and failed in others', () {
      final s = stats([
        [true],
        [false],
        [true],
        [true],
      ]).values.single;
      expect((s.runs, s.failedRuns, s.passedRuns), (4, 1, 3));
      expect(s.isFlaky, isTrue);
      expect(s.flakyText, 'passed 3 times and failed 1 of the last 4 runs');
    });

    test('always passing or always failing is not flaky', () {
      expect(stats([[true], [true], [true]]).values.single.isFlaky, isFalse);
      expect(stats([[false], [false], [false]]).values.single.isFlaky, isFalse);
    });

    test('only the last ten runs count', () {
      // Eleven runs, newest first: ten passes and, oldest of all, one failure that is outside the window.
      final runs = [for (var i = 0; i < 10; i++) [true], [false]];
      final s = stats(runs).values.single;
      expect(s.runs, 10);
      expect(s.isFlaky, isFalse);
      // With a smaller window than the history the same applies.
      final narrow = RequestHistoryStats.analyse([
        [entry('A')],
        [entry('A')],
        [failedWith('A', 500)],
      ], lastRuns: 2).values.single;
      expect(narrow.isFlaky, isFalse);
    });

    test('a pass over several data rows is one outcome: failed if any row failed', () {
      final run1 = [entry('A', iteration: 1), failedWith('A', 500, iteration: 2)];
      final run2 = [entry('A', iteration: 1), entry('A', iteration: 2)];
      final run3 = [failedWith('A', 500, iteration: 1), entry('A', iteration: 2)];
      final s = RequestHistoryStats.analyse([run1, run2, run3]).values.single;
      expect((s.runs, s.failedRuns, s.isFlaky), (3, 2, true));
    });

    test('a run in which the request was skipped says nothing about it', () {
      final s = RequestHistoryStats.analyse([
        [entry('A')],
        [entry('A', skipped: 'Run if', status: null)],
        [failedWith('A', 500)],
        [entry('A')],
      ]).values.single;
      expect((s.runs, s.failedRuns, s.isFlaky), (3, 1, true));
    });

    test('one change is a regression or a fix, not flakiness: it needs to go back and forth', () {
      // Newest first. Passed for a long time and has just started failing:
      expect(stats([[false], [true], [true], [true], [true]]).values.single.isFlaky, isFalse);
      // Failed for a while and has just been fixed:
      expect(stats([[true], [false], [false], [false]]).values.single.isFlaky, isFalse);
      // Passed, failed, passed: it changed twice.
      expect(stats([[true], [false], [true]]).values.single.isFlaky, isTrue);
      // Failed, passed, failed: twice as well.
      expect(stats([[false], [true], [false]]).values.single.isFlaky, isTrue);
      // The counts still say what happened.
      final s = stats([[false], [true], [true], [true], [true]]).values.single;
      expect((s.runs, s.failedRuns, s.passedRuns), (5, 1, 4));
    });
  });

  group('slower than usual', () {
    RequestStats slow(int latest, List<int?> earlierNewestFirst) => RequestHistoryStats.analyse([
          [entry('A', ms: latest)],
          for (final ms in earlierNewestFirst) [entry('A', ms: ms)],
        ]).values.single;

    test('more than twice the median of the earlier runs, and at least 100 ms slower', () {
      // Earlier times 100, 120, 140 -> median 120; 300 > 240 and 300 - 120 >= 100.
      final s = slow(300, [100, 120, 140]);
      expect(s.medianMs, 120);
      expect(s.isSlower, isTrue);
      expect(s.slowText, 'took 300 ms, usually about 120 ms');
    });

    test('exactly twice the median is not slower; just over it is', () {
      expect(slow(400, [200, 200, 200]).isSlower, isFalse);
      expect(slow(401, [200, 200, 200]).isSlower, isTrue);
    });

    test('an even number of earlier runs uses the mean of the two middle ones', () {
      // 100, 200, 300, 400 -> median 250: 500 is exactly twice, 501 is over.
      expect(slow(500, [100, 200, 300, 400]).medianMs, 250);
      expect(slow(500, [100, 200, 300, 400]).isSlower, isFalse);
      expect(slow(501, [100, 200, 300, 400]).isSlower, isTrue);
    });

    test('a fast request that doubled is not reported: 20 ms to 45 ms is noise', () {
      final s = slow(45, [20, 20, 20]);
      expect(s.medianMs, 20);
      expect(s.isSlower, isFalse);
    });

    test('needs three earlier runs with a time', () {
      expect(slow(900, [100, 100]).isSlower, isFalse);
      expect(slow(900, [100, 100]).medianMs, isNull);
      // A run without an answer time (a network error) is not a sample.
      expect(slow(900, [100, null, 100, 100]).isSlower, isTrue);
      expect(slow(900, [100, null, null, 100]).isSlower, isFalse);
    });

    test('the median is over the last ten runs, the one looked at not counted', () {
      // The latest run is 1000; the ten before it are 100 (the older ones, 5000, fall outside the window).
      final s = RequestHistoryStats.analyse([
        [entry('A', ms: 1000)],
        for (var i = 0; i < 9; i++) [entry('A', ms: 100)],
        [entry('A', ms: 5000)],
        [entry('A', ms: 5000)],
      ]).values.single;
      expect(s.medianMs, 100);
      expect(s.isSlower, isTrue);
    });
  });

  group('the analysis of one run against its history', () {
    test('compares with the previous run of the same environment only', () {
      final current = run([failedWith('A', 500), entry('B')], environment: 'Staging', at: DateTime.utc(2026, 10, 6, 12));
      final prod = run([entry('A'), entry('B')], environment: 'Production', at: DateTime.utc(2026, 10, 6, 11));
      final staging = run([entry('A'), entry('B')], environment: 'Staging', at: DateTime.utc(2026, 10, 6, 10));
      final a = TriageAnalysis.of(current, [prod, staging]);
      expect(a.previous, same(staging));
      expect(a.comparison!.newFailures.single.name, 'A');
      // Only Staging runs feed the flaky and slow statistics.
      expect(a.statsOf(current.results.first)!.runs, 2);
    });

    test('no earlier run in this environment means nothing to compare with', () {
      final current = run([failedWith('A', 500)], environment: 'Staging');
      final a = TriageAnalysis.of(current, [run([entry('A')], environment: 'Production')]);
      expect(a.previous, isNull);
      expect(a.comparison, isNull);
      expect(a.report.failedResults, 1);
    });

    test('lists the flaky and the slower requests of this run, and the ids to re-run', () {
      final current = run([failedWith('A', 500, requestId: 7), entry('B', ms: 900), entry('C', requestId: 9)]);
      final history = [
        run([entry('A'), entry('B', ms: 100), entry('C')]),
        // A failed here, so A went fail, pass, fail, pass over the last four runs: it changed back and forth.
        run([failedWith('A', 500, requestId: 7), entry('B', ms: 110), entry('C')]),
        run([entry('A'), entry('B', ms: 120), entry('C')]),
      ];
      final a = TriageAnalysis.of(current, history);
      expect(a.flaky.map((s) => s.requestKey.split('\u0001').last), ['A']);
      expect(a.slower.map((s) => s.requestKey.split('\u0001').last), ['B']);
      expect(a.isFlaky(current.results[0]), isTrue);
      expect(a.isSlower(current.results[1]), isTrue);
      expect(a.failedRequestIds, [7]);
    });
  });
}
