import '../../domain/entities/refactor_plan.dart';

/// A line of the preview list: a collection, folder or request heading, an occurrence, or a definition to delete.
sealed class PreviewRow {
  const PreviewRow();
}

/// A heading: one level of collection > folder > request (or Environments > Dev, Globals).
final class GroupRow extends PreviewRow {
  final int depth;
  final String title;

  /// Whether the heading is the request (or variable) the occurrences below belong to.
  final bool isLeaf;
  final bool isRequest;

  /// Every occurrence below it, at any depth: what its checkbox ticks.
  final List<String> editIds;

  const GroupRow({required this.depth, required this.title, required this.isLeaf, required this.isRequest, required this.editIds});
}

/// One occurrence, with the field it is in.
final class EditRow extends PreviewRow {
  final int depth;
  final FieldChange change;
  final RefactorEdit edit;

  /// The first occurrence of its field, which carries the field's label.
  final bool first;

  const EditRow({required this.depth, required this.change, required this.edit, required this.first});
}

/// A definition that will be deleted (the old variable of a merge).
final class DeletionRow extends PreviewRow {
  final RefactorDeletion deletion;
  const DeletionRow(this.deletion);
}

/// A plan laid out as the rows of the preview, grouped collection > folder > request.
///
/// Changes of one unit are next to each other in a plan, so a heading is written whenever the path changes. The rows
/// are built once per plan; which occurrences are ticked is the view model's, read as each row is drawn.
final class PreviewRows {
  final List<PreviewRow> rows;
  const PreviewRows(this.rows);

  static const empty = PreviewRows([]);

  bool get isEmpty => rows.isEmpty;

  static PreviewRows of(RefactorPlan plan) {
    final rows = <PreviewRow>[];
    final open = <GroupRow>[];
    List<String> previous = const [];
    String? previousUnit;

    void close(int keep) {
      while (open.length > keep) {
        open.removeLast();
      }
    }

    for (final change in plan.changes) {
      final trail = change.trail.isEmpty ? const ['Workspace'] : change.trail;
      var common = 0;
      while (common < previous.length && common < trail.length && previous[common] == trail[common] && common < open.length) {
        common++;
      }
      // Two units with the same path (two requests with one name) are two headings, not one.
      if (common == trail.length && previousUnit != change.unitKey) common = trail.length - 1;
      close(common);
      for (var depth = common; depth < trail.length; depth++) {
        final leaf = depth == trail.length - 1;
        final group = GroupRow(
          depth: depth,
          title: trail[depth],
          isLeaf: leaf,
          isRequest: leaf && change.unitKey.startsWith('request:'),
          editIds: <String>[],
        );
        rows.add(group);
        open.add(group);
      }
      for (var i = 0; i < change.edits.length; i++) {
        final edit = change.edits[i];
        for (final group in open) {
          group.editIds.add(edit.id);
        }
        rows.add(EditRow(depth: trail.length, change: change, edit: edit, first: i == 0));
      }
      previous = trail;
      previousUnit = change.unitKey;
    }

    if (plan.deletions.isNotEmpty) {
      rows.add(GroupRow(depth: 0, title: 'Definitions that will be deleted', isLeaf: false, isRequest: false, editIds: const []));
      for (final deletion in plan.deletions) {
        rows.add(DeletionRow(deletion));
      }
    }
    return PreviewRows(rows);
  }
}
