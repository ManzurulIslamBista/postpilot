import 'dart:convert';
import 'dart_names.dart';

/// How the generated classes serialise.
enum DartModelStyle {
  plain('Plain Dart', 'fromJson / toJson written by hand, no packages'),
  jsonSerializable('json_serializable', 'annotations + part file (run build_runner)'),
  freezed('freezed', 'immutable unions, copyWith, == (run build_runner)');

  const DartModelStyle(this.label, this.description);

  final String label;
  final String description;
}

class DartModelOptions {
  final DartModelStyle style;

  /// Parse ISO-8601 strings (`2026-10-02T10:00:00Z`) into [DateTime].
  final bool detectDates;

  /// Mark every field nullable, for APIs that omit things unpredictably.
  final bool allNullable;

  const DartModelOptions({this.style = DartModelStyle.plain, this.detectDates = true, this.allNullable = false});
}

class DartModelResult {
  final String code;
  final int classCount;

  /// What the user should know: a root list, mixed types, an unparseable sample.
  final List<String> notes;

  const DartModelResult(this.code, this.classCount, this.notes);
}

/// Turns one or more JSON samples into Dart model classes.
///
/// Several samples of the same endpoint are merged: a field missing from one,
/// or `null` in one, becomes nullable; `int` and `double` together become
/// `double`; conflicting types fall back to `dynamic`. That makes the result
/// far more trustworthy than a single response.
final class DartModelGenerator {
  const DartModelGenerator();

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$');

  DartModelResult generate(
    List<String> samples, {
    String rootName = 'Root',
    DartModelOptions options = const DartModelOptions(),
  }) {
    final notes = <String>[];
    final values = <Object?>[];
    for (final sample in samples) {
      final text = sample.trim();
      if (text.isEmpty) continue;
      try {
        values.add(jsonDecode(text));
      } on FormatException catch (e) {
        notes.add('A sample is not valid JSON and was skipped (${e.message}).');
      }
    }
    if (values.isEmpty) {
      return DartModelResult('', 0, [...notes, 'Paste a JSON response to generate models.']);
    }

    var shape = _Shape();
    var rootIsList = false;
    for (final value in values) {
      if (value is List) {
        rootIsList = true;
        for (final item in value) {
          shape.add(item, options);
        }
      } else {
        shape.add(value, options);
      }
    }
    if (rootIsList) notes.add('The response is a list: parse it with `list.map(${DartNames.pascal(rootName)}.fromJson)`.');
    if (!shape.hasObject) {
      return DartModelResult('', 0, [...notes, 'The response has no JSON object to turn into a class.']);
    }

    final root = DartNames.pascal(rootName, fallback: 'Root');
    final classes = <_ClassSpec>[];
    final taken = <String>{};
    _collect(shape.object!, root, classes, taken, options);

    final fileName = DartNames.snake(root);
    final buffer = StringBuffer();
    switch (options.style) {
      case DartModelStyle.plain:
        break;
      case DartModelStyle.jsonSerializable:
        buffer
          ..writeln("import 'package:json_annotation/json_annotation.dart';")
          ..writeln()
          ..writeln("part '$fileName.g.dart';")
          ..writeln();
      case DartModelStyle.freezed:
        buffer
          ..writeln("import 'package:freezed_annotation/freezed_annotation.dart';")
          ..writeln()
          ..writeln("part '$fileName.freezed.dart';")
          ..writeln("part '$fileName.g.dart';")
          ..writeln();
    }
    for (var i = 0; i < classes.length; i++) {
      if (i > 0) buffer.writeln();
      buffer.write(_emit(classes[i], options.style));
    }
    return DartModelResult(buffer.toString().trimRight(), classes.length, notes);
  }

  // --- shape collection ----------------------------------------------------

