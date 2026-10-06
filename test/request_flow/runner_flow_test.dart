// The collection runner with flow controls: retry, poll until and fetch all pages inside a run, Run if (skipped is
// not failed), and Always run after "stop on failure". The CLI has its own file, and a parity test runs one scenario
// through both.
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_report.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'flow_run_harness.dart';

RequestSettings _runIf(List<RunCondition> conditions, {bool alwaysRun = false}) =>
    RequestSettings(flow: FlowSettings(runIf: RunIfPolicy(enabled: true, conditions: conditions), alwaysRun: alwaysRun));

RequestSettings get _cleanup => const RequestSettings(flow: FlowSettings(alwaysRun: true));

RunCondition _when(RunConditionKind kind, [String name = '', String value = '']) =>
    RunCondition(kind: kind, name: name, value: value);

const _saveUserId = r'[{"source":"jsonPath","path":"$.id","scope":"environment","key":"userId"}]';

/// 12 items, 5 to a page, linked by a Link header.
ServerReply _page(Uri url) {
  final page = int.parse(url.queryParameters['page'] ?? '1');
  final first = (page - 1) * 5 + 1;
  final items = [for (var i = first; i < first + 5 && i <= 12; i++) {'id': i}];
  return reply(items, headers: {
    if (page < 3) 'Link': '<https://api.test/Items?page=${page + 1}>; rel="next"',
  });
}

