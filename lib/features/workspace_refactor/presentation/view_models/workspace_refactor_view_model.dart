import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/refactor_plan.dart';
import '../../domain/entities/refactor_receipt.dart';
import '../../domain/entities/refactor_scope.dart';
import '../../domain/entities/workspace_snapshot.dart';
import '../../domain/services/refactor_applier.dart';
import '../../domain/services/variable_renamer.dart';
import '../../domain/services/variable_report.dart';
import '../../domain/services/workspace_finder.dart';
import '../../domain/services/workspace_reader.dart';
import 'preview_rows.dart';

/// Backs the workspace refactoring dialog: the workspace read once, the three tools' inputs and plans, and the one
/// undo the session keeps. Nothing is written until an apply method is called.
///
/// Typing re-plans after [searchDelay] (so a large workspace is not searched on every keystroke); with a zero delay it
/// re-plans at once.
final class WorkspaceRefactorViewModel with ChangeNotifier {
  final WorkspaceSource _source;
  final RefactorApplier _applier;
  final RefactorUndoStore _undo;
  final Duration searchDelay;

  /// Called with the ids of the requests an apply or an undo changed, so open tabs can reload them.
  void Function(Set<int> requestIds)? onRequestsChanged;

  WorkspaceRefactorViewModel(this._source, this._applier, this._undo, {this.searchDelay = const Duration(milliseconds: 250)});

  Timer? _findTimer;
  Timer? _renameTimer;
  bool _disposed = false;

  // --- the workspace ---------------------------------------------------------------------------------------------

  WorkspaceSnapshot? snapshot;
  bool isLoading = false;
  String? loadError;

  Future<void> load() async {
    isLoading = true;
    loadError = null;
    _notify();
    try {
      snapshot = await _source.read();
    } catch (e) {
      loadError = 'Could not read the workspace: $e';
    }
    isLoading = false;
    _replanAll();
    _notify();
  }

  // --- find and replace -------------------------------------------------------------------------------------------

  String query = '';
  String replacement = '';
  bool regex = false;
  bool caseSensitive = false;
  bool wholeWord = false;
  bool includeSecret = false;
  Set<RefactorScope> scopes = {...RefactorScope.all};

  RefactorPlan findPlan = RefactorPlan.empty;
  PreviewRows findRows = PreviewRows.empty;
  final Set<String> _unticked = {};

  void setQuery(String value) {
    query = value;
    _scheduleFind();
  }

  void setReplacement(String value) {
    replacement = value;
    _scheduleFind();
  }

  void setOptions({bool? regex, bool? caseSensitive, bool? wholeWord, bool? includeSecret}) {
    this.regex = regex ?? this.regex;
    this.caseSensitive = caseSensitive ?? this.caseSensitive;
    this.wholeWord = wholeWord ?? this.wholeWord;
    this.includeSecret = includeSecret ?? this.includeSecret;
    _scheduleFind();
  }

  void toggleScope(RefactorScope scope) {
    scopes = scopes.contains(scope) ? ({...scopes}..remove(scope)) : {...scopes, scope};
    _scheduleFind();
  }

  void setAllScopes(bool all) {
    scopes = all ? {...RefactorScope.all} : {};
    _scheduleFind();
  }

  void _scheduleFind() {
    _findTimer?.cancel();
    if (searchDelay == Duration.zero) {
      _replanFind();
      _notify();
      return;
    }
    _findTimer = Timer(searchDelay, () {
      _replanFind();
      _notify();
    });
    _notify();
  }

  void _replanFind() {
    final current = snapshot;
    _unticked.clear();
    if (current == null || query.isEmpty) {
      findPlan = RefactorPlan.empty;
    } else {
      findPlan = WorkspaceFinder.plan(
        current,
        FindOptions(query: query, regex: regex, caseSensitive: caseSensitive, wholeWord: wholeWord),
        replacement,
        scopes: scopes,
        includeSecret: includeSecret,
      );
    }
    findRows = PreviewRows.of(findPlan);
  }

  /// Whether the occurrence will be replaced.
  bool isTicked(String editId) => !_unticked.contains(editId);

