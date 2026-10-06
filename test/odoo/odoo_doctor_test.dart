import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/data/odoo_doctor.dart';
import 'package:postpilot/features/odoo/data/odoo_error_doctor.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_diagnosis.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_error_parser.dart';
import 'support/fake_odoo.dart';

/// An error as Odoo's JSON-2 API sends it.
OdooErrorInfo _error(String name, String message) =>
    OdooErrorParser.parse(jsonEncode({'name': name, 'message': message, 'arguments': [message], 'debug': 'Traceback (most recent call last):\n$name: $message'}), statusCode: 403)!;

const _modelAccess = "You are not allowed to modify 'Contact' (res.partner) records.\n\n"
    'This operation is allowed for the following groups:\n\t- Contact Creation\n\t- Administration/Settings\n\n'
    'Contact your administrator to request access if necessary.';

void main() {
  group('what an error says, in plain words', () {
    test('an access right names the model, the operation and the groups that may', () {
      final e = _error('odoo.exceptions.AccessError', _modelAccess);
      expect(e.title, 'Access denied');
      final d = e.diagnosis!;
      expect(d.kind, OdooErrorKind.accessModel);
      expect((d.model, d.modelLabel, d.operation), ('res.partner', 'Contact', 'write'));
      expect(d.groups, ['Contact Creation', 'Administration/Settings']);
      expect(e.hint, contains('Contact (res.partner)'));
      expect(e.hint, contains('modify'));
      expect(e.hint, contains('Contact Creation, Administration/Settings'));
      expect(e.hint, contains('ir.model.access'));
    });

    test('each operation is told apart', () {
      OdooDiagnosis d(String verb) => _error('odoo.exceptions.AccessError', "You are not allowed to $verb 'Contact' (res.partner) records.").diagnosis!;
      expect(d('access').operation, 'read');
      expect(d('create').operation, 'create');
      expect(d('delete').operation, 'unlink');
      expect(d('modify').operation, 'write');
      expect(d('delete').operationWords, 'delete');
    });

    test('a record rule is not an access right: the records are hidden, not the model', () {
      final e = _error(
        'odoo.exceptions.AccessError',
        "Due to security restrictions, you are not allowed to access 'Contact' (res.partner) records.\n\nRecords: Azure Interior (id=2)\n\nUser: 7\n\nContact your administrator to request access if necessary.",
      );
      final d = e.diagnosis!;
      expect(d.kind, OdooErrorKind.accessRule);
      expect(d.model, 'res.partner');
      expect(d.userId, 7);
      expect(e.hint, contains('record rule'));
      expect(e.hint, contains('another company'));
      final old = _error('odoo.exceptions.AccessError', "Uh-oh! Looks like you have stumbled upon some top-secret records.\n\nSorry, Mitchell Admin (id=2) doesn't have 'write' access to:\n- Contact (res.partner)\n\nIf you really, really need access, perhaps you can win over your friendly administrator.");
      expect(old.diagnosis!.kind, OdooErrorKind.accessRule);
      expect(old.diagnosis!.operation, 'write');
      expect(old.diagnosis!.model, 'res.partner');
    });

    test('a record that does not exist names the ids and says what an id from another database does', () {
      final e = _error('odoo.exceptions.MissingError', 'Record does not exist or has been deleted.\n(Record: res.partner(999999,), User: 2)');
      expect(e.title, 'Record not found');
      final d = e.diagnosis!;
      expect((d.kind, d.model, d.recordIds, d.userId), (OdooErrorKind.missingRecord, 'res.partner', [999999], 2));
      expect(e.hint, contains('Record 999999 of res.partner does not exist'));
      expect(e.hint, contains('{{xmlid:module.name}}'));
    });

    test('a missing required field, in the words of every Odoo version', () {
      final orm = _error('odoo.exceptions.ValidationError', "Missing required value for the field 'Name' (name)");
      expect(orm.title, 'Missing required field');
      expect((orm.diagnosis!.field, orm.diagnosis!.fieldLabel), ('name', 'Name'));
      expect(orm.hint, contains('Add "name" to the values you send'));

      final older = _error('odoo.exceptions.ValidationError',
          'The operation cannot be completed:\n- Create/update: a mandatory field is not set.\n- Delete: another model requires the record being deleted. If possible, archive it instead.\n\nModel: Contact (res.partner), Field: Name (name)');
      expect((older.diagnosis!.kind, older.diagnosis!.model, older.diagnosis!.field), (OdooErrorKind.missingRequired, 'res.partner', 'name'));

      final pg = _error('psycopg2.errors.NotNullViolation', 'null value in column "name" of relation "res_partner" violates not-null constraint\nDETAIL:  Failing row contains (5, null).');
      expect(pg.diagnosis!.kind, OdooErrorKind.missingRequired);
      expect(pg.diagnosis!.field, 'name');
    });

    test('a unique constraint names the field and the value that is taken', () {
      final pg = _error('psycopg2.errors.UniqueViolation', 'duplicate key value violates unique constraint "res_users_login_key"\nDETAIL:  Key (login)=(admin) already exists.');
      final d = pg.diagnosis!;
      expect((d.kind, d.field, d.value), (OdooErrorKind.unique, 'login', 'admin'));
      expect(pg.title, 'Value already exists');
      expect(pg.hint, contains('login = admin'));
      final orm = _error('odoo.exceptions.ValidationError', "The value for the field 'email' already exists (this is probably 'Email' in the current model).");
      expect((orm.diagnosis!.kind, orm.diagnosis!.field), (OdooErrorKind.unique, 'email'));
      final several = _error('odoo.exceptions.ValidationError', "The values for the fields 'a, b' already exist (they are probably 'A, B' in the current model).");
      expect(several.diagnosis!.field, isNull, reason: 'two fields are not one');
      expect(several.hint, contains('a, b'));
    });

    test('a foreign key is either a record in use or an id that does not exist', () {
      final inUse = _error('psycopg2.errors.ForeignKeyViolation', 'update or delete on table "res_partner" violates foreign key constraint "res_users_partner_id_fkey" on table "res_users"\nDETAIL:  Key (id)=(3) is still referenced from table "res_users".');
      expect((inUse.title, inUse.diagnosis!.kind), ('Record is in use', OdooErrorKind.foreignKey));
      expect(inUse.hint, contains('Archive it instead'));
      final missing = _error('psycopg2.errors.ForeignKeyViolation', 'insert or update on table "res_partner" violates foreign key constraint "res_partner_parent_id_fkey"\nDETAIL:  Key (parent_id)=(9999) is not present in table "res_partner".');
      expect(missing.title, 'Unknown referenced record');
      expect((missing.diagnosis!.field, missing.diagnosis!.recordIds), ('parent_id', [9999]));
    });

    test('an unknown field, a wrong selection value and a bad date', () {
      final field = _error('builtins.ValueError', "Invalid field 'nmae' on model 'res.partner'");
      expect((field.title, field.diagnosis!.field, field.diagnosis!.model), ('Unknown field', 'nmae', 'res.partner'));
      final leaf = _error('builtins.ValueError', "Invalid field res.partner.nmae in leaf ('nmae', '=', 1)");
      expect((leaf.diagnosis!.model, leaf.diagnosis!.field), ('res.partner', 'nmae'));
      final selection = _error('builtins.ValueError', "Wrong value for res.partner.type: 'banana'");
      expect((selection.title, selection.diagnosis!.field, selection.diagnosis!.value), ('Invalid value', 'type', 'banana'));
      final date = _error('builtins.ValueError', "time data '06/10/2026' does not match format '%Y-%m-%d'");
      expect(date.hint, contains('YYYY-MM-DD'));
    });

    test('a constraint and a business rule keep their titles and tell what kind of refusal it is', () {
      expect(_error('odoo.exceptions.ValidationError', 'The end date must be after the start date.').title, 'Validation failed');
      expect(_error('odoo.exceptions.ValidationError', 'The end date must be after the start date.').hint, contains('@api.constrains'));
      expect(_error('odoo.exceptions.UserError', 'You cannot delete a posted invoice.').title, 'Rejected by a business rule');
      expect(_error('odoo.exceptions.UserError', 'You cannot delete a posted invoice.').hint, contains('state of the record'));
    });

    test('what is not one of these keeps the generic explanation', () {
      expect(_error('builtins.RuntimeError', 'boom').diagnosis, isNull);
      expect(_error('werkzeug.exceptions.Unauthorized', 'Invalid apikey').title, 'Invalid API key');
      expect(_error('werkzeug.exceptions.Unauthorized', 'Invalid apikey').diagnosis, isNull);
    });
  });

  group('looking into it on the live server', () {
    late FakeOdoo odoo;
    late OdooClient client;
    late OdooErrorDoctor doctor;
    late OdooConnection connection;

    setUp(() {
      odoo = FakeOdoo();
      odoo.records['ir.model.access'] = [
        {'id': 1, 'name': 'access_res_partner_manager', 'model_id.model': 'res.partner', 'group_id': [11, 'Contact Creation'], 'perm_read': true, 'perm_write': true, 'perm_create': true, 'perm_unlink': false, 'active': true},
        {'id': 2, 'name': 'access_res_partner_user', 'model_id.model': 'res.partner', 'group_id': [12, 'Sales / User: Own Documents Only'], 'perm_read': true, 'perm_write': false, 'perm_create': false, 'perm_unlink': false, 'active': true},
        {'id': 3, 'name': 'access_res_partner_public', 'model_id.model': 'res.partner', 'group_id': false, 'perm_read': true, 'perm_write': false, 'perm_create': false, 'perm_unlink': false, 'active': true},
        {'id': 4, 'name': 'access_other', 'model_id.model': 'res.country', 'group_id': [12, 'x'], 'perm_read': true, 'perm_write': true, 'perm_create': true, 'perm_unlink': true, 'active': true},
      ];
      odoo.records['res.groups'] = [
        {'id': 11, 'display_name': 'Contact Creation', 'users': [7]},
        {'id': 12, 'display_name': 'Sales / User: Own Documents Only', 'users': [2, 7]},
      ];
      odoo.records['ir.rule'] = [
        {'id': 1, 'name': 'res.partner company', 'model_id.model': 'res.partner', 'domain_force': "['|', ('company_id', '=', False), ('company_id', 'in', company_ids)]", 'global': true, 'groups': <int>[], 'perm_read': true, 'perm_write': true, 'perm_create': true, 'perm_unlink': true},
        {'id': 2, 'name': 'res.partner read only', 'model_id.model': 'res.partner', 'domain_force': '[("id", "=", 1)]', 'global': false, 'groups': [12], 'perm_read': true, 'perm_write': false, 'perm_create': false, 'perm_unlink': false},
      ];
      client = OdooClient(odoo);
      doctor = OdooErrorDoctor(client.call, client.schema);
      connection = OdooConnection(baseUrl: odoo.host, database: odoo.db, apiKey: odoo.apiKey);
    });

    void expectOnlyReads() {
      expect(odoo.writes, isEmpty);
      for (final call in odoo.calls) {
        expect(OdooErrorDoctor.readOnlyMethods, contains(call.split('.').last), reason: call);
      }
    }

    test('an access right: which groups may, which groups the user is in, and who to add where', () async {
      final report = await doctor.investigate(connection, _error('odoo.exceptions.AccessError', _modelAccess), userId: 2);

      expect(report.facts, [
        'res.partner has 3 access lines; these groups may modify its records: Contact Creation.',
        'User 2 is in 1 group: Sales / User: Own Documents Only.',
      ]);
      expect(report.steps, ['Add user 2 to one of: Contact Creation (Settings, Users & Companies, Users).']);
      expect(report.notice, isNull);
      expectOnlyReads();
    });

    test('a user who already has a group that grants it is told the cause is elsewhere', () async {
      final report = await doctor.investigate(connection, _error('odoo.exceptions.AccessError', _modelAccess), userId: 7);

      expect(report.facts.last, contains('already in a group that grants this'));
      expect(report.steps, isEmpty);
      expectOnlyReads();
    });

    test('without a user it still lists the groups to choose from', () async {
      final report = await doctor.investigate(connection, _error('odoo.exceptions.AccessError', _modelAccess));
      expect(report.steps, ['Add the API user to one of: Contact Creation (Settings, Users & Companies, Users).']);
    });

    test('a user who may not read ir.model.access is told so and who can', () async {
      odoo.deniedModels.add('ir.model.access');
      final report = await doctor.investigate(connection, _error('odoo.exceptions.AccessError', _modelAccess), userId: 2);

      expect(report.notice, allOf(contains('may not read ir.model.access'), contains('Settings, Technical, Security, Access Rights')));
      expect(report.steps, isEmpty);
      expectOnlyReads();
    });

    test('a read right that nobody has is said so', () async {
      final report = await doctor.investigate(connection, _error('odoo.exceptions.AccessError', "You are not allowed to delete 'Contact' (res.partner) records."), userId: 2);
      expect(report.facts.first, contains('none of them lets anyone delete its records'));
      expect(report.steps.single, contains('Delete box ticked'));
    });

    test('a record rule lists the rules of the model that apply to the operation', () async {
      final report = await doctor.investigate(
        connection,
        _error('odoo.exceptions.AccessError', "Due to security restrictions, you are not allowed to access 'Contact' (res.partner) records.\n\nRecords: Azure Interior (id=2)\n\nUser: 2"),
      );
      expect(report.facts.first, 'Record rules of res.partner that apply to reading:');
      expect(report.facts, contains(contains('res.partner company: [')));
      expect(report.facts, contains(contains('(every user)')));
      expect(report.facts.where((f) => f.contains('only for some groups')), hasLength(1));
      expectOnlyReads();
    });

    test('a missing required field lists the required ones and which Odoo fills in', () async {
      final report = await doctor.investigate(connection, _error('odoo.exceptions.ValidationError', "Missing required value for the field 'Name' (name)"), model: 'res.partner');
      expect(report.facts.first, 'Required on res.partner: name (char).');
      expect(report.steps, ['Send a value for: name.']);
      expectOnlyReads();
    });

    test('a duplicate value finds the record that holds it and says to update that one', () async {
      final report = await doctor.investigate(
        connection,
        _error('psycopg2.errors.UniqueViolation', 'duplicate key value violates unique constraint "res_partner_email_key"\nDETAIL:  Key (email)=(azure@example.com) already exists.'),
        model: 'res.partner',
      );
      expect(report.facts.single, 'email = azure@example.com is already used by: 2 (Azure Interior).');
      expect(report.steps.single, 'Update that record instead: write to id 2.');
    });

    test('ids that do not exist are told from the ones that do', () async {
      final report = await doctor.investigate(
        connection,
        _error('odoo.exceptions.MissingError', 'Record does not exist or has been deleted.\n(Record: res.partner(999999, 3), User: 2)'),
      );
      expect(report.facts, ['Still exist (for this user): 3.', 'Do not exist: 999999.']);
      expect(report.steps.single, contains('{{ref:res.partner:name}}'));
      expectOnlyReads();
    });

    test('an unknown field comes with the nearest real ones, a wrong selection value with the allowed ones', () async {
      final unknown = await doctor.investigate(connection, _error('builtins.ValueError', "Invalid field 'nmae' on model 'res.partner'"));
      expect(unknown.facts.single, 'Fields of res.partner that look like "nmae": name.');
      final selection = await doctor.investigate(connection, _error('builtins.ValueError', "Wrong value for res.partner.type: 'banana'"));
      expect(selection.facts.single, 'Allowed values of type: contact (Contact), invoice (Invoice Address), delivery (Delivery Address), other (Other Address).');
    });

    test('an error the doctor does not know, or no connection, gets nothing invented', () async {
      expect((await doctor.investigate(connection, _error('builtins.RuntimeError', 'boom'))).isEmpty, isTrue);
      final offline = await doctor.investigate(const OdooConnection(baseUrl: '', apiKey: ''), _error('odoo.exceptions.AccessError', _modelAccess));
      expect(offline.notice, contains('Connect Odoo Studio'));
      expect(odoo.requests, isEmpty);
    });

    test('it never writes, whatever it is asked about', () async {
      final errors = [
        _error('odoo.exceptions.AccessError', _modelAccess),
        _error('odoo.exceptions.AccessError', "Due to security restrictions, you are not allowed to access 'Contact' (res.partner) records."),
        _error('odoo.exceptions.ValidationError', "Missing required value for the field 'Name' (name)"),
        _error('psycopg2.errors.UniqueViolation', 'Key (email)=(azure@example.com) already exists.'),
        _error('odoo.exceptions.MissingError', 'Record does not exist or has been deleted.\n(Record: res.partner(3,), User: 2)'),
        _error('builtins.ValueError', "Invalid field 'nmae' on model 'res.partner'"),
      ];
      for (final e in errors) {
        await doctor.investigate(connection, e, userId: 2, model: 'res.partner');
      }
      expect(odoo.calls, isNotEmpty);
      expectOnlyReads();
      expect(odoo.records['res.partner'], hasLength(4), reason: 'no record was added, changed or removed');
    });
  });

  group('the doctor of the app', () {
    test('asks the server of the active environment, and for a JSON-RPC session knows which user to look at', () async {
      final odoo = FakeOdoo();
      odoo.records['ir.model.access'] = [
        {'id': 1, 'name': 'a', 'model_id.model': 'res.partner', 'group_id': [11, 'Contact Creation'], 'perm_read': true, 'perm_write': true, 'perm_create': true, 'perm_unlink': false, 'active': true},
      ];
      odoo.records['res.groups'] = [
        {'id': 11, 'display_name': 'Contact Creation', 'users': [7]},
        {'id': 12, 'display_name': 'Internal User', 'users': [2]},
      ];
      final client = OdooClient(odoo);
      final variables = {'odooUrl': odoo.host, 'odooDb': odoo.db, 'odooProtocol': 'jsonrpc', 'odooLogin': odoo.login, 'odooPassword': odoo.password};
      // The session of the active environment is open (the Studio connection test, or any call, opened it).
      expect((await client.connect(OdooConnection.fromVariables(variables))).ok, isTrue);

      final answer = await OdooDoctor(_Environments(variables), client).diagnose(_error('odoo.exceptions.AccessError', _modelAccess));

      expect(answer.server, 'https://odoo.test');
      expect(answer.report.facts.last, 'User 2 is in 1 group: Internal User.');
      expect(answer.report.steps.single, startsWith('Add user 2 to one of: Contact Creation'));
      expect(odoo.writes, isEmpty);
    });
  });
}

final class _Environments implements EnvironmentRepository {
  final Map<String, String> variables;
  _Environments(this.variables);

  @override
  Future<Map<String, String>> getActiveVariables() async => variables;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