void main() {
  // Two databases are opened in a few tests; each has its own in-memory connection.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FlowHarness h;

  Future<FlowHarness> harness(FakeApiServer server, {String? environment = 'Dev'}) async {
    h = await FlowHarness.create(server, environment: environment);
    addTearDown(h.dispose);
    return h;
  }

  FakeApiServer ok() => FakeApiServer((url, method, call) => reply({'ok': true}));

  /// 500 for the paths named, 200 for the rest.
  FakeApiServer failing(Set<String> paths) =>
      FakeApiServer((url, method, call) => paths.contains(url.path) ? reply({'no': true}, status: 500) : reply({'ok': true}));

  group('Run if', () {
    test('a request whose condition does not hold is skipped with the reason, nothing is sent, and it is not a failure', () async {
      final server = ok();
      await harness(server);
      await h.add('Login');
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('After');

      final results = await h.runApp();

      expect(results.map(stateOfApp), ['Login:passed', 'Staging only:skipped', 'After:passed']);
      final skipped = results[1];
      expect(skipped.skipped, 'Skipped: the environment is "Dev", but this runs only in "Staging"');
      expect((skipped.isSkipped, skipped.passed), (true, true));
      expect(skipped.response, isNull);
      expect(skipped.error, isNull);
      expect(server.paths, ['/Login', '/After'], reason: 'the skipped request never left');
      final summary = CollectionRunSummary.of(results);
      expect((summary.requests, summary.passed, summary.skipped, summary.failed), (3, 2, 1, 0));
    });

    test('a skipped request does not stop a run on failure, and only a request that was sent counts as "previous"', () async {
      await harness(ok());
      await h.add('A');
      await h.add('Skipped', settings: _runIf([_when(RunConditionKind.environmentIs, 'Nowhere')]));
      await h.add('C');

      final results = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true));

      expect(results.map(stateOfApp), ['A:passed', 'Skipped:skipped', 'C:passed']);
    });

    test('a variable an earlier request saved decides, and a missing one skips with that said', () async {
      final saves = FakeApiServer((url, method, call) => reply(url.path == '/Make-user' ? {'id': 7} : {'ok': true}));
      await harness(saves);
      await h.add('Make user', extractorsJson: _saveUserId);
      await h.add('Use user', settings: _runIf([_when(RunConditionKind.variableNotEmpty, 'userId')]));

      final ran = await h.runApp();

      expect(ran.map(stateOfApp), ['Make user:passed', 'Use user:passed']);

      final empty = FakeApiServer((url, method, call) => reply({'ok': true}));
      await harness(empty);
      await h.add('Make user', extractorsJson: _saveUserId);
      await h.add('Use user', settings: _runIf([_when(RunConditionKind.variableNotEmpty, 'userId')]));

      final skipped = await h.runApp();

      expect(skipped.map(stateOfApp), ['Make user:failed', 'Use user:skipped'], reason: 'the save failed, so nothing was defined');
      expect(skipped.last.skipped, 'Skipped: {{userId}} is not defined');
    });

    test('the previous request that was sent decides "previous passed" and "previous failed"', () async {
      await harness(failing({'/First'}));
      await h.add('First');
      await h.add('On failure', settings: _runIf([_when(RunConditionKind.previousFailed)]));
      await h.add('On pass', settings: _runIf([_when(RunConditionKind.previousPassed)]));
      await h.add('On failure again', settings: _runIf([_when(RunConditionKind.previousFailed)]));
      await h.add('On pass again', settings: _runIf([_when(RunConditionKind.previousPassed)]));

      final results = await h.runApp();

      expect(results.map(stateOfApp), [
        'First:failed',
        'On failure:passed',
        'On pass:passed',
        'On failure again:skipped',
        'On pass again:passed', // the skipped one is stepped over: the one before it passed
      ]);
      expect(results[3].skipped, 'Skipped: the previous request "On pass" passed, but this one runs only when it failed');
    });

    test('the first request of a run has no previous one, and every pass starts over', () async {
      final server = ok();
      await harness(server);
      await h.add('Gate', settings: _runIf([_when(RunConditionKind.previousPassed)]));
      await h.add('Plain');

      final results = await h.runApp(options: const CollectionRunOptions(iterations: 2));

      expect(results.map((r) => '${r.iteration} ${stateOfApp(r)}'), ['1 Gate:skipped', '1 Plain:passed', '2 Gate:skipped', '2 Plain:passed']);
      expect(results.first.skipped, contains('no previous request in this run'));
    });

    test('a data row decides per pass', () async {
      await harness(ok());
      await h.add('EU only', settings: _runIf([_when(RunConditionKind.variableEquals, 'region', 'eu')]));
      await h.add('Always');

      final results = await h.runApp(
        options: const CollectionRunOptions(dataRows: [
          {'region': 'eu'},
          {'region': 'us'},
        ]),
      );

      expect(results.map((r) => '${r.iteration} ${stateOfApp(r)}'), ['1 EU only:passed', '1 Always:passed', '2 EU only:skipped', '2 Always:passed']);
      expect(results[2].skipped, contains('is "us"'));
    });

    test('Send by hand ignores it: the editor sends a request whose condition does not hold', () async {
      final server = ok();
      await harness(server);
      final id = await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      final request = (await h.repos.requestRepository.findById(id))!;

      final outcome = await h.flow.send(request);

      expect(outcome.response!.statusCode, 200);
      expect(server.paths, ['/Staging-only']);
    });

    test('the run summary and the exports tell skipped apart, and leave their old shape alone when nothing was skipped', () async {
      await harness(ok());
      await h.add('Sent');
      await h.add('Left out', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      final results = await h.runApp();
      final iteration = RunIteration(1, const {})..results.addAll(results);
      const exporter = CollectionRunExporter();

      final json = jsonDecode(exporter.toJson([iteration])) as Map<String, dynamic>;
      final rows = ((json['iterations'] as List).single as Map)['results'] as List;
      expect((json['summary'] as Map)['skipped'], 1);
      expect((json['summary'] as Map)['failed'], 0);
      expect((rows.last as Map)['skipped'], contains('Staging'));
      expect((rows.last as Map)['passed'], isTrue);
      expect((rows.first as Map).containsKey('skipped'), isFalse);
      expect(iteration.passedCount, 1);
      expect(iteration.skippedCount, 1);
      expect(iteration.allPassed, isTrue);
      final csv = exporter.toCsv([iteration]);
      expect(csv.split('\n').first, endsWith(',flow'));
      expect(csv, contains('the environment is ""Dev""'), reason: 'the reason, with its quotes escaped for CSV');

      final plain = RunIteration(1, const {})..results.addAll([results.first]);
      expect(jsonDecode(exporter.toJson([plain])).toString(), isNot(contains('skipped')));
      expect(exporter.toCsv([plain]).split('\n').first, endsWith(',error'));
    });
  });

  group('Always run', () {
    test('after a failure that stops the run, only the requests marked always-run are still sent', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Setup');
      await h.add('Step');
      await h.add('Normal');
      await h.add('Cleanup', settings: _cleanup);
      await h.add('Last');

      final results = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true));

      expect(results.map(stateOfApp), ['Setup:passed', 'Step:failed', 'Cleanup:passed']);
      expect(server.paths, ['/Setup', '/Step', '/Cleanup']);
    });

    test('with its own Run if it is the classic cleanup: only when the one before failed', () async {
      await harness(failing({'/Step'}));
      await h.add('Step');
      await h.add('Cleanup', settings: _runIf([_when(RunConditionKind.previousFailed)], alwaysRun: true));

      final after = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true));

      expect(after.map(stateOfApp), ['Step:failed', 'Cleanup:passed']);

      await harness(ok());
      await h.add('Step');
      await h.add('Cleanup', settings: _runIf([_when(RunConditionKind.previousFailed)], alwaysRun: true));

      final fine = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true));

      expect(fine.map(stateOfApp), ['Step:passed', 'Cleanup:skipped']);
      expect(fine.last.skipped, contains('passed, but this one runs only when it failed'));
    });

    test('a cleanup whose Run if does not hold after the failure is reported skipped, not run', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Step');
      await h.add('Staging cleanup', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')], alwaysRun: true));

      final results = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true));

      expect(results.map(stateOfApp), ['Step:failed', 'Staging cleanup:skipped']);
      expect(server.paths, ['/Step']);
    });

    test('without "stop on failure" it changes nothing: everything runs, in order', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Step');
      await h.add('Cleanup', settings: _cleanup);
      await h.add('After');

      final results = await h.runApp();

      expect(results.map(stateOfApp), ['Step:failed', 'Cleanup:passed', 'After:passed']);
    });

    test('stop on failure still ends the whole run: no further pass, always-run or not', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Step');
      await h.add('Cleanup', settings: _cleanup);

      final results = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true, iterations: 3));

      expect(results.map((r) => '${r.iteration} ${stateOfApp(r)}'), ['1 Step:failed', '1 Cleanup:passed']);
    });

    test('pressing Stop ends the run at once: the cleanups do not run', () async {
      final server = failing({'/Step'});
      await harness(server);
      final token = ApiCancelToken();
      server.onRequest = (url) {
        if (url.path == '/Step') token.cancel();
      };
      await h.add('Step');
      await h.add('Cleanup', settings: _cleanup);

      final results = await h.runApp(options: const CollectionRunOptions(stopOnFailure: true), cancelToken: token);

      expect(results.map(stateOfApp), ['Step:failed']);
      expect(server.paths, ['/Step']);
    });

    test('the runner dialog\'s "stopped at the first failure" still says so when a cleanup ran after it', () async {
      await harness(failing({'/Step'}));
      await h.add('Step');
      await h.add('Normal');
      await h.add('Cleanup', settings: _cleanup);
      final vm = CollectionRunnerViewModel(h.runner);
      addTearDown(vm.dispose);
      await vm.load(h.collectionId);
      vm.setStopOnFailure(true);

      vm.start(h.collectionId);
      while (vm.isRunning) {
        await pumpEventQueue();
      }

      expect(vm.results.map(stateOfApp), ['Step:failed', 'Cleanup:passed']);
      expect(vm.stoppedOnFailure, isTrue);
      expect(vm.summary.failed, 1);
    });

    test('a run that fails on its very last request did not stop early', () async {
      await harness(failing({'/Last'}));
      await h.add('First');
      await h.add('Last');
      final vm = CollectionRunnerViewModel(h.runner);
      addTearDown(vm.dispose);
      await vm.load(h.collectionId);
      vm.setStopOnFailure(true);

      vm.start(h.collectionId);
      while (vm.isRunning) {
        await pumpEventQueue();
      }

      expect(vm.stoppedOnFailure, isFalse);
    });
  });

  group('the production lock', () {
    test('a request that will certainly be skipped here is not one the run asks about', () async {
      await harness(ok(), environment: 'Production');
      await h.add('Read');
      await h.add('Staging cleanup', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('Prod purge', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Production')]));
      await h.add('Gated write', method: HttpMethod.post, settings: _runIf([_when(RunConditionKind.variableEquals, 'mode', 'live')]));

      final asked = await h.runner.fullRequestsIn(h.collectionId);

      expect(asked.map((r) => r.name), ['Read', 'Prod purge', 'Gated write'], reason: 'the variable can still change, the environment cannot');
      final guard = ProductionGuard(h.repos.environmentRepository, SafetyPrefs());
      final warning = await guard.checkRunRequests(asked, 'Jobs');
      expect(warning!.description, 'Running "Jobs" sends 2 data-changing requests, 1 of them deletes data');
    });

    test('nothing is sent for the skipped one, in production or anywhere else', () async {
      final server = ok();
      await harness(server, environment: 'Production');
      await h.add('Staging cleanup', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('Read');

      final results = await h.runApp();

      expect(results.map(stateOfApp), ['Staging cleanup:skipped', 'Read:passed']);
      expect(server.requests, ['GET https://api.test/Read']);
    });

    test('a runner built without flow controls asks about every request and has no Run if, as before', () async {
      final server = ok();
      await harness(server, environment: 'Production');
      await h.add('Staging cleanup', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      final scripts = RunRequestScriptsUseCase(h.repos.scriptsRepository, h.resolver, h.repos.environmentRepository, h.repos.globalVariableRepository);
      final plain = CollectionRunnerService.withFolders(h.repos.requestRepository, h.send, scripts, h.repos.collectionRepository, (_) async {});

      expect((await plain.fullRequestsIn(h.collectionId)).map((r) => r.name), ['Staging cleanup']);
      final results = await plain.run(h.collectionId).toList();

      expect(results.map(stateOfApp), ['Staging cleanup:passed']);
      expect(server.paths, ['/Staging-cleanup']);
    });
  });

  group('retry in a run', () {
    const retry = RetryPolicy(enabled: true, maxRetries: 2, backoff: BackoffKind.fixed, delayMs: 500, jitter: false);

    test('a request that fails once and then works passes, and the result says it took two attempts', () async {
      final server = FakeApiServer((url, method, call) => call == 1 ? reply({}, status: 503) : reply({'ok': true}));
      await harness(server);
      await h.add('Flaky', settings: const RequestSettings(flow: FlowSettings(retry: retry)));

      final results = await h.runApp();

      final result = results.single;
      expect(stateOfApp(result), 'Flaky:passed');
      expect(result.flow!.retries, 1);
      expect(result.flowText, '2 attempts: attempt 2/3 after 500 ms');
      expect(result.flow!.attempts.map((a) => a.label), ['request', 'attempt 2/3 after 500 ms']);
      expect(h.clock.waits, [500]);
      expect(h.consoleNotes, ['attempt 2/3 after 500 ms']);
    });

    test('when every attempt fails the last answer stands, with a note that it gave up', () async {
      await harness(failing({'/Flaky'}));
      await h.add('Flaky', settings: const RequestSettings(flow: FlowSettings(retry: retry)));

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Flaky:failed');
      expect(result.response!.statusCode, 500);
      expect(result.flowText, contains('gave up after 3 attempts'));
    });

    test('a server that cannot be reached is an error of the request, with every attempt on record', () async {
      final down = FakeApiServer((url, method, call) => unreachable());
      await harness(down);
      await h.add('Down', settings: const RequestSettings(flow: FlowSettings(retry: retry)));

      final result = (await h.runApp()).single;

      expect(result.response, isNull);
      expect(result.error, "Couldn't reach api.test");
      expect(result.passed, isFalse);
      expect(result.flow!.attempts, hasLength(3));
      expect(down.requests, hasLength(3));
    });

    test('a POST is sent once unless the request says repeating is safe', () async {
      final server = FakeApiServer((url, method, call) => reply({}, status: 503));
      await harness(server);
      await h.add('Create', method: HttpMethod.post, settings: const RequestSettings(flow: FlowSettings(retry: retry)));
      await h.add('Create safely', method: HttpMethod.post, settings: const RequestSettings(flow: FlowSettings(retry: retry, repeatUnsafe: true)));

      final results = await h.runApp();

      expect(server.paths, ['/Create', '/Create-safely', '/Create-safely', '/Create-safely']);
      expect(results.first.flowText, contains('POST'));
    });
  });

  group('poll until in a run', () {
    PollPolicy poll({int maxAttempts = 10}) => PollPolicy(
          enabled: true,
          until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
          intervalMs: 1000,
          maxAttempts: maxAttempts,
        );

    test('asks again until the job is done, and the tests and variable saves see the final answer', () async {
      final server = FakeApiServer((url, method, call) => reply({'status': call < 3 ? 'running' : 'done'}));
      await harness(server);
      await h.add(
        'Job',
        settings: RequestSettings(flow: FlowSettings(poll: poll())),
        assertionsJson: '[{"type":"jsonPathEquals","path":"status","expected":"done"}]',
        extractorsJson: r'[{"source":"jsonPath","path":"$.status","scope":"environment","key":"jobStatus"}]',
      );

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Job:passed');
      expect(result.flow!.polls, 3);
      expect(result.flowText, 'polled 3 times');
      expect(h.clock.waits, [1000, 1000]);
      expect(result.scripts!.assertions.single.passed, isTrue);
      expect(result.scripts!.extracted.single.value, 'done');
      expect(server.paths, ['/Job', '/Job', '/Job']);
    });

    test('a job that never finishes fails the request with the last response and what it waited for', () async {
      await harness(FakeApiServer((url, method, call) => reply({'status': 'running'})));
      await h.add('Job', settings: RequestSettings(flow: FlowSettings(poll: poll(maxAttempts: 3))));

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Job:failed');
      expect(result.response!.statusCode, 200, reason: 'the last response is there');
      expect(result.error, isNull);
      expect(result.failures.first, contains('Polling gave up after 3 requests'));
      expect(result.failures.first, contains('status equals done (got running)'));
    });
  });

  group('fetch all pages in a run', () {
    const linked = PaginationSettings(enabled: true, kind: PaginationKind.linkHeader, itemsPath: '');

    test('the run sees ONE merged response: tests, extractors and the badge work on all the items', () async {
      final server = FakeApiServer((url, method, call) => _page(url));
      await harness(server);
      await h.add(
        'Items',
        settings: const RequestSettings(pagination: linked),
        assertionsJson: '[{"type":"jsonPathExists","path":"[11].id","expected":""}]',
        extractorsJson: r'[{"source":"jsonPath","path":"[11].id","scope":"environment","key":"lastId"}]',
      );

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Items:passed');
      expect(result.flow!.pages!.badge, '3 pages, 12 items');
      expect(result.flowText, '3 pages, 12 items');
      expect(result.scripts!.assertions.single.passed, isTrue, reason: 'item 12 exists only in the merged response');
      expect(result.scripts!.extracted.single.value, '12');
      expect(server.requests, [
        'GET https://api.test/Items',
        'GET https://api.test/Items?page=2',
        'GET https://api.test/Items?page=3',
      ]);
    });

    test('a page that fails fails the request, with the pages before it kept', () async {
      final server = FakeApiServer((url, method, call) => url.queryParameters['page'] == '3' ? reply({}, status: 500) : _page(url));
      await harness(server);
      await h.add('Items', settings: const RequestSettings(pagination: linked));

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Items:failed');
      expect(result.error, isNull);
      expect(result.failures.first, contains('Page 3 failed: HTTP 500'));
      expect(result.flow!.pages!.pages, 2);
    });

    test('the page limit is a note, not a failure', () async {
      await harness(FakeApiServer((url, method, call) => _page(url)));
      await h.add('Items', settings: RequestSettings(pagination: linked.copyWith(maxPages: 2)));

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Items:passed');
      expect(result.flowText, contains('page limit'));
    });

    test('retry, poll and pages together: each page is retried, and the walk is one flow', () async {
      final server = FakeApiServer((url, method, call) {
        if (url.queryParameters['page'] == '2' && call == 2) return reply({}, status: 503);
        return _page(url);
      });
      await harness(server);
      await h.add(
        'Items',
        settings: const RequestSettings(
          flow: FlowSettings(retry: RetryPolicy(enabled: true, maxRetries: 2, backoff: BackoffKind.fixed, delayMs: 200, jitter: false)),
          pagination: linked,
        ),
      );

      final result = (await h.runApp()).single;

      expect(stateOfApp(result), 'Items:passed');
      expect(result.flow!.pages!.badge, '3 pages, 12 items');
      expect(result.flow!.retries, 1);
      expect(result.flowText, '2 attempts: page 2, attempt 2/3 after 200 ms · 3 pages, 12 items');
    });
  });

  group('a plain collection is unchanged', () {
    test('requests without any flow settings run exactly as before: in order, once each, no flow report', () async {
      final server = ok();
      await harness(server);
      await h.add('A');
      await h.add('B');

      final results = await h.runApp();

      expect(results.map(stateOfApp), ['A:passed', 'B:passed']);
      expect(results.every((r) => r.flow == null && r.flowText == null), isTrue);
      expect(server.paths, ['/A', '/B']);
      expect(h.consoleNotes, isEmpty);
    });
  });
}
