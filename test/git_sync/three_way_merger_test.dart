import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/repo_layout.dart';
import 'package:postpilot/features/git_sync/domain/services/three_way_merger.dart';

import 'fakes/sync_fixtures.dart';

SyncDoc req({String url = 'https://api.test/things', Map<String, Object?> extra = const {}}) =>
    requestDoc('r1', 'List users', url: url, data: {'headers': 'h0', 'body': 'b0', ...extra});

MergeOutcome merge(SyncSnapshot base, SyncSnapshot local, SyncSnapshot remote, [ConflictResolutions? resolutions]) =>
    ThreeWayMerger.merge(base: base, local: local, remote: remote, resolutions: resolutions);

void main() {
  final base = snapshotOf([collectionDoc(), req()]);

  group('one side only', () {
    test('a doc that exists only locally is kept, one that exists only remotely is taken', () {
      final local = changed(base, docs: [requestDoc('r-local', 'Mine')]);
      final remote = changed(base, docs: [requestDoc('r-remote', 'Theirs')]);

      final out = merge(base, local, remote);

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs.keys.toSet(), {'col', 'r1', 'r-local', 'r-remote'});
    });

    test('nothing changed keeps the doc', () {
      final out = merge(base, base, base);
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs, base.docs);
    });

    test('only local changed takes the local doc, only remote changed the remote doc', () {
      final edit = changed(base, docs: [req(url: 'https://new.test')]);

      expect(merge(base, edit, base).merged.docs['r1']!.data['url'], 'https://new.test');
      expect(merge(base, base, edit).merged.docs['r1']!.data['url'], 'https://new.test');
    });
  });

  group('added on both sides', () {
    test('identical docs are kept without conflict', () {
      final added = requestDoc('r9', 'New');
      final out = merge(base, changed(base, docs: [added]), changed(base, docs: [added]));
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r9'], added);
    });

    test('differing docs conflict on every differing field, treating base as absent', () {
      final local = changed(base, docs: [requestDoc('r9', 'New', url: 'https://a.test', data: {'note': 'n'})]);
      final remote = changed(base, docs: [requestDoc('r9', 'New', url: 'https://b.test')]);

      final out = merge(base, local, remote);

      final conflict = out.conflicts.single;
      expect(conflict.uid, 'r9');
      expect(conflict.type, ConflictKind.bothModified);
      expect(conflict.fields.map((f) => f.field), ['note', 'url']);
      final url = conflict.fields.last;
      expect([url.base, url.local, url.remote], [null, 'https://a.test', 'https://b.test']);
      final note = conflict.fields.first;
      expect([note.local, note.remote], ['n', null]);
      expect(out.merged.docs['r9']!.data['url'], 'https://a.test');
    });

    test('a resolution settles the clash', () {
      final local = changed(base, docs: [requestDoc('r9', 'New', url: 'https://a.test')]);
      final remote = changed(base, docs: [requestDoc('r9', 'New', url: 'https://b.test')]);

      final out = merge(base, local, remote, {'r9': ConflictChoice.remote});

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r9']!.data['url'], 'https://b.test');
    });
  });

  group('deleted on one or both sides', () {
    test('deleted locally and untouched remotely is gone', () {
      expect(merge(base, changed(base, drop: ['r1']), base).merged.docs.containsKey('r1'), isFalse);
    });

    test('deleted remotely and untouched locally is gone', () {
      final out = merge(base, base, changed(base, drop: ['r1']));
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs.containsKey('r1'), isFalse);
    });

    test('deleted on both sides stays gone', () {
      final gone = changed(base, drop: ['r1']);
      final out = merge(base, gone, gone);
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs.keys, ['col']);
    });

    test('deleted locally, modified remotely: conflict; the local version (deleted) is left in the result', () {
      final out = merge(base, changed(base, drop: ['r1']), changed(base, docs: [req(url: 'https://x.test')]));

      expect(out.conflicts.single.type, ConflictKind.deletedLocallyModifiedRemotely);
      expect(out.conflicts.single.fields, isEmpty);
      expect(out.conflicts.single.name, 'List users');
      expect(out.merged.docs.containsKey('r1'), isFalse);
    });

    test('deleted locally, modified remotely: remote keeps the remote version, local stays deleted', () {
      final local = changed(base, drop: ['r1']);
      final remote = changed(base, docs: [req(url: 'https://x.test')]);

      final keepRemote = merge(base, local, remote, {'r1': ConflictChoice.remote});
      expect(keepRemote.conflicts, isEmpty);
      expect(keepRemote.merged.docs['r1']!.data['url'], 'https://x.test');

      final keepLocal = merge(base, local, remote, {'r1': ConflictChoice.local});
      expect(keepLocal.conflicts, isEmpty);
      expect(keepLocal.merged.docs.containsKey('r1'), isFalse);
    });

    test('modified locally, deleted remotely: conflict; the local version is left in the result', () {
      final out = merge(base, changed(base, docs: [req(url: 'https://x.test')]), changed(base, drop: ['r1']));

      expect(out.conflicts.single.type, ConflictKind.modifiedLocallyDeletedRemotely);
      expect(out.merged.docs['r1']!.data['url'], 'https://x.test');
    });

    test('modified locally, deleted remotely: local keeps it, remote deletes it', () {
      final local = changed(base, docs: [req(url: 'https://x.test')]);
      final remote = changed(base, drop: ['r1']);

      final keepLocal = merge(base, local, remote, {'r1': ConflictChoice.local});
      expect(keepLocal.conflicts, isEmpty);
      expect(keepLocal.merged.docs['r1']!.data['url'], 'https://x.test');

      final keepRemote = merge(base, local, remote, {'r1': ConflictChoice.remote});
      expect(keepRemote.conflicts, isEmpty);
      expect(keepRemote.merged.docs.containsKey('r1'), isFalse);
    });
  });

  group('modified on both sides', () {
    test('edits to different fields merge automatically', () {
      final local = changed(base, docs: [req(extra: {'headers': 'h-local'})]);
      final remote = changed(base, docs: [req(url: 'https://remote.test')]);

      final out = merge(base, local, remote);

      expect(out.conflicts, isEmpty);
      final doc = out.merged.docs['r1']!;
      expect(doc.data['headers'], 'h-local');
      expect(doc.data['url'], 'https://remote.test');
      expect(doc.data['body'], 'b0');
    });

    test('the same edit on both sides is not a conflict', () {
      final same = changed(base, docs: [req(url: 'https://same.test')]);
      final out = merge(base, same, same);
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.data['url'], 'https://same.test');
    });

    test('a doc edited to the same value in one field and differently in another only conflicts on the second', () {
      final local = changed(base, docs: [req(url: 'https://same.test', extra: {'body': 'local'})]);
      final remote = changed(base, docs: [req(url: 'https://same.test', extra: {'body': 'remote'})]);

      final conflict = merge(base, local, remote).conflicts.single;

      expect(conflict.fields.map((f) => f.field), ['body']);
      expect([conflict.fields.single.base, conflict.fields.single.local, conflict.fields.single.remote], ['b0', 'local', 'remote']);
    });

    test('clashing fields are all reported, name/parentUid/order first, and the local doc is left in place', () {
      final local = changed(base, docs: [edited(req(url: 'https://l.test'), {'name': 'Local name', 'order': 1})]);
      final remote = changed(base, docs: [edited(req(url: 'https://r.test'), {'name': 'Remote name', 'order': 2})]);

      final out = merge(base, local, remote);

      expect(out.conflicts.single.fields.map((f) => f.field), ['name', 'order', 'url']);
      expect(out.conflicts.single.name, 'Local name');
      expect(out.merged.docs['r1'], local.docs['r1']);
    });

    test('a local resolution keeps local values for clashing fields and still merges the other fields', () {
      final local = changed(base, docs: [req(url: 'https://l.test')]);
      final remote = changed(base, docs: [req(url: 'https://r.test', extra: {'body': 'remote body'})]);

      final out = merge(base, local, remote, {'r1': ConflictChoice.local});

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.data['url'], 'https://l.test');
      expect(out.merged.docs['r1']!.data['body'], 'remote body');
    });

    test('a remote resolution takes remote values for clashing fields and keeps local-only edits', () {
      final local = changed(base, docs: [req(url: 'https://l.test', extra: {'headers': 'local headers'})]);
      final remote = changed(base, docs: [req(url: 'https://r.test')]);

      final out = merge(base, local, remote, {'r1': ConflictChoice.remote});

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.data['url'], 'https://r.test');
      expect(out.merged.docs['r1']!.data['headers'], 'local headers');
    });

    test('resolutions are per entity: the unresolved ones stay in conflicts', () {
      final two = snapshotOf([collectionDoc(), req(), requestDoc('r2', 'Other', data: {'body': 'b0'})]);
      SyncSnapshot edit(String body) => changed(two, docs: [
            req(extra: {'body': body}),
            requestDoc('r2', 'Other', data: {'body': body}),
          ]);

      final out = merge(two, edit('local'), edit('remote'), {'r1': ConflictChoice.remote, 'unrelated': ConflictChoice.local});

      expect(out.conflicts.map((c) => c.uid), ['r2']);
      expect(out.merged.docs['r1']!.data['body'], 'remote');
      expect(out.merged.docs['r2']!.data['body'], 'local');
    });

    test('a move on one side and an edit on the other both apply', () {
      final withFolder = snapshotOf([collectionDoc(), folderDoc('f1', 'Users'), req()]);
      final local = changed(withFolder, docs: [edited(req(), {'parentUid': 'f1'})]);
      final remote = changed(withFolder, docs: [req(url: 'https://remote.test')]);

      final out = merge(withFolder, local, remote);

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.parentUid, 'f1');
      expect(out.merged.docs['r1']!.data['url'], 'https://remote.test');
    });

    test('renaming to different names conflicts on name', () {
      final local = changed(base, docs: [edited(req(), {'name': 'A'})]);
      final remote = changed(base, docs: [edited(req(), {'name': 'B'})]);
      final field = merge(base, local, remote).conflicts.single.fields.single;
      expect([field.field, field.base, field.local, field.remote], ['name', 'List users', 'A', 'B']);
    });

    test('structured values are compared deeply, regardless of key order', () {
      final start = snapshotOf([
        collectionDoc(),
        req(extra: {'headers': [{'key': 'A', 'value': '1'}]}),
      ]);
      final local = changed(start, docs: [
        req(extra: {'headers': [{'key': 'A', 'value': '1'}, {'key': 'B', 'value': '2'}], 'body': 'local body'}),
      ]);
      final remote = changed(start, docs: [
        req(
          url: 'https://remote.test',
          extra: {'headers': [{'value': '1', 'key': 'A'}, {'value': '2', 'key': 'B'}]},
        ),
      ]);

      final out = merge(start, local, remote);

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.data['body'], 'local body');
      expect(out.merged.docs['r1']!.data['url'], 'https://remote.test');
    });
  });

  group('absent keys are not null', () {
    final withNote = snapshotOf([collectionDoc(), req(extra: {'note': 'x', 'legacy': 1})]);

    test('a key removed on one side and another key edited on the other both apply', () {
      final local = changed(withNote, docs: [without(withNote.docs['r1']!, 'legacy')]);
      final remote = changed(withNote, docs: [edited(withNote.docs['r1']!, {'body': 'remote'})]);

      final doc = merge(withNote, local, remote).merged.docs['r1']!;

      expect(doc.data.containsKey('legacy'), isFalse);
      expect(doc.data['body'], 'remote');
    });

    test('removing a key on one side removes it when the other side did not touch it', () {
      final local = changed(withNote, docs: [without(withNote.docs['r1']!, 'note')]);
      final out = merge(withNote, local, withNote);
      expect(out.merged.docs['r1']!.data.containsKey('note'), isFalse);
    });

    test('a key set to null is kept as null, not dropped', () {
      final local = changed(base, docs: [req(extra: {'note': null})]);
      final doc = merge(base, local, base).merged.docs['r1']!;
      expect(doc.data.containsKey('note'), isTrue);
      expect(doc.data['note'], isNull);
    });

    test('removed on one side and set to null on the other is a conflict', () {
      final local = changed(withNote, docs: [without(withNote.docs['r1']!, 'note')]);
      final remote = changed(withNote, docs: [edited(withNote.docs['r1']!, {'note': null})]);

      final out = merge(withNote, local, remote);

      expect(out.conflicts.single.fields.single.field, 'note');
      expect(out.merged.docs['r1']!.data.containsKey('note'), isFalse);
    });

    test('removed on both sides stays removed without conflict', () {
      final removed = changed(withNote, docs: [without(withNote.docs['r1']!, 'legacy')]);
      final out = merge(withNote, removed, removed);
      expect(out.conflicts, isEmpty);
      expect(out.merged.docs['r1']!.data.containsKey('legacy'), isFalse);
    });
  });

  group('referential integrity', () {
    final tree = snapshotOf([
      collectionDoc(),
      folderDoc('f1', 'Users'),
      requestDoc('r-in', 'Inside', parent: 'f1'),
    ]);

    test('a request added locally to a folder the remote deleted moves to the collection', () {
      final local = changed(tree, docs: [requestDoc('r-new', 'New', parent: 'f1')]);
      final remote = changed(tree, drop: ['f1', 'r-in']);

      final out = merge(tree, local, remote);

      expect(out.conflicts, isEmpty);
      expect(out.merged.docs.containsKey('f1'), isFalse);
      expect(out.merged.docs['r-new']!.parentUid, 'col');
    });

    test('a request added remotely to a folder the local side deleted moves to the collection', () {
      final local = changed(tree, drop: ['f1', 'r-in']);
      final remote = changed(tree, docs: [requestDoc('r-new', 'New', parent: 'f1')]);

      final out = merge(tree, local, remote);

      expect(out.merged.docs['r-new']!.parentUid, 'col');
    });

    test('a request moved into a folder the other side deleted is never dropped or left dangling', () {
      final withRoot = snapshotOf([collectionDoc(), folderDoc('f1', 'Users'), req()]);
      final local = changed(withRoot, docs: [edited(req(), {'parentUid': 'f1'})]);
      final remote = changed(withRoot, drop: ['f1']);

      final out = merge(withRoot, local, remote);

      expect(out.merged.docs['r1']!.parentUid, 'col');
    });

    test('folders moved into each other on opposite sides do not form a cycle', () {
      final two = snapshotOf([collectionDoc(), folderDoc('f-a', 'A'), folderDoc('f-b', 'B')]);
      final local = changed(two, docs: [folderDoc('f-a', 'A', parent: 'f-b')]);
      final remote = changed(two, docs: [folderDoc('f-b', 'B', parent: 'f-a')]);

      final docs = merge(two, local, remote).merged.docs;

      expect(docs['f-a']!.parentUid, 'col');
      expect(docs['f-b']!.parentUid, 'f-a');
    });
  });

  group('the collection doc', () {
    test('is never deleted by a merge, even when the remote has no collection', () {
      final out = merge(base, base, SyncSnapshot.empty);

      expect(out.conflicts, isEmpty);
      expect(out.merged.root!.uid, 'col');
      expect(out.merged.docs.containsKey('r1'), isFalse);
    });

    test('local edits to it survive a remote without collection and raise no conflict', () {
      final local = changed(base, docs: [collectionDoc(name: 'Renamed')]);
      final out = merge(base, local, SyncSnapshot.empty);

      expect(out.conflicts, isEmpty);
      expect(out.merged.root!.name, 'Renamed');
    });

    test('a remote collection created under another uid merges as the same collection', () {
      final remote = snapshotOf([
        collectionDoc(uid: 'col-other', name: 'API', data: {'description': 'from remote'}),
        requestDoc('r-remote', 'Theirs', parent: 'col-other'),
      ]);

      final out = merge(base, base, remote);

      expect(out.merged.docs.values.where((d) => d.kind == SyncKind.collection).map((d) => d.uid), ['col']);
      expect(out.merged.docs['col']!.data['description'], 'from remote');
      expect(out.merged.docs['r-remote']!.parentUid, 'col');
    });
  });

  group('properties over random histories', () {
    const values = ['x', 'y', 'z'];

    SyncSnapshot randomTree(Random random) {
      final docs = <SyncDoc>[collectionDoc(data: {'description': 'd0'})];
      final containers = ['col'];
      for (var i = 0; i < 2 + random.nextInt(8); i++) {
        final parent = containers[random.nextInt(containers.length)];
        if (random.nextInt(3) == 0) {
          docs.add(folderDoc('d$i', 'Folder $i', parent: parent, order: random.nextInt(3)));
          containers.add('d$i');
        } else {
          docs.add(requestDoc('d$i', 'Request $i', parent: parent, order: random.nextInt(3), data: {'body': 'b$i', 'note': 'n$i'}));
        }
      }
      return snapshotOf(docs);
    }

    SyncSnapshot randomEdits(Random random, SyncSnapshot start, String tag) {
      final docs = {...start.docs};
      for (var step = 0; step < 1 + random.nextInt(4); step++) {
        final ids = (docs.keys.where((id) => id != 'col').toList()..sort());
        final pick = ids.isEmpty ? null : ids[random.nextInt(ids.length)];
        switch (random.nextInt(6)) {
          case 0 when pick != null:
            final key = const ['body', 'note', 'url'][random.nextInt(3)];
            final roll = random.nextInt(5);
            docs[pick] = roll == 0
                ? without(docs[pick]!, key)
                : edited(docs[pick]!, {key: roll == 1 ? null : values[random.nextInt(values.length)]});
          case 1 when pick != null:
            docs[pick] = edited(docs[pick]!, {'name': 'Name ${values[random.nextInt(values.length)]}'});
          case 2 when pick != null:
            final blocked = subtreeOf(docs, pick);
            final targets = ['col', ...ids.where((id) => docs[id]!.kind == SyncKind.folder && !blocked.contains(id))];
            docs[pick] = edited(docs[pick]!, {'parentUid': targets[random.nextInt(targets.length)]});
          case 3 when pick != null:
            final doomed = subtreeOf(docs, pick);
            docs.removeWhere((id, _) => doomed.contains(id));
          case 4:
            final parents = ['col', ...ids.where((id) => docs[id]!.kind == SyncKind.folder)];
            final uid = 'n$tag$step';
            docs[uid] = requestDoc(uid, 'New ${values[random.nextInt(values.length)]}', parent: parents[random.nextInt(parents.length)]);
          case 5:
            docs['col'] = edited(docs['col']!, {'description': values[random.nextInt(values.length)]});
        }
      }
      return SyncSnapshot(docs);
    }

    ConflictResolutions everyone(MergeOutcome outcome, ConflictChoice choice) =>
        {for (final conflict in outcome.conflicts) conflict.uid: choice};

    test('fast-forwards, identical edits, valid parents, one collection, symmetry and resolutions', () {
      var withConflicts = 0;
      var withoutConflicts = 0;
      for (var seed = 0; seed < 400; seed++) {
        final random = Random(seed);
        final base = randomTree(random);
        final local = randomEdits(random, base, 'l');
        final remote = randomEdits(random, base, 'r');
        final why = 'seed $seed';

        final ff = merge(base, base, remote);
        expect(ff.conflicts, isEmpty, reason: why);
        expect(ff.merged.docs, remote.docs, reason: why);
        final keep = merge(base, local, base);
        expect(keep.conflicts, isEmpty, reason: why);
        expect(keep.merged.docs, local.docs, reason: why);
        final same = merge(base, local, local);
        expect(same.conflicts, isEmpty, reason: why);
        expect(same.merged.docs, local.docs, reason: why);

        final out = merge(base, local, remote);
        expect(RepoLayout.repairParents(out.merged).docs, out.merged.docs, reason: why);
        expect(out.merged.docs.values.where((d) => d.kind == SyncKind.collection).map((d) => d.uid), ['col'], reason: why);
        if (out.conflicts.isEmpty) {
          withoutConflicts++;
          expect(merge(base, remote, local).merged.docs, out.merged.docs, reason: why);
        } else {
          withConflicts++;
        }

        final allLocal = merge(base, local, remote, everyone(out, ConflictChoice.local));
        final allRemote = merge(base, remote, local, everyone(out, ConflictChoice.remote));
        expect(allLocal.conflicts, isEmpty, reason: why);
        expect(allLocal.merged.docs, allRemote.merged.docs, reason: why);
      }
      expect(withConflicts, greaterThan(40));
      expect(withoutConflicts, greaterThan(40));
    });
  });

  test('conflicts are ordered collection, folders, requests, then by name', () {
    final all = snapshotOf([
      collectionDoc(),
      folderDoc('f1', 'Zed'),
      requestDoc('r-b', 'Bravo'),
      requestDoc('r-a', 'alpha'),
    ]);
    SyncSnapshot edit(String value) => snapshotOf([
          collectionDoc(data: {'description': value}),
          folderDoc('f1', 'Zed', data: {'x': value}),
          requestDoc('r-b', 'Bravo', data: {'x': value}),
          requestDoc('r-a', 'alpha', data: {'x': value}),
        ]);

    final out = merge(all, edit('local'), edit('remote'));

    expect(out.conflicts.map((c) => c.uid), ['col', 'f1', 'r-a', 'r-b']);
  });
}
