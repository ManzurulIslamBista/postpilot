import 'dart:convert';
import '../entities/odoo_connection.dart';
import '../entities/odoo_model_info.dart';
import 'odoo_json_doc.dart';
import 'odoo_json2.dart';
import 'odoo_jsonrpc.dart';

/// A `{{variable}}` or smart reference written where a number goes (`{{xmlid:base.main_company}}`): it is kept as
/// the text the person wrote and stays a bare token in the body, resolved when the request is sent.
final class OdooToken {
  final String text;
  const OdooToken(this.text);

  /// Reads `{{...}}` (the whole text, nothing else) as a token.
  static OdooToken? tryParse(String raw) {
    final t = raw.trim();
    return RegExp(r'^\{\{[^{}]+\}\}$').hasMatch(t) ? OdooToken(t) : null;
  }

  @override
  bool operator ==(Object other) => other is OdooToken && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => text;
}

/// One entry of the command list that a `one2many` / `many2many` field takes.
sealed class X2ManyCommand {
  const X2ManyCommand();

  /// The command as Odoo reads it: `[0, 0, {...}]`, `[4, 7]`...
  List<Object?> toJson();

  /// What the command does, in words, for a row of the builder.
  String get summary;

  /// The command number, 0 to 6.
  int get code;

  /// Reads one command. Null when [json] is not a valid command.
  static X2ManyCommand? fromJson(Object? json) {
    if (json is! List || json.isEmpty || json.first is! int) return null;
    Object? id(int i) => i < json.length && (json[i] is int || json[i] is OdooToken) ? json[i] : null;
    Map<String, Object?>? vals(int i) => i < json.length && json[i] is Map ? Map<String, Object?>.from(json[i] as Map) : null;
    switch (json.first) {
      case 0:
        final v = vals(2);
        return v == null ? null : CreateCommand(v);
      case 1:
        final i = id(1);
        final v = vals(2);
        return i == null || v == null ? null : UpdateCommand(i, v);
      case 2:
        final i = id(1);
        return i == null ? null : DeleteCommand(i);
      case 3:
        final i = id(1);
        return i == null ? null : UnlinkCommand(i);
      case 4:
        final i = id(1);
        return i == null ? null : LinkCommand(i);
      case 5:
        return const ClearCommand();
      case 6:
        final ids = json.length > 2 && json[2] is List ? json[2] as List : null;
        if (ids == null || ids.any((e) => e is! int && e is! OdooToken)) return null;
        return SetCommand(List<Object>.from(ids));
    }
    return null;
  }

  /// Every command of [json] (the value a field holds or `default_get` returns); null when one of them is not valid.
  static List<X2ManyCommand>? listFromJson(Object? json) {
    if (json is! List) return null;
    final out = <X2ManyCommand>[];
    for (final item in json) {
      final c = fromJson(item);
      if (c == null) return null;
      out.add(c);
    }
    return out;
  }

  static String _vals(Map<String, Object?> v) => v.isEmpty
      ? '{}'
      : jsonEncode(v, toEncodable: (o) => o is OdooToken ? o.text : (o is X2ManyCommand ? o.toJson() : o.toString()));
}

/// `[0, 0, {values}]`: a new record with these values, linked to the parent.
final class CreateCommand extends X2ManyCommand {
  final Map<String, Object?> vals;
  const CreateCommand(this.vals);
  @override
  int get code => 0;
  @override
  List<Object?> toJson() => [0, 0, vals];
  @override
  String get summary => 'Create a new record: ${X2ManyCommand._vals(vals)}';
}

/// `[1, id, {values}]`: write these values on the linked record [id].
final class UpdateCommand extends X2ManyCommand {
  final Object id;
  final Map<String, Object?> vals;
  const UpdateCommand(this.id, this.vals);
  @override
  int get code => 1;
  @override
  List<Object?> toJson() => [1, id, vals];
  @override
  String get summary => 'Update record $id: ${X2ManyCommand._vals(vals)}';
}

/// `[2, id]`: remove the link and delete the record.
final class DeleteCommand extends X2ManyCommand {
  final Object id;
  const DeleteCommand(this.id);
  @override
  int get code => 2;
  @override
  List<Object?> toJson() => [2, id];
  @override
  String get summary => 'Delete record $id';
}