  /// The occurrences that will be replaced.
  int get tickedCount => findPlan.editCount - _unticked.length;

  void setTicked(String editId, bool ticked) {
    ticked ? _unticked.remove(editId) : _unticked.add(editId);
    notifyListeners();
  }

  void setManyTicked(Iterable<String> editIds, bool ticked) {
    ticked ? _unticked.removeAll(editIds) : _unticked.addAll(editIds);
    notifyListeners();
  }

  void tickAll(bool ticked) => setManyTicked(findPlan.editIds, ticked);

  Set<String> get _ticked => findPlan.editIds.difference(_unticked);

  bool get canReplace => !isApplying && tickedCount > 0 && findPlan.error == null;

  Future<void> applyFind() => _run(
    () => _applier.apply(findPlan, editIds: _ticked),
    done: (r) => 'Replaced ${_plural(r.editsApplied, 'occurrence')} in ${_plural(r.unitCount, 'place')}${_staleNote(r)}.',
  );

  // --- rename a variable ------------------------------------------------------------------------------------------

  String oldName = '';
  String newName = '';
  RefactorPlan renamePlan = RefactorPlan.empty;
  PreviewRows renameRows = PreviewRows.empty;

  /// The user agreed to merge into a name that already exists.
  bool mergeConfirmed = false;

  void setOldName(String value) {
    oldName = value;
    _scheduleRename();
  }

  void setNewName(String value) {
    newName = value;
    _scheduleRename();
  }

  void confirmMerge(bool value) {
    mergeConfirmed = value;
    notifyListeners();
  }

  /// Defined names that contain what was typed, for the suggestions under the field.
  List<VariableName> suggestions(String typed, {int limit = 8}) {
    final all = snapshot?.variableNames ?? const <VariableName>[];
    final text = typed.trim().toLowerCase();
    return [
      for (final name in all)
        if (text.isEmpty || name.name.toLowerCase().contains(text)) name,
    ].take(limit).toList();
  }

  void _scheduleRename() {
    _renameTimer?.cancel();
    if (searchDelay == Duration.zero) {
      _replanRename();
      _notify();
      return;
    }
    _renameTimer = Timer(searchDelay, () {
      _replanRename();
      _notify();
    });
    _notify();
  }

  void _replanRename() {
    final current = snapshot;
    mergeConfirmed = false;
    if (current == null || VariableRenamer.clean(oldName).isEmpty || VariableRenamer.clean(newName).isEmpty) {
      renamePlan = RefactorPlan.empty;
    } else {
      renamePlan = VariableRenamer.plan(current, oldName, newName);
    }
    renameRows = PreviewRows.of(renamePlan);
  }

  int get definitionCount => renamePlan.changes.where((c) => c.definition).fold(0, (sum, c) => sum + c.edits.length);
  int get referenceCount => renamePlan.changes.where((c) => !c.definition).fold(0, (sum, c) => sum + c.edits.length);

  bool get canRename =>
      !isApplying &&
      renamePlan.error == null &&
      (renamePlan.editCount > 0 || renamePlan.deletions.isNotEmpty) &&
      (!renamePlan.needsConfirmation || mergeConfirmed);

  Future<void> applyRename() => _run(
    () => _applier.apply(renamePlan, editIds: renamePlan.editIds, mergeConfirmed: mergeConfirmed),
    done: (r) {
      final deleted = r.deletionsApplied == 0 ? '' : ' and removed ${_plural(r.deletionsApplied, 'old definition')}';
      return 'Renamed {{${VariableRenamer.clean(oldName)}}} to {{${VariableRenamer.clean(newName)}}}: ${_plural(r.editsApplied, 'occurrence')} in ${_plural(r.unitCount, 'place')}$deleted${_staleNote(r)}.';
    },
    after: () {
      oldName = '';
      newName = '';
    },
  );

  // --- unused and undefined variables -----------------------------------------------------------------------------

  List<UnusedVariable> unused = const [];
  List<UndefinedVariableUse> undefined = const [];
  final Set<String> _deleteTicked = {};

  bool isMarkedForDelete(String deletionId) => _deleteTicked.contains(deletionId);

