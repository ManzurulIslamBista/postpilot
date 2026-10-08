import '../../../documentation/domain/services/tag_normalizer.dart';
import '../entities/refactor_plan.dart';
import '../entities/refactor_receipt.dart';
import '../entities/request_unit.dart';
import '../entities/unit_field.dart';
import 'refactor_writer.dart';
import 'workspace_reader.dart';

/// Runs [action] so that its writes stand or fall together: the app passes a database transaction.
typedef Atomically = Future<T> Function<T>(Future<T> Function() action);

/// Turns the edits and deletions a user accepted into repository writes, as one operation, and takes them back.
///
/// Before anything is written the workspace is read again and every accepted change is checked against it: a text
/// that is not what the preview was made from (it was edited meanwhile) is left out and counted, never overwritten.
/// A copy of every unit that is about to change goes into the returned [RefactorReceipt]; [undo] puts those back.
/// If a write fails midway nothing is kept and the failure is reported: with an [Atomically] runner (the app gives a
/// database transaction) the database rolls everything back itself and announces one change when it commits; without
/// one, the units written so far are written back as they were.
///
/// Only the accepted edits are written, and only the part of a unit they touch (a request's URL, say, writes the
/// request and not its tests).
final class RefactorApplier {
  final WorkspaceSource _source;
  final RefactorWriter _writer;
  final Atomically? _atomically;

  const RefactorApplier(this._source, this._writer, {this._atomically});

  /// Applies the edits of [plan] whose ids are in [editIds] and its deletions whose ids are in [deletionIds] (all of
  /// them when null). A plan with conflicts needs [mergeConfirmed].
  Future<RefactorReceipt> apply(
    RefactorPlan plan, {
    required Set<String> editIds,
    Set<String>? deletionIds,
    bool mergeConfirmed = false,
  }) async {
    final error = plan.error;
    if (error != null) throw RefactorException(error);
    if (plan.needsConfirmation && !mergeConfirmed) {
      throw const RefactorException('The new name already exists. Confirm the merge, or pick another name.');
    }
    final fresh = await _source.read();
    var stale = 0;

    // Edits, per unit and field.
    final newTexts = <String, Map<String, String>>{};
    final groups = <String, Set<String>>{};
    var editsApplied = 0;
    final byUnit = <String, List<FieldChange>>{};
    for (final change in plan.changes) {
      if (change.edits.any((e) => editIds.contains(e.id))) byUnit.putIfAbsent(change.unitKey, () => []).add(change);
    }
    for (final entry in byUnit.entries) {
      final unit = fresh.unit(entry.key);
      final fields = {for (final f in unit?.fields() ?? const <UnitField>[]) f.path: f};
      for (final change in entry.value) {
        final accepted = [for (final e in change.edits) if (editIds.contains(e.id)) e];
        final field = fields[change.path];
        if (field == null || !_matches(field.value, change, accepted)) {
          stale += accepted.length;
          continue;
        }
        final text = TextSplice.apply(field.value, accepted);
        // A collection, folder or request with no name at all cannot be told apart in the sidebar: not written.
        if (change.path == 'name' && text.trim().isEmpty) {
          stale += accepted.length;
          continue;
        }
        newTexts.putIfAbsent(entry.key, () => {})[change.path] = text;
        groups.putIfAbsent(entry.key, () => {}).add(field.group);
        editsApplied += accepted.length;
      }
    }

    // Deletions: a variable row is deleted whole, a folder variable is cut out of its folder.
    final deletedRows = <RefactorUnit>[];
    final removals = <String, List<String>>{};
    var deletionsApplied = 0;
    for (final deletion in plan.deletions) {
      if (deletionIds != null && !deletionIds.contains(deletion.id)) continue;
      final unit = fresh.unit(deletion.unitKey);
      final field = unit?.fields().where((f) => f.path == deletion.keyPath).firstOrNull;
      if (unit == null || field == null || field.defines?.name != deletion.name) {
        stale++;
        continue;
      }
      if (unit.isRow) {
        deletedRows.add(unit);
      } else {
        removals.putIfAbsent(unit.key, () => []).add(deletion.removePath);
        groups.putIfAbsent(unit.key, () => {}).add(field.group);
      }
      deletionsApplied++;
    }
    final deletedKeys = {for (final unit in deletedRows) unit.key};

    final changes = <UnitChange>[];
    for (final key in {...newTexts.keys, ...removals.keys}) {
      if (deletedKeys.contains(key)) continue;
      final before = fresh.unit(key)!;
      var after = before;
      final texts = newTexts[key];
      if (texts != null) after = after.withValues(texts);
      // Highest position first, so a removal does not move the ones still to come.
      final parts = [...?removals[key]]..sort((a, b) => _position(b).compareTo(_position(a)));
      for (final part in parts) {
        after = after.removePart(part);
      }
      changes.add(UnitChange(before, after, groups[key]!));
    }

    final written = <UnitChange>[];
    final removedRows = <RefactorUnit>[];
    UnitChange? inFlight;
    Future<void> writeAll() async {
      for (final change in changes) {
        inFlight = change;
        final replaced = await _writer.write(change.before, change.after, change.groups);
        var after = change.after;
        if (after is RequestUnit) {
          for (final entry in replaced.entries) {
            after = (after as RequestUnit).withExampleId(entry.key, entry.value);
          }
        }
        written.add(UnitChange(change.before, after, change.groups));
        inFlight = null;
      }
      for (final unit in deletedRows) {
        await _writer.delete(unit);
        removedRows.add(unit);
      }
    }

    try {
      final atomically = _atomically;
      if (atomically == null) {
        await writeAll();
      } else {
        await atomically(writeAll);
      }
    } catch (e) {
      // A transaction has been rolled back by now; without one, put back by hand what was written.
      if (_atomically == null) await _restore(written, removedRows, inFlight);
      throw RefactorException('Could not write every change, so none were kept: $e');
    }

    return RefactorReceipt(
      title: plan.title,
      at: DateTime.now(),
      changes: written,
      deleted: removedRows,
      editsApplied: editsApplied,
      deletionsApplied: deletionsApplied,
      stale: stale,
    );
  }