/// `[3, id]`: remove the link, keep the record.
final class UnlinkCommand extends X2ManyCommand {
  final Object id;
  const UnlinkCommand(this.id);
  @override
  int get code => 3;
  @override
  List<Object?> toJson() => [3, id];
  @override
  String get summary => 'Unlink record $id (the record stays)';
}

/// `[4, id]`: link an existing record.
final class LinkCommand extends X2ManyCommand {
  final Object id;
  const LinkCommand(this.id);
  @override
  int get code => 4;
  @override
  List<Object?> toJson() => [4, id];
  @override
  String get summary => 'Link record $id';
}

/// `[5, 0, 0]`: unlink every record (none is deleted).
final class ClearCommand extends X2ManyCommand {
  const ClearCommand();
  @override
  int get code => 5;
  @override
  List<Object?> toJson() => [5, 0, 0];
  @override
  String get summary => 'Unlink all records';
}

/// `[6, 0, [ids]]`: replace the linked records with exactly these.
final class SetCommand extends X2ManyCommand {
  final List<Object> ids;
  const SetCommand(this.ids);
  @override
  int get code => 6;
  @override
  List<Object?> toJson() => [6, 0, ids];
  @override
  String get summary => ids.isEmpty ? 'Replace all with nothing (unlink all)' : 'Replace all with: ${ids.join(', ')}';
}

/// What a payload builder form is made of, and how its values become the body of a `create` or `write`: the fields
/// the form offers for a model, the editor of each type with its validation, the conversion of a record that was
/// read into an editable payload, and the body text for either Odoo API.
abstract final class OdooPayload {
  /// Types that carry a payload, in the form. Binary fields (files, images) are left to the explorer: their value
  /// would fill the body with base64.
  static const _skippedTypes = {'binary', 'properties', 'properties_definition', 'json_value'};

  /// Whether [f] belongs in the form: stored, not one of Odoo's own columns, not binary; read-only fields only when
  /// asked for (they are computed or locked, and Odoo ignores what is written to them).
  static bool isEditable(OdooField f, {bool includeReadonly = false}) {
    if (!f.stored || f.isMagic || _skippedTypes.contains(f.type)) return false;
    return includeReadonly || !f.readonly;
  }

  /// The fields of the form: the required ones first, then by name.
  static List<OdooField> editableFields(OdooModelInfo info, {bool includeReadonly = false}) {
    final fields = [for (final f in info.fields) if (isEditable(f, includeReadonly: includeReadonly)) f];
    fields.sort((a, b) {
      if (a.required != b.required) return a.required ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return fields;
  }

  static final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _datetime = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$');

  static bool _calendar(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    final date = DateTime.utc(y, m, d);
    return date.year == y && date.month == m && date.day == d;
  }

  /// Reads what was typed for [f]. [error] says what is wrong (and the value is then null); a `{{token}}` is accepted
  /// for every type that is not text, and stays a token.
  static ({Object? value, String? error}) parse(OdooField f, String raw) {
    final text = raw.trim();
    final token = OdooToken.tryParse(raw);
    switch (f.type) {
      case 'char' || 'text' || 'html' || 'reference':
        return (value: raw, error: null);
      case 'boolean':
        final lower = text.toLowerCase();
        if (lower == 'true' || lower == 'yes' || lower == '1') return (value: true, error: null);
        if (lower == 'false' || lower == 'no' || lower == '0' || text.isEmpty) return (value: false, error: null);
        return token != null ? (value: token, error: null) : (value: null, error: 'Enter true or false.');
      case 'integer' || 'many2one' || 'many2one_reference':
        if (token != null) return (value: token, error: null);
        final n = int.tryParse(text);
        if (n != null) return (value: n, error: null);
        return (value: null, error: f.type == 'integer' ? 'Enter a whole number.' : 'Enter the id of a ${f.relation ?? 'record'}: pick one from the list, or type its number.');
      case 'float' || 'monetary':
        if (token != null) return (value: token, error: null);
        final n = num.tryParse(text);
        return n != null ? (value: n, error: null) : (value: null, error: 'Enter a number such as 12.5.');
      case 'date':
        if (token != null) return (value: token, error: null);
        final m = _date.firstMatch(text);
        if (m != null && _calendar(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))) return (value: text, error: null);
        return (value: null, error: 'Use YYYY-MM-DD, for example 2026-10-06.');
      case 'datetime':
        if (token != null) return (value: token, error: null);
        final m = _datetime.firstMatch(text);
        if (m != null && _calendar(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)) && int.parse(m[4]!) < 24 && int.parse(m[5]!) < 60 && int.parse(m[6]!) < 60) {
          return (value: text.replaceFirst('T', ' '), error: null);
        }
        return (value: null, error: 'Use YYYY-MM-DD HH:MM:SS in UTC, for example 2026-10-06 14:30:00.');
      case 'selection':
        if (f.selection.isEmpty) return (value: raw, error: null);
        return f.selection.any((s) => s.$1 == text)
            ? (value: text, error: null)
            : (value: null, error: 'Choose one of: ${f.selection.map((s) => s.$1).join(', ')}.');
      case 'json':
        try {
          return (value: jsonDecode(text), error: null);
        } on FormatException catch (e) {
          return (value: null, error: 'Not valid JSON: ${e.message}');
        }
    }
    return (value: raw, error: null);
  }

