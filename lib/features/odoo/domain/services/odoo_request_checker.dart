import '../entities/odoo_model_info.dart';
import '../entities/odoo_request_shape.dart';
import 'odoo_domain.dart';
import 'odoo_json_doc.dart';
import 'odoo_names.dart';
import 'odoo_rpc_converter.dart';

enum OdooProblemSeverity { error, warning }

/// What a fix works on: a deep copy of the JSON-2 body, and the tokens of its text, to which a fix may add one
/// (a name written where an id goes becomes `{{ref:model:name}}`).
final class OdooFixContext {
  final Map<String, Object?> root;
  final Map<String, String> tokens;
  OdooFixContext(this.root, this.tokens);

  /// A placeholder value that is written as [token] (`{{ref:res.partner:Azure Interior}}`).
  String token(String token) {
    for (final e in tokens.entries) {
      if (e.value == token) return e.key;
    }
    final name = OdooJsonDoc.placeholder(tokens.length + 1000);
    tokens[name] = token;
    return name;
  }
}

/// One click that mends a problem: a change to the body, or a different model.
final class OdooFix {
  final String label;

  /// Set when the fix is to use another model (the model is not part of the body, so the host changes it).
  final String? model;
  final void Function(OdooFixContext context)? _apply;

  const OdooFix._(this.label, this._apply, this.model);

  factory OdooFix.edit(String label, void Function(OdooFixContext context) apply) => OdooFix._(label, apply, null);
  factory OdooFix.useModel(String label, String model) => OdooFix._(label, null, model);

  bool get changesBody => _apply != null;
  void apply(OdooFixContext context) => _apply?.call(context);
}

/// One thing wrong with a request, where it is, and the fix when there is an obvious one.
final class OdooProblem {
  /// A short stable name of the rule (`unknown_field`, `type`, `selection`, `required`...).
  final String code;
  final OdooProblemSeverity severity;
  final String message;

  /// Where in the body, as a person reads it: `vals.name`, `vals_list[0].parent_id`, `domain[1][2]`.
  final String path;
  final OdooFix? fix;

  const OdooProblem(this.code, this.severity, this.message, this.path, {this.fix});

  bool get isError => severity == OdooProblemSeverity.error;
}

/// What the checker knows besides the body: the fields of the model, whether the model exists, the other models it
/// has read, and the defaults of `create`.
final class OdooCheckContext {
  final OdooModelInfo? info;

  /// False when the server said the model does not exist; null when that was not asked or could not be told.
  final bool? modelExists;

  /// The models of the server, for "did you mean" on a model name.
  final List<String> knownModels;

  /// The fields Odoo fills in by itself on `create` (`default_get`); null when not read.
  final Set<String>? defaults;

  /// The already-read fields of another model (one2many commands, dotted domain paths), or null.
  final OdooModelInfo? Function(String model)? related;

  const OdooCheckContext({this.info, this.modelExists, this.knownModels = const [], this.defaults, this.related});
}

typedef _Report = void Function(String code, OdooProblemSeverity severity, String message, {OdooFix? fix});

/// Checks a request against the live schema of the model before it is sent: the model and the field names, the types
/// of the values, the required fields of `create`, the read-only ones, the shape of x2many commands, the domain and
/// its operators. Pure: the host reads the schema and passes it in [OdooCheckContext].
abstract final class OdooRequestChecker {
  static List<OdooProblem> check(OdooRequestShape shape, OdooCheckContext context) {
    final problems = <OdooProblem>[];
    final info = context.info;

    if (shape.model.isNotEmpty && context.modelExists == false) {
      final near = OdooNames.suggest(shape.model, context.knownModels);
      problems.add(OdooProblem(
        'model_missing',
        OdooProblemSeverity.error,
        'The server has no model "${shape.model}".${near.isEmpty ? '' : ' Did you mean ${near.map((m) => '"$m"').join(' or ')}?'}',
        'model',
        fix: near.isEmpty ? null : OdooFix.useModel('Use ${near.first}', near.first),
      ));
      return problems;
    }
    if (info == null && shape.model.isNotEmpty) {
      problems.add(const OdooProblem(
        'no_schema',
        OdooProblemSeverity.warning,
        'The fields of this model could not be read, so only the structure of the body was checked.',
        'model',
      ));
    }

    _checkParameters(shape, problems);
    _checkRecordsetIds(shape, problems);

    final named = shape.named;
    switch (shape.method) {
      case 'create':
        final list = named['vals_list'];
        if (list is List) {
          for (var i = 0; i < list.length; i++) {
            _checkVals(list[i], 'vals_list[$i]', ['vals_list', i], isCreate: true, info: info, context: context, problems: problems);
          }
        } else if (named.containsKey('vals_list') && !OdooJsonDoc.isToken(list)) {
          problems.add(OdooProblem(
            'vals_shape',
            OdooProblemSeverity.error,
            '"vals_list" is a list of dictionaries, one per record to create.',
            'vals_list',
            fix: list is Map ? OdooFix.edit('Wrap in a list', (c) => c.root['vals_list'] = [c.root['vals_list']]) : null,
          ));
        }
      case 'write':
        if (named.containsKey('vals')) {
          _checkVals(named['vals'], 'vals', ['vals'], isCreate: false, info: info, context: context, problems: problems);
        } else if (!named.containsKey('vals_list')) {
          problems.add(const OdooProblem('vals_missing', OdooProblemSeverity.error, 'write needs "vals", the dictionary of values to write.', 'vals'));
        }
      case 'copy':
        if (named.containsKey('default')) {
          _checkVals(named['default'], 'default', ['default'], isCreate: false, info: info, context: context, problems: problems);
        }
    }

    if (named.containsKey('domain')) _checkDomain(named['domain'], ['domain'], info, context, problems);
    if (named.containsKey('fields')) _checkNameList(named['fields'], 'fields', info, problems);
    if (named.containsKey('fields_list')) _checkNameList(named['fields_list'], 'fields_list', info, problems);
    if (named['order'] is String) _checkOrder(named['order'] as String, info, problems);
    if (named.containsKey('groupby')) _checkNameList(named['groupby'], 'groupby', info, problems);
    return problems;
  }

