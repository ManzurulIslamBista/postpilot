import 'dart:convert';
import 'api_layer_generator.dart';
import 'dart_model_generator.dart';

/// Whether the app reads a model (a response) or builds it (a request body). It decides what a change breaks: a field
/// that becomes optional breaks the code that reads it; one that becomes required breaks the code that constructs it.
enum SchemaRole {
  response('r'),
  request('q');

  final String code;
  const SchemaRole(this.code);

  static SchemaRole fromCode(Object? code) => code == 'q' ? request : response;
}

/// One field of a generated class: the wire name, the Dart name, the type as written (without the `?`) and whether it is nullable.
final class SchemaField {
  final String json;
  final String name;
  final String type;
  final bool nullable;
  const SchemaField(this.json, this.name, this.type, this.nullable);

  /// The type as it reads in the class: `String?`.
  String get declared => nullable ? '$type?' : type;

  List<Object?> toJson() => [json, name, type, nullable ? 1 : 0];

  static SchemaField? fromJson(Object? value) {
    if (value is! List || value.length < 4 || value[0] is! String || value[1] is! String || value[2] is! String) return null;
    return SchemaField(value[0] as String, value[1] as String, value[2] as String, value[3] == 1);
  }
}

final class SchemaClass {
  final String name;
  final List<SchemaField> fields;
  const SchemaClass(this.name, this.fields);
}

/// The classes of one generated file (or of one pasted sample set).
final class SchemaScope {
  final SchemaRole role;
  final List<SchemaClass> classes;
  const SchemaScope(this.role, this.classes);
}

/// The shape of everything a generation produced, small enough to keep in the settings: class names, field names, types
/// and nullability. Never a value from a response, so there is nothing secret in it.
final class SchemaSnapshot {
  static const currentVersion = 1;

  /// By the file the classes are written to (`lib/features/shop/data/models/list_users_response.dart`), or any key a
  /// caller picks for a sample set.
  final Map<String, SchemaScope> scopes;
  const SchemaSnapshot(this.scopes);

  bool get isEmpty => scopes.isEmpty;

  static SchemaScope scopeOf(DartModelResult result, {SchemaRole role = SchemaRole.response}) => SchemaScope(role, [
        for (final c in result.classes)
          SchemaClass(c.name, [for (final f in c.fields) SchemaField(f.json, f.name, f.typeName, f.nullable)]),
      ]);

  /// A snapshot of one model result (the "JSON to models" tab) under [key].
  static SchemaSnapshot ofModel(String key, DartModelResult result, {SchemaRole role = SchemaRole.response}) =>
      SchemaSnapshot({if (result.classes.isNotEmpty) key: scopeOf(result, role: role)});

  /// A snapshot of every DTO file of an API layer; a body DTO is a request, the rest are responses.
  static SchemaSnapshot ofApiLayer(ApiLayerResult result) => SchemaSnapshot({
        for (final entry in result.models.entries)
          if (entry.value.result.classes.isNotEmpty)
            entry.key: scopeOf(
              entry.value.result,
              role: RegExp(r'Request\d*$').hasMatch(entry.value.root) ? SchemaRole.request : SchemaRole.response,
            ),
      });

  String toText() => jsonEncode({
        'v': currentVersion,
        's': {
          for (final e in scopes.entries)
            e.key: {
              'r': e.value.role.code,
              'c': [
                for (final c in e.value.classes) {'n': c.name, 'f': [for (final f in c.fields) f.toJson()]},
              ],
            },
        },
      });

  /// Reads [text] back; null for anything that is not a snapshot of this version (a damaged setting is no baseline).
  static SchemaSnapshot? tryParse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['v'] != currentVersion || json['s'] is! Map) return null;
      final scopes = <String, SchemaScope>{};
      for (final entry in (json['s'] as Map).entries) {
        final scope = entry.value;
        if (scope is! Map || scope['c'] is! List) return null;
        final classes = <SchemaClass>[];
        for (final c in scope['c'] as List) {
          if (c is! Map || c['n'] is! String || c['f'] is! List) return null;
          final fields = [for (final f in c['f'] as List) SchemaField.fromJson(f)];
          if (fields.contains(null)) return null;
          classes.add(SchemaClass(c['n'] as String, fields.cast<SchemaField>()));
        }
        scopes['${entry.key}'] = SchemaScope(SchemaRole.fromCode(scope['r']), classes);
      }
      return SchemaSnapshot(scopes);
    } catch (_) {
      return null;
    }
  }
}