  /// The text a value is shown as in its box; the inverse of [parse].
  static String format(OdooField f, Object? value) {
    if (value == null || value == false && f.type != 'boolean') return '';
    if (value is OdooToken) return value.text;
    if (f.type == 'json') return jsonEncode(value);
    return '$value';
  }

  // --- a record read from the server -------------------------------------------------------------------------------

  /// The fields to ask `read` for so that [fromRecord] has what it needs: the editable ones.
  static List<String> readFields(OdooModelInfo info, {bool includeReadonly = false}) =>
      [for (final f in info.fields) if (isEditable(f, includeReadonly: includeReadonly)) f.name];

  /// A record as read (`many2one` as `[id, name]`, `one2many` / `many2many` as lists of ids, `false` for an unset
  /// value) turned into the values of an editable payload: read-only, computed, binary and Odoo's own fields dropped,
  /// a many2one reduced to its id, an x2many list to `[6, 0, ids]`, unset values left out (a boolean stays).
  static Map<String, Object?> fromRecord(OdooModelInfo info, Map<String, Object?> record, {bool includeReadonly = false}) {
    final out = <String, Object?>{};
    for (final f in info.fields) {
      if (!isEditable(f, includeReadonly: includeReadonly) || !record.containsKey(f.name)) continue;
      final v = record[f.name];
      if (f.type == 'boolean') {
        if (v is bool) out[f.name] = v;
        continue;
      }
      if (v == null || v == false) continue;
      switch (f.type) {
        case 'many2one':
          if (v is List && v.isNotEmpty && v.first is int) {
            out[f.name] = v.first;
          } else if (v is int) {
            out[f.name] = v;
          }
        case 'one2many' || 'many2many':
          if (v is List && v.isNotEmpty && v.every((e) => e is int)) out[f.name] = [SetCommand(List<Object>.from(v))];
        default:
          out[f.name] = v;
      }
    }
    return out;
  }

  /// The values `default_get` returned as form values: an x2many default is a list of commands.
  static Map<String, Object?> fromDefaults(OdooModelInfo info, Map<String, Object?> defaults) {
    final out = <String, Object?>{};
    for (final entry in defaults.entries) {
      final f = info.field(entry.key);
      if (f == null || !isEditable(f, includeReadonly: true)) continue;
      final v = entry.value;
      if (f.isX2many) {
        final commands = X2ManyCommand.listFromJson(v);
        if (commands != null && commands.isNotEmpty) out[f.name] = commands;
      } else if (f.type == 'many2one') {
        if (v is int) {
          out[f.name] = v;
        } else if (v is List && v.isNotEmpty && v.first is int) {
          out[f.name] = v.first;
        }
      } else if (v != null && !(v == false && f.type != 'boolean')) {
        out[f.name] = v;
      }
    }
    return out;
  }