  /// The body text after [fixes], in the form the request was written in (JSON-2 body or `call_kw` envelope).
  static String applyFixes(OdooRequestShape shape, Iterable<OdooFix> fixes) {
    final context = OdooFixContext(_copyMap(shape.named), {...shape.doc.tokens});
    for (final fix in fixes) {
      fix.apply(context);
    }
    return shape.writeBack(context.root, tokens: context.tokens);
  }

  // --- parameters and ids ----------------------------------------------------------------------------------------

  static void _checkParameters(OdooRequestShape shape, List<OdooProblem> problems) {
    final signature = OdooRpcConverter.signatureOf(shape.method);
    if (signature == null) return;
    final named = shape.named;
    final known = {...signature.params, 'ids', 'context'};

    // The two mix-ups everybody makes: `vals` for create and `vals_list` for write.
    if (shape.method == 'create' && named.containsKey('vals') && !named.containsKey('vals_list')) {
      problems.add(OdooProblem(
        'param_name',
        OdooProblemSeverity.error,
        'create takes "vals_list", a list of records to create, not "vals".',
        'vals',
        fix: OdooFix.edit('Rename to vals_list and wrap in a list', (c) {
          final value = c.root.remove('vals');
          c.root['vals_list'] = value is List ? value : [value];
        }),
      ));
    } else if (shape.method == 'write' && named.containsKey('vals_list') && !named.containsKey('vals')) {
      final value = named['vals_list'];
      problems.add(OdooProblem(
        'param_name',
        OdooProblemSeverity.error,
        'write takes "vals", one dictionary applied to every record in "ids", not "vals_list".',
        'vals_list',
        fix: value is List && value.length == 1
            ? OdooFix.edit('Rename to vals and unwrap the list', (c) {
                final list = c.root.remove('vals_list');
                c.root['vals'] = list is List && list.length == 1 ? list.single : list;
              })
            : null,
      ));
    }

    for (final key in named.keys) {
      if (known.contains(key)) continue;
      if ((shape.method == 'create' && key == 'vals') || (shape.method == 'write' && key == 'vals_list')) continue;
      final near = OdooNames.suggest(key, signature.params);
      problems.add(OdooProblem(
        'param_unknown',
        OdooProblemSeverity.error,
        '${shape.method} has no parameter "$key"${near.isEmpty ? '' : ': did you mean ${near.map((n) => '"$n"').join(' or ')}?'} '
            'JSON-2 passes every argument by name.',
        key,
        fix: near.isEmpty
            ? OdooFix.edit('Remove "$key"', (c) => c.root.remove(key))
            : OdooFix.edit('Rename to ${near.first}', (c) => _renameKey(c.root, key, near.first)),
      ));
    }
  }

  static void _checkRecordsetIds(OdooRequestShape shape, List<OdooProblem> problems) {
    final signature = OdooRpcConverter.signatureOf(shape.method);
    if (signature == null || !signature.recordset) return;
    if (!shape.named.containsKey('ids')) {
      problems.add(OdooProblem(
        'ids_missing',
        OdooProblemSeverity.error,
        '${shape.method} works on records: add "ids", the list of record ids, to the body.',
        'ids',
      ));
      return;
    }
    final ids = shape.named['ids'];
    if (ids is! List) {
      problems.add(OdooProblem(
        'ids_type',
        OdooProblemSeverity.error,
        '"ids" must be a list of record ids, for example [1, 2].',
        'ids',
        fix: ids is int || OdooJsonDoc.isToken(ids) ? OdooFix.edit('Wrap in a list', (c) => c.root['ids'] = [c.root['ids']]) : null,
      ));
    } else if (ids.isEmpty) {
      problems.add(const OdooProblem('ids_empty', OdooProblemSeverity.warning, '"ids" is empty: the call changes no record.', 'ids'));
    }
  }

  // --- values ----------------------------------------------------------------------------------------------------

