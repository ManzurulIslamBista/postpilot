// The applier against a recording writer: it must write only what the user accepted, only the parts of a unit that
// changed, refuse a text that moved since the preview, and put things back. No database.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_plan.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_receipt.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/request_unit.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/level_units.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/unit_field.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_applier.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_writer.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_renamer.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_report.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_finder.dart';

import 'refactor_fixtures.dart';
import 'refactor_fakes.dart';

String idOf(RefactorPlan plan, String unitKey, String path) =>
    plan.changes.firstWhere((c) => c.unitKey == unitKey && c.path == path).edits.single.id;

void main() {
  late FixedSource source;
  late RecordingWriter writer;
  late RefactorApplier applier;
  late RefactorPlan plan;

  setUp(() {
    source = FixedSource(acmeWorkspace());
    writer = RecordingWriter();
    applier = RefactorApplier(source, writer);
    plan = WorkspaceFinder.plan(source.snapshot, const FindOptions(query: 'acme'), 'Zeta');
  });

  group('only what was accepted is written', () {
    test('two accepted edits of one request are one write, and the rest of the request is as it was', () async {
      final receipt = await applier.apply(
        plan,
        editIds: {idOf(plan, 'request:100', 'url'), idOf(plan, 'request:100', 'tag.0')},
      );

      expect(writer.writes, hasLength(1));
      final write = writer.writes.single;
      expect(write.key, 'request:100');
      // The URL is saved with the request, the tag with the tags; nothing else of the request is saved.
      expect(write.groups, {'request', 'tags'});
      final target = write.target as RequestUnit;
      expect(target.request.url, 'https://Zeta.test/orders');
      expect(target.tags, ['Zeta']);
      // What was found in the same request but not accepted is left alone.
      expect(target.request.name, 'Acme list');
      expect(target.request.queryParams.single.value, 'acme');
      expect(target.description, 'About acme');
      expect(receipt.editsApplied, 2);
      expect(receipt.unitCount, 1);
    });

    test('a URL alone writes the request and not its tests, notes or examples', () async {
      await applier.apply(plan, editIds: {idOf(plan, 'request:100', 'url')});
      expect(writer.writes.single.groups, {'request'});
    });

    test('with everything accepted each unit is written once, with exactly the groups it changed', () async {
      final receipt = await applier.apply(plan, editIds: plan.editIds);

      expect({for (final w in writer.writes) w.key: w.groups}, {
        'collection:1': {'defaults'},
        'request:100': {'request', 'scripts', 'doc', 'tags', 'example.0'},
        'environmentVariable:500': {'row'},
      });
      expect(receipt.editsApplied, 12);
      expect(receipt.deleted, isEmpty);
    });

    test('nothing accepted writes nothing', () async {
      final receipt = await applier.apply(plan, editIds: {});
      expect(writer.writes, isEmpty);
      expect(receipt.isEmpty, isTrue);
    });

    test('a changed example is saved again and the receipt remembers its new id', () async {
      final receipt = await applier.apply(plan, editIds: {idOf(plan, 'request:100', 'example.0.body')});
      final after = receipt.changes.single.after as RequestUnit;
      expect(after.examples.single.id, 900);
      expect(after.examples.single.body, '{"vendor":"Zeta"}');
      expect(receipt.changes.single.before, isA<RequestUnit>());
      expect((receipt.changes.single.before as RequestUnit).examples.single.id, 7);
    });
  });

  group('a name is never written empty', () {
    test('replacing the whole name with nothing is left out and counted, the rest goes through', () async {
      source.snapshot = WorkspaceSnapshot([req(1, 'acme', url: 'https://acme.test/x'), folder(2, 'acme'), collection(3, 'acme')]);
      final everything = WorkspaceFinder.plan(source.snapshot, const FindOptions(query: 'acme'), '');

      final receipt = await applier.apply(everything, editIds: everything.editIds);

      // Three names would be empty; the URL becomes "https://.test/x" and is written.
      expect(receipt.stale, 3);
      expect(receipt.editsApplied, 1);
      expect(writer.writes.single.key, 'request:1');
      expect(writer.writes.single.groups, {'request'});
      expect((writer.writes.single.target as RequestUnit).request.name, 'acme');
    });

    test('a name that keeps some text is written', () async {
      source.snapshot = WorkspaceSnapshot([req(1, 'acme list')]);
      final plan = WorkspaceFinder.plan(source.snapshot, const FindOptions(query: 'acme '), '');
      await applier.apply(plan, editIds: plan.editIds);
      expect((writer.writes.single.target as RequestUnit).request.name, 'list');
    });
  });

  group('a text that moved since the preview is not overwritten', () {
    test('the edit is left out and counted', () async {
      // The user edited the URL after the preview was made.
      source.snapshot = WorkspaceSnapshot([
        for (final unit in source.snapshot.units)
          if (unit.key == 'request:100') (unit as RequestUnit).copyWith(request: unit.request.copyWith(url: 'https://acme.test/changed/by/hand')) else unit,
      ]);

      final receipt = await applier.apply(plan, editIds: {idOf(plan, 'request:100', 'url'), idOf(plan, 'request:100', 'tag.0')});

      expect(receipt.stale, 1);
      expect(receipt.editsApplied, 1);
      expect(writer.writes.single.groups, {'tags'});
      expect((writer.writes.single.target as RequestUnit).request.url, 'https://acme.test/changed/by/hand');
    });

    test('a request that was deleted since is skipped', () async {
      source.snapshot = WorkspaceSnapshot([for (final u in source.snapshot.units) if (u.key != 'request:100') u]);
      final receipt = await applier.apply(plan, editIds: plan.editIds);
      expect(receipt.stale, 10);
      expect(writer.writes.map((w) => w.key), unorderedEquals(['collection:1', 'environmentVariable:500']));
    });
  });

  group('when a write fails', () {
    test('what was written is put back, including the unit that failed, and the failure is reported', () async {
      writer.failOnWrite = 2;

      await expectLater(
        applier.apply(plan, editIds: plan.editIds),
        throwsA(isA<RefactorException>().having((e) => e.message, 'message', allOf(contains('none were kept'), contains('disk full')))),
      );

      // 1: collection (ok), 2: request (fails), 3: the request's groups written again as they were, 4: the collection put back.
      expect(writer.writes.map((w) => w.key), ['collection:1', 'request:100', 'request:100', 'collection:1']);
      expect((writer.writes[2].target as RequestUnit).request.url, 'https://acme.test/orders');
      expect(writer.writes[2].groups, {'request', 'scripts', 'doc', 'tags'}, reason: 'the example is not in the restore');
      final restored = writer.writes[3].target as CollectionUnit;
      expect(restored.defaults.headers.single.value, 'acme');
    });
  });

  group('undo', () {
    Future<RefactorReceipt> applyAll() async {
      final receipt = await applier.apply(plan, editIds: plan.editIds);
      // The workspace as the apply left it.
      source.snapshot = WorkspaceSnapshot([
        for (final unit in source.snapshot.units) receipt.changes.where((c) => c.before.key == unit.key).firstOrNull?.after ?? unit,
      ]);
      writer.writes.clear();
      return receipt;
    }

    test('writes every changed unit back as it was', () async {
      final receipt = await applyAll();

      final outcome = await applier.undo(receipt);

      expect(outcome.restored, 3);
      expect(outcome.skipped, isEmpty);
      final byKey = {for (final w in writer.writes) w.key: w};
      final request = byKey['request:100']!.target as RequestUnit;
      expect(request.request.url, 'https://acme.test/orders');
      expect(request.request.name, 'Acme list');
      expect(request.tags, ['acme']);
      expect(request.examples.single.body, '{"vendor":"acme"}');
      expect(request.examples.single.id, 7);
      expect(byKey['request:100']!.groups, {'request', 'scripts', 'doc', 'tags', 'example.0'});
      expect(outcome.requestIds, {100});
    });

    test('a unit that was edited after the apply is left alone and named', () async {
      final receipt = await applyAll();
      source.snapshot = WorkspaceSnapshot([
        for (final unit in source.snapshot.units)
          if (unit.key == 'request:100') (unit as RequestUnit).copyWith(description: 'Written after the replace') else unit,
      ]);

      final outcome = await applier.undo(receipt);

      expect(outcome.restored, 2);
      expect(outcome.skipped.single, 'Shop / Zeta list was edited since, so it was left as it is');
      expect(writer.writes.map((w) => w.key), isNot(contains('request:100')));
    });

    test('a unit that was deleted after the apply is named too', () async {
      final receipt = await applyAll();
      source.snapshot = WorkspaceSnapshot([for (final u in source.snapshot.units) if (u.key != 'environmentVariable:500') u]);

      final outcome = await applier.undo(receipt);

      expect(outcome.skipped.single, 'Environments / Dev was deleted since');
    });
  });

  group('deleting definitions', () {
    final snapshot = WorkspaceSnapshot([
      envVar(1, 'Dev', 'host', 'old-dev'),
      envVar(2, 'Dev', 'server', 'existing-dev'),
      folder(
        10,
        'F',
        defaults: LevelDefaults(
          variables: [DefaultVariable(key: 'a', value: '1'), DefaultVariable(key: 'host', value: '2'), DefaultVariable(key: 'c', value: '3'), DefaultVariable(key: 'server', value: '4')],
        ),
      ),
      req(100, 'R', url: '{{host}}/x'),
    ]);

    test('a merge is refused until it is confirmed', () async {
      final merge = VariableRenamer.plan(snapshot, 'host', 'server');
      source.snapshot = snapshot;
      await expectLater(applier.apply(merge, editIds: merge.editIds), throwsA(isA<RefactorException>()));
      expect(writer.writes, isEmpty);
      expect(writer.deleted, isEmpty);
    });

    test('a confirmed merge deletes the old rows, cuts the folder variable out and rewrites the references', () async {
      final merge = VariableRenamer.plan(snapshot, 'host', 'server');
      source.snapshot = snapshot;

      final receipt = await applier.apply(merge, editIds: merge.editIds, mergeConfirmed: true);

      expect(writer.deleted, ['environmentVariable:1']);
      expect(receipt.deleted.single.key, 'environmentVariable:1');
      final folderWrite = writer.writes.firstWhere((w) => w.key == 'folder:10');
      expect(folderWrite.groups, {'defaults'});
      expect([for (final v in (folderWrite.target as FolderUnit).defaults.variables) v.key], ['a', 'c', 'server']);
      expect((writer.writes.firstWhere((w) => w.key == 'request:100').target as RequestUnit).request.url, '{{server}}/x');
    });

    test('several variables cut out of one folder do not shift each other', () async {
      final plan = _unusedPlan(snapshot, ['folder:10|defaults.var.0', 'folder:10|defaults.var.2']);
      source.snapshot = snapshot;

      await applier.apply(plan, editIds: {});

      final target = writer.writes.single.target as FolderUnit;
      expect([for (final v in target.defaults.variables) v.key], ['host', 'server']);
    });

    test('a variable row that is not what the report saw is skipped', () async {
      final plan = _unusedPlan(snapshot, ['environmentVariable:1|row']);
      // Someone renamed the variable since.
      source.snapshot = WorkspaceSnapshot([
        for (final u in snapshot.units) u.key == 'environmentVariable:1' ? envVar(1, 'Dev', 'renamed', 'old-dev') : u,
      ]);

      final receipt = await applier.apply(plan, editIds: {});

      expect(receipt.stale, 1);
      expect(writer.deleted, isEmpty);
    });

    test('undo adds a deleted row back and the folder variable back', () async {
      final plan = _unusedPlan(snapshot, ['environmentVariable:1|row', 'folder:10|defaults.var.1']);
      source.snapshot = snapshot;
      final receipt = await applier.apply(plan, editIds: {});
      // The workspace after: the row is gone and the folder lost the variable.
      source.snapshot = WorkspaceSnapshot([
        for (final u in snapshot.units)
          if (u.key == 'folder:10') receipt.changes.single.after else if (u.key != 'environmentVariable:1') u,
      ]);
      writer.writes.clear();

      final outcome = await applier.undo(receipt);

      expect(outcome.restored, 2);
      expect(writer.recreated, ['environmentVariable:1']);
      expect([for (final v in (writer.writes.single.target as FolderUnit).defaults.variables) v.key], ['a', 'host', 'c', 'server']);
    });
  });

  group('unused variables from the report', () {
    test('the report offers deletions that the applier takes as they are', () async {
      final snapshot = WorkspaceSnapshot([envVar(1, 'Dev', 'legacy', 'x'), envVar(2, 'Dev', 'used', 'y'), req(3, 'R', url: '{{used}}')]);
      final report = VariableReport.build(snapshot);
      source.snapshot = snapshot;
      final plan = RefactorPlan(title: 'Delete', deletions: [for (final u in report.unused) ...u.definitions]);

      final receipt = await applier.apply(plan, editIds: {});

      expect(writer.deleted, ['environmentVariable:1']);
      expect(receipt.deletionsApplied, 1);
    });

    test('only the ticked deletions are carried out', () async {
      final snapshot = WorkspaceSnapshot([envVar(1, 'Dev', 'a', 'x'), envVar(2, 'Dev', 'b', 'y')]);
      final report = VariableReport.build(snapshot);
      source.snapshot = snapshot;
      final plan = RefactorPlan(deletions: [for (final u in report.unused) ...u.definitions]);

      await applier.apply(plan, editIds: {}, deletionIds: {'environmentVariable:2|row'});

      expect(writer.deleted, ['environmentVariable:2']);
    });
  });

  group('as one operation', () {
    test('every write of an apply, and of an undo, runs inside the atomic runner, which is entered once', () async {
      var depth = 0;
      var entered = 0;
      final insideWrites = <bool>[];
      Future<T> atomically<T>(Future<T> Function() action) async {
        entered++;
        depth++;
        try {
          return await action();
        } finally {
          depth--;
        }
      }

      final watching = _DepthWriter(writer, () => depth > 0, insideWrites);
      final atomic = RefactorApplier(source, watching, atomically: atomically);

      final receipt = await atomic.apply(plan, editIds: plan.editIds);
      expect(entered, 1);
      expect(insideWrites, [true, true, true]);

      source.snapshot = WorkspaceSnapshot([
        for (final unit in source.snapshot.units) receipt.changes.where((c) => c.before.key == unit.key).firstOrNull?.after ?? unit,
      ]);
      await atomic.undo(receipt);
      expect(entered, 2);
      expect(insideWrites, [true, true, true, true, true, true]);
    });

    test('a failure inside the runner is not written back by hand: the runner has rolled it back', () async {
      writer.failOnWrite = 2;
      Future<T> atomically<T>(Future<T> Function() action) => action();

      await expectLater(
        RefactorApplier(source, writer, atomically: atomically).apply(plan, editIds: plan.editIds),
        throwsA(isA<RefactorException>()),
      );

      // 1: collection (ok), 2: request (fails). No write puts either back.
      expect(writer.writes.map((w) => w.key), ['collection:1', 'request:100']);
    });
  });

  test('a plan that carries an error is refused', () async {
    await expectLater(applier.apply(RefactorPlan.failed('nope'), editIds: {}), throwsA(isA<RefactorException>()));
  });

  test('values the plan was made from are not changed by applying it', () async {
    final before = acmeWorkspace().unit('request:100')!.valuesOf({'request', 'scripts', 'doc', 'tags', 'example.0'});
    await applier.apply(plan, editIds: plan.editIds);
    expect(source.snapshot.unit('request:100')!.valuesOf({'request', 'scripts', 'doc', 'tags', 'example.0'}), before);
  });

  test('an auth edit rewrites the auth of the request', () async {
    source.snapshot = WorkspaceSnapshot([
      req(1, 'R', auth: const RequestAuth(type: AuthType.basic, basicUsername: 'acme-user')),
      req(2, 'S', assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: 'acme')]),
    ]);
    final plan = WorkspaceFinder.plan(source.snapshot, const FindOptions(query: 'acme'), 'x');
    await applier.apply(plan, editIds: plan.editIds);
    expect((writer.writes[0].target as RequestUnit).request.auth.basicUsername, 'x-user');
    expect(writer.writes[0].groups, {'request'});
    expect((writer.writes[1].target as RequestUnit).assertions.single.expected, 'x');
    expect(writer.writes[1].groups, {'scripts'});
  });
}