enum SchemaChangeKind {
  classAdded('Class added'),
  classRemoved('Class removed'),
  fieldAdded('Field added'),
  fieldRemoved('Field removed'),
  fieldRenamed('Field renamed (suspected)'),
  typeChanged('Type changed'),
  nullabilityChanged('Nullability changed');

  final String label;
  const SchemaChangeKind(this.label);
}

final class SchemaChange {
  final SchemaChangeKind kind;

  /// The file (or sample set) the class is in.
  final String scope;
  final String className;

  /// The Dart name of the field (the new one for a rename); null for a class change.
  final String? field;

  /// The old Dart name of a renamed field.
  final String? oldField;

  /// The old and the new type as declared (`int`, `String?`); null where they do not apply.
  final String? before;
  final String? after;

  /// Whether code that compiles against the old classes can stop compiling.
  final bool breaking;

  /// What the change is, in one line.
  final String summary;

  /// What to do in the app code.
  final String advice;

  const SchemaChange({
    required this.kind,
    required this.scope,
    required this.className,
    this.field,
    this.oldField,
    this.before,
    this.after,
    required this.breaking,
    required this.summary,
    required this.advice,
  });
}

/// The structured difference between two [SchemaSnapshot]s.
final class SchemaDiff {
  final List<SchemaChange> changes;
  const SchemaDiff(this.changes);

  bool get isEmpty => changes.isEmpty;
  List<SchemaChange> get breaking => [for (final c in changes) if (c.breaking) c];
  List<SchemaChange> get nonBreaking => [for (final c in changes) if (!c.breaking) c];
  bool get hasBreaking => changes.any((c) => c.breaking);

  /// The changes of each class, in the order the classes appear.
  Map<String, List<SchemaChange>> get byClass {
    final groups = <String, List<SchemaChange>>{};
    for (final c in changes) {
      groups.putIfAbsent(c.className, () => []).add(c);
    }
    return groups;
  }

  /// A text to read before touching the app: what changed per class, what breaks, what to do. Plain text, ready to paste
  /// into a pull request or an issue.
  String migrationNotes() {
    if (changes.isEmpty) return 'The generated models are unchanged.';
    final b = StringBuffer()
      ..writeln('Migration notes: ${changes.length} change${changes.length == 1 ? '' : 's'} '
          '(${breaking.length} breaking, ${nonBreaking.length} non-breaking)');
    void section(String title, List<SchemaChange> list) {
      if (list.isEmpty) return;
      b
        ..writeln()
        ..writeln(title);
      String? current;
      for (final c in list) {
        if (c.className != current) {
          current = c.className;
          b.writeln('  ${c.className}');
        }
        b
          ..writeln('    - ${c.summary}')
          ..writeln('      ${c.advice}');
      }
    }

    section('Breaking: the app may stop compiling until these are handled', breaking);
    section('Non-breaking: nothing has to change', nonBreaking);
    return b.toString().trimRight();
  }
}

/// Compares what was generated last time with what would be generated now.
abstract final class SchemaDiffer {
  static SchemaDiff diff(SchemaSnapshot before, SchemaSnapshot after) {
    final changes = <SchemaChange>[];
    final keys = <String>{...before.scopes.keys, ...after.scopes.keys};
    for (final key in keys) {
      final old = before.scopes[key];
      final now = after.scopes[key];
      final role = (now ?? old)!.role;
      final oldClasses = {for (final c in old?.classes ?? const <SchemaClass>[]) c.name: c};
      final newClasses = {for (final c in now?.classes ?? const <SchemaClass>[]) c.name: c};
      for (final c in oldClasses.values) {
        if (!newClasses.containsKey(c.name)) changes.add(_classRemoved(key, c));
      }
      for (final c in newClasses.values) {
        final previous = oldClasses[c.name];
        if (previous == null) {
          changes.add(_classAdded(key, c));
        } else {
          changes.addAll(_fields(key, role, previous, c));
        }
      }
    }
    return SchemaDiff(changes);
  }