  static void _checkVals(
    Object? vals,
    String where,
    List<Object> path, {
    required bool isCreate,
    required OdooModelInfo? info,
    required OdooCheckContext context,
    required List<OdooProblem> problems,
    bool nested = false,
  }) {
    if (OdooJsonDoc.isToken(vals)) return;
    if (vals is! Map) {
      problems.add(OdooProblem(
        'vals_shape',
        OdooProblemSeverity.error,
        '${path.first == 'vals_list' ? 'Each record of vals_list' : '"${path.first}"'} must be a dictionary of field values.',
        where,
      ));
      return;
    }
    if (info == null) return;
    for (final entry in vals.entries.toList()) {
      final key = '${entry.key}';
      final field = info.field(key);
      final here = '$where.$key';
      if (field == null) {
        final near = OdooNames.suggest(key, info.fields.map((f) => f.name));
        final target = near.where((n) => !vals.containsKey(n)).firstOrNull;
        problems.add(OdooProblem(
          'unknown_field',
          OdooProblemSeverity.error,
          'Field "$key" does not exist on ${info.model}.${near.isEmpty ? '' : ' Did you mean ${near.map((n) => '"$n"').join(' or ')}?'}',
          here,
          fix: target == null
              ? OdooFix.edit('Remove "$key"', (c) => _mapAt(c.root, path)?.remove(key))
              : OdooFix.edit('Rename to $target', (c) {
                  final m = _mapAt(c.root, path);
                  if (m != null) _renameKey(m, key, target);
                }),
        ));
        continue;
      }
      if (field.isMagic) {
        problems.add(OdooProblem(
          'magic_field',
          OdooProblemSeverity.error,
          '"$key" is set by Odoo itself and cannot be written.',
          here,
          fix: OdooFix.edit('Remove "$key"', (c) => _mapAt(c.root, path)?.remove(key)),
        ));
        continue;
      }
      if (field.readonly) {
        problems.add(OdooProblem(
          'readonly',
          OdooProblemSeverity.warning,
          '"$key" (${field.label}) is read-only${field.stored ? '' : ' and computed'}: Odoo ignores or rejects a value written to it.',
          here,
          fix: OdooFix.edit('Remove "$key"', (c) => _mapAt(c.root, path)?.remove(key)),
        ));
      }
      _checkValue(field, entry.value, [...path, key], here, context, problems, nested: nested);
    }

    // Nested records get their required fields from the parent (the inverse field), so only a top-level create is judged.
    if (isCreate && !nested) {
      for (final field in info.fields) {
        if (!field.required || !field.stored || field.isMagic || vals.containsKey(field.name)) continue;
        final defaults = context.defaults;
        if (defaults != null && defaults.contains(field.name)) continue;
        final fill = _emptyValue(field);
        problems.add(OdooProblem(
          'required',
          defaults == null ? OdooProblemSeverity.warning : OdooProblemSeverity.error,
          '"${field.name}" (${field.label}) is required${defaults == null ? ': send it unless Odoo has a default for it' : ' and has no default'}.',
          '$where.${field.name}',
          fix: fill.$1
              ? OdooFix.edit('Add "${field.name}" with ${_describe(fill.$2)}', (c) => _mapAt(c.root, path)?[field.name] = fill.$2)
              : null,
        ));
      }
    }
  }

  /// A value that fills a required field of a simple type, so the body is complete and the person only edits it.
  static (bool, Object?) _emptyValue(OdooField f) => switch (f.type) {
        'char' || 'text' || 'html' => (true, ''),
        'integer' || 'float' || 'monetary' => (true, 0),
        'boolean' => (true, false),
        'selection' when f.selection.isNotEmpty => (true, f.selection.first.$1),
        _ => (false, null),
      };

  static String _describe(Object? v) => v is String ? (v.isEmpty ? 'an empty text' : '"$v"') : '$v';

  static OdooFix _setTo(List<Object> path, Object? value) =>
      OdooFix.edit('Use ${_describe(value)}', (c) => _setAt(c.root, path, value));

