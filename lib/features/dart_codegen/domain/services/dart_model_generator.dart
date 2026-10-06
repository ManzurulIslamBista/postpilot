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

  /// Mark every field nullable and optional, for APIs that omit things
  /// unpredictably. The Plain style then also gets forgiving list parsing, a
  /// `toJson` that skips nulls, and `copyWith`.
  final bool allNullable;

  /// Class names the output must not use because the file that imports it also
  /// sees them (`Options`, `Response` of Dio). Core types (`String`, `List`...)
  /// are always avoided.
  final Set<String> avoidClassNames;

  const DartModelOptions({
    this.style = DartModelStyle.plain,
    this.detectDates = true,
    this.allNullable = false,
    this.avoidClassNames = const {},
  });
}

/// The shape of one JSON position, as the generator typed it.
enum DartFieldKind { string, integer, decimal, boolean, list, object, map, date, dynamicType }

/// One field of a generated class, for generators that build on the models (the test generator).
final class DartFieldInfo {
  /// The key in the JSON.
  final String json;

  /// The Dart field name.
  final String name;

  /// The type as written in the class, without the `?`.
  final String typeName;
  final DartFieldKind kind;
  final bool nullable;

  /// For a list or a map: what the items (values) are.
  final DartFieldKind? itemKind;
  final String? itemTypeName;
  final bool itemNullable;

  const DartFieldInfo({
    required this.json,
    required this.name,
    required this.typeName,
    required this.kind,
    required this.nullable,
    this.itemKind,
    this.itemTypeName,
    this.itemNullable = false,
  });
}

/// One generated class and its fields, in declaration order.
final class DartClassInfo {
  final String name;
  final List<DartFieldInfo> fields;
  const DartClassInfo(this.name, this.fields);
}

class DartModelResult {
  final String code;
  final int classCount;

  /// What the user should know: a root list, mixed types, an unparseable sample.
  final List<String> notes;

  /// The classes in [code], root first. Empty when nothing was generated.
  final List<DartClassInfo> classes;

  const DartModelResult(this.code, this.classCount, this.notes, {this.classes = const []});
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
    options = _avoidAnnotationNames(options);
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