  static SchemaChange _classRemoved(String scope, SchemaClass c) => SchemaChange(
        kind: SchemaChangeKind.classRemoved,
        scope: scope,
        className: c.name,
        breaking: true,
        summary: 'Class ${c.name} no longer exists (${c.fields.length} field${c.fields.length == 1 ? '' : 's'}).',
        advice: 'Remove its imports and every place that reads or builds ${c.name}; the compiler lists them.',
      );

  static SchemaChange _classAdded(String scope, SchemaClass c) => SchemaChange(
        kind: SchemaChangeKind.classAdded,
        scope: scope,
        className: c.name,
        breaking: false,
        summary: 'New class ${c.name} (${c.fields.length} field${c.fields.length == 1 ? '' : 's'}).',
        advice: 'Nothing to change unless you want to use it.',
      );

  static List<SchemaChange> _fields(String scope, SchemaRole role, SchemaClass before, SchemaClass after) {
    final changes = <SchemaChange>[];
    final oldByJson = {for (final f in before.fields) f.json: f};
    final newByJson = {for (final f in after.fields) f.json: f};
    final removed = [for (final f in before.fields) if (!newByJson.containsKey(f.json)) f];
    final added = [for (final f in after.fields) if (!oldByJson.containsKey(f.json)) f];
    final renames = _renames(removed, added);
    final renamedFrom = {for (final r in renames) r.$1.json};
    final renamedTo = {for (final r in renames) r.$2.json};

    for (final f in after.fields) {
      final old = oldByJson[f.json];
      if (old == null) continue;
      changes.addAll(_fieldChanges(scope, role, after.name, old, f));
    }
    for (final (old, now) in renames) {
      changes.add(SchemaChange(
        kind: SchemaChangeKind.fieldRenamed,
        scope: scope,
        className: after.name,
        field: now.name,
        oldField: old.name,
        before: old.declared,
        after: now.declared,
        breaking: true,
        summary: '${old.name} looks renamed to ${now.name} (same type ${old.type}, JSON key "${old.json}" is now "${now.json}").',
        advice: 'Replace `.${old.name}` with `.${now.name}`, and the `${old.name}:` named argument with `${now.name}:`. '
            'If they are unrelated fields, treat it as a removal plus a new field.',
      ));
      if (old.nullable != now.nullable) changes.addAll(_nullability(scope, role, after.name, now, old.nullable, now.nullable));
    }
    for (final f in removed) {
      if (renamedFrom.contains(f.json)) continue;
      changes.add(SchemaChange(
        kind: SchemaChangeKind.fieldRemoved,
        scope: scope,
        className: after.name,
        field: f.name,
        before: f.declared,
        breaking: true,
        summary: 'Field ${f.name} (${f.declared}) was removed.',
        advice: 'Delete every read or write of `.${f.name}`; the compiler lists them.',
      ));
    }
    for (final f in added) {
      if (renamedTo.contains(f.json)) continue;
      final breaking = !f.nullable && role == SchemaRole.request;
      changes.add(SchemaChange(
        kind: SchemaChangeKind.fieldAdded,
        scope: scope,
        className: after.name,
        field: f.name,
        after: f.declared,
        breaking: breaking,
        summary: 'New field ${f.name} (${f.declared})${f.nullable ? ', optional' : ', required'}.',
        advice: f.nullable
            ? 'Nothing to change.'
            : role == SchemaRole.request
                ? 'Add `${f.name}:` to every place that constructs ${after.name}.'
                : 'Nothing to change where it is read; tests that build ${after.name} by hand must now pass `${f.name}:`.',
      ));
    }
    return changes;
  }