  /// Resolves the merged shape into a Dart type and registers nested classes.
  _TypeRef _typeOf(_Shape shape, String suggestedName, List<_ClassSpec> classes, Set<String> taken, DartModelOptions o) {
    final kinds = shape.kinds;
    if (kinds.isEmpty) return const _TypeRef('dynamic', _Kind.dynamicType);
    if (kinds.length > 1) {
      // int + double widens to double; null alone does not count as a kind.
      if (kinds.length == 2 && kinds.containsAll({_Kind.integer, _Kind.decimal})) {
        return const _TypeRef('double', _Kind.decimal);
      }
      return const _TypeRef('dynamic', _Kind.dynamicType);
    }
    switch (kinds.single) {
      case _Kind.string:
        return shape.allDates && o.detectDates
            ? const _TypeRef('DateTime', _Kind.date)
            : const _TypeRef('String', _Kind.string);
      case _Kind.integer:
        return const _TypeRef('int', _Kind.integer);
      case _Kind.decimal:
        return const _TypeRef('double', _Kind.decimal);
      case _Kind.boolean:
        return const _TypeRef('bool', _Kind.boolean);
      case _Kind.list:
        final item = _typeOf(shape.items!, DartNames.singular(suggestedName), classes, taken, o);
        final itemNullable = shape.items!.sawNull;
        return _TypeRef('List<${item.name}${itemNullable ? '?' : ''}>', _Kind.list, item: item, itemNullable: itemNullable);
      case _Kind.object:
        final object = shape.object!;
        if (object.isMapLike) {
          final value = _typeOf(object.mapValue(), '${suggestedName}Value', classes, taken, o);
          return _TypeRef('Map<String, ${value.name}>', _Kind.map, item: value);
        }
        final name = _collect(object, DartNames.pascal(suggestedName), classes, taken, o);
        return _TypeRef(name, _Kind.object);
      case _Kind.map || _Kind.date || _Kind.dynamicType:
        return const _TypeRef('dynamic', _Kind.dynamicType);
    }
  }

  String _collect(_ObjectShape object, String wanted, List<_ClassSpec> classes, Set<String> taken, DartModelOptions o) {
    var name = wanted;
    var n = 2;
    while (taken.contains(name)) {
      name = '$wanted$n';
      n++;
    }
    taken.add(name);
    final spec = _ClassSpec(name);
    classes.add(spec); // Registered first so the root class comes first.
    final usedFields = <String>{};
    for (final entry in object.fields.entries) {
      final shape = entry.value;
      final type = _typeOf(shape, entry.key, classes, taken, o);
      var field = DartNames.camel(entry.key);
      var k = 2;
      while (!usedFields.add(field)) {
        field = '${DartNames.camel(entry.key)}$k';
        k++;
      }
      final nullable = o.allNullable ||
          shape.sawNull ||
          shape.missingIn(object.count) ||
          type.kind == _Kind.dynamicType;
      spec.fields.add(_FieldSpec(json: entry.key, name: field, type: type, nullable: nullable && type.name != 'dynamic'));
    }
    return name;
  }

  // --- code emission ---------------------------------------------------------

  String _emit(_ClassSpec c, DartModelStyle style) => switch (style) {
        DartModelStyle.plain => _plain(c),
        DartModelStyle.jsonSerializable => _jsonSerializable(c),
        DartModelStyle.freezed => _freezed(c),
      };

  String _typeDecl(_FieldSpec f) => '${f.type.name}${f.nullable ? '?' : ''}';

  String _plain(_ClassSpec c) {
    final b = StringBuffer();
    b.writeln('class ${c.name} {');
    for (final f in c.fields) {
      b.writeln('  final ${_typeDecl(f)} ${f.name};');
    }
    if (c.fields.isNotEmpty) b.writeln();
    if (c.fields.isEmpty) {
      b.writeln('  const ${c.name}();');
    } else {
      b.writeln('  const ${c.name}({');
      for (final f in c.fields) {
        b.writeln('    ${f.nullable ? '' : 'required '}this.${f.name},');
      }
      b.writeln('  });');
    }
    b.writeln();
    b.writeln('  factory ${c.name}.fromJson(Map<String, dynamic> json) => ${c.name}(');
    for (final f in c.fields) {
      b.writeln('        ${f.name}: ${_decode(f.type, "json[${DartNames.quote(f.json)}]", f.nullable)},');
    }
    b.writeln('      );');
    b.writeln();
    b.writeln('  Map<String, dynamic> toJson() => {');
    for (final f in c.fields) {
      b.writeln('        ${DartNames.quote(f.json)}: ${_encode(f.type, f.name, f.nullable)},');
    }
    b.writeln('      };');
    b.writeln('}');
    return b.toString();
  }

