import '../../../dart_codegen/domain/entities/generated_file.dart';
import '../../../dart_codegen/domain/services/dart_names.dart';
import '../entities/odoo_model_info.dart';

class OdooDartOptions {
  /// Fields to keep, by name. `null` keeps every stored field.
  final Set<String>? fieldNames;

  /// Keep computed (non-stored) fields too.
  final bool includeComputed;

  /// A `selection` field with at most this many values becomes an enum.
  final int enumLimit;

  const OdooDartOptions({this.fieldNames, this.includeComputed = false, this.enumLimit = 12});
}

/// Turns an Odoo model's `fields_get` into a Dart class that reads Odoo's
/// real JSON: an empty value is `false` (not `null`), a many2one is
/// `[id, "name"]`, a datetime is `"2026-10-02 10:00:00"` in UTC. The class
/// also lists its field names, ready for the `fields` parameter of `search_read`.
final class OdooDartGenerator {
  const OdooDartGenerator();

  static const supportPath = 'odoo_json.dart';

  List<GeneratedFile> generate(OdooModelInfo model, {OdooDartOptions options = const OdooDartOptions()}) {
    final className = DartNames.pascal(model.model);
    final fields = [
      for (final f in model.fields)
        if ((options.includeComputed || f.stored) && (options.fieldNames?.contains(f.name) ?? true)) f,
    ];
    final enums = <String, OdooField>{};
    for (final f in fields) {
      if (f.type == 'selection' && f.selection.isNotEmpty && f.selection.length <= options.enumLimit) {
        enums['$className${DartNames.pascal(f.name)}'] = f;
      }
    }

    final b = StringBuffer()
      ..writeln("import '$supportPath';")
      ..writeln();
    enums.forEach((name, f) => b
      ..writeln(_enum(name, f))
      ..writeln());

    b
      ..writeln('/// ${model.model}')
      ..writeln('class $className {');
    final names = <String, String>{};
    for (final f in fields) {
      names[f.name] = DartNames.camel(f.name);
    }
    for (final f in fields) {
      if (f.help != null || f.label != f.name) b.writeln('  /// ${_oneLine(f.help ?? f.label)}');
      b.writeln('  final ${_type(f, '$className${DartNames.pascal(f.name)}', enums)} ${names[f.name]};');
    }
    b.writeln();
    b.writeln('  const $className({');
    for (final f in fields) {
      b.writeln('    this.${names[f.name]}${_default(f)},');
    }
    b.writeln('  });');
    b.writeln();
    b.writeln('  /// The field names to send as `fields` in search_read / read.');
    b.writeln('  static const fieldNames = [${fields.map((f) => DartNames.quote(f.name)).join(', ')}];');
    b.writeln();
    b.writeln('  factory $className.fromJson(Map<String, dynamic> json) => $className(');
    for (final f in fields) {
      b.writeln('        ${names[f.name]}: ${_decode(f, "json['${f.name}']", '$className${DartNames.pascal(f.name)}', enums)},');
    }
    b.writeln('      );');
    b.writeln();
    b.writeln('  /// Values to send to create / write: unset (null) fields and read-only ones are left out.');
    b.writeln('  Map<String, dynamic> toJson() => {');
    for (final f in fields) {
      if (f.name == 'id' || (f.readonly && !f.required)) continue;
      final encoded = _encode(f, names[f.name]!, enums.containsKey('$className${DartNames.pascal(f.name)}'));
      b.writeln('        ${encoded.$1}${DartNames.quote(f.name)}: ${encoded.$2},');
    }
    b.writeln('      };');
    b.writeln('}');

    final path = 'lib/models/${DartNames.snake(model.model, fallback: 'model')}.dart';
    return [
      GeneratedFile(path, b.toString().trimRight()),
      const GeneratedFile('lib/models/$supportPath', _supportFile),
    ];
  }

  // --- types -------------------------------------------------------------------

  String _default(OdooField f) => switch (f.type) {
        'boolean' => ' = false',
        'one2many' || 'many2many' => ' = const []',
        _ => '',
      };

  String _type(OdooField f, String enumName, Map<String, OdooField> enums) {
    final base = switch (f.type) {
      'integer' => 'int',
      'float' || 'monetary' => 'double',
      'boolean' => 'bool',
      'date' || 'datetime' => 'DateTime',
      'many2one' => 'OdooRef',
      'one2many' || 'many2many' => 'List<int>',
      'json' || 'properties' => 'dynamic',
      'selection' when enums.containsKey(enumName) => enumName,
      _ => 'String',
    };
    final nonNull = f.type == 'boolean' || f.type == 'one2many' || f.type == 'many2many' || base == 'dynamic';
    return nonNull ? base : '$base?';
  }

