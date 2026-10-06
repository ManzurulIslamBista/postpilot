// Pure Dart (no Flutter).
import '../domain/entities/odoo_connection.dart';
import '../domain/entities/odoo_result.dart';
import '../domain/services/odoo_diagnosis.dart';
import '../domain/services/odoo_error_parser.dart';
import '../domain/services/odoo_json2.dart';
import '../domain/services/odoo_names.dart';
import 'odoo_schema_service.dart';

/// What the live lookups of the doctor found out.
final class OdooDoctorReport {
  /// What the server said, one fact each ("ir.model.access lines for res.partner: ...").
  final List<String> facts;

  /// Concrete next steps that the facts made possible.
  final List<String> steps;

  /// Why the live lookup could not run or could not finish ("this user cannot read ir.model.access"); null when it did.
  final String? notice;

  const OdooDoctorReport({this.facts = const [], this.steps = const [], this.notice});

  static const empty = OdooDoctorReport();

  bool get isEmpty => facts.isEmpty && steps.isEmpty && notice == null;
}

/// Looks into an Odoo error on the live server and says what to do about it ("your user is in none of the groups that
/// may create res.partner: Contact Creation, ..."). The first part of the explanation comes from the message alone
/// (see [OdooDiagnoser]); this adds what only the server knows: the access lines of the model, the groups of the user,
/// the record rules, the required fields, the record that holds a duplicate value, the ids that still exist.
///
/// It only reads. Every call goes through one gate that accepts nothing but read methods, so no failure of the
/// doctor can change data.
final class OdooErrorDoctor {
  /// The only methods the doctor ever calls.
  static const readOnlyMethods = {'search_read', 'read', 'search_count', 'exists', 'fields_get', 'default_get', 'name_search'};

  final OdooCaller _call;
  final OdooSchemaService _schema;
  OdooErrorDoctor(this._call, this._schema);

  Future<OdooResult> _read(OdooConnection connection, OdooCall call) {
    if (!readOnlyMethods.contains(call.method)) {
      throw StateError('The error doctor only reads; "${call.method}" is not a read method.');
    }
    return _call(connection, call);
  }

  static bool _denied(OdooResult r) =>
      r.status == 403 || (r.error?.exception.endsWith('AccessError') ?? false) || (r.error?.exception.endsWith('Forbidden') ?? false);

  /// [userId] is the user the failing request ran as, when the caller knows it (the id of a JSON-RPC session); the
  /// message of an older server names it too. [model] is the model the request was for, for the messages that do not
  /// name it themselves ("Missing required value for the field 'Name' (name)").
  Future<OdooDoctorReport> investigate(OdooConnection connection, OdooErrorInfo info, {int? userId, String? model}) async {
    final d = info.diagnosis;
    if (d == null) return OdooDoctorReport.empty;
    if (!connection.isComplete) {
      return const OdooDoctorReport(notice: 'Connect Odoo Studio to the server to look this up live.');
    }
    final target = d.model ?? model;
    try {
      return switch (d.kind) {
        OdooErrorKind.accessModel => await _accessModel(connection, d, target, userId ?? d.userId),
        OdooErrorKind.accessRule => await _accessRule(connection, d, target),
        OdooErrorKind.missingRequired => await _missingRequired(connection, d, target),
        OdooErrorKind.unique => await _unique(connection, d, target),
        OdooErrorKind.missingRecord => await _missingRecord(connection, d, target),
        OdooErrorKind.invalidField => await _invalidField(connection, d, target),
        OdooErrorKind.badValue => await _badValue(connection, d, target),
        OdooErrorKind.foreignKey || OdooErrorKind.validation => OdooDoctorReport.empty,
      };
    } on Object catch (e) {
      return OdooDoctorReport(notice: 'The live lookup failed: ${e is StateError ? e.message : e}');
    }
  }

  String _noModel(String what) => 'The error does not say which model $what concerns: look it up from the request that failed.';