  String _decode(_TypeRef t, String expr, bool nullable) {
    String inner(String e) => switch (t.kind) {
          _Kind.string => '$e as String',
          _Kind.integer => '($e as num).toInt()',
          _Kind.decimal => '($e as num).toDouble()',
          _Kind.boolean => '$e as bool',
          _Kind.date => 'DateTime.parse($e as String)',
          _Kind.object => '${t.name}.fromJson($e as Map<String, dynamic>)',
          _Kind.list => '($e as List<dynamic>).map((e) => ${_decodeItem(t, "e")}).toList()',
          _Kind.map => '($e as Map<String, dynamic>).map((k, v) => MapEntry(k, ${_decodeItem(t, "v")}))',
          _Kind.dynamicType => e,
        };
    if (t.kind == _Kind.dynamicType) return expr;
    return nullable ? '$expr == null ? null : ${inner(expr)}' : inner(expr);
  }

  String _decodeItem(_TypeRef t, String e) {
    final item = t.item!;
    final nullable = t.itemNullable;
    return _decode(item, e, nullable);
  }

  String _encode(_TypeRef t, String name, bool nullable) {
    final q = nullable ? '?' : '';
    return switch (t.kind) {
      _Kind.date => '$name$q.toIso8601String()',
      _Kind.object => '$name$q.toJson()',
      _Kind.list when _needsMapping(t.item!) =>
        '$name$q.map((e) => ${_encodeItem(t.item!, "e", t.itemNullable)}).toList()',
      _Kind.map when _needsMapping(t.item!) =>
        '$name$q.map((k, v) => MapEntry(k, ${_encodeItem(t.item!, "v", false)}))',
      _ => name,
    };
  }

  bool _needsMapping(_TypeRef t) =>
      t.kind == _Kind.date || t.kind == _Kind.object || ((t.kind == _Kind.list || t.kind == _Kind.map) && _needsMapping(t.item!));

  String _encodeItem(_TypeRef t, String e, bool nullable) {
    final q = nullable ? '?' : '';
    return switch (t.kind) {
      _Kind.date => '$e$q.toIso8601String()',
      _Kind.object => '$e$q.toJson()',
      _Kind.list => '$e$q.map((x) => ${_encodeItem(t.item!, "x", t.itemNullable)}).toList()',
      _Kind.map => '$e$q.map((k, v) => MapEntry(k, ${_encodeItem(t.item!, "v", false)}))',
      _ => e,
    };
  }

  String _jsonSerializable(_ClassSpec c) {
    final b = StringBuffer()
      ..writeln('@JsonSerializable()')
      ..writeln('class ${c.name} {');
    for (final f in c.fields) {
      if (f.json != f.name) b.writeln('  @JsonKey(name: ${DartNames.quote(f.json)})');
      b.writeln('  final ${_typeDecl(f)} ${f.name};');
    }
    if (c.fields.isNotEmpty) b.writeln();
    if (c.fields.isEmpty) {
      b.writeln('  const ${c.name}();');
    } else {
      b.writeln('  const ${c.name}({');
      for (final f in c.fields) {
        b.writeln('    ${f.nullable ? '' : 'required '}this.${f.name},');
      }
      b.writeln('  });');
    }
    b
      ..writeln()
      ..writeln('  factory ${c.name}.fromJson(Map<String, dynamic> json) => _\$${c.name}FromJson(json);')
      ..writeln()
      ..writeln('  Map<String, dynamic> toJson() => _\$${c.name}ToJson(this);')
      ..writeln('}');
    return b.toString();
  }