/// A plan that deletes the definitions with these ids, as the report would offer them.
RefactorPlan _unusedPlan(WorkspaceSnapshot snapshot, List<String> ids) {
  final deletions = <RefactorDeletion>[];
  for (final definition in snapshot.definitions) {
    final id = '${definition.unitKey}|${definition.removePath}';
    if (!ids.contains(id)) continue;
    deletions.add(
      RefactorDeletion(
        id: id,
        unitKey: definition.unitKey,
        removePath: definition.removePath!,
        keyPath: definition.keyPath,
        name: definition.name,
        trail: const [],
        where: definition.where,
        shownValue: definition.value,
        reason: 'test',
      ),
    );
  }
  return RefactorPlan(deletions: deletions);
}

/// Notes whether each write happens inside the atomic runner, and passes it on.
final class _DepthWriter implements RefactorWriter {
  final RefactorWriter _inner;
  final bool Function() _inside;
  final List<bool> _seen;
  _DepthWriter(this._inner, this._inside, this._seen);

  @override
  Future<Map<int, int>> write(RefactorUnit current, RefactorUnit target, Set<String> groups) {
    _seen.add(_inside());
    return _inner.write(current, target, groups);
  }

  @override
  Future<void> delete(RefactorUnit unit) {
    _seen.add(_inside());
    return _inner.delete(unit);
  }

  @override
  Future<void> recreate(RefactorUnit unit) {
    _seen.add(_inside());
    return _inner.recreate(unit);
  }
}
