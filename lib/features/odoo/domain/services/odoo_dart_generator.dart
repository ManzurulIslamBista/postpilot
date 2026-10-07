import '../../../dart_codegen/domain/entities/generated_file.dart';
import '../../../dart_codegen/domain/services/dart_model_generator.dart' show DartModelStyle;
import '../../../dart_codegen/domain/services/dart_names.dart';
import '../entities/odoo_model_info.dart';

class OdooDartOptions {
  /// Fields to keep, by name. `null` keeps every stored field.
  final Set<String>? fieldNames;

  /// Keep computed (non-stored) fields too.
  final bool includeComputed;

  /// A `selection` field with at most this many values becomes an enum.
  final int enumLimit;

  /// How the class serialises: by hand ([DartModelStyle.plain], the default), or annotated for json_serializable / freezed
  /// (run build_runner). All three read Odoo's JSON the same way (`false` for an empty value, `[id, name]` for a
  /// many2one, UTC datetimes) through the helpers of `odoo_json.dart`.
  final DartModelStyle style;

  /// The folder (below the project root) the model and the support file are written to.
  final String folder;

  /// The class name and file name to use instead of the ones derived from the model name (the client generator
  /// needs unique ones when two models would produce the same).
  final String? className;
  final String? fileName;

  /// Leave `binary` fields (images, attachments) out: a list read would download all of them.
  final bool skipBinary;

  const OdooDartOptions({
    this.fieldNames,
    this.includeComputed = false,
    this.enumLimit = 12,
    this.style = DartModelStyle.plain,
    this.folder = 'lib/models',
    this.className,
    this.fileName,
    this.skipBinary = false,
  });
}

/// Turns an Odoo model's `fields_get` into a Dart class that reads Odoo's
/// real JSON: an empty value is `false` (not `null`), a many2one is
/// `[id, "name"]`, a datetime is `"2026-10-02 10:00:00"` in UTC. The class
/// also lists its field names, ready for the `fields` parameter of `search_read`.
final class OdooDartGenerator {
  const OdooDartGenerator();

  static const supportPath = 'odoo_json.dart';

  /// The fields of [model] that [options] keep, in the order of the model.
  static List<OdooField> selectFields(OdooModelInfo model, OdooDartOptions options) => [
        for (final f in model.fields)
          if ((options.includeComputed || f.stored) &&
              (options.fieldNames?.contains(f.name) ?? true) &&
              !(options.skipBinary && f.type == 'binary'))
            f,
      ];