  static void _checkValue(
    OdooField f,
    Object? v,
    List<Object> path,
    String where,
    OdooCheckContext context,
    List<OdooProblem> problems, {
    bool nested = false,
  }) {
    if (OdooJsonDoc.isToken(v)) return; // a {{variable}}: known only when the request is sent
    final label = '"${f.name}" (${f.label})';
    void report(String code, OdooProblemSeverity severity, String message, {OdooFix? fix}) =>
        problems.add(OdooProblem(code, severity, message, where, fix: fix));
    const error = OdooProblemSeverity.error;
    const warning = OdooProblemSeverity.warning;

    switch (f.type) {
      case 'char' || 'text' || 'html':
        if (v is String || v == false || v == null) return;
        if (v is num) {
          report('type', warning, '$label is text; the number $v will be stored as text.', fix: _setTo(path, '$v'));
        } else {
          report('type', error, '$label is text, but the value is ${_kind(v)}.');
        }
      case 'integer':
        if (v is int || v == false || v == null) return;
        if (v is double && v == v.truncateToDouble()) {
          report('type', warning, '$label is a whole number; $v is written with a decimal part.', fix: _setTo(path, v.toInt()));
        } else if (v is String && int.tryParse(v.trim()) != null) {
          report('type', error, '$label is an integer, but the value is the text "$v".', fix: _setTo(path, int.parse(v.trim())));
        } else {
          report('type', error, '$label is an integer, but the value is ${_kind(v)}.');
        }
      case 'float' || 'monetary':
        if (v is num || v == false || v == null) return;
        final parsed = v is String ? num.tryParse(v.trim()) : null;
        if (parsed != null) {
          report('type', error, '$label is a number, but the value is the text "$v".', fix: _setTo(path, parsed));
        } else {
          report('type', error, '$label is a number, but the value is ${_kind(v)}.');
        }
      case 'boolean':
        if (v is bool) return;
        final word = v is String ? v.trim().toLowerCase() : null;
        final truthy = v == 1 || word == 'true' || word == 'yes' || word == '1';
        final falsy = v == 0 || word == 'false' || word == 'no' || word == '0';
        if (truthy || falsy) {
          report('type', error, '$label is true or false, but the value is ${_kind(v)} $v.', fix: _setTo(path, truthy));
        } else {
          report('type', error, '$label is true or false, but the value is ${_kind(v)}.');
        }
      case 'date':
        _checkDate(v, label, path, report);
      case 'datetime':
        _checkDatetime(v, label, path, report);
      case 'selection':
        _checkSelection(f, v, label, path, report);
      case 'many2one':
        _checkMany2one(f, v, label, path, report);
      case 'one2many' || 'many2many':
        _checkX2many(f, v, label, where, path, context, problems, nested: nested);
    }
  }

  static String _kind(Object? v) => switch (v) {
        null => 'null',
        bool() => 'a boolean',
        int() || double() => 'a number',
        String() => 'text',
        List() => 'a list',
        Map() => 'a dictionary',
        _ => 'of another kind',
      };

  // --- dates -----------------------------------------------------------------------------------------------------