  /// Puts back what [receipt] changed, unit by unit. A unit that was edited since (its texts are no longer what the
  /// apply wrote) or is gone is left alone and named in the outcome: undo never overwrites newer work.
  Future<UndoOutcome> undo(RefactorReceipt receipt) async {
    final fresh = await _source.read();
    var restored = 0;
    final skipped = <String>[];
    final requestIds = <int>{};

    Future<void> putBack() async {
      for (final change in receipt.changes.reversed) {
        final name = change.after.trail.join(' / ');
        final current = fresh.unit(change.after.key);
        if (current == null) {
          skipped.add('$name was deleted since');
          continue;
        }
        if (!_sameValues(current.valuesOf(change.groups), change.after.valuesOf(change.groups))) {
          skipped.add('$name was edited since, so it was left as it is');
          continue;
        }
        try {
          await _writer.write(current, change.before, change.groups);
          restored++;
          if (change.before is RequestUnit) requestIds.add(change.before.id);
        } catch (e) {
          skipped.add('$name could not be put back: $e');
        }
      }
      for (final unit in receipt.deleted) {
        if (fresh.unit(unit.key) != null) continue;
        try {
          await _writer.recreate(unit);
          restored++;
        } catch (e) {
          skipped.add('${unit.trail.join(' / ')} could not be added back: $e');
        }
      }
    }

    final atomically = _atomically;
    if (atomically == null) {
      await putBack();
    } else {
      await atomically(putBack);
    }
    return UndoOutcome(restored: restored, skipped: skipped, requestIds: requestIds);
  }

  /// Best effort after a failed write: the failure itself is what the user needs to see.
  Future<void> _restore(List<UnitChange> written, List<RefactorUnit> removedRows, UnitChange? inFlight) async {
    if (inFlight != null) {
      // Some of its groups may have been written before the failure; the original text of each is safe to write again.
      // (A saved example is left out: it is added before the old one is deleted, and there is no telling how far it got.)
      final groups = {for (final g in inFlight.groups) if (!g.startsWith('example.')) g};
      try {
        if (groups.isNotEmpty) await _writer.write(inFlight.before, inFlight.before, groups);
      } catch (_) {}
    }
    for (final change in written.reversed) {
      try {
        await _writer.write(change.after, change.before, change.groups);
      } catch (_) {}
    }
    for (final unit in removedRows) {
      try {
        await _writer.recreate(unit);
      } catch (_) {}
    }
  }

  /// Whether [text] is still what [change] was found in, at every place an accepted edit expects.
  static bool _matches(String text, FieldChange change, List<RefactorEdit> accepted) =>
      text.length == change.length && accepted.every((e) => e.end <= text.length && text.substring(e.start, e.end) == e.before);

  static int _position(String path) => int.tryParse(path.split('.').last) ?? 0;

  static bool _sameValues(Map<String, String> a, Map<String, String> b) {
    final left = _comparable(a);
    final right = _comparable(b);
    return left.length == right.length && left.entries.every((e) => right[e.key] == e.value);
  }

  /// The texts as the stores keep them: the tag store sorts the tags, ignores case and drops repeats and blanks, so
  /// the tags of two copies are compared as the set the store would hold.
  static Map<String, String> _comparable(Map<String, String> values) {
    final tags = <String>[];
    final out = <String, String>{};
    for (final entry in values.entries) {
      if (entry.key.startsWith('tag.')) {
        tags.add(entry.value);
      } else {
        out[entry.key] = entry.value;
      }
    }
    if (tags.isNotEmpty) out['tags'] = TagNormalizer.normalise(tags).join('\n');
    return out;
  }
}
