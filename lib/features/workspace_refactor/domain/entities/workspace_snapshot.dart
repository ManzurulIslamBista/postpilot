import 'unit_field.dart';

/// Names in the order a person reads them: letters without regard to case, then upper case before lower for the same word.
int compareNames(String a, String b) {
  final byLetters = a.toLowerCase().compareTo(b.toLowerCase());
  return byLetters != 0 ? byLetters : a.compareTo(b);
}

/// A variable name some scope defines, for the suggestions of the rename tool.
final class VariableName {
  final String name;

  /// How many places define it (a name set in three environments counts three).
  final int definitions;

  /// Where, worded for the user and without repeats.
  final List<String> homes;

  const VariableName(this.name, this.definitions, this.homes);
}

/// The whole workspace as units of text: every request, folder, collection and variable, each with the texts it holds.
/// Pure data, read once by a `WorkspaceSource`; the finding, renaming and reporting engines work on it without any
/// repository, so they can be tested with plain objects.
///
/// Units come in the order the preview shows them: per collection its own, its top-level requests, then each folder
/// (parents before children) followed by its requests; then the environments' variables and the globals.
final class WorkspaceSnapshot {
  final List<RefactorUnit> units;
  final Map<String, RefactorUnit> _byKey;

  WorkspaceSnapshot(Iterable<RefactorUnit> units) : this._(List.unmodifiable(units));

  WorkspaceSnapshot._(List<RefactorUnit> list) : units = list, _byKey = {for (final unit in list) unit.key: unit};

  static final empty = WorkspaceSnapshot(const []);

  RefactorUnit? unit(String key) => _byKey[key];

  /// Every place that defines a variable, in snapshot order.
  late final List<VariableDefinition> definitions = [
    for (final unit in units)
      for (final field in unit.fields())
        if (field.defines != null) field.defines!,
  ];

  /// The names that are defined somewhere, sorted, for the rename tool to suggest.
  late final List<VariableName> variableNames = _names();

  List<VariableName> _names() {
    final byName = <String, List<VariableDefinition>>{};
    for (final d in definitions) {
      byName.putIfAbsent(d.name, () => []).add(d);
    }
    final names = byName.keys.toList()..sort(compareNames);
    return [
      for (final name in names)
        VariableName(name, byName[name]!.length, {for (final d in byName[name]!) d.where}.toList()),
    ];
  }

  int countOf(UnitKind kind) => units.where((u) => u.kind == kind).length;
}
