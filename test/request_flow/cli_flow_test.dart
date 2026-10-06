// Flow controls on the command line and over MCP, and one scenario run through both the app's runner and the CLI's to
// show they do the same.
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/mcp_server.dart';
import 'package:postpilot/features/cli/reporters.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'flow_run_harness.dart';

RequestSettings _runIf(List<RunCondition> conditions, {bool alwaysRun = false}) =>
    RequestSettings(flow: FlowSettings(runIf: RunIfPolicy(enabled: true, conditions: conditions), alwaysRun: alwaysRun));

RunCondition _when(RunConditionKind kind, [String name = '', String value = '']) =>
    RunCondition(kind: kind, name: name, value: value);

const _cleanup = RequestSettings(flow: FlowSettings(alwaysRun: true));
const _retry = RetryPolicy(enabled: true, maxRetries: 2, backoff: BackoffKind.fixed, delayMs: 500, jitter: false);
const _linked = PaginationSettings(enabled: true, kind: PaginationKind.linkHeader, itemsPath: '');

ServerReply _page(Uri url) {
  final page = int.parse(url.queryParameters['page'] ?? '1');
  final first = (page - 1) * 5 + 1;
  return reply(
    [for (var i = first; i < first + 5 && i <= 12; i++) {'id': i}],
    headers: {if (page < 3) 'Link': '<https://api.test/Items?page=${page + 1}>; rel="next"'},
  );
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

  FakeApiServer failing(Set<String> paths) =>
      FakeApiServer((url, method, call) => paths.contains(url.path) ? reply({'no': true}, status: 500) : reply({'ok': true}));

  Future<RunSummary> run([RunOptions options = const RunOptions(environment: 'Dev')]) async => (await h.cliRunner()).run(options);

  group('retry, poll and pages', () {
    test('a retried request passes and the outcome says how many attempts it took', () async {
      final server = FakeApiServer((url, method, call) => call == 1 ? reply({}, status: 503) : reply({'ok': true}));
      await harness(server);
      await h.add('Flaky', settings: const RequestSettings(flow: FlowSettings(retry: _retry)));

      final summary = await run();

      final outcome = summary.outcomes.single;
      expect(outcome.passed, isTrue);
      expect(outcome.status, 200);
      expect(outcome.flow!.retries, 1);
      expect(outcome.flow!.attempts.map((a) => a.label), ['request', 'attempt 2/3 after 500 ms']);
      expect(h.clock.waits, [500]);
      expect(summary.ok, isTrue);
      expect(RunReporters.line(outcome), contains('(2 attempts: attempt 2/3 after 500 ms)'));
    });

    test('every attempt failing on the network is an error of the request, with the tries on record', () async {
      await harness(FakeApiServer((url, method, call) => unreachable()));
      await h.add('Down', settings: const RequestSettings(flow: FlowSettings(retry: _retry)));

      final outcome = (await run()).outcomes.single;

      expect(outcome.passed, isFalse);
      expect(outcome.status, isNull);
      expect(outcome.networkFailure, isTrue);
      expect(outcome.error, 'connect failed');
      expect(outcome.flow!.attempts, hasLength(3));
    });

    test('a request that was refused is not retried: the lock says no once', () async {
      final server = ok();
      await harness(server, environment: 'Production');
      await h.add('Delete all', method: HttpMethod.delete, settings: const RequestSettings(flow: FlowSettings(retry: _retry, repeatUnsafe: true)));

      final outcome = (await run(const RunOptions(environment: 'Production'))).outcomes.single;

      expect(outcome.blocked, contains('production lock'));
      expect(server.requests, isEmpty);
      expect(outcome.flow, isNull);
    });

    test('POST, PATCH and DELETE are sent once without the tick, and repeated with it', () async {
      final server = FakeApiServer((url, method, call) => reply({}, status: 503));
      await harness(server);
      await h.add('Create', method: HttpMethod.post, settings: const RequestSettings(flow: FlowSettings(retry: _retry)));
      await h.add('Create safely', method: HttpMethod.post, settings: const RequestSettings(flow: FlowSettings(retry: _retry, repeatUnsafe: true)));

      final summary = await run();

      expect(server.paths, ['/Create', '/Create-safely', '/Create-safely', '/Create-safely']);
      expect(summary.outcomes.first.flow!.notes.single, contains('POST'));
    });

    test('a job is polled until it is done, and the tests and variable saves see the final answer', () async {
      final server = FakeApiServer((url, method, call) => reply({'status': call < 3 ? 'running' : 'done'}));
      await harness(server);
      await h.add(
        'Job',
        settings: RequestSettings(
          flow: FlowSettings(
            poll: PollPolicy(
              enabled: true,
              until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
              intervalMs: 1000,
            ),
          ),
        ),
        assertionsJson: '[{"type":"jsonPathEquals","path":"status","expected":"done"}]',
        extractorsJson: r'[{"source":"jsonPath","path":"$.status","scope":"environment","key":"jobStatus"}]',
      );

      final outcome = (await run()).outcomes.single;

      expect(outcome.passed, isTrue);
      expect(outcome.flow!.polls, 3);
      expect(h.clock.waits, [1000, 1000]);
      expect(outcome.scripts.assertions.single.passed, isTrue);
      expect(outcome.scripts.extracted.single.value, 'done');
      expect(RunReporters.line(outcome), contains('(polled 3 times)'));
    });

    test('a job that never finishes fails with the last response and what it waited for', () async {
      await harness(FakeApiServer((url, method, call) => reply({'status': 'running'})));
      await h.add(
        'Job',
        settings: RequestSettings(
          flow: FlowSettings(
            poll: PollPolicy(
              enabled: true,
              until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
              maxAttempts: 3,
            ),
          ),
        ),
      );

      final summary = await run();

      final outcome = summary.outcomes.single;
      expect(outcome.passed, isFalse);
      expect(outcome.status, 200);
      expect(outcome.failures.first, contains('Polling gave up after 3 requests'));
      expect(summary.ok, isFalse);
      final json = jsonDecode(RunReporters.json(summary)) as Map<String, dynamic>;
      final request = (json['requests'] as List).single as Map;
      expect((request['flow'] as Map)['failure'], contains('Polling gave up'));
      expect(((request['flow'] as Map)['attempts'] as List), hasLength(3));
    });

    test('all pages come back as one response, and the tests see every item', () async {
      final server = FakeApiServer((url, method, call) => _page(url));
      await harness(server);
      await h.add(
        'Items',
        settings: const RequestSettings(pagination: _linked),
        assertionsJson: '[{"type":"jsonPathExists","path":"[11].id","expected":""}]',
        extractorsJson: r'[{"source":"jsonPath","path":"[11].id","scope":"environment","key":"lastId"}]',
      );

      final outcome = (await run()).outcomes.single;

      expect(outcome.passed, isTrue);
      expect(outcome.flow!.pages!.badge, '3 pages, 12 items');
      expect((jsonDecode(outcome.responseBody!) as List), hasLength(12));
      expect(outcome.sizeBytes, utf8.encode(outcome.responseBody!).length);
      expect(outcome.scripts.assertions.single.passed, isTrue);
      expect(outcome.scripts.extracted.single.value, '12');
      expect(server.requests, hasLength(3));
      expect(RunReporters.line(outcome), contains('(3 pages, 12 items)'));
    });

    test('a page that fails fails the request, with the pages before it kept', () async {
      final server = FakeApiServer((url, method, call) => url.queryParameters['page'] == '3' ? reply({}, status: 500) : _page(url));
      await harness(server);
      await h.add('Items', settings: const RequestSettings(pagination: _linked));

      final outcome = (await run()).outcomes.single;

      expect(outcome.passed, isFalse);
      expect(outcome.failures.first, contains('Page 3 failed: HTTP 500'));
    });

    test('the page limit is a note under the line, not a failure', () async {
      await harness(FakeApiServer((url, method, call) => _page(url)));
      await h.add('Items', settings: RequestSettings(pagination: _linked.copyWith(maxPages: 2)));

      final outcome = (await run()).outcomes.single;

      expect(outcome.passed, isTrue);
      expect(RunReporters.line(outcome), contains('page limit'));
    });

    test('a request that needs no flow is unchanged: no report, one request', () async {
      final server = ok();
      await harness(server);
      await h.add('Plain');

      final outcome = (await run()).outcomes.single;

      expect(outcome.flow, isNull);
      expect(server.requests, hasLength(1));
      expect(jsonDecode(RunReporters.json(RunSummary([outcome], Duration.zero))).toString(), isNot(contains('flow')));
    });
  });

  group('Run if', () {
    test('by environment: skipped with the reason, not sent, not a failure, and the run is still ok', () async {
      final server = ok();
      await harness(server);
      await h.add('Login');
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));

      final summary = await run();

      expect(summary.outcomes.map(stateOfCli), ['Login:passed', 'Staging only:skipped']);
      final skipped = summary.outcomes.last;
      expect(skipped.skipped, 'Skipped: the environment is "Dev", but this runs only in "Staging"');
      expect((skipped.skippedByRule, skipped.passed), (true, true));
      expect(server.paths, ['/Login']);
      expect((summary.total, summary.passed, summary.skipped, summary.failed, summary.skippedByRule), (2, 1, 1, 0, 1));
      expect(summary.ok, isTrue);
      expect(RunReporters.line(skipped), contains('Skipped: the environment is "Dev"'));
    });

    test('--fail-on-skip does not count a request that was left out on purpose', () async {
      await harness(ok());
      await h.add('Login');
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));

      final summary = await run(const RunOptions(environment: 'Dev', failOnSkip: true));

      expect(summary.ok, isTrue);
      expect(RunReporters.console(summary), isNot(contains('this fails the run')));
    });

    test('a run in which everything was left out verified nothing, so it is not ok', () async {
      await harness(ok());
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));

      final summary = await run();

      expect(summary.allSkipped, isTrue);
      expect(summary.ok, isFalse);
    });

    test('by variable: --var decides, and a variable a request saved decides', () async {
      final server = FakeApiServer((url, method, call) => reply(url.path == '/Make-user' ? {'id': 7} : {'ok': true}));
      await harness(server);
      await h.add('Make user', extractorsJson: r'[{"source":"jsonPath","path":"$.id","scope":"environment","key":"userId"}]');
      await h.add('Use user', settings: _runIf([_when(RunConditionKind.variableNotEmpty, 'userId')]));
      await h.add('EU only', settings: _runIf([_when(RunConditionKind.variableEquals, 'region', 'eu')]));

      final eu = await run(const RunOptions(environment: 'Dev', variables: {'region': 'eu'}));
      final us = await run(const RunOptions(environment: 'Dev', variables: {'region': 'us'}));

      expect(eu.outcomes.map(stateOfCli), ['Make user:passed', 'Use user:passed', 'EU only:passed']);
      expect(us.outcomes.map(stateOfCli), ['Make user:passed', 'Use user:passed', 'EU only:skipped']);
      expect(us.outcomes.last.skipped, 'Skipped: {{region}} is "us", but this runs only when it equals "eu"');
    });

    test('by the previous request: failed, passed, and a skipped one is stepped over', () async {
      await harness(failing({'/First'}));
      await h.add('First');
      await h.add('On failure', settings: _runIf([_when(RunConditionKind.previousFailed)]));
      await h.add('On pass', settings: _runIf([_when(RunConditionKind.previousPassed)]));
      await h.add('On failure again', settings: _runIf([_when(RunConditionKind.previousFailed)]));
      await h.add('On pass again', settings: _runIf([_when(RunConditionKind.previousPassed)]));

      final summary = await run();

      expect(summary.outcomes.map(stateOfCli), [
        'First:failed',
        'On failure:passed',
        'On pass:passed',
        'On failure again:skipped',
        'On pass again:passed',
      ]);
    });

    test('the first request has no previous one', () async {
      await harness(ok());
      await h.add('Gate', settings: _runIf([_when(RunConditionKind.previousPassed)]));
      await h.add('Plain');

      final summary = await run();

      expect(summary.outcomes.first.skipped, contains('no previous request in this run'));
    });

    test('it does not stop --bail, and the production lock is not asked about what is left out', () async {
      final server = ok();
      await harness(server, environment: 'Production');
      await h.add('Staging cleanup', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('Read');
      final runner = await h.cliRunner();
      const options = RunOptions(environment: 'Production', bail: true);

      expect(runner.productionBlocks(options), isEmpty, reason: 'the DELETE will certainly be skipped in Production');
      final summary = await runner.run(options);

      expect(summary.outcomes.map(stateOfCli), ['Staging cleanup:skipped', 'Read:passed']);
      expect(summary.outcomes.first.blocked, isNull);
      expect(server.requests, ['GET https://api.test/Read']);
    });

    test('a request the lock would refuse is still listed when its Run if may hold', () async {
      await harness(ok(), environment: 'Production');
      await h.add('Prod purge', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Production')]));
      await h.add('Gated write', method: HttpMethod.post, settings: _runIf([_when(RunConditionKind.variableEquals, 'mode', 'live')]));
      await h.add('Staging only', method: HttpMethod.delete, settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));

      final blocks = (await h.cliRunner()).productionBlocks(const RunOptions(environment: 'Production'));

      expect(blocks.map((b) => b.name), ['Prod purge', 'Gated write']);
    });
  });

  group('Always run', () {
    test('after --bail has ended the run, the always-run requests are still sent, the rest are not reported', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Setup');
      await h.add('Step');
      await h.add('Normal');
      await h.add('Cleanup', settings: _cleanup);
      await h.add('Last');

      final summary = await run(const RunOptions(environment: 'Dev', bail: true));

      expect(summary.outcomes.map(stateOfCli), ['Setup:passed', 'Step:failed', 'Cleanup:passed']);
      expect(server.paths, ['/Setup', '/Step', '/Cleanup']);
    });

    test('a cleanup with "previous failed" runs after a failure, and is skipped when nothing failed', () async {
      await harness(failing({'/Step'}));
      await h.add('Step');
      await h.add('Cleanup', settings: _runIf([_when(RunConditionKind.previousFailed)], alwaysRun: true));
      expect((await run(const RunOptions(environment: 'Dev', bail: true))).outcomes.map(stateOfCli), ['Step:failed', 'Cleanup:passed']);

      await harness(ok());
      await h.add('Step');
      await h.add('Cleanup', settings: _runIf([_when(RunConditionKind.previousFailed)], alwaysRun: true));
      expect((await run(const RunOptions(environment: 'Dev', bail: true))).outcomes.map(stateOfCli), ['Step:passed', 'Cleanup:skipped']);
    });

    test('without --bail it changes nothing', () async {
      await harness(failing({'/Step'}));
      await h.add('Step');
      await h.add('Cleanup', settings: _cleanup);
      await h.add('After');

      final summary = await run();

      expect(summary.outcomes.map(stateOfCli), ['Step:failed', 'Cleanup:passed', 'After:passed']);
    });
  });

  group('MCP', () {
    Future<Map<String, dynamic>> call(McpServer server, String tool, Map<String, Object?> arguments) async {
      final reply = await server.handleLine(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': tool, 'arguments': arguments},
      }));
      final result = (jsonDecode(reply!) as Map)['result'] as Map;
      final text = ((result['content'] as List).single as Map)['text'] as String;
      return {'isError': result['isError'], 'text': text, if (!(result['isError'] as bool)) 'json': jsonDecode(text)};
    }

    test('run_request sends a request with its flow settings and reports them; its Run if is not checked', () async {
      final server = FakeApiServer((url, method, call) => call == 1 ? reply({}, status: 503) : reply({'ok': true}));
      await harness(server);
      await h.add(
        'Flaky',
        settings: RequestSettings(
          flow: FlowSettings(
            retry: _retry,
            runIf: RunIfPolicy(enabled: true, conditions: [_when(RunConditionKind.environmentIs, 'Staging')]),
          ),
        ),
      );
      final mcp = McpServer(await h.cliRunner(), const RunOptions(environment: 'Dev'), const {});

      final answer = await call(mcp, 'run_request', {'request': 'Flaky'});

      expect(answer['isError'], isFalse);
      final json = answer['json'] as Map;
      expect(json['status'], '200 OK');
      expect(json['passed'], isTrue);
      expect((json['flow'] as Map)['summary'], '2 attempts');
      expect(server.requests, hasLength(2));
    });

    test('run_collection skips by Run if and still runs the always-run requests after a failure with bail', () async {
      final server = failing({'/Step'});
      await harness(server);
      await h.add('Step');
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('Cleanup', settings: _cleanup);
      final mcp = McpServer(await h.cliRunner(), const RunOptions(environment: 'Dev'), const {});

      final answer = await call(mcp, 'run_collection', {'collection': 'Jobs', 'bail': true});

      final json = answer['json'] as Map;
      expect(server.paths, ['/Step', '/Cleanup']);
      expect(json['failed'], 1);
      expect((json['failures'] as List).single['request'], 'Step');
      expect(json['ok'], isFalse);
    });

    test('the tool descriptions say what the flow controls do', () async {
      await harness(ok());
      final mcp = McpServer(await h.cliRunner(), const RunOptions(), const {});

      final listed = jsonDecode((await mcp.handleLine('{"jsonrpc":"2.0","id":2,"method":"tools/list"}'))!) as Map;
      final tools = ((listed['result'] as Map)['tools'] as List).cast<Map>();

      final runRequest = tools.singleWhere((t) => t['name'] == 'run_request')['description'] as String;
      final runCollection = tools.singleWhere((t) => t['name'] == 'run_collection')['description'] as String;
      expect(runRequest, contains('retry, poll-until or fetch-all-pages'));
      expect(runCollection, contains('always-run'));
    });
  });

  group('the app\'s runner and the CLI do the same', () {
    /// Ten requests that between them use every flow control, against a server that is flaky, slow and paged.
    Future<void> scenario(FlowHarness h) async {
      await h.add('Login');
      await h.add('Flaky', settings: const RequestSettings(flow: FlowSettings(retry: _retry)));
      await h.add(
        'Job',
        settings: RequestSettings(
          flow: FlowSettings(
            poll: PollPolicy(
              enabled: true,
              until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
              intervalMs: 1000,
            ),
          ),
        ),
      );
      await h.add('Items', settings: const RequestSettings(pagination: _linked));
      await h.add('Staging only', settings: _runIf([_when(RunConditionKind.environmentIs, 'Staging')]));
      await h.add('After login', settings: _runIf([_when(RunConditionKind.previousPassed)]));
      await h.add('Fails');
      await h.add('Normal after failure');
      await h.add('Cleanup', settings: _runIf([_when(RunConditionKind.previousFailed)], alwaysRun: true));
      await h.add('Never reached');
    }

    FakeApiServer server() => FakeApiServer((url, method, call) {
          switch (url.path) {
            case '/Flaky':
              return call == 1 ? reply({}, status: 503) : reply({'ok': true});
            case '/Job':
              return reply({'status': call < 3 ? 'running' : 'done'});
            case '/Items':
              return _page(url);
            case '/Fails':
              return reply({}, status: 500);
            default:
              return reply({'ok': true});
          }
        });

    test('same requests sent, same results, same flow reports', () async {
      final appServer = server();
      final app = await FlowHarness.create(appServer);
      addTearDown(app.dispose);
      await scenario(app);
      final cliServer = server();
      final cli = await FlowHarness.create(cliServer);
      addTearDown(cli.dispose);
      await scenario(cli);

      final appResults = await app.runApp(options: const CollectionRunOptions(stopOnFailure: true));
      final cliSummary = await (await cli.cliRunner()).run(const RunOptions(environment: 'Dev', bail: true));

      expect(appResults.map(stateOfApp), [
        'Login:passed',
        'Flaky:passed',
        'Job:passed',
        'Items:passed',
        'Staging only:skipped',
        'After login:passed',
        'Fails:failed',
        'Cleanup:passed',
      ]);
      expect(cliSummary.outcomes.map(stateOfCli), appResults.map(stateOfApp));
      expect(cliServer.requests, appServer.requests, reason: 'the same requests, in the same order');
      expect(
        cliSummary.outcomes.map((o) => o.flow?.summary ?? o.skipped ?? ''),
        appResults.map((r) => r.flow?.summary ?? r.skipped ?? ''),
      );
      expect(cli.clock.waits, app.clock.waits, reason: 'and the same waits between them');
      expect(appResults[1].flow!.summary, '2 attempts');
      expect(appResults[2].flow!.summary, 'polled 3 times');
      expect(appResults[3].flow!.summary, '3 pages, 12 items');
    });
  });
}