  void setMarkedForDelete(String deletionId, bool marked) {
    marked ? _deleteTicked.add(deletionId) : _deleteTicked.remove(deletionId);
    notifyListeners();
  }

  void markAllForDelete(bool marked) {
    _deleteTicked.clear();
    if (marked) _deleteTicked.addAll(_allDeletions.map((d) => d.id));
    notifyListeners();
  }

  Iterable<RefactorDeletion> get _allDeletions sync* {
    for (final variable in unused) {
      yield* variable.definitions;
    }
  }

  int get markedForDeleteCount => _deleteTicked.length;

  bool get canDeleteUnused => !isApplying && _deleteTicked.isNotEmpty;

  void _rebuildReport() {
    final current = snapshot;
    if (current == null) {
      unused = const [];
      undefined = const [];
    } else {
      final report = VariableReport.build(current);
      unused = report.unused;
      undefined = report.undefined;
    }
    final known = _allDeletions.map((d) => d.id).toSet();
    _deleteTicked.removeWhere((id) => !known.contains(id));
  }

  Future<void> deleteMarkedUnused() {
    final plan = RefactorPlan(title: 'Delete unused variables', deletions: [for (final d in _allDeletions) d]);
    return _run(
      () => _applier.apply(plan, editIds: const {}, deletionIds: {..._deleteTicked}),
      done: (r) => 'Deleted ${_plural(r.deletionsApplied, 'variable definition')}${_staleNote(r)}.',
    );
  }

  // --- applying and undoing --------------------------------------------------------------------------------------

  bool isApplying = false;

  /// What the last apply or undo did, or why it failed.
  String? notice;
  bool noticeIsError = false;

  /// The last change of this session, which can still be undone. Memory only.
  RefactorReceipt? get lastReceipt => _undo.last;

  Future<void> _run(Future<RefactorReceipt> Function() apply, {required String Function(RefactorReceipt receipt) done, void Function()? after}) async {
    if (isApplying) return;
    isApplying = true;
    notice = null;
    _notify();
    try {
      final receipt = await apply();
      if (receipt.isEmpty) {
        notice = receipt.stale > 0
            ? 'Nothing was changed: ${_plural(receipt.stale, 'change')} left out because the text changed since the preview, or a name would have been left empty. Search again.'
            : 'Nothing to change.';
        noticeIsError = receipt.stale > 0;
      } else {
        _undo.last = receipt;
        notice = done(receipt);
        noticeIsError = false;
        after?.call();
        onRequestsChanged?.call(receipt.requestIds);
      }
    } on RefactorException catch (e) {
      notice = e.message;
      noticeIsError = true;
    } catch (e) {
      notice = 'Could not apply the change: $e';
      noticeIsError = true;
    }
    isApplying = false;
    // The workspace is what it is now: read it again so every preview and the report describe it.
    await load();
  }

  /// Puts back what the last apply changed, except what was edited since.
  Future<void> undoLast() async {
    final receipt = _undo.last;
    if (receipt == null || isApplying) return;
    isApplying = true;
    notice = null;
    _notify();
    try {
      final outcome = await _applier.undo(receipt);
      _undo.last = null;
      final skipped = outcome.skipped.isEmpty ? '' : ' Left as they are: ${outcome.skipped.join('; ')}.';
      notice = 'Undone: ${_plural(outcome.restored, 'place')} put back.$skipped';
      noticeIsError = outcome.skipped.isNotEmpty;
      onRequestsChanged?.call(outcome.requestIds);
    } catch (e) {
      notice = 'Could not undo: $e';
      noticeIsError = true;
    }
    isApplying = false;
    await load();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  // --- helpers ---------------------------------------------------------------------------------------------------

  void _replanAll() {
    _replanFind();
    _replanRename();
    _rebuildReport();
  }

  static String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  static String _staleNote(RefactorReceipt r) =>
      r.stale == 0 ? '' : ' (${_plural(r.stale, 'change')} left out: the text changed since the preview, or a name would have been left empty)';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _findTimer?.cancel();
    _renameTimer?.cancel();
    super.dispose();
  }
}
