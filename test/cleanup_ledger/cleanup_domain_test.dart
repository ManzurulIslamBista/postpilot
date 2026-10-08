// The pure part of the cleanup ledger: finding the created ids, building the undo, the variables it is sent with, the
// settings that hold it and the order and isolation in which a cleanup runs. Expected values are written by hand from
// what Odoo and REST servers answer; none of them is computed by the code under test.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_entry.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/cleanup_executor.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/cleanup_planner.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/cleanup_urls.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/created_id_detector.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/created_variables.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'cleanup_support.dart';

final _now = DateTime.utc(2026, 10, 8, 9);

List<CleanupDraft> _plan(
  ApiRequestEntity request,
  Object? answer, {
  CleanupSettings settings = const CleanupSettings(enabled: true),
  int status = 200,
  String? environment = 'Staging',
  Map<String, String> data = const {},
}) =>
    CleanupPlanner.plan(
      request: request,
      settings: settings,
      statusCode: status,
      responseBody: answer is String ? answer : json(answer),
      environment: environment,
      now: _now,
      dataVariables: data,
    );

Map<String, Object?> _bodyOf(CleanupDraft draft) => jsonDecode(draft.plan.request!.body.rawText) as Map<String, Object?>;

void main() {
  group('finding the created ids', () {
    test('an Odoo JSON-2 create answers with the ids themselves', () {
      expect(CreatedIdDetector.detect([42])!.values, [42]);
      expect(CreatedIdDetector.detect([5, 6, 7])!.values, [5, 6, 7]);
      expect(CreatedIdDetector.detect(42)!.values, [42], reason: 'an older create answers with one id');
      expect(CreatedIdDetector.detect([42])!.source, 'the result');
    });

    test('Odoo answers false, null or an empty list when nothing was made', () {
      for (final nothing in <Object?>[false, null, true, <Object?>[]]) {
        expect(CreatedIdDetector.detect(nothing), isNull, reason: '$nothing');
        expect(CreatedIdDetector.saysNothingWasCreated(json(nothing)), isTrue, reason: '$nothing');
      }
      expect(CreatedIdDetector.saysNothingWasCreated('[42]'), isFalse);
      expect(CreatedIdDetector.saysNothingWasCreated('{"id": 1}'), isFalse);
      expect(CreatedIdDetector.saysNothingWasCreated('not json'), isFalse);
    });

    test('a list that is not all ids, and ids that cannot be records, are not taken', () {
      expect(CreatedIdDetector.detect([1, 'two']), isNull, reason: 'Odoo ids are numbers');
      expect(CreatedIdDetector.detect([1, null]), isNull);
      expect(CreatedIdDetector.detect([0]), isNull);
      expect(CreatedIdDetector.detect(-3), isNull);
      expect(CreatedIdDetector.detect(List<int>.generate(1001, (i) => i + 1)), isNull, reason: 'a thousand at most');
      expect(CreatedIdDetector.detect(7.0)!.values, [7], reason: 'the web build reads every number as a double');
      expect(CreatedIdDetector.detect(7.5), isNull);
    });

    test('a REST answer holds the id as id, data.id, result.id or result, looked at in that order', () {
      expect(CreatedIdDetector.detect({'id': 9, 'name': 'Ann'})!.values, [9]);
      expect(CreatedIdDetector.detect({'data': {'id': 10}})!.values, [10]);
      expect(CreatedIdDetector.detect({'data': {'id': 10}})!.source, 'data.id');
      expect(CreatedIdDetector.detect({'result': {'id': 11}})!.values, [11]);
      expect(CreatedIdDetector.detect({'result': 12})!.values, [12]);
      expect(CreatedIdDetector.detect({'result': 12})!.source, 'result');
      expect(CreatedIdDetector.detect({'id': 1, 'data': {'id': 2}})!.values, [1]);
      expect(CreatedIdDetector.detect({'data': {'id': 2}, 'result': 3})!.values, [2]);
    });

    test('a REST id may be text (a UUID); one with a blank in it is not an id', () {
      expect(CreatedIdDetector.detect({'id': '3f2a-9c'})!.values, ['3f2a-9c']);
      expect(CreatedIdDetector.detect({'id': '15'})!.values, [15], reason: 'a number written as text is a number');
      expect(CreatedIdDetector.detect({'id': 'a b'}), isNull);
      expect(CreatedIdDetector.detect({'id': ''}), isNull);
      expect(CreatedIdDetector.detect({'id': 0}), isNull);
    });

    test('a list of records each with an id is a bulk create', () {
      expect(CreatedIdDetector.detect([{'id': 3}, {'id': 4}])!.values, [3, 4]);
      expect(CreatedIdDetector.detect([{'id': 3}, {'name': 'x'}]), isNull);
    });

    test('an Odoo 18 JSON-RPC answer is read through result: its own id is the call, not a record', () {
      final ids = CreatedIdDetector.detect({'jsonrpc': '2.0', 'id': 1, 'result': 42})!;
      expect(ids.values, [42]);
      expect(ids.source, 'result');
      expect(CreatedIdDetector.detect({'jsonrpc': '2.0', 'id': 1, 'result': [8, 9]})!.values, [8, 9]);
      expect(CreatedIdDetector.detect({'jsonrpc': '2.0', 'id': 1, 'result': false}), isNull);
      expect(CreatedIdDetector.detect({'jsonrpc': '2.0', 'id': 1, 'error': {'code': 200}}), isNull);
      expect(CreatedIdDetector.detect({'jsonrpc': '2.0', 'id': 1, 'result': {'id': 5}})!.values, [5]);
      expect(CreatedIdDetector.saysNothingWasCreated(json({'jsonrpc': '2.0', 'id': 1, 'result': false})), isTrue);
      expect(CreatedIdDetector.saysNothingWasCreated(json({'jsonrpc': '2.0', 'id': 1, 'error': {}})), isTrue);
    });

    test('a path the person names beats the usual places', () {
      final body = {'id': 1, 'data': {'items': [{'id': 77}, {'id': 78}], 'code': 'x-5'}};
      expect(CreatedIdDetector.detect(body, idPath: r'$.data.items[0].id')!.values, [77]);
      expect(CreatedIdDetector.detect(body, idPath: 'data.items')!.values, [77, 78], reason: 'a list of records at the path');
      expect(CreatedIdDetector.detect(body, idPath: 'data.code')!.values, ['x-5']);
      expect(CreatedIdDetector.detect(body, idPath: 'data.nothing'), isNull);
      expect(CreatedIdDetector.detect(body, idPath: 'data.items')!.source, 'data.items');
    });

    test('a body that is not JSON names no id', () {
      expect(CreatedIdDetector.fromBody('<html>created</html>'), isNull);
      expect(CreatedIdDetector.fromBody('[42]')!.values, [42]);
      expect(CreatedIdDetector.fromBody('{"id": 4}')!.values, [4]);
    });
  });

  group('reading URLs', () {
    test('an Odoo URL is split into server, model and method', () {
      final json2 = CleanupUrls.odoo('{{odooUrl}}/json/2/res.partner/create')!;
      expect((json2.base, json2.model, json2.method, json2.jsonRpc, json2.isCreate), ('{{odooUrl}}', 'res.partner', 'create', false, true));
      expect(json2.urlFor('unlink'), '{{odooUrl}}/json/2/res.partner/unlink');

      final rpc = CleanupUrls.odoo('https://odoo.test:8069/web/dataset/call_kw/sale.order/create?x=1')!;
      expect((rpc.base, rpc.model, rpc.method, rpc.jsonRpc), ('https://odoo.test:8069', 'sale.order', 'create', true));
      expect(rpc.urlFor('unlink'), 'https://odoo.test:8069/web/dataset/call_kw/sale.order/unlink');

      expect(CleanupUrls.odoo('{{baseUrl}}/partners'), isNull);
      expect(CleanupUrls.odoo('{{odooUrl}}/json/2/res.partner/search_read')!.isCreate, isFalse);
      expect(CleanupUrls.odoo('{{odooUrl}}/json/2/res.partner/copy')!.isCreate, isTrue);
    });

    test('a REST delete URL is the create URL without its query, plus the id', () {
      expect(CleanupUrls.restDelete('{{baseUrl}}/partners', 42), '{{baseUrl}}/partners/42');
      expect(CleanupUrls.restDelete('{{baseUrl}}/partners/', 42), '{{baseUrl}}/partners/42');
      expect(CleanupUrls.restDelete('{{baseUrl}}/partners?notify=1&x=2#top', 42), '{{baseUrl}}/partners/42');
      expect(CleanupUrls.restDelete('https://api.test/v1/items//', 'a-b'), 'https://api.test/v1/items/a-b');
    });

    test('an id from a response cannot add a path or a {{variable}} to the URL', () {
      expect(CleanupUrls.restDelete('https://api.test/items', 'a#b'), 'https://api.test/items/a%23b');
      expect(CleanupUrls.restDelete('https://api.test/items', '../admin'), 'https://api.test/items/..%2Fadmin');
      expect(CleanupUrls.restDelete('https://api.test/items', '{{token}}'), 'https://api.test/items/%7B%7Btoken%7D%7D');
    });
  });

  group('the Odoo undo', () {
    test('a JSON-2 create is undone with unlink on the same server, with the same headers', () {
      final drafts = _plan(odooCreate(), [42]);

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      final undo = draft.plan.request!;
      expect(draft.plan.kind, CleanupUndo.odooUnlink);
      expect(draft.state, CleanupState.pending);
      expect(undo.method, HttpMethod.post);
      expect(undo.url, '{{odooUrl}}/json/2/res.partner/unlink');
      expect(_bodyOf(draft), {'ids': [42]});
      expect(undo.body.type, BodyType.raw);
      expect([for (final h in undo.headers) '${h.key}: ${h.value}'], [
        'Authorization: bearer {{odooApiKey}}',
        'X-Odoo-Database: {{odooDb}}',
        'Content-Type: application/json; charset=utf-8',
      ], reason: 'the key stays a {{variable}}: the send resolves it, nothing secret is copied');
      expect(undo.id, 0, reason: 'it is never a saved request');
      expect(undo.collectionId, 3);
      expect(draft.plan.summary, 'Odoo unlink res.partner [42]');
      expect(draft.ids, [42]);
      expect(draft.environment, 'Staging');
      expect(draft.requestName, 'Create partner');
      expect(draft.createdAt, _now);
    });

    test('a bulk create is one unlink of every id', () {
      final draft = _plan(odooCreate(model: 'sale.order'), [5, 6, 7]).single;

      expect(draft.plan.request!.url, '{{odooUrl}}/json/2/sale.order/unlink');
      expect(_bodyOf(draft), {'ids': [5, 6, 7]});
      expect(draft.plan.summary, 'Odoo unlink sale.order [5, 6, 7]');
      expect(draft.variables['created.count'], '3');
    });

    test('the context the create was sent with is sent with the unlink', () {
      final request = odooCreate(
        body: rawBody('{"context": {"lang": "en_US", "allowed_company_ids": [2]}, "vals_list": [{"name": "A"}]}'),
      );
      final draft = _plan(request, [9]).single;

      expect(_bodyOf(draft), {'ids': [9], 'context': {'lang': 'en_US', 'allowed_company_ids': [2]}});
    });

    test('a body with a {{variable}} where a value should be gives no context, not a failure', () {
      final request = odooCreate(body: rawBody('{"vals_list": [{"partner_id": {{partnerId}}}]}'));
      final draft = _plan(request, [9]).single;

      expect(draft.state, CleanupState.pending);
      expect(_bodyOf(draft), {'ids': [9]});
    });

    test('an Odoo 18 call_kw create is undone with a call_kw unlink read from the JSON-RPC answer', () {
      final request = createRequest(
        url: '{{odooUrl}}/web/dataset/call_kw/res.partner/create',
        body: rawBody(
          '{"jsonrpc":"2.0","method":"call","params":{"model":"res.partner","method":"create","args":[[{"name":"A"}]],"kwargs":{"context":{"lang":"fr_FR"}}}}',
        ),
      );
      final draft = _plan(request, {'jsonrpc': '2.0', 'id': 1, 'result': 42}).single;

      expect(draft.ids, [42], reason: 'the envelope id 1 is the call, not a record');
      expect(draft.plan.request!.url, '{{odooUrl}}/web/dataset/call_kw/res.partner/unlink');
      final body = _bodyOf(draft);
      final params = body['params'] as Map;
      expect(body['jsonrpc'], '2.0');
      expect(params['model'], 'res.partner');
      expect(params['method'], 'unlink');
      expect(params['args'], [[42]]);
      expect((params['kwargs'] as Map)['context'], {'lang': 'fr_FR'});
    });

    test('a copy is undone like a create', () {
      final request = createRequest(url: '{{odooUrl}}/json/2/res.partner/copy', body: rawBody('{"ids": [1]}'));

      expect(_plan(request, [60]).single.plan.kind, CleanupUndo.odooUnlink);
    });

    test('an Odoo create that made nothing, or failed, leaves nothing to undo', () {
      expect(_plan(odooCreate(), false), isEmpty);
      expect(_plan(odooCreate(), <Object?>[]), isEmpty);
      expect(_plan(odooCreate(), {'name': 'odoo.exceptions.UserError'}, status: 422), isEmpty);
      expect(_plan(odooCreate(), [1], status: 500), isEmpty);
      expect(_plan(odooCreate(), {'jsonrpc': '2.0', 'id': 1, 'error': {'code': 200}}), isEmpty);
    });

    test('unlink asked for on a request that is not an Odoo create is skipped with the reason', () {
      final draft = _plan(createRequest(), {'id': 4}, settings: const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink)).single;

      expect(draft.state, CleanupState.skipped);
      expect(draft.reason, contains('not an Odoo create'));
      expect(draft.plan.request, isNull);
    });

    test('an Odoo unlink cannot take a text id', () {
      final draft = _plan(odooCreate(), {'id': 'abc'}, settings: const CleanupSettings(enabled: true, idPath: 'id')).single;

      expect(draft.state, CleanupState.skipped);
      expect(draft.reason, contains('numbers'));
    });
  });

  group('the REST undo', () {
    test('a POST that answers with an id is undone with a DELETE of the URL plus the id', () {
      final request = createRequest(
        url: '{{baseUrl}}/partners?notify=1',
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}'), KeyValueItem(key: 'Content-Type', value: 'application/json')],
      );
      final draft = _plan(request, {'id': 9, 'name': 'Ann', 'address': {'city': 'Dhaka'}}).single;

      final undo = draft.plan.request!;
      expect(draft.plan.kind, CleanupUndo.restDelete);
      expect(undo.method, HttpMethod.delete);
      expect(undo.url, '{{baseUrl}}/partners/9');
      expect(undo.body.type, BodyType.none);
      expect([for (final h in undo.headers) h.key], ['Authorization'], reason: 'a DELETE has no body to describe');
      expect(draft.plan.summary, 'DELETE {{baseUrl}}/partners/9');
      expect(draft.ids, [9]);
    });

    test('the id of the answer is where the person said it is', () {
      final settings = const CleanupSettings(enabled: true, idPath: 'data.id');
      final draft = _plan(createRequest(), {'id': 1, 'data': {'id': 55}}, settings: settings).single;

      expect(draft.plan.request!.url, '{{baseUrl}}/partners/55');
    });

    test('several records are several DELETEs, one per id, in the order the server listed them', () {
      final drafts = _plan(createRequest(), [{'id': 3}, {'id': 4}, {'id': 5}]);

      expect([for (final d in drafts) d.plan.request!.url], ['{{baseUrl}}/partners/3', '{{baseUrl}}/partners/4', '{{baseUrl}}/partners/5']);
      expect([for (final d in drafts) d.variables['created.id']], ['3', '4', '5']);
    });

    test('a credential in the query is carried to the delete, other parameters are not', () {
      final request = createRequest(
        url: '{{baseUrl}}/partners?api_key=K-123&notify=1',
        queryParams: [KeyValueItem(key: 'token', value: '{{token}}'), KeyValueItem(key: 'page', value: '2')],
      );
      final undo = _plan(request, {'id': 9}).single.plan.request!;

      expect(undo.url, '{{baseUrl}}/partners/9');
      expect({for (final p in undo.queryParams) p.key: p.value}, {'token': '{{token}}', 'api_key': 'K-123'});
    });

    test('the summary hides a password written into the URL', () {
      final draft = _plan(createRequest(url: 'https://bob:hunter2@api.test/partners'), {'id': 1}).single;

      expect(draft.plan.summary, isNot(contains('hunter2')));
      expect(draft.plan.summary, startsWith('DELETE https://bob:'));
    });

    test('automatic cleanup only guesses for a POST, and not from a JSON-RPC envelope on an unknown URL', () {
      final put = _plan(createRequest(method: HttpMethod.put, url: '{{baseUrl}}/partners/1'), {'id': 1}).single;
      expect(put.state, CleanupState.skipped);
      expect(put.reason, contains('POST'));

      final rpc = _plan(createRequest(url: '{{odooUrl}}/jsonrpc'), {'jsonrpc': '2.0', 'id': 1, 'result': 8}).single;
      expect(rpc.state, CleanupState.skipped);

      final chosen = _plan(
        createRequest(method: HttpMethod.put, url: '{{baseUrl}}/partners/1'),
        {'id': 1},
        settings: const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete),
      ).single;
      expect(chosen.state, CleanupState.pending, reason: 'when the person chose, it is not guessed');
      expect(chosen.plan.request!.url, '{{baseUrl}}/partners/1/1');
    });
  });

  group('another request as the undo', () {
    const viaRequest = CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Partners/Delete partner');

    test('is sent later with the created id, ids and fields as variables, on top of the run\'s data row', () {
      final draft = _plan(createRequest(), {'id': 9, 'name': 'Ann'}, settings: viaRequest, data: {'region': 'eu'}).single;

      expect(draft.plan.kind, CleanupUndo.request);
      expect(draft.plan.request, isNull, reason: 'looked up by name when it is sent');
      expect(draft.plan.undoRequest, 'Partners/Delete partner');
      expect(draft.plan.collectionId, 3);
      expect(draft.plan.summary, 'Send "Partners/Delete partner" with {{created.id}} = 9');
      expect(draft.variables, {
        'region': 'eu',
        'created.id': '9',
        'created.ids': '9',
        'created.count': '1',
        'created.name': 'Ann',
      });
    });

    test('for a bulk create it gets all the ids at once', () {
      final draft = _plan(odooCreate(), [5, 6], settings: viaRequest).single;

      expect(draft.ids, [5, 6]);
      expect(draft.variables['created.id'], '5');
      expect(draft.variables['created.ids'], '5,6');
      expect(draft.plan.summary, 'Send "Partners/Delete partner" with {{created.ids}} = 5, 6');
    });

    test('without a request named it is skipped, saying what to do', () {
      final draft = _plan(createRequest(), {'id': 9}, settings: const CleanupSettings(enabled: true, undo: CleanupUndo.request)).single;

      expect(draft.state, CleanupState.skipped);
      expect(draft.reason, contains('Choose the request'));
    });
  });

  group('when no id can be read', () {
    test('a success with no id in it is kept as a skipped entry that says where it looked', () {
      final draft = _plan(createRequest(), {'ok': true}).single;

      expect(draft.state, CleanupState.skipped);
      expect(draft.reason, contains('id, data.id, result.id and result'));
      expect(draft.ids, isEmpty);
    });

    test('so is a body that is not JSON, and a path that leads nowhere', () {
      expect(_plan(createRequest(), '<html>created</html>').single.state, CleanupState.skipped);
      final missing = _plan(createRequest(), {'id': 1}, settings: const CleanupSettings(enabled: true, idPath: 'data.id')).single;
      expect(missing.state, CleanupState.skipped);
      expect(missing.reason, 'Nothing at "data.id" in the response.');
    });

    test('a request with cleanup off, or one that failed, leaves nothing in the ledger', () {
      expect(_plan(createRequest(), {'id': 1}, settings: CleanupSettings.none), isEmpty);
      expect(_plan(createRequest(), {'id': 1}, status: 404), isEmpty);
      expect(_plan(createRequest(), {'id': 1}, status: 302), isEmpty);
    });
  });

  group('the variables an undo request is sent with', () {
    test('are the first id, all ids, the count and the fields of the response', () {
      final vars = CreatedVariables.build(
        const CreatedIds([8, 9], 'id'),
        {'id': 8, 'name': 'Ann', 'paid': true, 'tags': ['a', 'b'], 'address': {'city': 'Dhaka', 'geo': {'lat': 23.7}}, 'note': null},
      );

      expect(vars, {
        'created.id': '8',
        'created.ids': '8,9',
        'created.count': '2',
        'created.name': 'Ann',
        'created.paid': 'true',
        'created.tags.0': 'a',
        'created.tags.1': 'b',
        'created.address.city': 'Dhaka',
        'created.address.geo.lat': '23.7',
      });
    });

    test('the created id wins over a field of the same name, and a plain id gives only the three', () {
      expect(CreatedVariables.build(const CreatedIds([5], 'data.id'), {'created': {'id': 99}}).keys, ['created.created.id', 'created.id', 'created.ids', 'created.count']);
      expect(CreatedVariables.build(const CreatedIds([42], 'the result'), [42]), {'created.id': '42', 'created.ids': '42', 'created.count': '1'});
    });

    test('a value that holds {{...}} is left out, so a response cannot make the undo read a variable it never named', () {
      final vars = CreatedVariables.build(const CreatedIds([1], 'id'), {'id': 1, 'note': 'see {{odooApiKey}}', 'name': 'ok'});

      expect(vars.containsKey('created.note'), isFalse);
      expect(vars['created.name'], 'ok');
    });

    test('a field whose name no variable could have is left out; a huge response is capped', () {
      final vars = CreatedVariables.build(const CreatedIds([1], 'id'), {'a b': 1, 'ok-name': 2, 'x}y': 3});
      expect(vars['created.ok-name'], '2');
      expect(vars.keys.where((k) => k.contains(' ') || k.contains('}')), isEmpty);

      final many = CreatedVariables.build(const CreatedIds([1], 'id'), {for (var i = 0; i < 500; i++) 'f$i': i});
      expect(many.length, CreatedVariables.maxFields + 3);
      final deep = CreatedVariables.build(const CreatedIds([1], 'id'), {'a': {'b': {'c': {'d': {'e': 1}}}}});
      expect(deep.containsKey('created.a.b.c.d.e'), isFalse, reason: 'four levels deep at most');
    });
  });

  group('the settings', () {
    test('an untouched request stores nothing, and a configured one reads back what was stored', () {
      expect(CleanupSettings.none.toJson(), isEmpty);
      expect(CleanupSettings.none.isEmpty, isTrue);

      const configured = CleanupSettings(enabled: true, idPath: ' data.id ', undo: CleanupUndo.request, request: ' Partners/Delete ');
      expect(configured.toJson(), {'enabled': true, 'idPath': 'data.id', 'undo': 'request', 'request': 'Partners/Delete'});
      expect(CleanupSettings.fromJson(configured.toJson()), configured);
      expect(CleanupSettings.fromJson(configured.toJson()).effectiveIdPath, 'data.id');
    });

    test('damaged or unknown stored values fall back instead of failing', () {
      expect(CleanupSettings.fromJson(null), CleanupSettings.none);
      expect(CleanupSettings.fromJson('x'), CleanupSettings.none);
      expect(CleanupSettings.fromJson({'enabled': 'yes', 'undo': 'teleport', 'idPath': 3, 'request': []}), CleanupSettings.none);
      expect(CleanupSettings.fromJson({'enabled': true, 'undo': 'odooUnlink'}), const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink));
    });

    test('turning it off keeps what was set up, but stores no more than the choices', () {
      const off = CleanupSettings(idPath: 'data.id', undo: CleanupUndo.restDelete);
      expect(off.toJson(), {'idPath': 'data.id', 'undo': 'restDelete'});
      expect(off.isEmpty, isFalse);
    });

    test('they live under flow.cleanup of the request settings, with no new column', () {
      const settings = RequestSettings(flow: FlowSettings(cleanup: CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink)));

      expect(settings.toJson(), {
        'flow': {
          'cleanup': {'enabled': true, 'undo': 'odooUnlink'},
        },
      });
      expect(RequestSettings.decode(settings.encode()), settings);
      expect(RequestSettings.decode(settings.encode()).flow.cleanup.enabled, isTrue);
      expect(const RequestSettings().toJson(), isEmpty, reason: 'a request without cleanup adds no key');
      expect(const FlowSettings().toJson(), isEmpty);
    });

    test('cleanup survives the other flow settings being edited, and the overrides being reset', () {
      const flow = FlowSettings(cleanup: CleanupSettings(enabled: true));
      final edited = flow.copyWith(alwaysRun: true);
      expect(edited.cleanup.enabled, isTrue);
      expect(edited.alwaysRun, isTrue);
      expect(const RequestSettings(timeoutSeconds: 5, flow: flow).withoutOverrides().flow.cleanup.enabled, isTrue);
    });
  });

  group('suggesting it', () {
    test('an Odoo create is recognised from its URL alone', () {
      final suggestion = CleanupSuggester.suggest(odooCreate(), CleanupSettings.none)!;

      expect(suggestion.title, 'Odoo create detected: delete with unlink');
      expect(suggestion.settings, const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink));
    });

    test('a REST create is recognised by its answer, and the path is written down only when it is not id', () {
      final plain = CleanupSuggester.suggest(createRequest(), CleanupSettings.none, lastBody: '{"id": 4}', lastStatus: 201)!;
      expect(plain.settings, const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete));
      expect(plain.title, contains('REST create detected'));

      final nested = CleanupSuggester.suggest(createRequest(), CleanupSettings.none, lastBody: '{"data": {"id": 4}}', lastStatus: 200)!;
      expect(nested.settings.idPath, 'data.id');
    });

    test('nothing is suggested for a GET, an unsent POST, a failed one, or once it is set up', () {
      expect(CleanupSuggester.suggest(createRequest(method: HttpMethod.get), CleanupSettings.none, lastBody: '{"id": 4}', lastStatus: 200), isNull);
      expect(CleanupSuggester.suggest(createRequest(), CleanupSettings.none), isNull);
      expect(CleanupSuggester.suggest(createRequest(), CleanupSettings.none, lastBody: '{"id": 4}', lastStatus: 500), isNull);
      expect(CleanupSuggester.suggest(createRequest(), CleanupSettings.none, lastBody: '{"ok": true}', lastStatus: 200), isNull);
      expect(CleanupSuggester.suggest(odooCreate(), const CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink)), isNull);
      expect(CleanupSuggester.suggest(odooCreate(), const CleanupSettings(enabled: true)), isNull, reason: 'automatic already does it');
      expect(CleanupSuggester.suggest(odooCreate(name: 'Search', body: null).copyWith(url: '{{odooUrl}}/json/2/res.partner/search_read'), CleanupSettings.none), isNull);
    });

    test('it is offered again when cleanup is set up but switched off', () {
      expect(CleanupSuggester.suggest(odooCreate(), const CleanupSettings(undo: CleanupUndo.odooUnlink)), isNotNull);
    });
  });

  group('running a cleanup', () {
    CleanupEntry entry(int id, {CleanupState state = CleanupState.pending, String name = 'Create'}) => CleanupEntry(
          id: id,
          requestName: '$name $id',
          environment: 'Staging',
          createdAt: _now,
          ids: [id * 10],
          plan: CleanupPlan(kind: CleanupUndo.restDelete, summary: 'DELETE /items/${id * 10}', collectionId: 3, request: createRequest(id: 0)),
          variables: const {},
          state: state,
        );

    test('goes from the last record created to the first', () async {
      final sender = _FakeSender();

      final run = await CleanupExecutor.run([entry(1), entry(3), entry(2)], sender);

      expect(sender.sent, [3, 2, 1]);
      expect([for (final r in run.results) r.entry.id], [3, 2, 1]);
      expect(run.deleted, 3);
      expect(run.failed, 0);
    });

    test('one that fails is reported with its reason and does not stop the others', () async {
      final sender = _FakeSender(fail: {2: 'HTTP 404: no such record'}, throwOn: {4});
      final heard = <int>[];

      final run = await CleanupExecutor.run([entry(1), entry(2), entry(3), entry(4)], sender, onResult: (r) => heard.add(r.entry.id));

      expect(sender.sent, [4, 3, 2, 1], reason: 'every entry is tried');
      expect(heard, [4, 3, 2, 1]);
      expect({for (final r in run.results) r.entry.id: r.state}, {
        4: CleanupState.failed,
        3: CleanupState.deleted,
        2: CleanupState.failed,
        1: CleanupState.deleted,
      });
      expect(run.results.firstWhere((r) => r.entry.id == 2).reason, 'HTTP 404: no such record');
      expect(run.results.firstWhere((r) => r.entry.id == 4).reason, contains('send blew up'));
      expect(run.deleted, 2);
      expect(run.failed, 2);
    });

    test('an entry that cannot be prepared fails on its own; a throw while preparing is a failure, not a crash', () async {
      final sender = _FakeSender(cannotPrepare: {3: 'Created in "Staging"; the active environment is "Production".'}, throwWhenPreparing: {2});

      final run = await CleanupExecutor.run([entry(1), entry(2), entry(3)], sender);

      expect(sender.sent, [1], reason: 'the others still went');
      expect(run.results.map((r) => r.state), [CleanupState.failed, CleanupState.failed, CleanupState.deleted]);
      expect(run.results[0].reason, contains('active environment'));
      expect(run.results[1].reason, contains('prepare blew up'));
    });

    test('a failure with a secret in its text is masked before it is kept', () async {
      final sender = _FakeSender(throwText: 'could not reach https://bob:hunter2@api.test/items/10?api_key=SECRETVALUE99');

      final run = await CleanupExecutor.run([entry(1)], sender);

      final reason = run.results.single.reason!;
      expect(reason, isNot(contains('hunter2')));
      expect(reason, isNot(contains('SECRETVALUE99')));
    });

    test('a network failure is told by its one-line summary', () async {
      final sender = _FakeSender(throwError: const NetworkException('SocketException: Connection refused (OS Error)', kind: NetworkErrorKind.connectionError, summary: "Couldn't reach api.test"));

      final run = await CleanupExecutor.run([entry(1)], sender);

      expect(run.results.single.reason, "Couldn't reach api.test");
    });

    test('entries that are already deleted or skipped are left alone; failed and pending ones are tried', () async {
      final sender = _FakeSender();

      final run = await CleanupExecutor.run([
        entry(1, state: CleanupState.deleted),
        entry(2, state: CleanupState.skipped),
        entry(3, state: CleanupState.failed),
        entry(4),
      ], sender);

      expect(sender.sent, [4, 3]);
      expect(run.results, hasLength(2));
    });

    test('the gate sees every request that will go out, once, before the first one is sent', () async {
      final sender = _FakeSender();
      final seen = <List<String>>[];

      await CleanupExecutor.run([entry(1), entry(2)], sender, gate: (requests) async {
        seen.add([for (final r in requests) r.url]);
        expect(sender.sent, isEmpty, reason: 'nothing has gone yet');
        return true;
      });

      expect(seen, hasLength(1));
      expect(seen.single, hasLength(2));
      expect(sender.sent, [2, 1]);
    });

    test('a gate that says no (the production warning was declined) sends nothing and changes nothing', () async {
      final sender = _FakeSender();

      final run = await CleanupExecutor.run([entry(1), entry(2)], sender, gate: (_) async => false);

      expect(run.declined, isTrue);
      expect(run.results, isEmpty);
      expect(sender.sent, isEmpty);
    });

    test('with nothing to delete there is nothing to ask and nothing to send', () async {
      final sender = _FakeSender();
      var asked = false;

      final run = await CleanupExecutor.run([entry(1, state: CleanupState.deleted)], sender, gate: (_) async => asked = true);

      expect(run.results, isEmpty);
      expect(run.declined, isFalse);
      expect(asked, isFalse);
    });

    test('entries that cannot be prepared are not shown to the gate', () async {
      final sender = _FakeSender(cannotPrepare: {1: 'gone'});
      var asked = false;

      final run = await CleanupExecutor.run([entry(1)], sender, gate: (_) async => asked = true);

      expect(asked, isFalse);
      expect(run.results.single.state, CleanupState.failed);
    });
  });
}

final class _FakeSender implements CleanupSender {
  final Map<int, String> fail;
  final Set<int> throwOn;
  final Map<int, String> cannotPrepare;
  final Set<int> throwWhenPreparing;
  final String? throwText;
  final Object? throwError;
  final List<int> sent = [];

  _FakeSender({
    this.fail = const {},
    this.throwOn = const {},
    this.cannotPrepare = const {},
    this.throwWhenPreparing = const {},
    this.throwText,
    this.throwError,
  });

  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) async {
    if (throwWhenPreparing.contains(entry.id)) throw StateError('prepare blew up');
    final why = cannotPrepare[entry.id];
    if (why != null) return CleanupPrepared.failed(entry, why);
    return CleanupPrepared.ready(entry, entry.plan.request!);
  }

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) async {
    final id = prepared.entry.id;
    sent.add(id);
    if (throwText != null) throw StateError(throwText!);
    if (throwError != null) throw throwError!;
    if (throwOn.contains(id)) throw StateError('send blew up');
    final why = fail[id];
    return why == null ? CleanupResult(prepared.entry, CleanupState.deleted) : CleanupResult(prepared.entry, CleanupState.failed, why);
  }
}
