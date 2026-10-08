// The ledger fed by the app's real send path (the flow service), and its deletes sent back through it: over an in-memory
// database and a scripted server, with no fake of the code under test. A manual send and a collection run both leave
// entries; a delete is a normal request, so the environment, the variable check and the production guard apply to it.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/request_flow/data/app_flow_environment.dart';
import 'package:postpilot/features/request_flow/domain/usecases/request_flow_service.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_entry.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/sent_request.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'cleanup_harness.dart';
import 'cleanup_support.dart';

/// A server that creates partners (`POST /partners` answers with the next id from 101) and deletes them.
Answer Function(SentCall) _partners({Set<String> missing = const {}, Map<String, Answer> overrides = const {}}) {
  var next = 100;
  return (call) {
    final path = Uri.parse(call.url).path;
    if (overrides.containsKey(call.line)) return overrides[call.line]!;
    if (call.method == 'POST' && path == '/partners') return ok({'id': ++next, 'name': 'Ann', 'address': {'city': 'Dhaka'}});
    if (call.method == 'DELETE' && missing.contains(path)) return ok({'message': 'Record does not exist.'}, status: 404);
    return ok({'deleted': true});
  };
}

RequestSettings _cleanup(CleanupSettings settings) => RequestSettings(flow: FlowSettings(cleanup: settings));

