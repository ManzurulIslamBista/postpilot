import 'refactor_scope.dart';

/// What to look for in find-and-replace.
final class FindOptions {
  final String query;

  /// [query] is a regular expression, and the replacement may use `$1`, `$&` and `$$`.
  final bool regex;
  final bool caseSensitive;

  /// Only where the match is not touching a letter, digit or underscore on either side.
  final bool wholeWord;

  const FindOptions({required this.query, this.regex = false, this.caseSensitive = false, this.wholeWord = false});
}

/// One occurrence to replace in one text: where it is, what it is now and what it becomes.
final class RefactorEdit {
  /// Stable for the same text and the same search: the checkbox of the preview is kept under it.
  final String id;

  /// The span of the original text.
  final int start;
  final int end;

  /// The text at [start], and what replaces it. Never shown when the field is a secret.
  final String before;
  final String after;

  /// What the preview shows: the words before, the old text, the new text and the words after. All four are the mask
  /// when the field is a secret, so a secret is not in anything the screen reads from the plan.
  final String lead;
  final String shownBefore;
  final String shownAfter;
  final String tail;

  const RefactorEdit({
    required this.id,
    required this.start,
    required this.end,
    required this.before,
    required this.after,
    required this.lead,
    required this.shownBefore,
    required this.shownAfter,
    required this.tail,
  });
}

/// The occurrences found in one text field, and enough to find the field again and check it is still what was planned from.
final class FieldChange {
  final String unitKey;
  final String path;
  final String group;
  final RefactorScope scope;
  final String label;
  final List<String> trail;
  final bool secret;

  /// The length of the text the edits were found in.
  final int length;
  final List<RefactorEdit> edits;

  /// The text is the name of a variable (a rename changes the definition itself, not a reference to it).
  final bool definition;

  const FieldChange({
    required this.unitKey,
    required this.path,
    required this.group,
    required this.scope,
    required this.label,
    required this.trail,
    required this.secret,
    required this.length,
    required this.edits,
    this.definition = false,
  });

  String get key => '$unitKey|$path';
}

/// A variable definition to delete: the old one a rename merges into the existing one, or an unused one the report found.
final class RefactorDeletion {
  final String id;
  final String unitKey;

  /// What to remove from the unit (see `VariableDefinition.removePath`).
  final String removePath;

  /// The field that holds the name, and the name: the deletion is skipped when it no longer says that.
  final String keyPath;
  final String name;
  final List<String> trail;
  final String where;

  /// The value, masked when it is a secret.
  final String shownValue;
  final String reason;

  const RefactorDeletion({
    required this.id,
    required this.unitKey,
    required this.removePath,
    required this.keyPath,
    required this.name,
    required this.trail,
    required this.where,
    required this.shownValue,
    required this.reason,
  });
}

/// A scope that already defines the name a variable is renamed to.
final class RefactorConflict {
  final String where;

  /// What the existing variable is set to (masked when it is a secret).
  final String existingValue;

  /// The scope defines the old name too. Merging then deletes the old definition and keeps the existing value.
  /// Otherwise the old name's references simply start pointing at the existing variable.
  final bool collides;

  /// What the old definition in the same scope is set to (masked when it is a secret); empty unless [collides].
  final String oldValue;

  const RefactorConflict({required this.where, required this.existingValue, required this.collides, this.oldValue = ''});
}

/// Everything a tool wants to change, before anything is written: the occurrences found, the definitions to delete,
/// and the conflicts the user has to settle first.
final class RefactorPlan {
  final String title;
  final List<FieldChange> changes;
  final List<RefactorDeletion> deletions;
  final List<RefactorConflict> conflicts;

  /// Matches that were not listed because their field is a secret and "include secret values" was off.
  final int secretSkipped;

  /// Why the plan could not be made (a regular expression that does not compile, a name that is not one).
  final String? error;

  const RefactorPlan({
    this.title = '',
    this.changes = const [],
    this.deletions = const [],
    this.conflicts = const [],
    this.secretSkipped = 0,
    this.error,
  });

  static const empty = RefactorPlan();

  factory RefactorPlan.failed(String error) => RefactorPlan(error: error);

  Iterable<RefactorEdit> get edits sync* {
    for (final change in changes) {
      yield* change.edits;
    }
  }

  int get editCount => changes.fold(0, (sum, c) => sum + c.edits.length);

  bool get isEmpty => changes.isEmpty && deletions.isEmpty;

  /// The user has to say yes to a merge before this can be applied.
  bool get needsConfirmation => conflicts.isNotEmpty;

  Set<String> get editIds => {for (final edit in edits) edit.id};
  Set<String> get deletionIds => {for (final d in deletions) d.id};
}

/// Puts the replacements of [edits] into [text].
abstract final class TextSplice {
  /// [text] with each of [edits] replaced. Edits that overlap an earlier one are left out.
  static String apply(String text, Iterable<RefactorEdit> edits) {
    final sorted = edits.toList()..sort((a, b) => a.start.compareTo(b.start));
    final out = StringBuffer();
    var cursor = 0;
    for (final edit in sorted) {
      if (edit.start < cursor || edit.end > text.length) continue;
      out
        ..write(text.substring(cursor, edit.start))
        ..write(edit.after);
      cursor = edit.end;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }
}