  static List<SchemaChange> _fieldChanges(String scope, SchemaRole role, String className, SchemaField old, SchemaField now) {
    final changes = <SchemaChange>[];
    if (old.type != now.type) {
      final listOnlyNullability = old.type.replaceAll('?', '') == now.type.replaceAll('?', '');
      changes.add(SchemaChange(
        kind: SchemaChangeKind.typeChanged,
        scope: scope,
        className: className,
        field: now.name,
        before: old.declared,
        after: now.declared,
        breaking: true,
        summary: 'Field ${now.name} changed from ${old.type} to ${now.type}.',
        advice: listOnlyNullability
            ? 'The list items ${now.type.contains('?') ? 'can now be null: handle null items when you loop over `.${now.name}`' : 'are never null now: null checks on the items can go'}.'
            : 'Update the code that reads or builds `.${now.name}`: arithmetic, casts, comparisons and the widgets that show it.',
      ));
    }
    if (old.nullable != now.nullable) changes.addAll(_nullability(scope, role, className, now, old.nullable, now.nullable));
    return changes;
  }

  static List<SchemaChange> _nullability(String scope, SchemaRole role, String className, SchemaField now, bool wasNullable, bool isNullable) {
    final toNullable = isNullable && !wasNullable;
    final breaking = toNullable ? role == SchemaRole.response : role == SchemaRole.request;
    return [
      SchemaChange(
        kind: SchemaChangeKind.nullabilityChanged,
        scope: scope,
        className: className,
        field: now.name,
        before: wasNullable ? '${now.type}?' : now.type,
        after: isNullable ? '${now.type}?' : now.type,
        breaking: breaking,
        summary: toNullable
            ? 'Field ${now.name} can now be null (${now.type} to ${now.type}?).'
            : 'Field ${now.name} is no longer nullable (${now.type}? to ${now.type}).',
        advice: toNullable
            ? (role == SchemaRole.response
                ? 'Handle null where you read `.${now.name}`: `?? default`, `?.` or a null check.'
                : 'Nothing to change: callers may now leave `${now.name}:` out.')
            : (role == SchemaRole.request
                ? 'Add `${now.name}:` to every place that constructs $className; it is required now.'
                : 'Reading code can drop its null checks; tests that build $className by hand must now pass `${now.name}:`.'),
      ),
    ];
  }

  /// Removed and added fields that are probably one field under a new name: the same type, and either a similar name or
  /// the only pair of that type in the class.
  static List<(SchemaField, SchemaField)> _renames(List<SchemaField> removed, List<SchemaField> added) {
    final candidates = <(double, SchemaField, SchemaField)>[];
    for (final r in removed) {
      for (final a in added) {
        if (r.type != a.type) continue;
        final unique = removed.where((x) => x.type == r.type).length == 1 && added.where((x) => x.type == a.type).length == 1;
        final score = _similarity(r.json, a.json);
        if (unique || score >= 0.5) candidates.add((unique ? 1 + score : score, r, a));
      }
    }
    candidates.sort((x, y) => y.$1.compareTo(x.$1));
    final takenOld = <String>{};
    final takenNew = <String>{};
    final pairs = <(SchemaField, SchemaField)>[];
    for (final (_, r, a) in candidates) {
      if (takenOld.contains(r.json) || takenNew.contains(a.json)) continue;
      takenOld.add(r.json);
      takenNew.add(a.json);
      pairs.add((r, a));
    }
    return pairs;
  }

  /// 0 to 1: how alike two names are (edit distance over the separator-free lowercase text, with a bonus for a shared word).
  static double _similarity(String a, String b) {
    List<String> words(String s) => s
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final wa = words(a);
    final wb = words(b);
    final x = wa.join();
    final y = wb.join();
    if (x.isEmpty || y.isEmpty) return 0;
    final distance = _levenshtein(x, y);
    var score = 1 - distance / (x.length > y.length ? x.length : y.length);
    if (wa.any((w) => w.length >= 3 && wb.contains(w))) score += 0.3;
    return score > 1 ? 1 : score;
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var best = previous[j] + 1;
        if (current[j - 1] + 1 < best) best = current[j - 1] + 1;
        if (previous[j - 1] + cost < best) best = previous[j - 1] + cost;
        current[j] = best;
      }
      previous = current;
    }
    return previous[b.length];
  }
}