/// What the flow service would tell the ledger after sending [request] once.
Future<SentRequest> _sentOf(CleanupHarness h, ApiRequestEntity request) async {
  final outcome = await h.flow.send(request);
  return SentRequest(request: request, response: outcome.response!, settings: CleanupHarness.cleanupOn, dataVariables: const {}, environment: 'Staging');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late CleanupHarness h;

  Future<CleanupHarness> harness({Answer Function(SentCall)? server, String? environment = 'Staging'}) async {
    h = await CleanupHarness.create(server: server ?? _partners(), environment: environment);
    addTearDown(h.dispose);
    return h;
  }

  group('what feeds the ledger', () {
    test('a send by hand of a request with cleanup switched on leaves an entry that says how it is undone', () async {
      await harness();
      final create = await h.add('Create partner');

      final outcome = await h.flow.send(create);

      expect(outcome.response!.statusCode, 200, reason: 'the send itself is unchanged');
      final entry = h.ledger.entries.single;
      expect(entry.requestName, 'Create partner');
      expect(entry.environment, 'Staging');
      expect(entry.ids, [101]);
      expect(entry.state, CleanupState.pending);
      expect(entry.plan.summary, 'DELETE {{baseUrl}}/partners/101');
      expect(entry.variables, {'created.id': '101', 'created.ids': '101', 'created.count': '1', 'created.name': 'Ann', 'created.address.city': 'Dhaka'});
      expect(h.calls.single.line, 'POST https://api.test/partners', reason: 'recording sends nothing of its own');
    });

    test('a request without cleanup, a failed create, and a create that made nothing leave no entry', () async {
      await harness(server: (call) {
        if (call.url.endsWith('/broken')) return ok({'error': 'no'}, status: 500);
        if (call.url.endsWith('/none')) return ok(false);
        return ok({'id': 5});
      });
      final plain = await h.add('Plain create', settings: RequestSettings.none);
      final broken = await h.add('Broken create', url: '{{baseUrl}}/broken');
      final none = await h.add('Nothing created', url: '{{baseUrl}}/none');

      await h.flow.send(plain);
      await h.flow.send(broken);
      await h.flow.send(none);

      expect(h.ledger.entries, isEmpty);
    });

    test('a success with no id in it is kept as a "not cleaned up" entry that says why', () async {
      await harness(server: (call) => ok({'ok': true}));
      final create = await h.add('Create partner');

      await h.flow.send(create);

      final entry = h.ledger.entries.single;
      expect(entry.state, CleanupState.skipped);
      expect(entry.reason, contains('No id found'));
      expect(h.ledger.deletableCount, 0);
    });

    test('a collection run feeds it too, and the mark tells which entries the run made', () async {
      await harness();
      final a = await h.add('Create A');
      await h.add('Create B');
      await h.add('List partners', method: HttpMethod.get, url: '{{baseUrl}}/partners', settings: RequestSettings.none);
      await h.add('Create C');
      await h.flow.send(a);
      final mark = h.ledger.mark;

      final results = await h.runner.run(h.collectionId).toList();

      expect(results, hasLength(4));
      final mine = h.ledger.since(mark);
      expect([for (final e in mine) e.requestName], ['Create A', 'Create B', 'Create C']);
      expect([for (final e in mine) e.ids.single], [102, 103, 104]);
      expect(h.ledger.entries, hasLength(4));
      expect(mine.map((e) => e.id), everyElement(greaterThan(mark)));
    });

    test('the data row of a run is kept with the entry, under the created variables', () async {
      await harness();
      await h.add('Create partner', url: '{{baseUrl}}/partners');

      await h.runner.run(h.collectionId, options: const CollectionRunOptions(dataRows: [{'region': 'eu'}, {'region': 'us'}])).toList();

      expect([for (final e in h.ledger.entries) e.variables['region']], ['eu', 'us']);
      expect([for (final e in h.ledger.entries) e.variables['created.id']], ['101', '102']);
    });

    test('the observer is told about answers only, with the environment, and one that throws cannot fail a send', () async {
      await harness(server: (call) {
        if (call.url.endsWith('/down')) throw const NetworkException('refused', kind: NetworkErrorKind.connectionError);
        return ok({'id': 1}, status: call.url.endsWith('/bad') ? 500 : 200);
      });
      final told = <String>[];
      final flow = RequestFlowService(
        h.repos.requestSettingsRepository,
        h.send,
        AppFlowEnvironment(h.resolver, h.repos.environmentRepository),
        onSent: (sent) async {
          told.add('${sent.response.statusCode} ${sent.environment} ${sent.request.name}');
          throw StateError('the observer is broken');
        },
      );

      final good = await flow.send(await h.add('Good', url: '{{baseUrl}}/good'));
      final bad = await flow.send(await h.add('Bad', url: '{{baseUrl}}/bad'));
      await expectLater(flow.send(await h.add('Down', url: '{{baseUrl}}/down')), throwsA(isA<NetworkException>()));

      expect(good.response!.statusCode, 200, reason: 'a broken observer changes nothing for the person');
      expect(bad.response!.statusCode, 500, reason: 'a 500 is an answer; the ledger decides it is not a create');
      expect(told, ['200 Staging Good', '500 Staging Bad'], reason: 'a send that got no answer is not announced');
    });

    test('the ledger keeps nothing outside memory: no row anywhere mentions it', () async {
      await harness();
      final create = await h.add('Create partner');
      await h.flow.send(create);

      final stored = await h.repos.requestSettingsRepository.get(create.id);

      expect(stored.encode(), '{"flow":{"cleanup":{"enabled":true}}}', reason: 'only the setting is stored, never an id');
      expect(stored.encode(), isNot(contains('101')));
    });
  });

  group('deleting', () {
    test('a record is deleted with a DELETE of the create URL plus its id, and the entry says so', () async {
      await harness();
      await h.flow.send(await h.add('Create partner'));

      final run = await h.ledger.cleanupAll();

      expect(h.lines, ['POST https://api.test/partners', 'DELETE https://api.test/partners/101']);
      expect(run.deleted, 1);
      expect(h.ledger.entries.single.state, CleanupState.deleted);
      expect(h.ledger.entries.single.settledAt, isNotNull);
      expect(h.ledger.deletableCount, 0);
    });

    test('a run is cleaned up newest first, whatever order it is asked in', () async {
      await harness();
      await h.add('Create A');
      await h.add('Create B');
      await h.add('Create C');
      await h.runner.run(h.collectionId).toList();
      h.calls.clear();

      await h.ledger.cleanup(h.ledger.entries.toList());

      expect(h.lines, [
        'DELETE https://api.test/partners/103',
        'DELETE https://api.test/partners/102',
        'DELETE https://api.test/partners/101',
      ]);
    });

    test('an Odoo create is unlinked on the same server with the same headers, and the context rides along', () async {
      await harness(server: (call) => call.url.endsWith('/create') ? ok([7, 8]) : ok(true));
      final create = await h.add(
        'Create partners',
        url: '{{odooUrl}}/json/2/res.partner/create',
        body: rawBody('{"context": {"lang": "en_US"}, "vals_list": [{"name": "A"}, {"name": "B"}]}'),
      );
      await h.repos.requestRepository.saveRequest(create.copyWith(headers: [KeyValueItem(key: 'X-Odoo-Database', value: 'staging-db')]));
      await h.flow.send((await h.repos.requestRepository.findById(create.id))!);

      await h.ledger.cleanupAll();

      expect(h.lines, ['POST https://odoo.test/json/2/res.partner/create', 'POST https://odoo.test/json/2/res.partner/unlink']);
      final unlink = h.calls.last;
      expect(unlink.json, {'ids': [7, 8], 'context': {'lang': 'en_US'}});
      expect(unlink.headers['X-Odoo-Database'], 'staging-db');
      expect(h.ledger.entries.single.state, CleanupState.deleted);
      expect(h.ledger.entries.single.plan.summary, 'Odoo unlink res.partner [7, 8]');
    });

    test('another request is the undo: it is sent with the created id and the fields of the answer', () async {
      await harness();
      await h.add(
        'Remove partner',
        method: HttpMethod.delete,
        url: '{{baseUrl}}/remove/{{created.id}}?owner={{created.name}}&city={{created.address.city}}&region={{region}}',
        settings: RequestSettings.none,
      );
      await h.add('Create partner', settings: _cleanup(const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Remove partner')));
      await h.runner.run(h.collectionId, options: const CollectionRunOptions(dataRows: [{'region': 'eu'}])).toList();
      h.calls.clear();

      // The run also ran "Remove partner" once, with nothing created yet; that call is not what is under test.
      await h.ledger.cleanupAll();

      expect(h.lines, ['DELETE https://api.test/remove/101?owner=Ann&city=Dhaka&region=eu']);
      expect(h.ledger.entries.single.state, CleanupState.deleted);
    });

    test('an undo request that names no request of the collection fails with that, and sends nothing', () async {
      await harness();
      final create = await h.add('Create partner', settings: _cleanup(const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Gone')));
      await h.flow.send(create);
      h.calls.clear();

      await h.ledger.cleanupAll();

      expect(h.calls, isEmpty);
      final entry = h.ledger.entries.single;
      expect(entry.state, CleanupState.failed);
      expect(entry.reason, 'No request of this collection is called "Gone" any more.');
    });

    test('one delete that fails is reported with the server\'s reason, and the others still go', () async {
      await harness(server: _partners(missing: {'/partners/102'}));
      await h.add('Create A');
      await h.add('Create B');
      await h.add('Create C');
      await h.runner.run(h.collectionId).toList();
      h.calls.clear();

      final run = await h.ledger.cleanupAll();

      expect(h.lines, hasLength(3), reason: 'all three were tried');
      expect(run.deleted, 2);
      expect(run.failed, 1);
      final byName = {for (final e in h.ledger.entries) e.requestName: e};
      expect(byName['Create A']!.state, CleanupState.deleted);
      expect(byName['Create C']!.state, CleanupState.deleted);
      expect(byName['Create B']!.state, CleanupState.failed);
      expect(byName['Create B']!.reason, 'HTTP 404: Record does not exist.');
      expect(h.ledger.deletableCount, 1, reason: 'the failed one can be tried again');
    });

    test('a failed delete can be retried, and a deleted one is never sent twice', () async {
      var online = false;
      await harness(server: (call) {
        if (call.method == 'DELETE') return online ? ok({'deleted': true}) : ok({'message': 'Try later'}, status: 503);
        return ok({'id': 101});
      });
      await h.flow.send(await h.add('Create partner'));

      await h.ledger.cleanupAll();
      expect(h.ledger.entries.single.state, CleanupState.failed);
      online = true;
      await h.ledger.cleanupAll();
      expect(h.ledger.entries.single.state, CleanupState.deleted);
      expect(h.ledger.entries.single.reason, isNull);
      final sent = h.calls.length;
      final again = await h.ledger.cleanupAll();

      expect(again.results, isEmpty);
      expect(h.calls, hasLength(sent));
    });

    test('an Odoo 18 style answer of 200 with an error in the body is a failure', () async {
      await harness(server: (call) => call.method == 'DELETE'
          ? ok({'jsonrpc': '2.0', 'id': 1, 'error': {'code': 200, 'message': 'Odoo Server Error', 'data': {'message': 'Record does not exist'}}})
          : ok({'id': 9}));
      await h.flow.send(await h.add('Create partner'));

      await h.ledger.cleanupAll();

      expect(h.ledger.entries.single.state, CleanupState.failed);
      expect(h.ledger.entries.single.reason, 'Record does not exist');
    });

    test('under another environment nothing is sent: the same URL would reach another server', () async {
      await harness();
      await h.flow.send(await h.add('Create partner'));
      await h.useEnvironment('Production');
      h.calls.clear();

      final run = await h.ledger.cleanupAll();

      expect(h.calls, isEmpty);
      expect(run.failed, 1);
      expect(h.ledger.entries.single.state, CleanupState.failed);
      expect(h.ledger.entries.single.reason, 'Created under environment "Staging", but environment "Production" is active now. Switch back to it to delete this record.');
    });

    test('an undefined variable in the undo blocks it like any request: it fails and sends nothing', () async {
      await harness();
      await h.add('Remove partner', method: HttpMethod.delete, url: '{{baseUrl}}/remove/{{created.id}}/{{reason}}', settings: RequestSettings.none);
      await h.flow.send(await h.add('Create partner', settings: _cleanup(const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Remove partner'))));
      h.calls.clear();

      await h.ledger.cleanupAll();

      expect(h.calls, isEmpty);
      final entry = h.ledger.entries.single;
      expect(entry.state, CleanupState.failed);
      expect(entry.reason, contains('reason'));
    });

    test('an undo request that creates something itself does not feed the ledger', () async {
      await harness(server: (call) => ok({'id': 500}));
      final undoAlsoCreates = await h.add(
        'Undo that is a create',
        url: '{{baseUrl}}/undo/{{created.id}}',
        settings: _cleanup(const CleanupSettings(enabled: true)),
      );
      await h.flow.send(await h.add('Create partner', settings: _cleanup(CleanupSettings(enabled: true, undo: CleanupUndo.request, request: undoAlsoCreates.name))));
      expect(h.ledger.entries, hasLength(1));

      await h.ledger.cleanupAll();

      expect(h.ledger.entries, hasLength(1), reason: 'the answer to the undo is not a record to undo');
      expect(h.ledger.entries.single.state, CleanupState.deleted);
    });

    test('two cleanups at once do not delete the same record twice', () async {
      await harness();
      await h.flow.send(await h.add('Create partner'));
      h.calls.clear();

      await Future.wait([h.ledger.cleanupAll(), h.ledger.cleanupAll()]);

      expect(h.lines, ['DELETE https://api.test/partners/101']);
    });

    test('forgetting an entry removes it without deleting anything; finished ones can be cleared', () async {
      await harness();
      await h.add('Create A');
      await h.add('Create B');
      await h.runner.run(h.collectionId).toList();
      h.calls.clear();

      h.ledger.forget(h.ledger.entries.first.id);
      expect(h.calls, isEmpty);
      expect(h.ledger.entries, hasLength(1));

      await h.ledger.cleanupAll();
      h.ledger.clearFinished();
      expect(h.ledger.entries, isEmpty);
    });

    test('listeners hear every change: a new entry, each delete as it settles', () async {
      await harness();
      var heard = 0;
      h.ledger.addListener(() => heard++);

      await h.flow.send(await h.add('Create partner'));
      final afterCreate = heard;
      await h.ledger.cleanupAll();

      expect(afterCreate, 1);
      expect(heard, greaterThan(afterCreate + 1), reason: 'working, then settled, then idle');
    });

    test('the list is capped, dropping settled entries before pending ones, and the oldest pending one last', () async {
      await harness(server: (call) => ok({'id': 1}));
      final capped = CleanupLedger(h.sender, maxEntries: 3);
      final create = await h.add('Create partner');
      for (var i = 0; i < 4; i++) {
        await capped.recordSend(await _sentOf(h, create));
      }
      expect(capped.entries.map((e) => e.id), [2, 3, 4], reason: 'the oldest pending one went when nothing was settled');

      await capped.cleanup([capped.entries.first]);
      await capped.recordSend(await _sentOf(h, create));

      expect(capped.entries.map((e) => e.id), [3, 4, 5], reason: 'the settled entry went first');
      expect(capped.entries.map((e) => e.state), everyElement(CleanupState.pending));
    });
  });

  group('the production lock', () {
    test('a delete is destructive: the guard asks about it, and when the answer is no nothing is sent and nothing changes', () async {
      await harness(
        environment: 'Production',
        server: (call) => call.url.endsWith('/create') ? ok([9]) : (call.method == 'POST' ? ok({'id': 101}) : ok(true)),
      );
      await h.flow.send(await h.add('Create partner'));
      await h.flow.send(await h.add('Create other', url: '{{odooUrl}}/json/2/res.partner/create'));
      h.calls.clear();
      var asked = <String>[];
      var warnedDestructive = false;

      final run = await h.ledger.cleanupAll(gate: (requests) async {
        asked = [for (final r in requests) '${r.method.label} ${r.url}'];
        final warning = await h.guard.checkRunRequests(requests, 'the cleanup');
        warnedDestructive = warning?.destructive ?? false;
        return false;
      });

      expect(asked, ['POST {{odooUrl}}/json/2/res.partner/unlink', 'DELETE {{baseUrl}}/partners/101'], reason: 'newest first, the guard sees exactly what would go');
      expect(warnedDestructive, isTrue, reason: 'unlink and DELETE both delete data, so "don\'t ask again" never covers them');
      expect(run.declined, isTrue);
      expect(h.calls, isEmpty);
      expect(h.ledger.entries.map((e) => e.state), everyElement(CleanupState.pending));
    });

    test('when the person confirms, the deletes go through the same send', () async {
      await harness(environment: 'Production');
      await h.flow.send(await h.add('Create partner'));
      h.calls.clear();

      final run = await h.ledger.cleanupAll(gate: (requests) async => (await h.guard.checkRunRequests(requests, 'the cleanup')) != null);

      expect(run.deleted, 1);
      expect(h.lines, ['DELETE https://api.test/partners/101']);
    });

    test('a staging environment is not asked about', () async {
      await harness(environment: 'Staging');
      await h.flow.send(await h.add('Create partner'));

      final warning = await h.guard.checkRunRequests([h.ledger.entries.single.plan.request!], 'the cleanup');

      expect(warning, isNull);
    });
  });
}