  Future<OdooDoctorReport> _accessModel(OdooConnection c, OdooDiagnosis d, String? model, int? userId) async {
    if (model == null) return OdooDoctorReport(notice: _noModel('the access right'));
    final operation = d.operation ?? 'read';
    final perm = 'perm_$operation';
    final access = await _read(
      c,
      OdooCall(model: 'ir.model.access', method: 'search_read', params: {
        'domain': [['model_id.model', '=', model]],
        'fields': ['name', 'group_id', 'perm_read', 'perm_write', 'perm_create', 'perm_unlink', 'active'],
      }),
    );
    if (!access.ok || access.json is! List) {
      if (_denied(access)) {
        return OdooDoctorReport(
          notice: 'This user may not read ir.model.access, so the access lines of $model cannot be looked at from here. '
              'Ask an administrator to open Settings, Technical, Security, Access Rights and filter on $model.',
        );
      }
      return OdooDoctorReport(notice: 'Could not read ir.model.access: ${access.failureText()}');
    }
    final rows = [for (final r in access.json as List) if (r is Map && r['active'] != false) r];
    final granting = [for (final r in rows) if (r[perm] == true) r];
    final groupIds = <int>{};
    final groupNames = <String>[];
    var global = false;
    for (final r in granting) {
      final g = r['group_id'];
      if (g is List && g.length >= 2 && g.first is int) {
        if (groupIds.add(g.first as int)) groupNames.add('${g[1]}');
      } else {
        global = true;
      }
    }
    final facts = <String>[
      if (rows.isEmpty)
        '$model has no access line at all: no group may use it through the API.'
      else
        '$model has ${rows.length} access line${rows.length == 1 ? '' : 's'}; '
            '${granting.isEmpty ? 'none of them lets anyone ${d.operationWords} its records' : 'these groups may ${d.operationWords} its records: ${groupNames.join(', ')}${global ? ' and every user (a line without a group)' : ''}'}.',
    ];
    final steps = <String>[];
    if (userId != null) {
      final mine = await _read(
        c,
        OdooCall(model: 'res.groups', method: 'search_read', params: {
          'domain': [['users', 'in', [userId]]],
          'fields': ['display_name'],
        }),
      );
      if (mine.ok && mine.json is List) {
        final mineRows = [for (final g in mine.json as List) if (g is Map && g['id'] is int) g];
        final mineIds = {for (final g in mineRows) g['id'] as int};
        facts.add('User $userId is in ${mineRows.length} group${mineRows.length == 1 ? '' : 's'}'
            '${mineRows.isEmpty ? '' : ': ${mineRows.take(8).map((g) => g['display_name']).join(', ')}${mineRows.length > 8 ? ', ...' : ''}'}.');
        final overlap = groupIds.intersection(mineIds);
        if (overlap.isNotEmpty) {
          facts.add('The user is already in a group that grants this, so the access line is not the cause: look at the record rules and the company of the record.');
        } else if (groupNames.isNotEmpty) {
          steps.add('Add user $userId to one of: ${groupNames.take(6).join(', ')} (Settings, Users & Companies, Users).');
        }
      }
    } else if (groupNames.isNotEmpty) {
      steps.add('Add the API user to one of: ${groupNames.take(6).join(', ')} (Settings, Users & Companies, Users).');
    }
    if (steps.isEmpty && granting.isEmpty) {
      steps.add('Add an access line for $model with the ${operation == 'unlink' ? 'Delete' : operation[0].toUpperCase() + operation.substring(1)} box ticked, for a group the user is in (a module, or Settings, Technical, Access Rights).');
    }
    return OdooDoctorReport(facts: facts, steps: steps);
  }

  Future<OdooDoctorReport> _accessRule(OdooConnection c, OdooDiagnosis d, String? model) async {
    if (model == null) return OdooDoctorReport(notice: _noModel('the record rule'));
    final operation = d.operation ?? 'read';
    final rules = await _read(
      c,
      OdooCall(model: 'ir.rule', method: 'search_read', params: {
        'domain': [['model_id.model', '=', model]],
        'fields': ['name', 'domain_force', 'global', 'groups', 'perm_read', 'perm_write', 'perm_create', 'perm_unlink'],
      }),
    );
    if (!rules.ok || rules.json is! List) {
      if (_denied(rules)) {
        return const OdooDoctorReport(
          notice: 'This user may not read ir.rule, so the record rules cannot be looked at from here: ask an administrator to open '
              'Settings, Technical, Security, Record Rules.',
        );
      }
      return OdooDoctorReport(notice: 'Could not read ir.rule: ${rules.failureText()}');
    }
    final relevant = [for (final r in rules.json as List) if (r is Map && r['perm_$operation'] != false) r];
    if (relevant.isEmpty) {
      return OdooDoctorReport(facts: ['$model has no record rule for ${d.operationGerund}: the denial is not a record rule.']);
    }
    return OdooDoctorReport(
      facts: [
        'Record rules of $model that apply to ${d.operationGerund}:',
        for (final r in relevant.take(8))
          '${r['name']}: ${r['domain_force']} (${r['global'] == true ? 'every user' : 'only for some groups'})',
      ],
      steps: const ['The record has to satisfy these domains for the user; the usual cause is a record of a company the user is not allowed to use.'],
    );
  }

