import '../../../../core/utils/variable_resolver.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/services/request_spec_builder.dart';
import '../../../request_builder/domain/services/undefined_variables.dart';
import '../entities/field_builders.dart';
import '../entities/refactor_plan.dart';
import '../entities/refactor_scope.dart';
import '../entities/request_unit.dart';
import '../entities/unit_field.dart';
import '../entities/variable_units.dart';
import '../entities/workspace_snapshot.dart';

/// A variable that is defined and never referenced, with each place that defines it (as a deletion the user may tick).
final class UnusedVariable {
  final String name;
  final List<RefactorDeletion> definitions;
  const UnusedVariable(this.name, this.definitions);
}

/// A `{{name}}` that is used and defined nowhere, with where it is used.
final class UndefinedVariableUse {
  final String name;

  /// `Shop / Orders / List orders: the URL, the "X-Token" header`.
  final List<String> places;

  /// A definition that exists but cannot count, e.g. `only defined while disabled, in Environment "Dev"`.
  final String? hint;

  const UndefinedVariableUse(this.name, this.places, {this.hint});
}

/// Which variables nothing uses, and which names are used without being defined.
///
/// "Defined" means an enabled environment, global, collection or folder variable, or the target of an extractor, in
/// any scope of the workspace; "used" is a `{{name}}` (spaces inside the braces allowed) in any text, or in the value
/// of another variable. The undefined half asks the same questions a send does (see `RequestSpecBuilder`), so the
/// built-in `{{$guid}}` family is not reported, and a variable set only to empty counts as defined. Odoo's live
/// `{{xmlid:...}}` and `{{ref:...}}` references are not variables and are not reported either.
///
/// It reads the workspace, not the world: a variable may still be used by a command-line run, an exported `.env` file
/// or a teammate's collection, so the unused list is a list of candidates.
abstract final class VariableReport {
  static final _reference = RegExp(r'\{\{\s*([\w.$-]+)\s*\}\}');

  static ({List<UnusedVariable> unused, List<UndefinedVariableUse> undefined}) build(WorkspaceSnapshot snapshot) {
    final definitions = snapshot.definitions;
    final defined = {for (final d in definitions) if (d.enabled) d.name};

    final referenced = <String>{};
    for (final unit in snapshot.units) {
      for (final field in unit.fields()) {
        if (field.defines != null || !field.value.contains('{{')) continue;
        for (final match in _reference.allMatches(field.value)) {
          referenced.add(match[1]!);
        }
      }
    }

    final unusedByName = <String, List<RefactorDeletion>>{};
    for (final d in definitions) {
      if (d.removePath == null || referenced.contains(d.name)) continue;
      unusedByName
          .putIfAbsent(d.name, () => [])
          .add(
            RefactorDeletion(
              id: '${d.unitKey}|${d.removePath}',
              unitKey: d.unitKey,
              removePath: d.removePath!,
              keyPath: d.keyPath,
              name: d.name,
              trail: snapshot.unit(d.unitKey)?.trail ?? const [],
              where: d.where,
              shownValue: d.secret ? SecretMasker.mask : shorten(d.value, 60),
              reason: 'Never referenced',
            ),
          );
    }
    final names = unusedByName.keys.toList()..sort(compareNames);
    final unused = [for (final name in names) UnusedVariable(name, unusedByName[name]!)];

    return (unused: unused, undefined: _undefined(snapshot, defined, definitions));
  }

  static List<UndefinedVariableUse> _undefined(
    WorkspaceSnapshot snapshot,
    Set<String> defined,
    List<VariableDefinition> definitions,
  ) {
    final resolver = VariableResolver.layered([
      {for (final name in defined) name: ''},
    ]);
    final builder = RequestSpecBuilder();
    final places = <String, List<String>>{};

    void add(String name, String place) {
      // Odoo's `{{xmlid:...}}` and `{{ref:...}}` are looked up on the server, not defined by a variable.
      if (name.startsWith('xmlid:') || name.startsWith('ref:')) return;
      final list = places.putIfAbsent(name, () => []);
      if (!list.contains(place)) list.add(place);
    }

    for (final unit in snapshot.units) {
      final where = unit.trail.join(' / ');
      // What a send reads from the request itself (an inherited header or auth is read where it is set, below).
      if (unit is RequestUnit) {
        final uses = builder.undefinedVariables(unit.request, resolver);
        for (final UndefinedVariable use in uses) {
          add(use.name, '$where: ${_join(use.places)}');
        }
      }
      // Whatever a send does not read from the request: its tests, what the collections and folders pass down, and
      // the value of a variable.
      for (final field in unit.fields()) {
        if (!field.active || !field.value.contains('{{') || !_scanned(unit, field)) continue;
        for (final name in resolver.undefinedIn(field.value)) {
          add(name, '$where: ${field.label}');
        }
      }
    }

    final names = places.keys.toList()..sort(compareNames);
    return [
      for (final name in names)
        UndefinedVariableUse(
          name,
          places[name]!,
          hint: _hint([for (final d in definitions) if (d.name == name && !d.enabled) d.where]),
        ),
    ];
  }

  /// Fields a send does not read from the request itself (see `RequestSpecBuilder.undefinedVariables` for those).
  static bool _scanned(RefactorUnit unit, UnitField field) {
    if (field.defines != null) return false;
    if (unit is RequestUnit) return field.scope == RefactorScope.scripts;
    if (unit is VariableRowUnit) return field.path == 'value';
    return field.scope == RefactorScope.defaults || field.scope == RefactorScope.variables;
  }

  static String? _hint(List<String> disabledIn) =>
      disabledIn.isEmpty ? null : 'It is defined, but only while disabled: ${{...disabledIn}.join(', ')}.';

  static String _join(List<String> places) => switch (places.length) {
    1 => places.single,
    2 => '${places.first} and ${places.last}',
    _ => '${places.sublist(0, places.length - 1).join(', ')} and ${places.last}',
  };
}