    final root = DartNames.className(rootName, fallback: 'Root', also: options.avoidClassNames);
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
      buffer.write(_emit(classes[i], options));
    }
    return DartModelResult(
      buffer.toString().trimRight(),
      classes.length,
      notes,
      classes: [
        for (final c in classes)
          DartClassInfo(c.name, [
            for (final f in c.fields)
              DartFieldInfo(
                json: f.json,
                name: f.name,
                typeName: f.type.name,
                kind: f.type.kind,
                nullable: f.nullable,
                itemKind: f.type.item?.kind,
                itemTypeName: f.type.item?.name,
                itemNullable: f.type.itemNullable,
              ),
          ]),
      ],
    );
  }

  /// The generated file imports json_annotation / freezed_annotation, whose public
  /// names a class of ours must not shadow.
  static const _annotationTypes = {'JsonKey', 'JsonSerializable', 'JsonConverter', 'JsonEnum', 'JsonValue', 'JsonLiteral', 'Freezed', 'Default', 'Assert'};

  DartModelOptions _avoidAnnotationNames(DartModelOptions o) => o.style == DartModelStyle.plain
      ? o
      : DartModelOptions(
          style: o.style,
          detectDates: o.detectDates,
          allNullable: o.allNullable,
          avoidClassNames: {...o.avoidClassNames, ..._annotationTypes},
        );

  // --- shape collection ----------------------------------------------------

  /// Resolves the merged shape into a Dart type and registers nested classes.
  _TypeRef _typeOf(_Shape shape, String suggestedName, List<_ClassSpec> classes, Set<String> taken, DartModelOptions o) {
    final kinds = shape.kinds;
    if (kinds.isEmpty) return const _TypeRef('dynamic', DartFieldKind.dynamicType);
    if (kinds.length > 1) {
      // int + double widens to double; null alone does not count as a kind.
      if (kinds.length == 2 && kinds.containsAll({DartFieldKind.integer, DartFieldKind.decimal})) {
        return const _TypeRef('double', DartFieldKind.decimal);
      }
      return const _TypeRef('dynamic', DartFieldKind.dynamicType);
    }
    switch (kinds.single) {
      case DartFieldKind.string:
        return shape.allDates && o.detectDates
            ? const _TypeRef('DateTime', DartFieldKind.date)
            : const _TypeRef('String', DartFieldKind.string);
      case DartFieldKind.integer:
        return const _TypeRef('int', DartFieldKind.integer);
      case DartFieldKind.decimal:
        return const _TypeRef('double', DartFieldKind.decimal);
      case DartFieldKind.boolean:
        return const _TypeRef('bool', DartFieldKind.boolean);
      case DartFieldKind.list:
        final item = _typeOf(shape.items!, DartNames.singular(suggestedName), classes, taken, o);
        final itemNullable = shape.items!.sawNull;
        return _TypeRef('List<${item.name}${itemNullable ? '?' : ''}>', DartFieldKind.list, item: item, itemNullable: itemNullable);
      case DartFieldKind.object:
        final object = shape.object!;
        if (object.isMapLike) {
          final value = _typeOf(object.mapValue(), '${suggestedName}Value', classes, taken, o);
          return _TypeRef('Map<String, ${value.name}>', DartFieldKind.map, item: value);
        }
        final name = _collect(object, DartNames.className(suggestedName, also: o.avoidClassNames), classes, taken, o);
        return _TypeRef(name, DartFieldKind.object);
      case DartFieldKind.map || DartFieldKind.date || DartFieldKind.dynamicType:
        return const _TypeRef('dynamic', DartFieldKind.dynamicType);
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
          type.kind == DartFieldKind.dynamicType;
      spec.fields.add(_FieldSpec(json: entry.key, name: field, type: type, nullable: nullable && type.name != 'dynamic'));
    }
    return name;
  }

  // --- code emission ---------------------------------------------------------

  String _emit(_ClassSpec c, DartModelOptions o) => switch (o.style) {
        DartModelStyle.plain => o.allNullable ? _plainOptional(c) : _plain(c),
        DartModelStyle.jsonSerializable => _jsonSerializable(c, includeIfNull: !o.allNullable),
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

  /// The "All fields optional" flavour: every field is nullable and optional in
  /// the constructor, list items that do not fit are skipped instead of
  /// throwing, `toJson` leaves out null fields, and `copyWith` is included.
  String _plainOptional(_ClassSpec c) {
    final b = StringBuffer();
    b.writeln('class ${c.name} {');
    if (c.fields.isEmpty) {
      b.writeln('  const ${c.name}();');
    } else {
      b.writeln('  const ${c.name}({');
      for (final f in c.fields) {
        b.writeln('    this.${f.name},');
      }
      b.writeln('  });');
      b.writeln();
      for (final f in c.fields) {
        b.writeln('  final ${_typeDecl(f)} ${f.name};');
      }
    }
    b.writeln();
    b.writeln('  factory ${c.name}.fromJson(Map<String, dynamic> json) => ${c.name}(');
    for (final f in c.fields) {
      b.writeln('        ${f.name}: ${_decodeOptional(f.type, "json[${DartNames.quote(f.json)}]")},');
    }
    b.writeln('      );');
    b.writeln();
    b.writeln('  Map<String, dynamic> toJson() => {');
    for (final f in c.fields) {
      b.writeln('        if (${f.name} != null) ${DartNames.quote(f.json)}: ${_encodeNonNull(f)},');
    }
    b.writeln('      };');
    if (c.fields.isNotEmpty) {
      b.writeln();
      b.writeln('  ${c.name} copyWith({');
      for (final f in c.fields) {
        b.writeln('    ${_typeDecl(f)} ${f.name},');
      }
      b.writeln('  }) =>');
      b.writeln('      ${c.name}(');
      for (final f in c.fields) {
        b.writeln('        ${f.name}: ${f.name} ?? this.${f.name},');
      }
      b.writeln('      );');
    }
    b.writeln('}');
    return b.toString();
  }

  /// Decoding for a field that may be absent or null. Lists tolerate stray
  /// items (nulls, wrong types) by skipping them.
  String _decodeOptional(_TypeRef t, String e) {
    switch (t.kind) {
      case DartFieldKind.string:
        return '$e as String?';
      case DartFieldKind.integer:
        return '($e as num?)?.toInt()';
      case DartFieldKind.decimal:
        return '($e as num?)?.toDouble()';
      case DartFieldKind.boolean:
        return '$e as bool?';
      case DartFieldKind.date:
        return "DateTime.tryParse(($e as String?) ?? '')";
      case DartFieldKind.list:
        final item = t.item!;
        if (item.kind == DartFieldKind.dynamicType) return '$e as List<dynamic>?';
        if (t.itemNullable) return _decode(t, e, true);
        final tail = switch (item.kind) {
          DartFieldKind.string => '.whereType<String>().toList()',
          DartFieldKind.boolean => '.whereType<bool>().toList()',
          DartFieldKind.integer => '.whereType<num>().map((e) => e.toInt()).toList()',
          DartFieldKind.decimal => '.whereType<num>().map((e) => e.toDouble()).toList()',
          DartFieldKind.date => '.whereType<String>().map(DateTime.tryParse).whereType<DateTime>().toList()',
          DartFieldKind.object => '.whereType<Map<String, dynamic>>().map(${item.name}.fromJson).toList()',
          _ => null,
        };
        return tail == null ? _decode(t, e, true) : '($e as List<dynamic>?)?$tail';
      case DartFieldKind.object || DartFieldKind.map || DartFieldKind.dynamicType:
        return _decode(t, e, true);
    }
  }

  /// The value to write under `if (field != null)`; public fields are not
  /// promoted by the analyzer, hence the `!`.
  String _encodeNonNull(_FieldSpec f) {
    final banged = _encode(f.type, '${f.name}!', false);
    return banged == '${f.name}!' ? f.name : banged;
  }

  String _decode(_TypeRef t, String expr, bool nullable) {
    String inner(String e) => switch (t.kind) {
          DartFieldKind.string => '$e as String',
          DartFieldKind.integer => '($e as num).toInt()',
          DartFieldKind.decimal => '($e as num).toDouble()',
          DartFieldKind.boolean => '$e as bool',
          DartFieldKind.date => 'DateTime.parse($e as String)',
          DartFieldKind.object => '${t.name}.fromJson($e as Map<String, dynamic>)',
          DartFieldKind.list when t.item!.kind == DartFieldKind.dynamicType => '$e as List<dynamic>',
          DartFieldKind.list => '($e as List<dynamic>).map((e) => ${_decodeItem(t, "e")}).toList()',
          DartFieldKind.map when t.item!.kind == DartFieldKind.dynamicType => '$e as Map<String, dynamic>',
          DartFieldKind.map => '($e as Map<String, dynamic>).map((k, v) => MapEntry(k, ${_decodeItem(t, "v")}))',
          DartFieldKind.dynamicType => e,
        };
    if (t.kind == DartFieldKind.dynamicType) return expr;
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
      DartFieldKind.date => '$name$q.toIso8601String()',
      DartFieldKind.object => '$name$q.toJson()',
      DartFieldKind.list when _needsMapping(t.item!) =>
        '$name$q.map((e) => ${_encodeItem(t.item!, "e", t.itemNullable)}).toList()',
      DartFieldKind.map when _needsMapping(t.item!) =>
        '$name$q.map((k, v) => MapEntry(k, ${_encodeItem(t.item!, "v", false)}))',
      _ => name,
    };
  }

  bool _needsMapping(_TypeRef t) =>
      t.kind == DartFieldKind.date || t.kind == DartFieldKind.object || ((t.kind == DartFieldKind.list || t.kind == DartFieldKind.map) && _needsMapping(t.item!));

  String _encodeItem(_TypeRef t, String e, bool nullable) {
    final q = nullable ? '?' : '';
    return switch (t.kind) {
      DartFieldKind.date => '$e$q.toIso8601String()',
      DartFieldKind.object => '$e$q.toJson()',
      DartFieldKind.list => '$e$q.map((x) => ${_encodeItem(t.item!, "x", t.itemNullable)}).toList()',
      DartFieldKind.map => '$e$q.map((k, v) => MapEntry(k, ${_encodeItem(t.item!, "v", false)}))',
      _ => e,
    };
  }

  String _jsonSerializable(_ClassSpec c, {required bool includeIfNull}) {
    final b = StringBuffer()
      ..writeln(includeIfNull ? '@JsonSerializable()' : '@JsonSerializable(includeIfNull: false)')
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

class _TypeRef {
  final String name;
  final DartFieldKind kind;
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
  final Set<DartFieldKind> _seen = {};
  bool sawNull = false;
  bool _allDates = true;
  bool _anyString = false;
  _Shape? items;
  _ObjectShape? object;

  bool get hasObject => object != null;

  /// Everything [other] saw, as if its values had been added here too.
  void mergeFrom(_Shape other) {
    _present += other._present;
    sawNull = sawNull || other.sawNull;
    _seen.addAll(other._seen);
    _anyString = _anyString || other._anyString;
    _allDates = _allDates && other._allDates;
    if (other.items != null) (items ??= _Shape()).mergeFrom(other.items!);
    if (other.object != null) (object ??= _ObjectShape()).mergeFrom(other.object!);
  }

  /// Kinds seen, without null.
  Set<DartFieldKind> get kinds => _seen;

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
        _seen.add(DartFieldKind.string);
        _anyString = true;
        if (!DartModelGenerator._iso.hasMatch(s)) _allDates = false;
      case int _:
        _seen.add(DartFieldKind.integer);
      case double _:
        _seen.add(DartFieldKind.decimal);
      case bool _:
        _seen.add(DartFieldKind.boolean);
      case List<dynamic> list:
        _seen.add(DartFieldKind.list);
        final shape = items ??= _Shape();
        for (final item in list) {
          shape.add(item, o);
        }
      case Map<String, dynamic> map:
        _seen.add(DartFieldKind.object);
        (object ??= _ObjectShape()).add(map, o);
      default:
        _seen.add(DartFieldKind.dynamicType);
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

  /// The shape every value of a map-like object has in common. The values are
  /// merged, not picked: a field only some entries have must come out optional,
  /// or reading the others throws.
  _Shape mapValue() {
    final merged = _Shape();
    for (final s in fields.values) {
      merged.mergeFrom(s);
    }
    return merged;
  }

  /// Folds [other] (objects seen elsewhere in the same position) into this one.
  void mergeFrom(_ObjectShape other) {
    count += other.count;
    other.fields.forEach((key, shape) => fields.putIfAbsent(key, _Shape.new).mergeFrom(shape));
  }

  void add(Map<String, dynamic> map, DartModelOptions o) {
    count++;
    map.forEach((key, value) => fields.putIfAbsent(key, _Shape.new).add(value, o));
  }
}