  String _decode(OdooField f, String expr, String enumName, Map<String, OdooField> enums) => switch (f.type) {
        'integer' => 'odooInt($expr)',
        'float' || 'monetary' => 'odooDouble($expr)',
        'boolean' => 'odooBool($expr)',
        'date' => 'odooDate($expr)',
        'datetime' => 'odooDateTime($expr)',
        'many2one' => 'OdooRef.from($expr)',
        'one2many' || 'many2many' => 'odooIds($expr)',
        'json' || 'properties' => expr,
        'selection' when enums.containsKey(enumName) => '$enumName.fromOdoo($expr)',
        _ => 'odooString($expr)',
      };

  /// `(prefix, value expression)`: a nullable field is only written when set.
  (String, String) _encode(OdooField f, String name, bool isEnum) {
    final value = switch (f.type) {
      'date' => "$name!.toIso8601String().substring(0, 10)",
      'datetime' => "odooFormatDateTime($name!)",
      'many2one' => '$name!.id',
      'selection' when isEnum => '$name!.odoo',
      _ => f.type == 'boolean' || f.type == 'one2many' || f.type == 'many2many' || f.type == 'json' || f.type == 'properties'
          ? name
          : '$name!',
    };
    final always = f.type == 'boolean' || f.type == 'one2many' || f.type == 'many2many';
    return (always ? '' : 'if ($name != null) ', value);
  }

  String _enum(String name, OdooField f) {
    final used = <String>{};
    String id(String v) {
      var base = DartNames.camel(v, fallback: 'value');
      if (base == 'value' && v.isNotEmpty) base = 'v${DartNames.camel(v)}';
      var n = base;
      var i = 2;
      while (!used.add(n)) {
        n = '$base$i';
        i++;
      }
      return n;
    }

    final entries = [for (final (value, label) in f.selection) (id(value), value, label)];
    final b = StringBuffer()..writeln('/// ${_oneLine(f.label)}')..writeln('enum $name {');
    for (var i = 0; i < entries.length; i++) {
      final (n, value, label) = entries[i];
      b.writeln("  $n(${DartNames.quote(value)}, ${DartNames.quote(label)})${i == entries.length - 1 ? ';' : ','}");
    }
    b
      ..writeln()
      ..writeln('  const $name(this.odoo, this.label);')
      ..writeln()
      ..writeln('  /// The value Odoo stores.')
      ..writeln('  final String odoo;')
      ..writeln()
      ..writeln('  /// The text Odoo shows.')
      ..writeln('  final String label;')
      ..writeln()
      ..writeln('  static $name? fromOdoo(Object? value) {')
      ..writeln('    for (final v in values) {')
      ..writeln('      if (v.odoo == value) return v;')
      ..writeln('    }')
      ..writeln('    return null;')
      ..writeln('  }')
      ..write('}');
    return b.toString();
  }

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _supportFile = r'''/// Reads values the way Odoo sends them: an empty field is `false`, not null.
library;

/// A many2one value: `[id, "display name"]`, or just the id.
class OdooRef {
  final int id;
  final String? name;
  const OdooRef(this.id, [this.name]);

  static OdooRef? from(Object? value) {
    if (value is num) return OdooRef(value.toInt());
    if (value is List && value.isNotEmpty && value.first is num) {
      return OdooRef((value.first as num).toInt(), value.length > 1 && value[1] is String ? value[1] as String : null);
    }
    return null;
  }

  @override
  String toString() => name ?? '#$id';
}

String? odooString(Object? v) => v is String ? v : null;
int? odooInt(Object? v) => v is num ? v.toInt() : null;
double? odooDouble(Object? v) => v is num ? v.toDouble() : null;
bool odooBool(Object? v) => v == true;
DateTime? odooDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Odoo datetimes are UTC and written `2026-10-02 10:00:00`.
DateTime? odooDateTime(Object? v) => v is String ? DateTime.tryParse('${v.replaceFirst(' ', 'T')}Z') : null;

String odooFormatDateTime(DateTime v) {
  final u = v.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
}

List<int> odooIds(Object? v) => v is List ? [for (final e in v) if (e is num) e.toInt()] : const [];
''';
}