  static bool _validDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    final date = DateTime.utc(y, m, d);
    return date.year == y && date.month == m && date.day == d;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static void _checkDate(Object? v, String label, List<Object> path, _Report report) {
    if (v == false || v == null) return;
    const error = OdooProblemSeverity.error;
    if (v is! String) return report('format', error, '$label is a date written "YYYY-MM-DD", but the value is ${_kind(v)}.');
    final text = v.trim();
    final exact = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (exact != null) {
      if (!_validDate(int.parse(exact[1]!), int.parse(exact[2]!), int.parse(exact[3]!))) {
        return report('format', error, '$label: "$v" is not a real calendar date.');
      }
      if (text == v) return;
      return report('format', OdooProblemSeverity.warning, '$label: "$v" has spaces around the date.', fix: _setTo(path, text));
    }
    final withTime = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ]\d{2}:\d{2}').firstMatch(text);
    if (withTime != null && _validDate(int.parse(withTime[1]!), int.parse(withTime[2]!), int.parse(withTime[3]!))) {
      return report('format', OdooProblemSeverity.warning, '$label is a date, but "$v" has a time: a date field takes "YYYY-MM-DD".',
          fix: _setTo(path, text.substring(0, 10)));
    }
    final slash = RegExp(r'^(\d{4})[/.](\d{1,2})[/.](\d{1,2})$').firstMatch(text);
    if (slash != null && _validDate(int.parse(slash[1]!), int.parse(slash[2]!), int.parse(slash[3]!))) {
      return report('format', error, '$label must be written "YYYY-MM-DD", not "$v".',
          fix: _setTo(path, '${slash[1]}-${_two(int.parse(slash[2]!))}-${_two(int.parse(slash[3]!))}'));
    }
    final dayFirst = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(text);
    if (dayFirst != null) {
      final a = int.parse(dayFirst[1]!);
      final b = int.parse(dayFirst[2]!);
      final year = int.parse(dayFirst[3]!);
      // 06/10/2026 is the 6th of October or the 10th of June: only a part above 12 settles it.
      if (a > 12 && _validDate(year, b, a)) {
        return report('format', error, '$label must be written "YYYY-MM-DD", not "$v".', fix: _setTo(path, '$year-${_two(b)}-${_two(a)}'));
      }
      if (b > 12 && _validDate(year, a, b)) {
        return report('format', error, '$label must be written "YYYY-MM-DD", not "$v".', fix: _setTo(path, '$year-${_two(a)}-${_two(b)}'));
      }
      return report('format', error, '$label must be written "YYYY-MM-DD", and "$v" could be day/month or month/day: write it out as YYYY-MM-DD.');
    }
    report('format', error, '$label must be written "YYYY-MM-DD", not "$v".');
  }

  static void _checkDatetime(Object? v, String label, List<Object> path, _Report report) {
    if (v == false || v == null) return;
    const error = OdooProblemSeverity.error;
    if (v is! String) {
      return report('format', error, '$label is a datetime written "YYYY-MM-DD HH:MM:SS" (UTC), but the value is ${_kind(v)}.');
    }
    final text = v.trim();
    bool real(RegExpMatch m) =>
        _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)) && int.parse(m[4]!) < 24 && int.parse(m[5]!) < 60;
    final exact = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(text);
    if (exact != null) {
      if (!real(exact) || int.parse(exact[6]!) > 59) return report('format', error, '$label: "$v" is not a real date and time.');
      if (text == v) return;
      return report('format', OdooProblemSeverity.warning, '$label: "$v" has spaces around it.', fix: _setTo(path, text));
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return; // a date alone is read as midnight
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$').firstMatch(text);
    if (iso != null && real(iso)) {
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        // Without an offset the time is taken as UTC already, with one it is converted.
        final utc = iso[7] == null
            ? DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second)
            : parsed.toUtc();
        final fixed = '${utc.year.toString().padLeft(4, '0')}-${_two(utc.month)}-${_two(utc.day)} '
            '${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}';
        return report(
          'format',
          OdooProblemSeverity.warning,
          '$label is written "YYYY-MM-DD HH:MM:SS" in UTC, not "$v".${iso[7] != null && iso[7] != 'Z' ? ' The offset is converted to UTC.' : ''}',
          fix: _setTo(path, fixed),
        );
      }
    }
    report('format', error, '$label must be written "YYYY-MM-DD HH:MM:SS" (UTC), not "$v".');
  }

  // --- selection, many2one, x2many -------------------------------------------------------------------------------

  static void _checkSelection(OdooField f, Object? v, String label, List<Object> path, _Report report) {
    if (v == false || v == null || f.selection.isEmpty) return;
    final keys = f.selection.map((s) => s.$1).toList();
    if (v is String && keys.contains(v)) return;
    final text = '$v';
    // The label shown in the UI instead of the stored value is the usual mistake.
    final byLabel = f.selection.where((s) => s.$2.toLowerCase() == text.trim().toLowerCase()).firstOrNull;
    if (byLabel != null) {
      return report('selection', OdooProblemSeverity.error, '$label stores "${byLabel.$1}", not its label "$text".', fix: _setTo(path, byLabel.$1));
    }
    final near = OdooNames.suggest(text, keys);
    final allowed = keys.take(12).join(', ') + (keys.length > 12 ? ', ...' : '');
    report(
      'selection',
      OdooProblemSeverity.error,
      '"$text" is not a value of $label. Allowed: $allowed.${near.isEmpty ? '' : ' Did you mean "${near.first}"?'}',
      fix: near.isEmpty ? null : _setTo(path, near.first),
    );
  }

  static void _checkMany2one(OdooField f, Object? v, String label, List<Object> path, _Report report) {
    if (v is int || v == false || v == null) return;
    const error = OdooProblemSeverity.error;
    final relation = f.relation ?? 'the related model';
    if (v is List && v.length == 2 && v.first is int && v[1] is String) {
      return report('many2one', error, '$label takes the id of the record, not the pair [id, name] that a read returns.', fix: _setTo(path, v.first));
    }
    if (v is String) {
      final id = int.tryParse(v.trim());
      if (id != null) return report('many2one', error, '$label takes a number, but the value is the text "$v".', fix: _setTo(path, id));
      final name = v.trim();
      if (name.isEmpty) return report('many2one', error, '$label takes the id of a $relation record, not an empty text.');
      // A name where an id goes becomes a lookup Odoo resolves when the request is sent.
      final model = f.relation;
      final lookup = model != null && !name.contains('{') && !name.contains('}');
      return report(
        'many2one',
        error,
        '$label takes the id of a $relation record, not a name ("$name").${lookup ? ' {{ref:$model:$name}} makes PostPilot look the id up when the request is sent.' : ''}',
        fix: lookup
            ? OdooFix.edit('Use {{ref:$model:$name}}', (c) => _setAt(c.root, path, c.token('{{ref:$model:$name}}')))
            : null,
      );
    }
    report('many2one', error, '$label takes the id of a $relation record, but the value is ${_kind(v)}.');
  }

  static const _commandNames = {
    0: 'create (0, 0, {values})',
    1: 'update (1, id, {values})',
    2: 'delete (2, id)',
    3: 'unlink (3, id)',
    4: 'link (4, id)',
    5: 'clear (5)',
    6: 'set (6, 0, [ids])',
  };

  static void _checkX2many(
    OdooField f,
    Object? v,
    String label,
    String where,
    List<Object> path,
    OdooCheckContext context,
    List<OdooProblem> problems, {
    bool nested = false,
  }) {
    if (v == false || v == null) return;
    void add(String message, {OdooFix? fix, String? at}) =>
        problems.add(OdooProblem('x2many', OdooProblemSeverity.error, message, at ?? where, fix: fix));
    if (v is! List) {
      if (v is int) {
        return add('$label takes a list of commands, not a single id. [[4, $v]] links record $v.',
            fix: OdooFix.edit('Use [[4, $v]]', (c) => _setAt(c.root, path, [[4, v]])));
      }
      return add('$label takes a list of commands such as [[6, 0, [1, 2]]] or [[0, 0, {values}]], but the value is ${_kind(v)}.');
    }
    if (v.isNotEmpty && v.every((e) => e is int)) {
      return add('$label takes commands, not a plain list of ids. [[6, 0, $v]] replaces the records with exactly these.',
          fix: OdooFix.edit('Use [[6, 0, $v]]', (c) => _setAt(c.root, path, [[6, 0, v]])));
    }
    final relationInfo = f.relation == null ? null : context.related?.call(f.relation!);
    bool idLike(Object? x) => x is int || OdooJsonDoc.isToken(x);
    bool valuesLike(Object? x) => x is Map || OdooJsonDoc.isToken(x);
    for (var i = 0; i < v.length; i++) {
      final command = v[i];
      final at = '$where[$i]';
      if (OdooJsonDoc.isToken(command)) continue;
      if (command is! List || command.isEmpty || command.first is! int) {
        add('Command $i of $label must be a list starting with a number 0 to 6, for example [4, 7]. Commands: ${_commandNames.values.join('; ')}.', at: at);
        continue;
      }
      final op = command.first as int;
      final name = _commandNames[op];
      if (name == null) {
        add('Command $i of $label starts with $op, which is not a command. Use 0 to 6: ${_commandNames.values.join('; ')}.', at: at);
        continue;
      }
      switch (op) {
        case 0:
          if (command.length != 3 || command[1] != 0 || !valuesLike(command[2])) {
            add('Command $i of $label: create is [0, 0, {values}], with the field values in a dictionary.', at: at);
          } else if (relationInfo != null) {
            _checkVals(command[2], '$at[2]', [...path, i, 2], isCreate: true, info: relationInfo, context: context, problems: problems, nested: true);
          }
        case 1:
          if (command.length != 3 || !idLike(command[1]) || !valuesLike(command[2])) {
            add('Command $i of $label: update is [1, id, {values}].', at: at);
          } else if (relationInfo != null) {
            _checkVals(command[2], '$at[2]', [...path, i, 2], isCreate: false, info: relationInfo, context: context, problems: problems, nested: true);
          }
        case 2 || 3 || 4:
          if (command.length < 2 || command.length > 3 || !idLike(command[1])) {
            add('Command $i of $label: $name takes the id of the record.', at: at);
          }
        case 5:
          if (command.length > 3) add('Command $i of $label: clear is [5].', at: at);
        case 6:
          if (command.length != 3 || command[1] != 0 || (command[2] is! List && !OdooJsonDoc.isToken(command[2]))) {
            add('Command $i of $label: set is [6, 0, [id, id, ...]], with the ids in a list.', at: at);
          } else if (command[2] is List && (command[2] as List).any((e) => !idLike(e))) {
            add('Command $i of $label: the ids of [6, 0, [...]] must be numbers.', at: at);
          }
      }
    }
  }

  // --- domain, field lists, order --------------------------------------------------------------------------------

  /// Operators Odoo accepts at all.
  static const _allOperators = {
    '=', '!=', 'ilike', 'like', 'not ilike', 'not like', '=ilike', '=like', 'in', 'not in', '>', '>=', '<', '<=', '=?',
    'child_of', 'parent_of', 'any', 'not any', '<>',
  };

  /// What each type is queried with; anything else Odoo accepts, or rejects late, but it is almost certainly a mistake.
  static Set<String> _typeOperators(String type) => switch (type) {
        'char' || 'text' || 'html' => {'=', '!=', 'like', 'not like', 'ilike', 'not ilike', '=like', '=ilike', 'in', 'not in', '=?'},
        'integer' || 'float' || 'monetary' => {'=', '!=', '>', '>=', '<', '<=', 'in', 'not in', '=?'},
        'date' || 'datetime' => {'=', '!=', '>', '>=', '<', '<=', 'in', 'not in', '=?'},
        'boolean' => {'=', '!=', 'in', 'not in'},
        'selection' => {'=', '!=', 'in', 'not in', 'like', 'ilike', 'not like', 'not ilike', '=?'},
        'many2one' => {'=', '!=', 'in', 'not in', 'like', 'ilike', 'not like', 'not ilike', '=like', '=ilike', 'child_of', 'parent_of', 'any', 'not any', '=?', '>', '<', '>=', '<='},
        'one2many' || 'many2many' => {'=', '!=', 'in', 'not in', 'like', 'ilike', 'not like', 'not ilike', 'child_of', 'parent_of', 'any', 'not any'},
        _ => _allOperators,
      };

  static void _checkDomain(Object? domain, List<Object> path, OdooModelInfo? info, OdooCheckContext context, List<OdooProblem> problems) {
    if (OdooJsonDoc.isToken(domain)) return;
    if (domain is! List) {
      problems.add(const OdooProblem('domain', OdooProblemSeverity.error, 'The domain must be a list of conditions such as [["name", "ilike", "a"]].', 'domain'));
      return;
    }
    // The shape: prefix operators and [field, operator, value] conditions.
    var expected = 1;
    for (var i = 0; i < domain.length; i++) {
      final item = domain[i];
      if (item == '&' || item == '|') {
        expected += 1;
      } else if (item == '!') {
        // takes the next term: nothing more is expected
      } else if (item is List || OdooJsonDoc.isToken(item)) {
        expected -= 1;
      } else {
        problems.add(OdooProblem('domain', OdooProblemSeverity.error,
            'Item $i of the domain is ${item is String ? '"$item"' : _kind(item)}: it must be "&", "|", "!" or a [field, operator, value] list.', 'domain[$i]'));
        return;
      }
    }
    if (domain.isNotEmpty && expected > 0) {
      problems.add(const OdooProblem('domain', OdooProblemSeverity.error,
          'The domain is not complete: a "&" or "|" has no condition to join. Prefix notation puts the operator before its two conditions.', 'domain'));
    }
    for (var i = 0; i < domain.length; i++) {
      final item = domain[i];
      if (item is List) _checkLeaf(item, [...path, i], 'domain[$i]', info, context, problems);
    }
  }

  static void _checkLeaf(List<Object?> leaf, List<Object> path, String where, OdooModelInfo? info, OdooCheckContext context, List<OdooProblem> problems) {
    if (leaf.length != 3 || leaf.first is! String || leaf[1] is! String) {
      problems.add(OdooProblem('domain', OdooProblemSeverity.error, 'A condition is [field, operator, value] (three parts); this one has ${leaf.length}.', where));
      return;
    }
    final fieldPath = leaf.first as String;
    final operator = leaf[1] as String;
    final value = leaf[2];

    if (!_allOperators.contains(operator)) {
      final near = OdooNames.suggest(operator, _allOperators);
      problems.add(OdooProblem(
        'operator',
        OdooProblemSeverity.error,
        '"$operator" is not an operator of a domain.${near.isEmpty ? '' : ' Did you mean "${near.first}"?'} Operators: ${OdooOperators.all.keys.join(', ')}.',
        '$where[1]',
        fix: near.isEmpty ? null : _setTo([...path, 1], near.first),
      ));
      return;
    }

    // The field, following `partner_id.country_id` through the models that are already read.
    final field = _resolveField(fieldPath, info, context, problems, [...path, 0], '$where[0]');
    if (field == null) return;

    if (!_typeOperators(field.type).contains(operator)) {
      problems.add(OdooProblem(
        'operator',
        OdooProblemSeverity.warning,
        'Operator "$operator" does not suit "${field.name}" (type ${field.type}). Use one of: ${OdooOperators.forType(field.type).join(', ')}.',
        '$where[1]',
      ));
    }
    if (OdooJsonDoc.isToken(value)) return;
    final many = operator == 'in' || operator == 'not in';
    if (many && value is! List) {
      problems.add(OdooProblem(
        'operator',
        OdooProblemSeverity.error,
        '"$operator" compares with a list of values, for example [1, 2]; this value is ${_kind(value)}.',
        '$where[2]',
        fix: OdooFix.edit('Wrap the value in a list', (c) => _setAt(c.root, [...path, 2], [value])),
      ));
      return;
    }
    final scalars = many && value is List ? value : [value];
    for (var i = 0; i < scalars.length; i++) {
      _checkLeafValue(field, scalars[i], many ? [...path, 2, i] : [...path, 2], '$where[2]', operator, problems);
    }
  }

  static OdooField? _resolveField(String fieldPath, OdooModelInfo? info, OdooCheckContext context, List<OdooProblem> problems, List<Object> path, String where) {
    if (info == null) return null;
    var current = info;
    OdooField? field;
    final parts = fieldPath.split('.');
    for (var i = 0; i < parts.length; i++) {
      // `field:granularity` and a `{{variable}}` part are not plain names.
      final part = parts[i].split(':').first;
      if (part.isEmpty || part.contains('{')) return null;
      field = current.field(part);
      if (field == null) {
        final near = OdooNames.suggest(part, current.fields.map((f) => f.name));
        String rebuilt(String better) => [...parts.sublist(0, i), better, ...parts.sublist(i + 1)].join('.');
        problems.add(OdooProblem(
          'unknown_field',
          OdooProblemSeverity.error,
          'Field "$part" does not exist on ${current.model}.${near.isEmpty ? '' : ' Did you mean ${near.map((n) => '"$n"').join(' or ')}?'}',
          where,
          fix: near.isEmpty ? null : _setTo(path, rebuilt(near.first)),
        ));
        return null;
      }
      if (i < parts.length - 1) {
        final relation = field.relation;
        final next = relation == null ? null : context.related?.call(relation);
        if (next == null) return null; // the rest cannot be checked until that model is read
        current = next;
      }
    }
    return field;
  }

  static void _checkLeafValue(OdooField f, Object? v, List<Object> path, String where, String operator, List<OdooProblem> problems) {
    if (OdooJsonDoc.isToken(v) || v == null || v is bool || operator.contains('like')) return;
    void warn(String message, {Object? fixTo, bool fixable = false}) => problems.add(
          OdooProblem('type', OdooProblemSeverity.warning, message, where, fix: fixable ? _setTo(path, fixTo) : null),
        );
    switch (f.type) {
      case 'integer':
        if (v is String && int.tryParse(v.trim()) != null) {
          warn('"${f.name}" is an integer: compare with ${v.trim()}, not the text "$v".', fixTo: int.parse(v.trim()), fixable: true);
        }
      case 'float' || 'monetary':
        if (v is String && num.tryParse(v.trim()) != null) {
          warn('"${f.name}" is a number: compare with ${v.trim()}, not the text "$v".', fixTo: num.parse(v.trim()), fixable: true);
        }
      case 'many2one':
        if (v is String && int.tryParse(v.trim()) != null) {
          warn('"${f.name}" holds an id: compare with ${v.trim()}, not the text "$v".', fixTo: int.parse(v.trim()), fixable: true);
        }
      case 'date':
        if (v is String && !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) warn('"${f.name}" is a date: write "$v" as YYYY-MM-DD.');
      case 'selection':
        if (v is String && f.selection.isNotEmpty && !f.selection.any((s) => s.$1 == v)) {
          final near = OdooNames.suggest(v, f.selection.map((s) => s.$1));
          warn(
            '"$v" is not a value of ${f.name}. Allowed: ${f.selection.map((s) => s.$1).take(12).join(', ')}.${near.isEmpty ? '' : ' Did you mean "${near.first}"?'}',
            fixTo: near.isEmpty ? null : near.first,
            fixable: near.isNotEmpty,
          );
        }
    }
  }

  static void _checkNameList(Object? list, String name, OdooModelInfo? info, List<OdooProblem> problems) {
    if (OdooJsonDoc.isToken(list) || info == null) return;
    if (list is String) {
      problems.add(OdooProblem('fields', OdooProblemSeverity.error, '"$name" is a list of field names, for example ["$list"]; this is a single text.', name,
          fix: OdooFix.edit('Wrap in a list', (c) => c.root[name] = [list])));
      return;
    }
    if (list is! List) return;
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! String || OdooJsonDoc.isToken(item) || item.startsWith('__')) continue;
      // `field:sum` (read_group), `field:month` (groupby) and `partner_id.name` start with the field's own name.
      final base = item.split(':').first.split('.').first;
      if (base.isEmpty || base.contains('{') || info.field(base) != null) continue;
      final near = OdooNames.suggest(base, info.fields.map((f) => f.name));
      problems.add(OdooProblem(
        'unknown_field',
        OdooProblemSeverity.error,
        'Field "$base" in "$name" does not exist on ${info.model}.${near.isEmpty ? '' : ' Did you mean ${near.map((n) => '"$n"').join(' or ')}?'}',
        '$name[$i]',
        fix: near.isEmpty
            ? OdooFix.edit('Remove "$item"', (c) => _listAt(c.root, [name])?.remove(item))
            : _setTo([name, i], item.replaceFirst(base, near.first)),
      ));
    }
  }

  static void _checkOrder(String order, OdooModelInfo? info, List<OdooProblem> problems) {
    if (info == null || order.contains('{')) return;
    for (final term in order.split(',')) {
      final name = term.trim().split(RegExp(r'\s+')).first;
      if (name.isEmpty || info.field(name) != null) continue;
      final near = OdooNames.suggest(name, info.fields.map((f) => f.name));
      problems.add(OdooProblem(
        'unknown_field',
        OdooProblemSeverity.error,
        'Field "$name" in "order" does not exist on ${info.model}.${near.isEmpty ? '' : ' Did you mean ${near.map((n) => '"$n"').join(' or ')}?'}',
        'order',
        fix: near.isEmpty ? null : _setTo(['order'], order.replaceFirst(name, near.first)),
      ));
    }
  }

  // --- editing the body ------------------------------------------------------------------------------------------

  static Map<String, Object?> _copyMap(Map<String, Object?> m) => {for (final e in m.entries) e.key: _copy(e.value)};

  static Object? _copy(Object? v) => switch (v) {
        Map() => {for (final e in v.entries) '${e.key}': _copy(e.value)},
        List() => [for (final e in v) _copy(e)],
        _ => v,
      };

  static Object? _walk(Object? root, List<Object> path) {
    var node = root;
    for (final step in path) {
      if (node is Map && step is String) {
        node = node[step];
      } else if (node is List && step is int && step >= 0 && step < node.length) {
        node = node[step];
      } else {
        return null;
      }
    }
    return node;
  }

  static Map<Object?, Object?>? _mapAt(Object? root, List<Object> path) {
    final node = _walk(root, path);
    return node is Map ? node.cast<Object?, Object?>() : null;
  }

  static List<Object?>? _listAt(Object? root, List<Object> path) {
    final node = _walk(root, path);
    return node is List ? node.cast<Object?>() : null;
  }

  static void _setAt(Object? root, List<Object> path, Object? value) {
    if (path.isEmpty) return;
    final parent = _walk(root, path.sublist(0, path.length - 1));
    final last = path.last;
    if (parent is Map && last is String) {
      parent[last] = value;
    } else if (parent is List && last is int && last >= 0 && last < parent.length) {
      parent[last] = value;
    }
  }

  /// Renames [from] to [to] in [map] where it stands, so the order of the keys does not change.
  static void _renameKey(Map<Object?, Object?> map, String from, String to) {
    if (!map.containsKey(from) || map.containsKey(to)) return;
    final entries = map.entries.toList();
    map.clear();
    for (final e in entries) {
      map[e.key == from ? to : e.key] = e.value;
    }
  }
}
