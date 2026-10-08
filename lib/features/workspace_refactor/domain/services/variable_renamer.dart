import '../../../../core/constants/app_constants.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../entities/field_builders.dart';
import '../entities/refactor_plan.dart';
import '../entities/refactor_scope.dart';
import '../entities/unit_field.dart';
import '../entities/workspace_snapshot.dart';
import 'text_finder.dart';

/// Renames a variable everywhere: the definitions (an environment, global, collection or folder variable, an
/// extractor's target) and every `{{old}}` reference in a URL, header, body, auth, test, note or default, with or
/// without spaces inside the braces (`{{ old }}` stays `{{ new }}`).
///
/// Only the whole name counts: `{{baseUrlV2}}`, `{{base}}` and the dynamic `{{$guid}}` are other names and are not
/// touched. Saved response examples and tags are not touched either: they hold data, not references.
///
/// When a scope already defines the new name, the plan lists it as a conflict. Merging then deletes the old definition
/// of any scope that holds both (the existing value wins) and lets the references of the old name point at the
/// existing variable; the user has to confirm that before the plan is applied.
abstract final class VariableRenamer {
  /// A name as typed: `{{ baseUrl }}` and ` baseUrl ` are both baseUrl, since people paste the token they see.
  static String clean(String typed) {
    final text = typed.trim();
    final braces = RegExp(r'^\{\{\s*(.*?)\s*\}\}$').firstMatch(text);
    return braces == null ? text : braces[1]!;
  }

  /// Why [oldName] cannot be renamed to [newName], or null when it can.
  static String? validate(String oldName, String newName) {
    final from = clean(oldName);
    final to = clean(newName);
    if (from.isEmpty) return 'Pick the variable to rename.';
    if (to.isEmpty) return 'Type the new name.';
    if (!_isName(from)) return '"$from" is not a variable name. Use letters, digits, _ - . and \$ only.';
    if (!_isName(to)) return '"$to" is not a valid variable name. Use letters, digits, _ - . and \$ only.';
    if (from.startsWith(r'$')) return '$from is a built-in dynamic variable and cannot be renamed.';
    if (to.startsWith(r'$')) return 'Names that start with \$ belong to the built-in dynamic variables. Pick another name.';
    if (from == to) return 'The new name is the same as the old one.';
    return null;
  }

  static bool _isName(String name) {
    final token = '{{$name}}';
    return AppConstants.variablePattern.matchAsPrefix(token)?.end == token.length;
  }

  static RefactorPlan plan(WorkspaceSnapshot snapshot, String oldName, String newName) {
    final error = validate(oldName, newName);
    if (error != null) return RefactorPlan.failed(error);
    final from = clean(oldName);
    final to = clean(newName);
    final reference = RegExp('\\{\\{(\\s*)${RegExp.escape(from)}(\\s*)\\}\\}');

    final oldDefinitions = [for (final d in snapshot.definitions) if (d.name == from) d];
    final existing = [for (final d in snapshot.definitions) if (d.name == to) d];

    // A scope that defines both names: the old definition is deleted, the existing one is kept.
    final existingContainers = {for (final d in existing) d.containerKey};
    final merged = [
      for (final d in oldDefinitions)
        if (d.removePath != null && existingContainers.contains(d.containerKey)) d,
    ];
    final mergedContainers = {for (final d in merged) d.containerKey};
    final byContainer = {for (final d in oldDefinitions) d.containerKey: d};

    final conflicts = [
      for (final d in existing)
        RefactorConflict(
          where: d.where,
          existingValue: _shown(d),
          collides: mergedContainers.contains(d.containerKey),
          oldValue: mergedContainers.contains(d.containerKey) ? _shown(byContainer[d.containerKey]!) : '',
        ),
    ];
    final deletions = [
      for (final d in merged)
        RefactorDeletion(
          id: '${d.unitKey}|${d.removePath}',
          unitKey: d.unitKey,
          removePath: d.removePath!,
          keyPath: d.keyPath,
          name: d.name,
          trail: snapshot.unit(d.unitKey)?.trail ?? const [],
          where: d.where,
          shownValue: _shown(d),
          reason: 'Merged into the existing variable "$to"',
        ),
    ];
    // What the deletions take with them is not renamed.
    final removed = <String, List<String>>{
      for (final d in merged) d.unitKey: [for (final m in merged) if (m.unitKey == d.unitKey) m.removePath!],
    };

    final changes = <FieldChange>[];
    for (final unit in snapshot.units) {
      final gone = removed[unit.key];
      if (gone != null && unit.isRow) continue;
      for (final field in unit.fields()) {
        if (gone != null && gone.any((prefix) => field.path.startsWith('$prefix.'))) continue;
        final definition = field.defines;
        final fieldKey = '${unit.key}|${field.path}';
        List<RefactorEdit>? edits;
        if (definition != null) {
          if (definition.name != from) continue;
          final start = field.value.indexOf(from);
          edits = [
            EditSnippets.edit(fieldKey: fieldKey, text: field.value, start: start, end: start + from.length, after: to, secret: false),
          ];
        } else if (field.scope != RefactorScope.examples && field.scope != RefactorScope.tags) {
          for (final match in reference.allMatches(field.value)) {
            (edits ??= []).add(
              EditSnippets.edit(
                fieldKey: fieldKey,
                text: field.value,
                start: match.start,
                end: match.end,
                after: '{{${match[1]}$to${match[2]}}}',
                secret: field.secret,
              ),
            );
          }
        }
        if (edits == null || edits.isEmpty) continue;
        changes.add(
          FieldChange(
            unitKey: unit.key,
            path: field.path,
            group: field.group,
            scope: field.scope,
            label: field.label,
            trail: unit.trail,
            secret: field.secret,
            length: field.value.length,
            edits: edits,
            definition: definition != null,
          ),
        );
      }
    }
    return RefactorPlan(
      title: 'Rename {{$from}} to {{$to}}',
      changes: changes,
      deletions: deletions,
      conflicts: conflicts,
    );
  }

  static String _shown(VariableDefinition d) => d.secret ? SecretMasker.mask : shorten(d.value, 60);
}