  List<GeneratedFile> generate(OdooModelInfo model, {OdooDartOptions options = const OdooDartOptions()}) {
    final className = options.className ?? DartNames.pascal(model.model);
    final fields = selectFields(model, options);
    final enums = <String, OdooField>{};
    for (final f in fields) {
      if (f.type == 'selection' && f.selection.isNotEmpty && f.selection.length <= options.enumLimit) {
        enums['$className${DartNames.pascal(f.name)}'] = f;
      }
    }
    final fileName = options.fileName ?? DartNames.snake(model.model, fallback: 'model');
    final path = '${options.folder}/$fileName.dart';
    // Shared by every generated model, so a copy already in the project is kept.
    final support = GeneratedFile('${options.folder}/$supportPath', _supportFile, shared: true);
    if (options.style != DartModelStyle.plain) {
      return [GeneratedFile(path, _annotated(model, className, fileName, fields, enums, options).trimRight()), support];
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

    return [GeneratedFile(path, b.toString().trimRight()), support];
  }

  // --- json_serializable and freezed ----------------------------------------------------

  /// The same class with annotations instead of hand-written code. Every field names the helper of `odoo_json.dart`
  /// that reads it, so Odoo's `false` for an empty value, its `[id, name]` pairs and its UTC datetimes come out right
  /// without a custom converter class per type.
  String _annotated(
    OdooModelInfo model,
    String className,
    String fileName,
    List<OdooField> fields,
    Map<String, OdooField> enums,
    OdooDartOptions options,
  ) {
    final freezed = options.style == DartModelStyle.freezed;
    final names = {for (final f in fields) f.name: DartNames.camel(f.name)};
    String enumOf(OdooField f) => '$className${DartNames.pascal(f.name)}';
    final b = StringBuffer()
      ..writeln(freezed ? "import 'package:freezed_annotation/freezed_annotation.dart';" : "import 'package:json_annotation/json_annotation.dart';")
      ..writeln()
      ..writeln("import '$supportPath';")
      ..writeln()
      ..writeln(freezed ? "part '$fileName.freezed.dart';" : "part '$fileName.g.dart';");
    if (freezed) b.writeln("part '$fileName.g.dart';");
    b.writeln();
    enums.forEach((name, f) => b
      ..writeln(_enum(name, f, withToOdoo: true))
      ..writeln());

    String annotation(OdooField f) {
      final enumName = enumOf(f);
      final isEnum = enums.containsKey(enumName);
      final fromJson = _fromJsonFunction(f, enumName, isEnum);
      final toJson = _toJsonFunction(f, enumName, isEnum);
      final parts = <String>[
        if (names[f.name] != f.name) 'name: ${DartNames.quote(f.name)}',
        if (fromJson != null) 'fromJson: $fromJson',
        if (toJson != null) 'toJson: $toJson',
        if (f.name == 'id' || (f.readonly && !f.required)) 'includeToJson: false',
        if (_type(f, enumName, enums).endsWith('?')) 'includeIfNull: false',
      ];
      return parts.isEmpty ? '' : '@JsonKey(${parts.join(', ')})';
    }

    b.writeln('/// ${model.model}');
    if (freezed) {
      b
        ..writeln('@freezed')
        ..writeln('abstract class $className with _\$$className {')
        ..writeln('  const factory $className({');
      for (final f in fields) {
        if (f.help != null || f.label != f.name) b.writeln('    /// ${_oneLine(f.help ?? f.label)}');
        final type = _type(f, enumOf(f), enums);
        final fallback = switch (f.type) {
          'boolean' => '@Default(false) ',
          'one2many' || 'many2many' => '@Default(<int>[]) ',
          _ => '',
        };
        final prefix = [annotation(f), fallback.trim()].where((s) => s.isNotEmpty).join(' ');
        b.writeln('    ${prefix.isEmpty ? '' : '$prefix '}$type ${names[f.name]},');
      }
      b
        ..writeln('  }) = _$className;')
        ..writeln()
        ..writeln('  /// The field names to send as `fields` in search_read / read.')
        ..writeln('  static const fieldNames = [${fields.map((f) => DartNames.quote(f.name)).join(', ')}];')
        ..writeln()
        ..writeln('  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);')
        ..writeln('}');
    } else {
      b
        ..writeln('@JsonSerializable()')
        ..writeln('class $className {');
      for (final f in fields) {
        if (f.help != null || f.label != f.name) b.writeln('  /// ${_oneLine(f.help ?? f.label)}');
        final a = annotation(f);
        if (a.isNotEmpty) b.writeln('  $a');
        b.writeln('  final ${_type(f, enumOf(f), enums)} ${names[f.name]};');
      }
      b
        ..writeln()
        ..writeln('  const $className({');
      for (final f in fields) {
        b.writeln('    this.${names[f.name]}${_default(f)},');
      }
      b
        ..writeln('  });')
        ..writeln()
        ..writeln('  /// The field names to send as `fields` in search_read / read.')
        ..writeln('  static const fieldNames = [${fields.map((f) => DartNames.quote(f.name)).join(', ')}];')
        ..writeln()
        ..writeln('  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);')
        ..writeln()
        ..writeln('  /// Values to send to create / write: unset (null) fields and read-only ones are left out.')
        ..writeln('  Map<String, dynamic> toJson() => _\$${className}ToJson(this);')
        ..writeln('}');
    }
    return b.toString();
  }

  /// The helper that reads the field; none for a `dynamic` one, which takes the value as it is.
  String? _fromJsonFunction(OdooField f, String enumName, bool isEnum) => switch (f.type) {
        'integer' => 'odooInt',
        'float' || 'monetary' => 'odooDouble',
        'boolean' => 'odooBool',
        'date' => 'odooDate',
        'datetime' => 'odooDateTime',
        'many2one' => 'OdooRef.from',
        'one2many' || 'many2many' => 'odooIds',
        'json' || 'properties' => null,
        'selection' when isEnum => '$enumName.fromOdoo',
        _ => 'odooString',
      };

  String? _toJsonFunction(OdooField f, String enumName, bool isEnum) => switch (f.type) {
        'date' => 'odooDateToJson',
        'datetime' => 'odooDateTimeToJson',
        'many2one' => 'odooRefToJson',
        'selection' when isEnum => '$enumName.toOdoo',
        _ => null,
      };

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

  /// [withToOdoo] adds the static `toOdoo` that json_serializable / freezed name as the field's `toJson`.
  String _enum(String name, OdooField f, {bool withToOdoo = false}) {
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
      ..writeln('  }');
    if (withToOdoo) {
      b
        ..writeln()
        ..writeln('  static String? toOdoo($name? value) => value?.odoo;');
    }
    b.write('}');
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
  bool operator ==(Object other) => other is OdooRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

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

/// What `write` takes for a many2one: the id.
int? odooRefToJson(OdooRef? v) => v?.id;

/// `2026-10-02`.
String? odooDateToJson(DateTime? v) => v?.toIso8601String().substring(0, 10);

String? odooDateTimeToJson(DateTime? v) => v == null ? null : odooFormatDateTime(v);
''';
}
