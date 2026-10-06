import 'dart:convert';

/// One field of an Odoo model, as `fields_get` describes it.
final class OdooField {
  final String name;
  final String type;
  final String label;
  final bool required;
  final bool readonly;

  /// False for computed fields that Odoo does not keep in the database.
  final bool stored;

  /// Target model of `many2one` / `one2many` / `many2many`.
  final String? relation;

  /// `(value, label)` pairs of a `selection` field.
  final List<(String, String)> selection;
  final String? help;

  /// The many2one field of the related model that a `one2many` mirrors (`order_id` for `sale.order.order_line`).
  final String? relationField;

  const OdooField({
    required this.name,
    required this.type,
    required this.label,
    this.required = false,
    this.readonly = false,
    this.stored = true,
    this.relation,
    this.selection = const [],
    this.help,
    this.relationField,
  });

  bool get isRelational => type == 'many2one' || type == 'one2many' || type == 'many2many';
  bool get isNumeric => type == 'integer' || type == 'float' || type == 'monetary';
  bool get isX2many => type == 'one2many' || type == 'many2many';

  /// The columns Odoo maintains itself: no payload should write them.
  static const magicNames = {'id', 'create_uid', 'create_date', 'write_uid', 'write_date', 'display_name', '__last_update'};
  bool get isMagic => magicNames.contains(name);
}

/// A model and its fields, read from a `fields_get` response.
final class OdooModelInfo {
  final String model;
  final List<OdooField> fields;
  const OdooModelInfo(this.model, this.fields);

  OdooField? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Accepts the JSON-2 body (`{field: {...}}`) and the legacy JSON-RPC
  /// envelope (`{"result": {field: {...}}}`). Returns `null` when [text] is not
  /// a `fields_get` result.
  static OdooModelInfo? parse(String model, String text) {
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is Map && json['result'] is Map && json['jsonrpc'] != null) json = json['result'];
    if (json is! Map || json.isEmpty) return null;

    final fields = <OdooField>[];
    for (final entry in json.entries) {
      final def = entry.value;
      if (def is! Map || def['type'] is! String) return null;
      final selection = <(String, String)>[];
      final raw = def['selection'];
      if (raw is List) {
        for (final s in raw) {
          if (s is List && s.length >= 2) selection.add(('${s[0]}', '${s[1]}'));
        }
      }
      fields.add(OdooField(
        name: '${entry.key}',
        type: def['type'] as String,
        label: (def['string'] as String?) ?? '${entry.key}',
        required: def['required'] == true,
        readonly: def['readonly'] == true,
        stored: def['store'] != false,
        relation: def['relation'] as String?,
        selection: selection,
        help: def['help'] is String && (def['help'] as String).isNotEmpty ? def['help'] as String : null,
        relationField: def['relation_field'] is String && (def['relation_field'] as String).isNotEmpty
            ? def['relation_field'] as String
            : null,
      ));
    }
    fields.sort((a, b) => a.name == 'id' ? -1 : (b.name == 'id' ? 1 : a.name.compareTo(b.name)));
    return OdooModelInfo(model, fields);
  }
}
