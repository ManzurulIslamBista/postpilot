// The view models behind the Payload and Check tabs, against an in-process Odoo: what the form offers, the defaults,
// the lookups, a record loaded into the form, the body that comes out, the request that is saved, the checker with its
// fixes and the schema that is read once and read again on request.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_payload.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_check_view_model.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_payload_view_model.dart';
import 'package:postpilot/features/odoo/presentation/view_models/odoo_studio_view_model.dart';
import '../support/drift_repos.dart';
import 'support/fake_odoo.dart';

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late FakeOdoo odoo;
  late OdooStudioViewModel studio;

  OdooStudioViewModel studioFor(FakeOdoo server, {bool jsonRpc = false}) {
    final vm = OdooStudioViewModel(
      OdooClient(server),
      repos.environmentRepository,
      CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository),
    );
    jsonRpc
        ? vm.setConnection(url: server.host, database: server.db, apiKey: server.password, login: server.login, protocol: OdooProtocol.jsonRpc)
        : vm.setConnection(url: server.host, database: server.db, apiKey: server.apiKey);
    return vm;
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    odoo = FakeOdoo();
    studio = studioFor(odoo);
  });
  tearDown(() async {
    studio.dispose();
    await db.close();
  });

  group('the Payload tab\'s model', () {
    test('reading a model fills the form with what Odoo would give a new record', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');

      expect(vm.error, isNull);
      expect(vm.fields.first.name, 'name', reason: 'the required field first');
      expect(vm.values, {'active': true, 'type': 'contact', 'is_company': false, 'color': 0});
      expect(vm.raw['type'], 'contact');
      expect(vm.defaults, {'active', 'type', 'is_company', 'color'});
      expect(vm.missingRequired.map((f) => f.name), ['name']);
      expect(jsonDecode(vm.bodyText), {
        'vals_list': [
          {'active': true, 'type': 'contact', 'is_company': false, 'color': 0},
        ],
      });
      expect(odoo.writes, isEmpty);
      vm.dispose();
    });

    test('typing a value sets it, a wrong one is reported and left out, emptying the box takes the field out', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');

      vm.setRaw('name', 'Acme');
      vm.setRaw('credit_limit', '12.5');
      vm.setRaw('color', 'x');
      vm.setRaw('date', '2026-10-06');
      expect(vm.values['name'], 'Acme');
      expect(vm.values['credit_limit'], 12.5);
      expect(vm.values.containsKey('color'), isFalse);
      expect(vm.errors['color'], 'Enter a whole number.');
      expect(vm.hasErrors, isTrue);
      expect(vm.missingRequired, isEmpty);

      vm.setRaw('color', '4');
      expect(vm.errors, isEmpty);
      vm.setRaw('credit_limit', '');
      expect(vm.isSet('credit_limit'), isFalse);
      vm.setRaw('name', '');
      expect(vm.values['name'], '', reason: 'an empty text is a value for a text field');
      vm.unset('name');
      expect(vm.missingRequired.map((f) => f.name), ['name']);
      vm.dispose();
    });

    test('x2many commands and a many2one picked are written the way Odoo reads them', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.setRaw('name', 'Acme');
      vm.setValue('parent_id', 2, pickedName: 'Azure Interior');
      vm.setCommands('category_id', const [LinkCommand(1), SetCommand([1, 2])]);
      vm.setCommands('child_ids', const [CreateCommand({'name': 'Kid'}), ClearCommand()]);
      vm.setValue('country_id', const OdooToken('{{xmlid:base.bd}}'));

      final body = vm.bodyText;
      expect(body, contains('"country_id": {{xmlid:base.bd}}'));
      final vals = (jsonDecode(body.replaceAll('{{xmlid:base.bd}}', '20'))['vals_list'] as List).first as Map;
      expect(vals['parent_id'], 2);
      expect(vals['category_id'], [
        [4, 1],
        [6, 0, [1, 2]],
      ]);
      expect(vals['child_ids'], [
        [0, 0, {'name': 'Kid'}],
        [5, 0, 0],
      ]);
      expect(vm.pickedNames['parent_id'], 'Azure Interior');
      vm.setCommands('category_id', const []);
      expect(vm.isSet('category_id'), isFalse);
      vm.dispose();
    });

    test('a write names its ids; without them it uses the variable that stays undefined', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.setMethod('write');
      vm.setRaw('name', 'N');
      expect(vm.bodyText, contains('"ids": [{{recordId}}]'));
      expect(vm.draft!.note, contains('{{recordId}}'));
      vm.setIds('7, 8');
      expect(jsonDecode(vm.bodyText)['ids'], [7, 8]);
      expect(vm.draft!.note, isNot(contains('{{recordId}}')));
      vm.setIds('7, x');
      expect(vm.idsError, contains('"x"'));
      expect(vm.hasErrors, isTrue);
      expect(vm.path, '/json/2/res.partner/write');
      vm.dispose();
    });

    test('a record is loaded into the form: read-only fields dropped, pairs become ids, id lists become [6, 0, ids]', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.setMethod('write');

      await vm.loadRecord(2);

      expect(vm.error, isNull);
      expect(vm.idsText, '2', reason: 'a write is for the record that was loaded');
      expect(vm.values['name'], 'Azure Interior');
      expect(vm.values['country_id'], 233);
      expect(vm.pickedNames['country_id'], 'United States');
      expect([for (final c in vm.values['child_ids'] as List) (c as X2ManyCommand).toJson()], [
        [6, 0, [4]],
      ]);
      expect([for (final c in vm.values['category_id'] as List) (c as X2ManyCommand).toJson()], [
        [6, 0, [1]],
      ]);
      expect(vm.values.keys, isNot(containsAll(['id', 'display_name', 'create_date', 'commercial_partner_id'])));
      expect(vm.values.containsKey('parent_id'), isFalse, reason: 'false means nothing is set');
      expect(vm.values['credit_limit'], 1500.5);
      expect(vm.notice, startsWith('Loaded record 2 of res.partner'));
      expect(jsonDecode(vm.bodyText)['ids'], [2]);
      expect(odoo.writes, isEmpty);
      vm.dispose();
    });

    test('loading a record that does not exist says so and leaves the form alone', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.setRaw('name', 'Keep me');

      await vm.loadRecord(999);

      expect(vm.error, isNotNull);
      expect(vm.values['name'], 'Keep me');
      vm.dispose();
    });

    test('the lookups of the form: a name search, an XML-ID', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');

      expect([for (final r in await vm.searchRecords('res.country', 'ban')) (r.id, r.name)], [(20, 'Bangladesh')]);
      expect(await vm.searchRecords('res.country', '  '), isEmpty);
      expect(await vm.xmlIdOf('res.country', 20), 'base.bd');
      expect(await vm.xmlIdOf('res.partner', 2), '__export__.res_partner_2_abc', reason: 'the only one it has');
      expect(await vm.xmlIdOf('res.partner', 3), isNull);
      vm.dispose();
    });

    test('a request is made from the payload and saved into the collection, as the body shows it', () async {
      final collection = await repos.collectionRepository.createCollection('Odoo');
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.setRaw('name', 'Acme');

      final id = await vm.saveAsRequest(collection);

      expect(id, isNotNull);
      final saved = (await repos.requestRepository.findById(id!))!;
      expect(saved.name, 'Create res.partner (payload)');
      expect(saved.url, '{{odooUrl}}/json/2/res.partner/create');
      expect(saved.body.rawText, vm.bodyText);
      expect(saved.headers.map((h) => h.key), containsAll(['Authorization', 'X-Odoo-Database']));
      expect(vm.notice, 'Added "Create res.partner (payload)" to the collection.');
      vm.dispose();
    });

    test('for Odoo 18 the same payload is a call_kw request with no Authorization header', () async {
      final rpc = FakeOdoo();
      final studio18 = studioFor(rpc, jsonRpc: true);
      final collection = await repos.collectionRepository.createCollection('Odoo 18');
      final vm = OdooPayloadViewModel(studio18);
      await vm.loadModel('res.partner');
      vm.setRaw('name', 'Acme');

      expect(vm.path, '/web/dataset/call_kw/res.partner/create');
      final body = jsonDecode(vm.bodyText);
      expect(body['params']['method'], 'create');
      expect(body['params']['args'][0][0]['name'], 'Acme');

      final id = (await vm.saveAsRequest(collection))!;
      final saved = (await repos.requestRepository.findById(id))!;
      expect(saved.url, '{{odooUrl}}/web/dataset/call_kw/res.partner/create');
      expect(saved.headers.map((h) => h.key), ['Content-Type']);
      vm.dispose();
      studio18.dispose();
    });

    test('check compares the payload with the schema it came from', () async {
      final vm = OdooPayloadViewModel(studio);
      await vm.loadModel('res.partner');
      vm.check();
      expect(vm.problems!.map((p) => p.code), ['required'], reason: 'name is required and has no default');
      vm.setRaw('name', 'Acme');
      vm.check();
      expect(vm.problems, isEmpty);
      vm.dispose();
    });

    test('a connection that is not complete is asked for, nothing is sent', () async {
      final empty = OdooStudioViewModel(OdooClient(odoo), repos.environmentRepository, CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository));
      final vm = OdooPayloadViewModel(empty);
      await vm.loadModel('res.partner');
      expect(vm.error, 'Enter the server URL first.');
      expect(odoo.requests, isEmpty);
      vm.dispose();
      empty.dispose();
    });
  });

  group('the Check tab\'s model', () {
    test('checks a typed body against the live fields and applies a fix, then checks again', () async {
      final vm = OdooCheckViewModel(studio, body: '{"vals_list": [{"nmae": "A", "color": "3"}]}')..setTarget(model: 'res.partner', method: 'create');

      await vm.run();

      expect(vm.error, isNull);
      expect(vm.problems!.map((p) => p.code).toSet(), {'unknown_field', 'type', 'required'}, reason: 'the typo hides the name, which is required');
      await vm.applyFix(vm.problems!.firstWhere((p) => p.code == 'unknown_field'));
      expect(jsonDecode(vm.bodyText), {
        'vals_list': [
          {'name': 'A', 'color': '3'},
        ],
      });
      expect(vm.problems!.map((p) => p.code), ['type'], reason: 'checked again after the fix');
      expect(vm.bodyChanged, isTrue);
      await vm.applyAll();
      expect(jsonDecode(vm.bodyText)['vals_list'][0]['color'], 3);
      expect(vm.problems, isEmpty);
      vm.dispose();
    });

    test('a model that does not exist comes with the nearest names, and the fix switches to one and checks again', () async {
      final vm = OdooCheckViewModel(studio, body: '{"vals_list": [{"name": "A"}]}')..setTarget(model: 'res.partnr', method: 'create');

      await vm.run();

      expect(vm.problems!.single.code, 'model_missing');
      expect(vm.problems!.single.message, contains('"res.partner"'));
      await vm.applyFix(vm.problems!.single);
      expect(vm.model, 'res.partner');
      expect(vm.problems, isEmpty);
      vm.dispose();
    });

    test('the fields of a model are read once and again only when asked', () async {
      final vm = OdooCheckViewModel(studio, body: '{"ids": [1], "vals": {"name": "A"}}')..setTarget(model: 'res.partner', method: 'write');
      int fieldReads() => odoo.calls.where((c) => c == 'res.partner.fields_get').length;

      await vm.run();
      await vm.run();
      expect(fieldReads(), 1);

      await vm.refresh();
      expect(fieldReads(), 2);

      // Another tool asking for the same model reads nothing either.
      await studio.schema.fields(studio.connection, 'res.partner');
      expect(fieldReads(), 2);
      vm.dispose();
    });

    test('the models a body points into are read for the checks that need them, a few at most', () async {
      final vm = OdooCheckViewModel(studio, body: '{"vals_list": [{"name": "A", "category_id": [[0, 0, {"colour": 1}]]}]}')..setTarget(model: 'res.partner', method: 'create');
      await vm.run();
      expect(vm.problems!.single.message, contains('does not exist on res.partner.category'));
      expect(odoo.calls, contains('res.partner.category.fields_get'));
    });

    test('a request tab hands over its URL: the model and the method come from it', () async {
      final vm = OdooCheckViewModel(studio, url: 'https://odoo.test/json/2/res.partner/write', body: '{"ids": [1], "vals": {"emial": "x"}}');
      expect((vm.model, vm.method, vm.protocol), ('res.partner', 'write', OdooProtocol.json2));
      await vm.run();
      expect(vm.problems!.single.message, contains('Did you mean "email"'));
      vm.dispose();
    });

    test('through the JSON-RPC session of Odoo 18 the same checks run', () async {
      final rpc = FakeOdoo();
      final studio18 = studioFor(rpc, jsonRpc: true);
      final vm = OdooCheckViewModel(
        studio18,
        url: '{{odooUrl}}/web/dataset/call_kw/res.partner/write',
        body: '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "write", "args": [[7], {"nmae": "X"}], "kwargs": {}}}',
      );

      await vm.run();

      expect(vm.problems!.single.code, 'unknown_field');
      expect(rpc.authenticateCount, 1);
      await vm.applyAll();
      expect(jsonDecode(vm.bodyText)['params']['args'], [
        [7],
        {'name': 'X'},
      ]);
      vm.dispose();
      studio18.dispose();
    });

    test('a body that is not JSON is the one problem, with nothing asked of the server', () async {
      final vm = OdooCheckViewModel(studio, body: '{"vals_list": [')..setTarget(model: 'res.partner', method: 'create');
      await vm.run();
      expect(vm.problems!.single.message, startsWith('The body is not valid JSON'));
      expect(odoo.requests, isEmpty);
      vm.dispose();
    });

    test('without a server only the structure is checked, and the missing connection is said', () async {
      final empty = OdooStudioViewModel(OdooClient(odoo), repos.environmentRepository, CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository));
      final vm = OdooCheckViewModel(empty, body: '{"vals": {"name": "A"}}')..setTarget(model: 'res.partner', method: 'create');
      await vm.run();
      expect(vm.error, 'Enter the server URL and an API key first.');
      expect(vm.problems!.map((p) => p.code), contains('param_name'));
      expect(odoo.requests, isEmpty);
      vm.dispose();
      empty.dispose();
    });
  });

  group('Studio itself with either API', () {
    test('the connection test, the model list and the fields work through JSON-2 and through a session', () async {
      for (final jsonRpc in [false, true]) {
        final server = FakeOdoo();
        final vm = studioFor(server, jsonRpc: jsonRpc);
        await vm.testConnection();
        expect(vm.error, isNull, reason: 'jsonRpc=$jsonRpc');
        expect(vm.connectionOk, startsWith(jsonRpc ? 'Connected as admin · Odoo 17.0' : 'Connected · language en_US'));
        await vm.loadModels();
        expect(vm.modelNames, containsAll(['res.partner', 'res.country']));
        await vm.loadFields('res.partner');
        expect(vm.info!.field('name')!.required, isTrue);
        expect(vm.info!.field('child_ids')!.relationField, 'parent_id');
        await vm.runSearch(domain: [['is_company', '=', true]], limit: 2);
        expect(vm.rows.map((r) => r['id']), [1, 2]);
        vm.dispose();
      }
    });

    test('a wrong password is shown with its title, not as a bare server error', () async {
      final server = FakeOdoo();
      final vm = studioFor(server, jsonRpc: true)..setConnection(apiKey: 'wrong');
      await vm.testConnection();
      expect(vm.errorInfo!.title, 'Wrong login or password');
      expect(vm.error, 'Access Denied');
      vm.dispose();
    });

    test('Find databases lists them, picks the only one, and says so when the list is switched off', () async {
      final server = FakeOdoo();
      final vm = studioFor(server, jsonRpc: true)..setConnection(database: '');
      await vm.findDatabases();
      expect(vm.databases, ['prod']);
      expect(vm.database, 'prod');
      final closed = FakeOdoo()..listsDatabases = false;
      final other = studioFor(closed, jsonRpc: true)..setConnection(database: '');
      await other.findDatabases();
      expect(other.databases, isEmpty);
      expect(other.databaseNote, contains('list_db'));
      vm.dispose();
      other.dispose();
    });

    test('saving the environment of an Odoo 18 server keeps the login, the password as a secret and the protocol', () async {
      final server = FakeOdoo();
      final vm = studioFor(server, jsonRpc: true);
      final id = await vm.saveEnvironment('Legacy');
      expect(id, isNotNull);
      expect(await repos.environmentRepository.getActiveVariables(), {
        'odooUrl': 'https://odoo.test',
        'odooDb': 'prod',
        'odooProtocol': 'jsonrpc',
        'odooLogin': 'admin',
        'odooPassword': 'pw-456',
      });
      final variables = await repos.environmentRepository.watchVariables(id!).first;
      expect({for (final v in variables) v.key: v.isSecret}, {'odooUrl': false, 'odooDb': false, 'odooProtocol': false, 'odooLogin': false, 'odooPassword': true});
      // And Studio picks it up again.
      final again = OdooStudioViewModel(OdooClient(server), repos.environmentRepository, CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository));
      await again.loadFromActiveEnvironment();
      expect((again.protocol, again.login, again.apiKey), (OdooProtocol.jsonRpc, 'admin', 'pw-456'));
      vm.dispose();
      again.dispose();
    });

    test('a JSON-2 environment is still the one it was: no protocol, no login', () async {
      final vm = studioFor(odoo);
      await vm.saveEnvironment('Modern');
      expect(await repos.environmentRepository.getActiveVariables(), {'odooUrl': 'https://odoo.test', 'odooDb': 'prod', 'odooApiKey': 'key-123'});
      vm.dispose();
    });

    test('ready-made requests for Odoo 18 come with a Log in request at the top', () async {
      final vm = studioFor(odoo, jsonRpc: true);
      final result = await vm.createCollection('Legacy', ['res.partner']);
      expect(result!.requestCount, 11);
      final requests = await repos.requestRepository.watchByCollection(result.collectionId!).first;
      expect(requests.map((r) => r.name), contains('Log in to Odoo (run first)'));
      expect(requests.where((r) => r.folderId == null).map((r) => r.name), ['Log in to Odoo (run first)']);
      vm.dispose();
    });
  });
}
