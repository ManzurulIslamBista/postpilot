import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_exceptions.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/repo_layout.dart';

import 'fakes/sync_fixtures.dart';

SyncSnapshot sampleTree() => snapshotOf([
      collectionDoc(name: 'API', data: {'description': 'Shared'}),
      folderDoc('f-users', 'Users'),
      folderDoc('f-admin', 'Admin Tools', parent: 'f-users'),
      requestDoc('r-reset', 'Reset password', parent: 'f-admin'),
      requestDoc('r-list', 'List users', parent: 'f-users', order: 1),
      requestDoc('r-health', 'Health'),
    ]);

void main() {
  group('slug', () {
    test('lowercases and turns runs of other characters into one dash', () {
      expect(RepoLayout.slug('Get User #1'), 'get-user-1');
      expect(RepoLayout.slug('  --Hello__World--  '), 'hello-world');
      expect(RepoLayout.slug(r'A/B\C'), 'a-b-c');
    });

    test('falls back to untitled when nothing usable is left', () {
      expect(RepoLayout.slug(''), 'untitled');
      expect(RepoLayout.slug('!!!'), 'untitled');
      expect(RepoLayout.slug('ইউজার'), 'untitled');
    });
  });

  group('normalizeBasePath', () {
    test('trims spaces and slashes and unifies separators', () {
      expect(RepoLayout.normalizeBasePath('  /team//apis/ '), 'team/apis');
      expect(RepoLayout.normalizeBasePath(r'team\apis'), 'team/apis');
      expect(RepoLayout.normalizeBasePath('./a/./b'), 'a/b');
      expect(RepoLayout.normalizeBasePath('/'), '');
      expect(RepoLayout.normalizeBasePath(''), '');
    });

    test('rejects .. segments', () {
      expect(() => RepoLayout.normalizeBasePath('../x'), throwsA(isA<GitSyncException>()));
      expect(() => RepoLayout.normalizeBasePath('a/../b'), throwsA(isA<GitSyncException>()));
    });
  });

  group('toFiles', () {
    test('lays collection, folders and requests out under the base path', () {
      final files = RepoLayout.toFiles(sampleTree(), basePath: 'team/apis');
      expect(files.keys.toSet(), {
        'team/apis/collection.json',
        'team/apis/users/_folder.json',
        'team/apis/users/admin-tools/_folder.json',
        'team/apis/users/admin-tools/reset-password.request.json',
        'team/apis/users/list-users.request.json',
        'team/apis/health.request.json',
      });
    });

    test('an empty base path is the repository root', () {
      final files = RepoLayout.toFiles(sampleTree(), basePath: '');
      expect(files.keys, containsAll(['collection.json', 'users/_folder.json', 'health.request.json']));
      expect(files.keys.every((path) => !path.startsWith('/')), isTrue);
    });

    test('file text is the canonical text of the doc', () {
      final tree = sampleTree();
      final files = RepoLayout.toFiles(tree, basePath: '');
      expect(files['collection.json'], tree.docs['col']!.canonicalText);
      expect(files['collection.json'], endsWith('}\n'));
      expect(files['users/list-users.request.json'], tree.docs['r-list']!.canonicalText);
    });

    test('siblings with the same slug get the uid prefix; the first in (order, name, uid) keeps the plain slug', () {
      final files = RepoLayout.toFiles(
        snapshotOf([
          collectionDoc(),
          requestDoc('bbbb2222xyz', 'get user', order: 1),
          requestDoc('aaaa1111xyz', 'Get User'),
          requestDoc('u-2', 'Ping'),
          requestDoc('u-1', 'Ping'),
        ]),
        basePath: '',
      );
      expect(files.keys.toSet(), {
        'collection.json',
        'get-user.request.json',
        'get-user-bbbb2222.request.json',
        'ping.request.json',
        'ping-u-2.request.json',
      });
      expect(files['get-user.request.json'], contains('aaaa1111xyz'));
      expect(files['ping.request.json'], contains('"u-1"'));
    });

    test('a folder and a request with the same slug do not collide', () {
      final files = RepoLayout.toFiles(
        snapshotOf([collectionDoc(), folderDoc('f1', 'Users'), requestDoc('r1', 'Users')]),
        basePath: '',
      );
      expect(files.keys.toSet(), {'collection.json', 'users/_folder.json', 'users.request.json'});
    });

    test('the same slug in different folders is fine', () {
      final files = RepoLayout.toFiles(
        snapshotOf([
          collectionDoc(),
          folderDoc('f1', 'A'),
          folderDoc('f2', 'B'),
          requestDoc('r1', 'List', parent: 'f1'),
          requestDoc('r2', 'List', parent: 'f2'),
        ]),
        basePath: '',
      );
      expect(files.keys, containsAll(['a/list.request.json', 'b/list.request.json']));
    });

    test('output does not depend on the insertion order of the docs', () {
      final docs = sampleTree().docs.values.toList();
      final forward = RepoLayout.toFiles(snapshotOf(docs), basePath: 'x');
      final backward = RepoLayout.toFiles(snapshotOf(docs.reversed), basePath: 'x');
      expect(backward.keys.toList(), forward.keys.toList());
      expect(backward.values.toList(), forward.values.toList());
      expect(RepoLayout.toFiles(snapshotOf(docs), basePath: 'x').entries.map((e) => '${e.key}=${e.value}').join(),
          forward.entries.map((e) => '${e.key}=${e.value}').join());
    });

    test('a rename or a move changes the path but not the uid', () {
      final tree = sampleTree();
      final before = RepoLayout.pathsByUid(tree, basePath: '');
      final renamed = snapshotOf([
        for (final doc in tree.docs.values)
          if (doc.uid == 'f-users') edited(doc, {'name': 'Accounts'}) else doc,
      ]);
      final moved = snapshotOf([
        for (final doc in tree.docs.values)
          if (doc.uid == 'r-list') edited(doc, {'parentUid': 'col'}) else doc,
      ]);

      final afterRename = RepoLayout.pathsByUid(renamed, basePath: '');
      expect(afterRename['f-users'], 'accounts/_folder.json');
      expect(afterRename['r-list'], 'accounts/list-users.request.json');
      expect(afterRename['r-reset'], 'accounts/admin-tools/reset-password.request.json');
      expect(before['r-list'], 'users/list-users.request.json');

      expect(RepoLayout.pathsByUid(moved, basePath: '')['r-list'], 'list-users.request.json');
    });

    test('a doc whose parent is missing is placed under the collection instead of being dropped', () {
      final files = RepoLayout.toFiles(
        snapshotOf([collectionDoc(), requestDoc('r1', 'Lost', parent: 'gone')]),
        basePath: '',
      );
      expect(files.keys.toSet(), {'collection.json', 'lost.request.json'});
      expect(RepoLayout.tryParseDoc(files['lost.request.json']!)!.parentUid, 'col');
    });
  });

  group('fromFiles', () {
    test('reads back exactly what toFiles wrote', () {
      final tree = sampleTree();
      for (final base in ['', 'team/apis']) {
        final parsed = RepoLayout.fromFiles(RepoLayout.toFiles(tree, basePath: base), basePath: base);
        expect(parsed.snapshot.docs, tree.docs);
        expect(parsed.skippedPaths, isEmpty);
      }
    });

    test('ignores other files and files outside the base path, and reports unusable ones', () {
      final list = requestDoc('r-list', 'List', parent: 'f-users');
      final files = {
        'apis/collection.json': collectionDoc().canonicalText,
        'apis/README.md': '# hi',
        'apis/notes.txt': 'x',
        'apis/users/_folder.json': folderDoc('f-users', 'Users').canonicalText,
        'apis/users/list.request.json': list.canonicalText,
        'apis/broken.request.json': '{not json',
        'apis/wrongkind.request.json': folderDoc('f-x', 'X').canonicalText,
        'apis/zz-copy.request.json': list.canonicalText,
        'other/collection.json': collectionDoc(uid: 'other', name: 'Other').canonicalText,
        'other/x.request.json': requestDoc('r-other', 'Other request', parent: 'other').canonicalText,
      };

      final parsed = RepoLayout.fromFiles(files, basePath: 'apis');

      expect(parsed.snapshot.docs.keys.toSet(), {'col', 'f-users', 'r-list'});
      expect(parsed.skippedPaths, ['apis/broken.request.json', 'apis/wrongkind.request.json', 'apis/zz-copy.request.json']);
    });

    test('no collection.json gives an empty snapshot', () {
      final parsed = RepoLayout.fromFiles({
        'users/_folder.json': folderDoc('f1', 'Users').canonicalText,
        'a.request.json': requestDoc('r1', 'A').canonicalText,
      }, basePath: '');
      expect(parsed.snapshot.isEmpty, isTrue);
    });

    test('a base path is a folder, not a string prefix', () {
      final parsed = RepoLayout.fromFiles({
        'apis/collection.json': collectionDoc().canonicalText,
        'apis2/collection.json': collectionDoc(uid: 'two', name: 'Two').canonicalText,
        'apis2/a.request.json': requestDoc('r-two', 'A', parent: 'two').canonicalText,
      }, basePath: 'apis');
      expect(parsed.snapshot.docs.keys.toSet(), {'col'});
    });

    test('a folder holding its own collection.json belongs to another collection', () {
      final files = {
        'collection.json': collectionDoc().canonicalText,
        'users/_folder.json': folderDoc('f1', 'Users').canonicalText,
        'sub/collection.json': collectionDoc(uid: 'sub', name: 'Sub').canonicalText,
        'sub/a.request.json': requestDoc('r-sub', 'A', parent: 'sub').canonicalText,
        'sub/deeper/_folder.json': folderDoc('f-deep', 'Deeper', parent: 'sub').canonicalText,
      };
      expect(RepoLayout.fromFiles(files, basePath: '').snapshot.docs.keys.toSet(), {'col', 'f1'});
      expect(RepoLayout.fromFiles(files, basePath: 'sub').snapshot.docs.keys.toSet(), {'sub', 'r-sub', 'f-deep'});
      expect(RepoLayout.relevantPaths(files.keys, basePath: ''), ['collection.json', 'users/_folder.json']);
    });

    test('a missing or unknown parent comes from the enclosing folder file, else the collection', () {
      SyncDoc noParent(String uid, SyncKind kind) => SyncDoc(uid: uid, kind: kind, parentUid: null, name: uid);
      final files = {
        'collection.json': collectionDoc().canonicalText,
        'users/_folder.json': noParent('f-users', SyncKind.folder).canonicalText,
        'users/list.request.json': requestDoc('r-list', 'List', parent: 'nope').canonicalText,
        'users/admin/_folder.json': folderDoc('f-admin', 'Admin', parent: 'r-list').canonicalText,
        'users/admin/reset.request.json': noParent('r-reset', SyncKind.request).canonicalText,
        'lonely/x.request.json': noParent('r-x', SyncKind.request).canonicalText,
        'deep/_folder.json': noParent('f-deep', SyncKind.folder).canonicalText,
        'deep/a/b/y.request.json': noParent('r-y', SyncKind.request).canonicalText,
        'missing-key.request.json': jsonEncode({'uid': 'r-m', 'kind': 'request', 'name': 'M', 'order': 0}),
      };

      final docs = RepoLayout.fromFiles(files, basePath: '').snapshot.docs;

      expect(docs['f-users']!.parentUid, 'col');
      expect(docs['r-list']!.parentUid, 'f-users');
      expect(docs['f-admin']!.parentUid, 'f-users');
      expect(docs['r-reset']!.parentUid, 'f-admin');
      expect(docs['r-x']!.parentUid, 'col');
      expect(docs['r-y']!.parentUid, 'f-deep');
      expect(docs['r-m']!.parentUid, 'col');
    });

    test('a declared parent wins over the directory the file sits in', () {
      final files = {
        'collection.json': collectionDoc().canonicalText,
        'a/_folder.json': folderDoc('f-a', 'A').canonicalText,
        'b/_folder.json': folderDoc('f-b', 'B').canonicalText,
        'a/moved.request.json': requestDoc('r1', 'Moved', parent: 'f-b').canonicalText,
      };
      expect(RepoLayout.fromFiles(files, basePath: '').snapshot.docs['r1']!.parentUid, 'f-b');
    });

    test('a parent cycle is broken by re-parenting to the collection', () {
      final files = {
        'collection.json': collectionDoc().canonicalText,
        'a/_folder.json': folderDoc('f-a', 'A', parent: 'f-b').canonicalText,
        'b/_folder.json': folderDoc('f-b', 'B', parent: 'f-a').canonicalText,
      };
      final docs = RepoLayout.fromFiles(files, basePath: '').snapshot.docs;
      expect(docs['f-a']!.parentUid, 'col');
      expect(docs['f-b']!.parentUid, 'f-a');
    });

    test('tolerates a byte order mark', () {
      final parsed = RepoLayout.fromFiles({'collection.json': '﻿${collectionDoc().canonicalText}'}, basePath: '');
      expect(parsed.snapshot.docs.keys, ['col']);
    });

    test('the collection doc never keeps a parent', () {
      final json = jsonDecode(collectionDoc().canonicalText) as Map<String, dynamic>..['parent'] = 'x';
      final parsed = RepoLayout.fromFiles({'collection.json': jsonEncode(json)}, basePath: '');
      expect(parsed.snapshot.docs['col']!.parentUid, isNull);
    });
  });

  test('random trees survive a round trip through files: nothing lost, duplicated or reordered', () {
    const names = ['Alpha', 'alpha', 'ALPHA!', 'Beta', '', '..', 'a/b', 'Δ', 'get user', 'get-user', 'Get  User'];
    for (var seed = 0; seed < 300; seed++) {
      final random = Random(seed);
      final docs = <SyncDoc>[collectionDoc()];
      final folders = ['col'];
      for (var i = 0; i < 1 + random.nextInt(30); i++) {
        final uid = 'u$i-${random.nextInt(9999)}';
        final parent = folders[random.nextInt(folders.length)];
        final name = names[random.nextInt(names.length)];
        final order = random.nextInt(3);
        if (random.nextBool()) {
          docs.add(folderDoc(uid, name, parent: parent, order: order));
          folders.add(uid);
        } else {
          docs.add(requestDoc(uid, name, parent: parent, order: order));
        }
      }
      final tree = snapshotOf(docs);
      final base = seed.isEven ? '' : 'x/y';
      final why = 'seed $seed';

      final files = RepoLayout.toFiles(tree, basePath: base);

      expect(files.length, docs.length, reason: why);
      final parsed = RepoLayout.fromFiles(files, basePath: base);
      expect(parsed.skippedPaths, isEmpty, reason: why);
      expect(parsed.snapshot.docs, tree.docs, reason: why);
      final reversed = RepoLayout.toFiles(snapshotOf(docs.reversed), basePath: base);
      expect(reversed.keys.toList(), files.keys.toList(), reason: why);
    }
  });

  group('repairParents', () {
    test('re-parents dangling docs, docs under a request and cycles; leaves valid docs alone', () {
      final tree = snapshotOf([
        collectionDoc(),
        requestDoc('r1', 'One'),
        requestDoc('r-gone', 'Gone', parent: 'nowhere'),
        requestDoc('r-under', 'Under', parent: 'r1'),
        folderDoc('f-a', 'A', parent: 'f-b'),
        folderDoc('f-b', 'B', parent: 'f-a'),
        folderDoc('f-ok', 'Ok'),
        requestDoc('r-ok', 'Fine', parent: 'f-ok'),
      ]);

      final docs = RepoLayout.repairParents(tree).docs;

      expect(docs['r-gone']!.parentUid, 'col');
      expect(docs['r-under']!.parentUid, 'col');
      expect(docs['f-a']!.parentUid, 'col');
      expect(docs['f-b']!.parentUid, 'f-a');
      expect(docs['r-ok'], same(tree.docs['r-ok']));
      expect(docs['f-ok'], same(tree.docs['f-ok']));
    });
  });
}
