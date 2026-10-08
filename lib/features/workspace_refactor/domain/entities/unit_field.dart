import 'refactor_scope.dart';

/// The kinds of thing the repositories save as one piece. A [RefactorUnit] is one of these, with the text it holds.
enum UnitKind { request, folder, collection, environmentVariable, globalVariable, collectionVariable }

/// Where a variable is defined.
enum VariableHome { environment, global, collection, folder, extractor }

/// One place that defines a variable: the key of an environment, global, collection or folder variable, or the
/// target of an extractor (which fills a variable from a response).
final class VariableDefinition {
  final String name;
  final VariableHome home;

  /// Two definitions with the same container sit in the same scope: one environment, the globals, one collection,
  /// one folder. Defining a name twice in one container is what a rename can turn into a conflict.
  final String containerKey;

  /// Where it is, worded for the user: `Environment "Dev"`, `Globals`, `Folder "Shop / Orders"`.
  final String where;
  final String unitKey;

  /// The field of the unit that holds [name].
  final String keyPath;

  /// What deleting this definition removes from the unit; null when the report may not delete it (an extractor).
  final String? removePath;

  /// What the variable is set to (an extractor: the path it reads). Masked wherever it is shown when [secret].
  final String value;
  final bool secret;
  final bool enabled;

  const VariableDefinition({
    required this.name,
    required this.home,
    required this.containerKey,
    required this.where,
    required this.unitKey,
    required this.keyPath,
    required this.value,
    this.removePath,
    this.secret = false,
    this.enabled = true,
  });

  /// Stable across two reads of the same data.
  String get id => '$unitKey|$keyPath';
}

/// One piece of text a unit holds, addressable by [path] inside it, and the way to put another text there.
final class UnitField {
  /// Unique inside the unit and the same for the same field in two reads of the same data
  /// (`url`, `header.2.value`, `assert.0.expected`).
  final String path;

  /// Fields of one group are written together by one repository call; only the groups an edit touched are written.
  final String group;
  final RefactorScope scope;

  /// What the field is, for the preview: `URL`, `Header "X-Token" value`.
  final String label;
  final String value;

  /// A secret value: never shown in a preview, and left alone by find-and-replace unless the user asked for it.
  final bool secret;

  /// Whether a send reads the text: false for a row that is switched off, and for what is left of an auth type or a
  /// body type that is not the one in use. Find and rename still list it; the unused-and-undefined report does not.
  final bool active;

  /// Set when this field is the name of a variable.
  final VariableDefinition? defines;

  /// A copy of the unit with this field set to the given text.
  final RefactorUnitCopy write;

  const UnitField({
    required this.path,
    required this.group,
    required this.scope,
    required this.label,
    required this.value,
    required this.write,
    this.secret = false,
    this.active = true,
    this.defines,
  });
}

typedef RefactorUnitCopy = RefactorUnit Function(String value);

/// A piece of the workspace the repositories save as one: a request with its tests, notes and examples, a folder, a
/// collection, or one variable. Pure data: [fields] lists every text in it, and [withValues] returns a changed copy,
/// so the matching and replacing engine never touches a repository.
abstract class RefactorUnit {
  const RefactorUnit();

  UnitKind get kind;

  /// The database id of the request, folder, collection or variable row.
  int get id;

  /// `request:12`: unique in a workspace.
  String get key => '${kind.name}:$id';

  /// Where it sits for the preview: the collection, the folders, then the unit itself.
  List<String> get trail;

  /// Whether the unit is a single variable row, which is deleted as a whole.
  bool get isRow => false;

  /// Every non-empty text of the unit, in the order the preview lists them.
  Iterable<UnitField> fields();

  /// A copy without the part [path] names (a folder variable); only units that have such parts support it.
  RefactorUnit removePart(String path) => throw UnsupportedError('$key has no part to remove');

  /// A copy with each field in [values] (by path) set to its text. A path the unit no longer has is an error: the
  /// caller checked the unit still matches what it planned from.
  RefactorUnit withValues(Map<String, String> values) {
    var unit = this;
    for (final entry in values.entries) {
      final field = unit.fields().firstWhere((f) => f.path == entry.key, orElse: () => throw StateError('$key has no ${entry.key}'));
      unit = field.write(entry.value);
    }
    return unit;
  }

  /// The texts of the fields in [groups], by path: what is compared to see whether two copies of a unit hold the same.
  Map<String, String> valuesOf(Set<String> groups) => {
    for (final f in fields())
      if (groups.contains(f.group)) f.path: f.value,
  };
}