  Future<OdooDoctorReport> _missingRequired(OdooConnection c, OdooDiagnosis d, String? model) async {
    if (model == null) return OdooDoctorReport(notice: _noModel('the required field'));
    final fields = await _schema.fields(c, model);
    final info = fields.value;
    if (info == null) return OdooDoctorReport(notice: 'Could not read the fields of $model: ${fields.error}');
    final required = [for (final f in info.fields) if (f.required && f.stored && !f.isMagic) f];
    final defaults = await _schema.defaultGet(c, model, [for (final f in required) f.name]);
    final given = defaults.value?.keys.toSet() ?? const <String>{};
    final mustSend = [for (final f in required) if (!given.contains(f.name)) f];
    return OdooDoctorReport(
      facts: [
        'Required on $model: ${required.map((f) => '${f.name} (${f.type})').join(', ')}.',
        if (defaults.ok) 'Odoo fills in by itself: ${given.isEmpty ? 'none of them' : given.where((n) => required.any((f) => f.name == n)).join(', ')}.',
      ],
      steps: [if (mustSend.isNotEmpty) 'Send a value for: ${mustSend.map((f) => f.name).join(', ')}.'],
    );
  }

  Future<OdooDoctorReport> _unique(OdooConnection c, OdooDiagnosis d, String? model) async {
    final field = d.field;
    final value = d.value;
    if (model == null || field == null || value == null) {
      return const OdooDoctorReport(notice: 'The error does not name the model, the field and the value together, so the record that holds it cannot be looked up.');
    }
    final found = await _read(
      c,
      OdooCall(model: model, method: 'search_read', params: {
        'domain': [[field, '=', value]],
        'fields': ['display_name'],
        'limit': 3,
      }),
    );
    final rows = found.json;
    if (!found.ok || rows is! List) return OdooDoctorReport(notice: 'Could not search $model: ${found.failureText()}');
    if (rows.isEmpty) {
      return OdooDoctorReport(facts: ['No visible record of $model has $field = $value: it may belong to an archived or hidden record.']);
    }
    return OdooDoctorReport(
      facts: ['$field = $value is already used by: ${rows.whereType<Map>().map((r) => '${r['id']} (${r['display_name']})').join(', ')}.'],
      steps: [
        'Update that record instead: write to id ${(rows.first as Map)['id']}.',
      ],
    );
  }

  Future<OdooDoctorReport> _missingRecord(OdooConnection c, OdooDiagnosis d, String? model) async {
    if (model == null || d.recordIds.isEmpty) {
      return const OdooDoctorReport(notice: 'The error names no model or no ids, so there is nothing to check.');
    }
    final exists = await _read(c, OdooCall(model: model, method: 'exists', ids: d.recordIds));
    final json = exists.json;
    if (!exists.ok || json is! List) return OdooDoctorReport(notice: 'Could not check the ids: ${exists.failureText()}');
    final alive = {for (final id in json) if (id is int) id};
    final gone = [for (final id in d.recordIds) if (!alive.contains(id)) id];
    return OdooDoctorReport(
      facts: [
        if (alive.isNotEmpty) 'Still exist (for this user): ${alive.join(', ')}.',
        if (gone.isNotEmpty) 'Do not exist: ${gone.join(', ')}.',
      ],
      steps: [if (gone.isNotEmpty) 'Look the record up again: search_read on $model with the name or code you know, or use {{xmlid:module.name}} / {{ref:$model:name}}.'],
    );
  }

  Future<OdooDoctorReport> _invalidField(OdooConnection c, OdooDiagnosis d, String? model) async {
    final field = d.field;
    if (model == null || field == null) return OdooDoctorReport.empty;
    final fields = await _schema.fields(c, model);
    final info = fields.value;
    if (info == null) return OdooDoctorReport(notice: 'Could not read the fields of $model: ${fields.error}');
    final near = OdooNames.suggest(field, info.fields.map((f) => f.name));
    return OdooDoctorReport(
      facts: [near.isEmpty ? '$model has no field that looks like "$field".' : 'Fields of $model that look like "$field": ${near.join(', ')}.'],
    );
  }

  Future<OdooDoctorReport> _badValue(OdooConnection c, OdooDiagnosis d, String? model) async {
    final field = d.field;
    if (model == null || field == null) return OdooDoctorReport.empty;
    final fields = await _schema.fields(c, model);
    final f = fields.value?.field(field);
    if (f == null || f.selection.isEmpty) return OdooDoctorReport.empty;
    return OdooDoctorReport(facts: ['Allowed values of $field: ${f.selection.map((s) => '${s.$1} (${s.$2})').join(', ')}.']);
  }
}