  String _freezed(_ClassSpec c) {
    final b = StringBuffer()
      ..writeln('@freezed')
      ..writeln('abstract class ${c.name} with _\$${c.name} {');
    if (c.fields.isEmpty) {
      b.writeln('  const factory ${c.name}() = _${c.name};');
    } else {
      b.writeln('  const factory ${c.name}({');
      for (final f in c.fields) {
        if (f.json != f.name) b.writeln('    @JsonKey(name: ${DartNames.quote(f.json)})');
        b.writeln('    ${f.nullable ? '' : 'required '}${_typeDecl(f)} ${f.name},');
      }
      b.writeln('  }) = _${c.name};');
    }
    b
      ..writeln()
      ..writeln('  factory ${c.name}.fromJson(Map<String, dynamic> json) => _\$${c.name}FromJson(json);')
      ..writeln('}');
    return b.toString();
  }
}

// --- inference model -----------------------------------------------------------

enum _Kind { string, integer, decimal, boolean, list, object, map, date, dynamicType }

class _TypeRef {
  final String name;
  final _Kind kind;
  final _TypeRef? item;
  final bool itemNullable;
  const _TypeRef(this.name, this.kind, {this.item, this.itemNullable = false});
}

class _FieldSpec {
  final String json;
  final String name;
  final _TypeRef type;
  final bool nullable;
  const _FieldSpec({required this.json, required this.name, required this.type, required this.nullable});
}

class _ClassSpec {
  final String name;
  final List<_FieldSpec> fields = [];
  _ClassSpec(this.name);
}

/// Everything seen for one JSON position across all samples.
class _Shape {
  final Set<_Kind> _seen = {};
  bool sawNull = false;
  bool _allDates = true;
  bool _anyString = false;
  _Shape? items;
  _ObjectShape? object;

  bool get hasObject => object != null;

  /// Kinds seen, without null.
  Set<_Kind> get kinds => _seen;

  bool get allDates => _anyString && _allDates;

  /// Absent from some of the [total] objects that contain this field.
  bool missingIn(int total) => _present < total;
  int _present = 0;

  void add(Object? value, DartModelOptions o) {
    _present++;
    switch (value) {
      case null:
        sawNull = true;
      case String s:
        _seen.add(_Kind.string);
        _anyString = true;
        if (!DartModelGenerator._iso.hasMatch(s)) _allDates = false;
      case int _:
        _seen.add(_Kind.integer);
      case double _:
        _seen.add(_Kind.decimal);
      case bool _:
        _seen.add(_Kind.boolean);
      case List<dynamic> list:
        _seen.add(_Kind.list);
        final shape = items ??= _Shape();
        for (final item in list) {
          shape.add(item, o);
        }
      case Map<String, dynamic> map:
        _seen.add(_Kind.object);
        (object ??= _ObjectShape()).add(map, o);
      default:
        _seen.add(_Kind.dynamicType);
    }
  }
}

class _ObjectShape {
  final Map<String, _Shape> fields = {};
  int count = 0;

  /// Keys that look like data (ids, dates) rather than names make this a map.
  bool get isMapLike {
    if (fields.length < 6) return false;
    final dataLike = fields.keys.where((k) => RegExp(r'^[0-9a-fA-F-]{8,}$|^\d+$').hasMatch(k)).length;
    return dataLike > fields.length * 0.7;
  }

  _Shape mapValue() {
    final merged = _Shape();
    for (final s in fields.values) {
      merged.sawNull = merged.sawNull || s.sawNull;
      merged._seen.addAll(s._seen);
      merged._present++;
      if (s.object != null) merged.object = s.object;
      if (s.items != null) merged.items = s.items;
      merged._anyString = merged._anyString || s._anyString;
      merged._allDates = merged._allDates && s._allDates;
    }
    return merged;
  }

  void add(Map<String, dynamic> map, DartModelOptions o) {
    count++;
    map.forEach((key, value) => fields.putIfAbsent(key, _Shape.new).add(value, o));
  }
}