  // --- the body ----------------------------------------------------------------------------------------------------

  /// The ids of a `write` or `copy` as typed: numbers and `{{tokens}}`, separated by commas or spaces.
  /// Null for a piece that is neither; [idsVariable] stands in when nothing was typed.
  static ({List<Object> ids, String? error}) parseIds(String raw) {
    final ids = <Object>[];
    final pieces = RegExp(r'\{\{[^{}]+\}\}|[^\s,]+').allMatches(raw).map((m) => m[0]!);
    for (final p in pieces) {
      final n = int.tryParse(p);
      final t = OdooToken.tryParse(p);
      if (n != null) {
        ids.add(n);
      } else if (t != null) {
        ids.add(t);
      } else {
        return (ids: const [], error: '"$p" is not a record id: use numbers separated by commas.');
      }
    }
    return (ids: ids, error: null);
  }

  /// The body of `create`, `write` or `copy` for [model], as text, for [protocol]: JSON-2's named arguments, or the
  /// `call_kw` envelope of Odoo 18 and older. [values] holds typed values (an [OdooToken] stays a bare token, a list
  /// of [X2ManyCommand] becomes command arrays). With no [ids] a `write` uses `[{{idsVariable}}]`, a variable that is
  /// left undefined on purpose so it cannot touch a record nobody chose.
  static String bodyText({
    required OdooProtocol protocol,
    required String model,
    required String method,
    required Map<String, Object?> values,
    List<Object> ids = const [],
    String? idsVariable = OdooVars.recordId,
  }) {
    final tokens = <String, String>{};
    final vals = _plain(values, tokens);
    final named = <String, Object?>{};
    if (method == 'create') {
      named['vals_list'] = [vals];
    } else {
      named['ids'] = ids.isNotEmpty
          ? [for (final id in ids) _plain(id, tokens)]
          : (idsVariable == null ? <Object?>[] : [_plain(OdooToken('{{$idsVariable}}'), tokens)]);
      named[method == 'write' ? 'vals' : 'default'] = vals;
    }
    final root = protocol == OdooProtocol.json2 ? named : OdooJsonRpc.callBodyOf(model, method, named);
    return _tidy(OdooJsonDoc(null, tokens).encode(root));
  }

  /// `[{{recordId}}]` reads better in one piece than the pretty printer's three lines.
  static String _tidy(String text) => text.replaceAllMapped(RegExp(r'\[\s*(\{\{[^{}]+\}\})\s*\]'), (m) => '[${m[1]}]');

  /// [v] as plain JSON values, each [OdooToken] replaced by a placeholder that [tokens] writes back as the bare token.
  static Object? _plain(Object? v, Map<String, String> tokens) {
    switch (v) {
      case OdooToken():
        final name = OdooJsonDoc.placeholder(tokens.length);
        tokens[name] = v.text;
        return name;
      case X2ManyCommand():
        return _plain(v.toJson(), tokens);
      case Map():
        return {for (final e in v.entries) '${e.key}': _plain(e.value, tokens)};
      case List():
        return [for (final e in v) _plain(e, tokens)];
      default:
        return v;
    }
  }

  /// A value (values of a nested record, say) as JSON text, with tokens written bare.
  static String encodeValue(Object? value, {bool indent = true}) {
    final tokens = <String, String>{};
    final plain = _plain(value, tokens);
    final text = OdooJsonDoc(null, tokens).encode(plain, indent: indent);
    return _tidy(text);
  }

  /// The inverse of [encodeValue]: JSON text, with bare `{{tokens}}` read back as [OdooToken]s.
  static ({Object? value, String? error}) decodeValue(String text) {
    final parsed = OdooJsonDoc.parse(text);
    final doc = parsed.doc;
    if (doc == null) return (value: null, error: parsed.error);
    Object? back(Object? v) => switch (v) {
          String() when doc.tokens.containsKey(v) => OdooToken(doc.tokens[v]!),
          Map() => {for (final e in v.entries) '${e.key}': back(e.value)},
          List() => [for (final e in v) back(e)],
          _ => v,
        };
    return (value: back(doc.value), error: null);
  }
}
