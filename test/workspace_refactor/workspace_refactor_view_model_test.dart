// What the dialog's view model does between the user and the applier: re-planning as the options change, the ticks,
// the merge gate, the one undo of the session. A fixed workspace and a recording writer stand in for the database.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_receipt.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_scope.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/request_unit.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_applier.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_reader.dart';
import 'package:postpilot/features/workspace_refactor/presentation/view_models/preview_rows.dart';
import 'package:postpilot/features/workspace_refactor/presentation/view_models/workspace_refactor_view_model.dart';

import 'refactor_fakes.dart';
import 'refactor_fixtures.dart';

void main() {
  late FixedSource source;
  late RecordingWriter writer;
  late RefactorUndoStore undo;
  late WorkspaceRefactorViewModel vm;

  Future<void> start([WorkspaceSnapshot? snapshot]) async {
    source = FixedSource(snapshot ?? acmeWorkspace());
    writer = RecordingWriter();
    undo = RefactorUndoStore();
    vm = WorkspaceRefactorViewModel(source, RefactorApplier(source, writer), undo, searchDelay: Duration.zero);
    addTearDown(vm.dispose);
    await vm.load();
  }

  group('loading', () {
    test('reads the workspace once and starts with nothing to show', () async {
      await start();
      expect(vm.snapshot, isNotNull);
      expect(vm.isLoading, isFalse);
      expect(vm.findPlan.isEmpty, isTrue);
      expect(vm.findRows.isEmpty, isTrue);
    });

    test('a workspace that cannot be read is an error with a way to try again', () async {
      final failing = _Failing();
      vm = WorkspaceRefactorViewModel(failing, RefactorApplier(failing, RecordingWriter()), RefactorUndoStore(), searchDelay: Duration.zero);
      addTearDown(vm.dispose);
      await vm.load();
      expect(vm.snapshot, isNull);
      expect(vm.loadError, contains('Could not read the workspace'));
    });
  });

  group('find and replace', () {
    test('typing plans at once with no delay, and every option replans', () async {
      await start();
      vm.setQuery('acme');
      expect(vm.findPlan.editCount, 12);
      vm.setOptions(caseSensitive: true);
      // Only the lower-case ones: not the "Acme" of the request name.
      expect(vm.findPlan.editCount, 11);
      vm.setOptions(wholeWord: true);
      // "acme-key", "acme-user", "acme.test" and "acme.example" still have a boundary; so does every other one.
      expect(vm.findPlan.editCount, 11);
      vm.setOptions(regex: true);
      vm.setQuery('acme(-\\w+)');
      expect(vm.findPlan.editCount, 2);
      vm.setReplacement(r'zeta$1');
      expect(vm.findPlan.edits.map((e) => e.after), ['zeta-key', 'zeta-user']);
    });

    test('the scopes narrow the search', () async {
      await start();
      vm.setQuery('acme');
      vm.setAllScopes(false);
      expect(vm.findPlan.editCount, 0);
      vm.toggleScope(RefactorScope.urls);
      expect(vm.findPlan.editCount, 1);
      vm.setAllScopes(true);
      expect(vm.findPlan.editCount, 12);
    });

    test('a regular expression that does not compile is an error, not a crash', () async {
      await start();
      vm.setOptions(regex: true);
      vm.setQuery('(');
      expect(vm.findPlan.error, startsWith('Not a valid regular expression'));
      expect(vm.canReplace, isFalse);
    });

    test('unticking leaves an occurrence out, and a heading unticks everything below it', () async {
      await start();
      vm.setQuery('acme');
      final urlEdit = vm.findPlan.changes.firstWhere((c) => c.path == 'url').edits.single.id;
      vm.setTicked(urlEdit, false);
      expect(vm.tickedCount, 11);
      expect(vm.isTicked(urlEdit), isFalse);

      final request = vm.findRows.rows.whereType<GroupRow>().firstWhere((g) => g.title == 'Acme list');
      vm.setManyTicked(request.editIds, false);
      // Ten of the twelve are in that request; the collection's header and the environment's value stay ticked.
      expect(request.editIds, hasLength(10));
      expect(vm.tickedCount, 2);

      vm.tickAll(true);
      expect(vm.tickedCount, 12);
    });

    test('the preview is grouped collection, then request, in the order of the workspace', () async {
      await start();
      vm.setQuery('acme');
      final headings = [for (final r in vm.findRows.rows.whereType<GroupRow>()) '${r.depth}:${r.title}'];
      // The collection's own default header sits under "Shop", and so does the request, one level down.
      expect(headings, ['0:Shop', '1:Acme list', '0:Environments', '1:Dev']);
    });

    test('replacing writes only the ticked occurrences, says so, and keeps one undo', () async {
      await start();
      vm.setQuery('acme');
      vm.setReplacement('Zeta');
      final tag = vm.findPlan.changes.firstWhere((c) => c.path == 'tag.0').edits.single.id;
      vm.tickAll(false);
      vm.setTicked(tag, true);
      final changedRequests = <int>[];
      vm.onRequestsChanged = changedRequests.addAll;

      await vm.applyFind();

      expect(writer.writes.single.groups, {'tags'});
      expect(vm.notice, 'Replaced 1 occurrence in 1 place.');
      expect(vm.noticeIsError, isFalse);
      expect(vm.lastReceipt, isNotNull);
      expect(changedRequests, [100]);
      expect(vm.isApplying, isFalse);
    });

    test('replace is off with nothing ticked and while it is running', () async {
      await start();
      expect(vm.canReplace, isFalse);
      vm.setQuery('acme');
      expect(vm.canReplace, isTrue);
      vm.tickAll(false);
      expect(vm.canReplace, isFalse);
    });

    test('secret values are counted, not listed, until asked for', () async {
      await start(WorkspaceSnapshot([envVar(1, 'Dev', 'key', 'sk-acme-1', secret: true), envVar(2, 'Dev', 'host', 'acme.test')]));
      vm.setQuery('acme');
      expect(vm.findPlan.editCount, 1);
      expect(vm.findPlan.secretSkipped, 1);
      vm.setOptions(includeSecret: true);
      expect(vm.findPlan.editCount, 2);
      expect(vm.findPlan.secretSkipped, 0);
    });

    test('a text that changed since the preview is reported and nothing is stored for undo', () async {
      await start();
      vm.setQuery('acme');
      source.snapshot = WorkspaceSnapshot([
        for (final u in source.snapshot.units) u is RequestUnit ? u.copyWith(request: u.request.copyWith(name: 'Renamed', url: 'x', headers: [], queryParams: [])) : u,
      ]);
      vm.tickAll(false);
      vm.setTicked(vm.findPlan.changes.firstWhere((c) => c.path == 'url').edits.single.id, true);

      await vm.applyFind();

      expect(vm.notice, contains('changed since the preview'));
      expect(vm.noticeIsError, isTrue);
      expect(vm.lastReceipt, isNull);
    });
  });

  group('undo', () {
    test('puts back what the last replace changed, then there is nothing left to undo', () async {
      await start();
      vm.setQuery('acme');
      vm.setReplacement('Zeta');
      await vm.applyFind();
      final receipt = vm.lastReceipt!;
      source.snapshot = WorkspaceSnapshot([
        for (final u in source.snapshot.units) receipt.changes.where((c) => c.before.key == u.key).firstOrNull?.after ?? u,
      ]);
      writer.writes.clear();
      final changedRequests = <int>[];
      vm.onRequestsChanged = changedRequests.addAll;

      await vm.undoLast();

      expect(vm.notice, 'Undone: 3 places put back.');
      expect(vm.lastReceipt, isNull);
      expect(writer.writes, hasLength(3));
      expect(changedRequests, [100]);
    });

    test('the undo outlives the view model: a new dialog of the session still offers it', () async {
      await start();
      vm.setQuery('acme');
      await vm.applyFind();
      final second = WorkspaceRefactorViewModel(source, RefactorApplier(source, writer), undo, searchDelay: Duration.zero);
      addTearDown(second.dispose);
      expect(second.lastReceipt, isNotNull);
      expect(second.lastReceipt!.editsApplied, 12);
    });

    test('says what it left alone', () async {
      await start();
      vm.setQuery('acme');
      await vm.applyFind();
      // The workspace is still the one before the replace: the texts no longer say what the replace wrote.
      await vm.undoLast();
      expect(vm.noticeIsError, isTrue);
      expect(vm.notice, contains('was edited since'));
    });
  });

  group('rename a variable', () {
    final workspace = WorkspaceSnapshot([
      envVar(1, 'Dev', 'host', 'old-dev'),
      envVar(2, 'Dev', 'server', 'existing-dev'),
      globalVar(3, 'token', 't'),
      req(10, 'R', url: '{{host}}/x/{{token}}'),
    ]);

    test('suggests the defined names that contain what was typed', () async {
      await start(workspace);
      expect([for (final n in vm.suggestions('')) n.name], ['host', 'server', 'token']);
      expect([for (final n in vm.suggestions('SER')) n.name], ['server']);
      expect(vm.suggestions('zzz'), isEmpty);
    });

    test('counts definitions and references', () async {
      await start(workspace);
      vm.setOldName('token');
      vm.setNewName('apiToken');
      expect(vm.definitionCount, 1);
      expect(vm.referenceCount, 1);
      expect(vm.canRename, isTrue);
    });

    test('a name that is taken needs the merge to be confirmed first', () async {
      await start(workspace);
      vm.setOldName('host');
      vm.setNewName('server');
      expect(vm.renamePlan.needsConfirmation, isTrue);
      expect(vm.canRename, isFalse);
      vm.confirmMerge(true);
      expect(vm.canRename, isTrue);
      // Typing again asks again.
      vm.setNewName('server2');
      expect(vm.mergeConfirmed, isFalse);
    });

    test('renaming writes, empties the fields and tells what it did', () async {
      await start(workspace);
      vm.setOldName('token');
      vm.setNewName('apiToken');

      await vm.applyRename();

      expect(vm.notice, 'Renamed {{token}} to {{apiToken}}: 2 occurrences in 2 places.');
      expect(vm.oldName, isEmpty);
      expect(vm.newName, isEmpty);
      expect(writer.writes.map((w) => w.key), unorderedEquals(['globalVariable:3', 'request:10']));
    });

    test('a merge deletes the old definition', () async {
      await start(workspace);
      vm.setOldName('host');
      vm.setNewName('server');
      vm.confirmMerge(true);

      await vm.applyRename();

      expect(writer.deleted, ['environmentVariable:1']);
      expect(vm.notice, contains('removed 1 old definition'));
    });

    test('a bad name is an error on the plan and cannot be applied', () async {
      await start(workspace);
      vm.setOldName('host');
      vm.setNewName(r'$guid');
      expect(vm.renamePlan.error, isNotNull);
      expect(vm.canRename, isFalse);
    });
  });

  group('the report', () {
    final workspace = WorkspaceSnapshot([
      envVar(1, 'Dev', 'legacy', 'x'),
      envVar(2, 'Dev', 'old', 'y'),
      envVar(3, 'Dev', 'used', 'z'),
      req(10, 'R', url: '{{used}}/{{missing}}'),
    ]);

    test('lists what is unused and what is undefined, with nothing ticked', () async {
      await start(workspace);
      expect([for (final u in vm.unused) u.name], ['legacy', 'old']);
      expect([for (final u in vm.undefined) u.name], ['missing']);
      expect(vm.markedForDeleteCount, 0);
      expect(vm.canDeleteUnused, isFalse);
    });

    test('deletes only the ticked ones', () async {
      await start(workspace);
      vm.setMarkedForDelete('environmentVariable:2|row', true);
      expect(vm.canDeleteUnused, isTrue);

      await vm.deleteMarkedUnused();

      expect(writer.deleted, ['environmentVariable:2']);
      expect(vm.notice, 'Deleted 1 variable definition.');
    });

    test('tick all, then none', () async {
      await start(workspace);
      vm.markAllForDelete(true);
      expect(vm.markedForDeleteCount, 2);
      vm.markAllForDelete(false);
      expect(vm.markedForDeleteCount, 0);
    });
  });

  testWidgets('with a delay, typing plans once after it and not before', (tester) async {
    source = FixedSource(acmeWorkspace());
    writer = RecordingWriter();
    vm = WorkspaceRefactorViewModel(source, RefactorApplier(source, writer), RefactorUndoStore(), searchDelay: const Duration(milliseconds: 200));
    await tester.runAsync(vm.load);

    vm.setQuery('a');
    vm.setQuery('ac');
    vm.setQuery('acme');
    await tester.pump(const Duration(milliseconds: 150));
    expect(vm.findPlan.isEmpty, isTrue, reason: 'still waiting');
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.findPlan.editCount, 12);
    vm.dispose();
  });
}

final class _Failing implements WorkspaceSource {
  @override
  Future<WorkspaceSnapshot> read() async => throw StateError('disk is gone');
}
