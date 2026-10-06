// The request editor's Send with flow controls: what the person sees while it runs and after (the response that
// stays, the one-line error, the report strip's data, the Send label), and that the tests run on the final response.
import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'flow_run_harness.dart';

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

PollPolicy _pollUntilDone({int maxAttempts = 10}) => PollPolicy(
      enabled: true,
      until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
      intervalMs: 1000,
      maxAttempts: maxAttempts,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FlowHarness h;

  Future<RequestBuilderViewModel> editor(FakeApiServer server, String name, RequestSettings settings, {String? assertions, String? extractors}) async {
    h = await FlowHarness.create(server);
    addTearDown(h.dispose);
    final id = await h.add(name, settings: settings, assertionsJson: assertions, extractorsJson: extractors);
    final vm = RequestBuilderViewModel(
      h.repos.requestRepository,
      h.send,
      GenerateCodeSnippetUseCase(h.resolver, h.repos.collectionAuthRepository),
      RunRequestScriptsUseCase(h.repos.scriptsRepository, h.resolver, h.repos.environmentRepository, h.repos.globalVariableRepository),
      h.flow,
    );
    addTearDown(vm.dispose);
    await vm.load(id);
    return vm;
  }

  group('retry', () {
    test('a send that works on the second try shows the response and a report of two attempts, with no error', () async {
      final server = FakeApiServer((url, method, call) => call == 1 ? reply({}, status: 503) : reply({'ok': true}));
      final vm = await editor(server, 'Flaky', const RequestSettings(flow: FlowSettings(retry: _retry)));

      await vm.send();

      expect(vm.response!.statusCode, 200);
      expect(vm.errorMessage, isNull);
      expect(vm.lastFlow!.retries, 1);
      expect(vm.lastFlow!.summary, '2 attempts');
      expect(vm.isSending, isFalse);
      expect(vm.flowStatus, isNull);
      expect(h.consoleNotes, ['attempt 2/3 after 500 ms']);
    });

    test('while it waits and tries again, the status line says what it is doing', () async {
      final server = FakeApiServer((url, method, call) => call < 3 ? reply({}, status: 503) : reply({'ok': true}));
      final vm = await editor(server, 'Flaky', const RequestSettings(flow: FlowSettings(retry: _retry)));
      final seen = <String?>[];
      vm.addListener(() => seen.add(vm.flowStatus));

      await vm.send();

      expect(seen.whereType<String>().toSet(), {'attempt 2/3 after 500 ms', 'attempt 3/3 after 500 ms'});
      expect(vm.flowStatus, isNull, reason: 'and it clears when the send is over');
    });

    test('a server that never answers shows the same one-line error a plain send shows, and what was tried', () async {
      final vm = await editor(
        FakeApiServer((url, method, call) => unreachable()),
        'Down',
        const RequestSettings(flow: FlowSettings(retry: _retry)),
      );

      await vm.send();

      expect(vm.response, isNull);
      expect(vm.errorMessage, "Couldn't reach api.test");
      expect(vm.lastFlow!.attempts, hasLength(3));
    });

    test('a request with no flow settings sends once, with no report', () async {
      final server = FakeApiServer((url, method, call) => reply({}, status: 503));
      final vm = await editor(server, 'Plain', RequestSettings.none);

      await vm.send();

      expect(server.requests, hasLength(1));
      expect(vm.lastFlow, isNull);
      expect(vm.response!.statusCode, 503);
      expect(vm.errorMessage, isNull);
    });
  });

  group('poll until', () {
    test('the response is the final one and the tests run on it, not on the earlier ones', () async {
      final server = FakeApiServer((url, method, call) => reply({'status': call < 3 ? 'running' : 'done'}));
      final vm = await editor(
        server,
        'Job',
        RequestSettings(flow: FlowSettings(poll: _pollUntilDone())),
        assertions: '[{"type":"jsonPathEquals","path":"status","expected":"done"}]',
      );

      await vm.send();

      expect(utf8.decode(vm.response!.bodyBytes), '{"status":"done"}');
      expect(vm.lastFlow!.polls, 3);
      expect(vm.lastScriptResult!.assertions.single.passed, isTrue);
      expect(vm.errorMessage, isNull);
    });

    test('a job that never finishes keeps the last response on screen and says why it gave up', () async {
      final vm = await editor(
        FakeApiServer((url, method, call) => reply({'status': 'running'})),
        'Job',
        RequestSettings(flow: FlowSettings(poll: _pollUntilDone(maxAttempts: 3))),
        assertions: '[{"type":"statusIn2xx","path":"","expected":""}]',
      );

      await vm.send();

      expect(vm.response!.statusCode, 200);
      expect(vm.errorMessage, contains('Polling gave up after 3 requests'));
      expect(vm.errorMessage, contains('status equals done (got running)'));
      expect(vm.lastFlow!.failure, vm.errorMessage);
      expect(vm.lastScriptResult, isNotNull, reason: 'the tests still ran on the last response');
    });

    test('Cancel during the waits ends the send quietly, with no error', () async {
      final server = FakeApiServer((url, method, call) => reply({'status': 'running'}));
      final vm = await editor(server, 'Job', RequestSettings(flow: FlowSettings(poll: _pollUntilDone())));
      server.onRequest = (url) {
        if (server.requests.length == 2) vm.cancelSend();
      };

      await vm.send();

      expect(vm.isSending, isFalse);
      expect(vm.errorMessage, isNull);
      expect(vm.response, isNull);
      expect(server.requests, hasLength(2), reason: 'no third poll after Cancel');
    });
  });

  group('fetch all pages', () {
    test('the response in the viewer is ONE merged response, and scripts, extractors and the badge use it', () async {
      final vm = await editor(
        FakeApiServer((url, method, call) => _page(url)),
        'Items',
        const RequestSettings(pagination: _linked),
        assertions: '[{"type":"jsonPathExists","path":"[11].id","expected":""}]',
        extractors: r'[{"source":"jsonPath","path":"[11].id","scope":"environment","key":"lastId"}]',
      );

      await vm.send();

      expect((jsonDecode(utf8.decode(vm.response!.bodyBytes)) as List), hasLength(12));
      expect(vm.lastFlow!.pages!.badge, '3 pages, 12 items');
      expect(vm.lastScriptResult!.assertions.single.passed, isTrue);
      expect(vm.lastScriptResult!.extracted.single.value, '12');
      expect(vm.errorMessage, isNull);
    });

    test('a page that fails leaves what was fetched on screen and the failure as the error', () async {
      final vm = await editor(
        FakeApiServer((url, method, call) => url.queryParameters['page'] == '3' ? reply({}, status: 500) : _page(url)),
        'Items',
        const RequestSettings(pagination: _linked),
      );

      await vm.send();

      expect((jsonDecode(utf8.decode(vm.response!.bodyBytes)) as List), hasLength(10));
      expect(vm.errorMessage, contains('Page 3 failed: HTTP 500'));
      expect(vm.lastFlow!.pages!.stop.name, 'failed');
    });

    test('the production question is asked once for the whole walk, not for every page', () async {
      final vm = await editor(
        FakeApiServer((url, method, call) => _page(url)),
        'Items',
        const RequestSettings(pagination: _linked),
      );
      var asked = 0;
      vm.confirmSend = (request) async {
        asked++;
        return true;
      };

      await vm.send();

      expect(asked, 1);
      expect(vm.lastFlow!.pages!.pages, 3);
    });

    test('answering no to that question sends nothing at all', () async {
      final server = FakeApiServer((url, method, call) => _page(url));
      final vm = await editor(server, 'Items', const RequestSettings(pagination: _linked));
      vm.confirmSend = (request) async => false;

      await vm.send();

      expect(server.requests, isEmpty);
      expect(vm.response, isNull);
    });
  });

  group('the Send button', () {
    test('says "Send (all pages)" exactly while fetching all pages is on for the request, and follows a change', () async {
      final vm = await editor(FakeApiServer((url, method, call) => reply({})), 'Items', RequestSettings.none);
      await pumpEventQueue();
      expect(vm.sendLabel, 'Send');
      expect(vm.fetchAllPages, isFalse);
      final id = vm.request!.id;

      await h.repos.requestSettingsRepository.save(id, const RequestSettings(pagination: _linked));
      await pumpEventQueue();

      expect(vm.sendLabel, 'Send (all pages)');
      expect(vm.fetchAllPages, isTrue);

      await h.repos.requestSettingsRepository.save(id, RequestSettings(pagination: _linked.copyWith(enabled: false)));
      await pumpEventQueue();

      expect(vm.sendLabel, 'Send');
    });

    test('is "Send (all pages)" from the start for a request that already has it on', () async {
      final vm = await editor(FakeApiServer((url, method, call) => reply({})), 'Items', const RequestSettings(pagination: _linked));
      await pumpEventQueue();

      expect(vm.sendLabel, 'Send (all pages)');
    });

    test('is the plain label without a flow service, as in every older test', () async {
      h = await FlowHarness.create(FakeApiServer((url, method, call) => reply({})));
      addTearDown(h.dispose);
      final id = await h.add('Items', settings: const RequestSettings(pagination: _linked));
      final vm = RequestBuilderViewModel(
        h.repos.requestRepository,
        h.send,
        GenerateCodeSnippetUseCase(h.resolver, h.repos.collectionAuthRepository),
        RunRequestScriptsUseCase(h.repos.scriptsRepository, h.resolver, h.repos.environmentRepository, h.repos.globalVariableRepository),
      );
      addTearDown(vm.dispose);
      await vm.load(id);
      await pumpEventQueue();

      expect(vm.sendLabel, 'Send');
      await vm.send();
      expect(vm.lastFlow, isNull);
      expect((h.server.requests), hasLength(1), reason: 'without the service a send is one request, whatever the settings say');
    });
  });
}
