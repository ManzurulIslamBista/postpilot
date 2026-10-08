import '../entities/refactor_plan.dart';
import '../entities/refactor_scope.dart';
import '../entities/workspace_snapshot.dart';
import 'text_finder.dart';

/// Find and replace over a whole workspace: walks every text of every unit in [scopes], and lists each occurrence of
/// the query with what it would become. Writes nothing; the plan goes to the `RefactorApplier`.
abstract final class WorkspaceFinder {
  /// The plan for replacing [options] by [replacement]. A query that does not compile (or is empty) gives a plan with
  /// an [RefactorPlan.error]. Secret values are not looked at unless [includeSecret]; they are only counted.
  static RefactorPlan plan(
    WorkspaceSnapshot snapshot,
    FindOptions options,
    String replacement, {
    Set<RefactorScope>? scopes,
    bool includeSecret = false,
  }) {
    final TextFinder finder;
    try {
      finder = TextFinder(options);
    } on FormatException catch (e) {
      return RefactorPlan.failed(e.message);
    }
    final searched = scopes ?? RefactorScope.all;
    final changes = <FieldChange>[];
    var secretSkipped = 0;
    for (final unit in snapshot.units) {
      final trail = unit.trail;
      for (final field in unit.fields()) {
        if (!searched.contains(field.scope)) continue;
        if (field.secret && !includeSecret) {
          secretSkipped++;
          continue;
        }
        final fieldKey = '${unit.key}|${field.path}';
        final edits = <RefactorEdit>[];
        for (final match in finder.matches(field.value)) {
          final after = finder.replacement(match, replacement);
          // Replacing a text with itself changes nothing, so it is not offered.
          if (after == match[0]) continue;
          edits.add(
            EditSnippets.edit(
              fieldKey: fieldKey,
              text: field.value,
              start: match.start,
              end: match.end,
              after: after,
              secret: field.secret,
            ),
          );
        }
        if (edits.isEmpty) continue;
        changes.add(
          FieldChange(
            unitKey: unit.key,
            path: field.path,
            group: field.group,
            scope: field.scope,
            label: field.label,
            trail: trail,
            secret: field.secret,
            length: field.value.length,
            edits: edits,
          ),
        );
      }
    }
    return RefactorPlan(title: 'Replace "${options.query}"', changes: changes, secretSkipped: secretSkipped);
  }
}
