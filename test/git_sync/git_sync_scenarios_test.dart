import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_exceptions.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/repo_layout.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_create_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discover_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_history_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_save_token_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_update_link_settings_usecase.dart';

import 'fakes/fake_git_host.dart';
import 'fakes/sync_fixtures.dart';
import 'fakes/teammate.dart';

const repoName = 'acme/payments';
const basePath = 'apis/payments';

/// Alice's and Bob's copies of one collection that lives at [basePath] of one repository.
class Pair {
  final Teammate a;
  final Teammate b;
  final int aId;
  final int bId;
  final RepoRef repo;

  const Pair(this.a, this.b, this.aId, this.bId, this.repo);
}

void seedCollection(Teammate t, int id) {
  t.store.upsert(id, folderDoc('f-users', 'Users'));
  t.store.upsert(
    id,
    requestDoc('r-list', 'List users', parent: 'f-users', data: {
      'headers': [
        {'key': 'Accept', 'value': 'application/json'},
      ],
    }),
  );
  t.store.upsert(id, requestDoc('r-get', 'Get user', parent: 'f-users', order: 1));
  t.store.upsert(id, requestDoc('r-health', 'Health'));
}

/// A creates the collection, connects and pushes it; B clones it.
Future<Pair> connectedPair(
  FakeGitHost host, {
  Map<String, Object?> collectionData = const {},
  void Function(Teammate a, int id)? seed,
  bool includeSecrets = false,
  bool cloneWithSecrets = false,
}) async {
  final repo = host.seedRepo(repoName);
  final a = Teammate(host);
  final b = Teammate(host);
  final aId = a.store.addCollection(name: 'Payments', data: collectionData);
  seedCollection(a, aId);
  seed?.call(a, aId);
  await a.connect(GitConnectParams(
    collectionId: aId,
    repo: repo,
    branch: 'main',
    basePath: basePath,
    includeSecrets: includeSecrets,
  ));
  await a.pushAll(aId, 'Initial');
  final clone = await b.clone(GitCloneParams(repo: repo, branch: 'main', basePath: basePath, includeSecrets: cloneWithSecrets));
  return Pair(a, b, aId, clone.collectionId, repo);
}

const _names = ['Alpha', 'alpha', 'Beta', 'Gamma!', '..'];
const _values = ['x', 'y', 'z'];

/// One random local change: edit, rename, move, delete or add.
void randomLocalEdit(Random random, Teammate t, int id, String tag) {
  final docs = t.docsOf(id);
  final ids = docs.keys.where((uid) => uid != 'col').toList()..sort();
  final folders = ['col', ...ids.where((uid) => docs[uid]!.kind == SyncKind.folder)];
  final pick = ids.isEmpty ? null : ids[random.nextInt(ids.length)];
  String name() => _names[random.nextInt(_names.length)];
  switch (random.nextInt(8)) {
    case 0 when pick != null:
      t.edit(id, pick, {'note': _values[random.nextInt(_values.length)]});
    case 1 when pick != null:
      t.edit(id, pick, {'name': name()});
    case 2 when pick != null:
      final blocked = subtreeOf(docs, pick);
      final targets = [for (final folder in folders) if (!blocked.contains(folder)) folder];
      t.edit(id, pick, {'parentUid': targets[random.nextInt(targets.length)]});
    case 3 when pick != null:
      t.store.remove(id, pick);
    case 4 || 5:
      t.store.upsert(id, requestDoc('r-$tag', name(), parent: folders[random.nextInt(folders.length)], order: random.nextInt(3)));
    case 6:
      t.store.upsert(id, folderDoc('f-$tag', name(), parent: folders[random.nextInt(folders.length)], order: random.nextInt(3)));
    case 7:
      t.edit(id, 'col', {'description': _values[random.nextInt(_values.length)]});
  }
}

/// What a random session went through, so a test can prove it exercised the interesting paths.
class SyncTally {
  var conflictedPulls = 0;
  var pullsThatChangedSomething = 0;
  var pushes = 0;
}

/// Pull (settling any conflicts at random), then push what is left.
Future<void> syncUp(Teammate t, int id, Random random, SyncTally tally) async {
  var pulled = await t.pullAll(id);
  if (pulled is PullConflicts) {
    tally.conflictedPulls++;
    final choices = {
      for (final conflict in pulled.conflicts) conflict.uid: random.nextBool() ? ConflictChoice.local : ConflictChoice.remote,
    };
    pulled = await t.pullAll(id, choices);
  }
  expect(pulled, isNot(isA<PullConflicts>()));
  if (pulled is PullApplied && pulled.added + pulled.updated + pulled.deleted > 0) tally.pullsThatChangedSomething++;
  try {
    await t.pushAll(id, 'sync');
    tally.pushes++;
  } on GitNothingToCommitException {
    return;
  }
}

Map<String, String> collectionFiles(FakeGitHost host, RepoRef repo, [String branch = 'main']) => {
      for (final file in host.filesAt(repo, branch).entries)
        if (file.key.startsWith('$basePath/')) file.key: file.value,
    };

void main() {
  late FakeGitHost host;

  setUp(() => host = FakeGitHost());

  group('connect and first push', () {
    test('writes the layout, tracks the commit and leaves nothing to push', () async {
      final repo = host.seedRepo(repoName);
      final a = Teammate(host);
      final id = a.store.addCollection(name: 'Payments');
      seedCollection(a, id);
      final seedHead = host.headOf(repo);

      final link = await a.connect(GitConnectParams(
        collectionId: id,
        repo: repo,
        branch: 'main',
        basePath: ' /apis//payments/ ',
      ));
      expect(link.basePath, basePath);
      expect(link.lastSyncedSha, seedHead);
      final before = await a.statusOf(id);
      expect(before.localChanges, hasLength(5));
      expect(before.localChanges.map((c) => c.type).toSet(), {DocChangeType.added});
      expect(before.localChanges.first.uid, 'col');

      final pushed = await a.pushAll(id, 'Initial import');

      expect(pushed.changedFiles, 5);
      expect(pushed.commitSha, host.headOf(repo));
      expect(pushed.commitUrl, 'https://github.com/acme/payments/commit/${pushed.commitSha}');
      expect(host.filesAt(repo).keys.toSet(), {
        'README.md',
        'apis/payments/collection.json',
        'apis/payments/users/_folder.json',
        'apis/payments/users/list-users.request.json',
        'apis/payments/users/get-user.request.json',
        'apis/payments/health.request.json',
      });
      expect((await host.listCommits(repo, branch: 'main')).first.message, 'Initial import');
      expect((await a.linkOf(id)).lastSyncedSha, pushed.commitSha);
      expect((await a.statusOf(id)).localChanges, isEmpty);
    });

    test('an empty repository is allowed: the first push creates the initial commit and the branch', () async {
      final repo = host.seedRepo('acme/empty', files: {});
      final a = Teammate(host);
      final id = a.store.addCollection(name: 'Payments');
      seedCollection(a, id);

      final link = await a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'main'));
      expect(link.lastSyncedSha, isNull);
      expect(await host.listBranches(repo), isEmpty);
      expect((await a.statusOf(id, checkRemote: true)).behind, isFalse);

      final pushed = await a.pushAll(id, 'Initial');

      expect(host.headOf(repo), pushed.commitSha);
      expect(host.filesAt(repo).keys, containsAll(['collection.json', 'users/_folder.json', 'health.request.json']));
      expect((await a.linkOf(id)).lastSyncedSha, pushed.commitSha);
      await expectLater(a.pushAll(id), throwsA(isA<GitNothingToCommitException>()));
    });

    test('refuses a folder that already holds a collection but accepts another folder', () async {
      final t = await connectedPair(host);
      final c = Teammate(host);
      final id = c.store.addCollection(uid: 'col-c', name: 'Other');

      await expectLater(
        c.connect(GitConnectParams(collectionId: id, repo: t.repo, branch: 'main', basePath: basePath)),
        throwsA(isA<GitPathOccupiedException>()),
      );
      expect(await c.links.findByCollection(id), isNull);

      final link = await c.connect(GitConnectParams(collectionId: id, repo: t.repo, branch: 'main', basePath: 'apis/other'));
      expect(link.basePath, 'apis/other');
    });

    test('fails for a missing branch, an unknown repository and a path with ..', () async {
      final repo = host.seedRepo(repoName);
      final a = Teammate(host);
      final id = a.store.addCollection();

      await expectLater(
        a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'nope')),
        throwsA(isA<GitBranchMissingException>()),
      );
      await expectLater(
        a.connect(GitConnectParams(collectionId: id, repo: RepoRef.parse('acme/missing')!, branch: 'main')),
        throwsA(isA<GitNotFoundException>()),
      );
      await expectLater(
        a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'main', basePath: '../x')),
        throwsA(isA<GitSyncException>()),
      );
      expect(await a.links.findByCollection(id), isNull);
    });

    test('the branch moving between connect and the first push only needs a pull', () async {
      final repo = host.seedRepo(repoName);
      final a = Teammate(host);
      final id = a.store.addCollection(name: 'Payments');
      seedCollection(a, id);
      await a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'main', basePath: basePath));
      host.commitFiles(repo, {'README.md': '# moved'});

      await expectLater(a.pushAll(id), throwsA(isA<GitNotFastForwardException>()));
      final applied = await a.pullAll(id) as PullApplied;
      await a.pushAll(id, 'First push');

      expect([applied.added, applied.updated, applied.deleted], [0, 0, 0]);
      expect(collectionFiles(host, repo), hasLength(5));
      expect((await a.statusOf(id)).localChanges, isEmpty);
    });

    test('a failing download stops the fetch and surfaces the error', () async {
      final t = await connectedPair(host);
      final broken = host.commitFiles(t.repo, {'$basePath/health.request.json': '{"uid":"r-health"}'});
      host.failBlobReads = true;

      await expectLater(t.b.pullAll(t.bId), throwsA(isA<GitHostException>()));

      host.failBlobReads = false;
      expect((await t.b.linkOf(t.bId)).lastSyncedSha, isNot(broken));
      expect(t.b.docsOf(t.bId), hasLength(5));
    });

    test('connecting again replaces the link and starts from an empty base', () async {
      final t = await connectedPair(host);
      final firstLink = await t.a.linkOf(t.aId);

      final link = await t.a.connect(GitConnectParams(collectionId: t.aId, repo: t.repo, branch: 'main', basePath: 'apis/copy'));

      expect(link.id, firstLink.id);
      expect(link.basePath, 'apis/copy');
      expect((await t.a.statusOf(t.aId)).localChanges, hasLength(5));
    });
  });

  group('clone', () {
    test('gives a teammate identical docs, linked, with nothing to push or pull', () async {
      final t = await connectedPair(host);

      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
      final link = await t.b.linkOf(t.bId);
      expect(link.lastSyncedSha, host.headOf(t.repo));
      expect(link.basePath, basePath);
      expect(link.branch, 'main');
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
      expect(await t.b.pullAll(t.bId), isA<PullUpToDate>());
      await expectLater(t.b.pushAll(t.bId), throwsA(isA<GitNothingToCommitException>()));
      final basePaths = (await t.b.links.readBase(link.id)).values.map((e) => e.path).toSet();
      expect(basePaths, collectionFiles(host, t.repo).keys.toSet());
    });

    test('fails where there is no collection or no such branch', () async {
      final t = await connectedPair(host);
      final c = Teammate(host);

      await expectLater(
        c.clone(GitCloneParams(repo: t.repo, branch: 'main', basePath: 'apis/nothing')),
        throwsA(isA<GitNothingToCloneException>()),
      );
      await expectLater(
        c.clone(GitCloneParams(repo: t.repo, branch: 'nope', basePath: basePath)),
        throwsA(isA<GitBranchMissingException>()),
      );
      expect(c.store.collections, isEmpty);
    });
  });

  group('two teammates', () {
    test('edits to different fields of one request merge without a conflict and both end identical', () async {
      final t = await connectedPair(host);
      final plain = [
        {'key': 'Accept', 'value': 'text/plain'},
      ];
      t.a.edit(t.aId, 'r-list', {'headers': plain});
      t.b.edit(t.bId, 'r-list', {'url': 'https://b.test/users'});

      await t.a.pushAll(t.aId, 'headers');
      final pulled = await t.b.pullAll(t.bId) as PullApplied;

      expect(pulled.updated, 1);
      expect(pulled.changedRequestIds, [t.b.store.requestId(t.bId, 'r-list')]);
      expect(t.b.doc(t.bId, 'r-list').data['headers'], plain);
      expect(t.b.doc(t.bId, 'r-list').data['url'], 'https://b.test/users');
      final status = await t.b.statusOf(t.bId);
      expect(status.localChanges.map((c) => c.uid), ['r-list']);
      expect(status.localChanges.single.changedFields, ['url']);

      await t.b.pushAll(t.bId, 'url');
      await t.a.pullAll(t.aId);

      expect(t.a.docsOf(t.aId), t.b.docsOf(t.bId));
      expect((await t.a.statusOf(t.aId)).localChanges, isEmpty);
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
      final all = await t.a.store.readSnapshot(t.aId, includeSecrets: true);
      expect(collectionFiles(host, t.repo), RepoLayout.toFiles(all, basePath: basePath));
    });

    test('the same field edited on both sides raises a conflict and touches nothing until it is resolved', () async {
      final t = await connectedPair(host);
      t.a.edit(t.aId, 'r-list', {'url': 'https://a.test/users'});
      t.b.edit(t.bId, 'r-list', {'url': 'https://b.test/users'});
      await t.a.pushAll(t.aId);
      final linkBefore = await t.b.linkOf(t.bId);

      final result = await t.b.pullAll(t.bId);

      final conflict = (result as PullConflicts).conflicts.single;
      expect(conflict.uid, 'r-list');
      expect(conflict.type, ConflictKind.bothModified);
      final field = conflict.fields.single;
      expect([field.field, field.base, field.local, field.remote], [
        'url',
        'https://api.test/things',
        'https://b.test/users',
        'https://a.test/users',
      ]);
      expect(t.b.doc(t.bId, 'r-list').data['url'], 'https://b.test/users');
      expect((await t.b.linkOf(t.bId)).lastSyncedSha, linkBefore.lastSyncedSha);
    });

    test('resolving a conflict with the local side keeps my value and pushes it', () async {
      final t = await connectedPair(host);
      t.a.edit(t.aId, 'r-list', {'url': 'https://a.test/users'});
      t.b.edit(t.bId, 'r-list', {'url': 'https://b.test/users'});
      await t.a.pushAll(t.aId);
      await t.b.pullAll(t.bId);

      final result = await t.b.pullAll(t.bId, {'r-list': ConflictChoice.local});

      expect(result, isA<PullApplied>());
      expect(t.b.doc(t.bId, 'r-list').data['url'], 'https://b.test/users');
      expect((await t.b.statusOf(t.bId)).localChanges.single.changedFields, ['url']);
      await t.b.pushAll(t.bId, 'Mine wins');
      await t.a.pullAll(t.aId);
      expect(t.a.doc(t.aId, 'r-list').data['url'], 'https://b.test/users');
      expect(t.a.docsOf(t.aId), t.b.docsOf(t.bId));
    });

    test('resolving a conflict with the remote side takes their value and leaves nothing to push', () async {
      final t = await connectedPair(host);
      t.a.edit(t.aId, 'r-list', {'url': 'https://a.test/users'});
      t.b.edit(t.bId, 'r-list', {'url': 'https://b.test/users'});
      await t.a.pushAll(t.aId);

      final result = await t.b.pullAll(t.bId, {'r-list': ConflictChoice.remote}) as PullApplied;

      expect(result.updated, 1);
      expect(t.b.doc(t.bId, 'r-list').data['url'], 'https://a.test/users');
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
    });

    test('a request deleted by A while B edited it is a conflict; B can accept the deletion', () async {
      final t = await connectedPair(host);
      t.a.store.remove(t.aId, 'r-get');
      final pushed = await t.a.pushAll(t.aId, 'Remove get');
      expect(pushed.changedFiles, 1);
      expect(collectionFiles(host, t.repo).keys, isNot(contains('$basePath/users/get-user.request.json')));
      t.b.edit(t.bId, 'r-get', {'name': 'Get one user'});

      final conflict = ((await t.b.pullAll(t.bId)) as PullConflicts).conflicts.single;
      expect(conflict.type, ConflictKind.modifiedLocallyDeletedRemotely);
      expect(conflict.uid, 'r-get');
      expect(conflict.name, 'Get one user');

      final applied = await t.b.pullAll(t.bId, {'r-get': ConflictChoice.remote}) as PullApplied;
      expect(applied.deleted, 1);
      expect(applied.deletedRequestIds, [t.b.store.requestId(t.bId, 'r-get')]);
      expect(t.b.store.doc(t.bId, 'r-get'), isNull);
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
    });

    test('a request deleted by A while B edited it: B can keep it and push it back', () async {
      final t = await connectedPair(host);
      t.a.store.remove(t.aId, 'r-get');
      await t.a.pushAll(t.aId);
      t.b.edit(t.bId, 'r-get', {'name': 'Get one user'});

      await t.b.pullAll(t.bId, {'r-get': ConflictChoice.local});

      final status = await t.b.statusOf(t.bId);
      expect(status.localChanges.single.type, DocChangeType.added);
      await t.b.pushAll(t.bId, 'Keep it');
      final applied = await t.a.pullAll(t.aId) as PullApplied;
      expect(applied.added, 1);
      expect(t.a.doc(t.aId, 'r-get').name, 'Get one user');
      expect(t.a.docsOf(t.aId), t.b.docsOf(t.bId));
    });

    test('a request edited by A while B deleted it is a conflict in the other direction', () async {
      final t = await connectedPair(host);
      t.b.store.remove(t.bId, 'r-get');
      t.a.edit(t.aId, 'r-get', {'url': 'https://a.test/get'});
      await t.a.pushAll(t.aId);

      final conflict = ((await t.b.pullAll(t.bId)) as PullConflicts).conflicts.single;
      expect(conflict.type, ConflictKind.deletedLocallyModifiedRemotely);

      final keepRemote = await t.b.pullAll(t.bId, {'r-get': ConflictChoice.remote}) as PullApplied;
      expect(keepRemote.added, 1);
      expect(t.b.doc(t.bId, 'r-get').data['url'], 'https://a.test/get');
    });

    test('deleting on B what A edited: B can insist on the deletion and pushes it', () async {
      final t = await connectedPair(host);
      t.b.store.remove(t.bId, 'r-get');
      t.a.edit(t.aId, 'r-get', {'url': 'https://a.test/get'});
      await t.a.pushAll(t.aId);

      await t.b.pullAll(t.bId, {'r-get': ConflictChoice.local});
      expect((await t.b.statusOf(t.bId)).localChanges.single.type, DocChangeType.deleted);
      await t.b.pushAll(t.bId, 'Remove get');
      final applied = await t.a.pullAll(t.aId) as PullApplied;

      expect(applied.deleted, 1);
      expect(t.a.store.doc(t.aId, 'r-get'), isNull);
      expect(collectionFiles(host, t.repo).keys, isNot(contains('$basePath/users/get-user.request.json')));
    });

    test('a rename and a move change repository paths and reach the other teammate', () async {
      final t = await connectedPair(host);
      t.a.edit(t.aId, 'f-users', {'name': 'Accounts'});
      t.a.store.upsert(t.aId, folderDoc('f-admin', 'Admin', order: 1));
      t.a.edit(t.aId, 'r-list', {'parentUid': 'f-admin'});

      final changes = (await t.a.statusOf(t.aId)).localChanges;
      expect(changes.map((c) => c.uid), ['f-users', 'f-admin', 'r-list']);
      expect(changes.map((c) => c.type), [DocChangeType.modified, DocChangeType.added, DocChangeType.modified]);
      expect(changes.first.changedFields, ['name']);
      expect(changes.last.changedFields, ['parentUid']);

      final pushed = await t.a.pushAll(t.aId, 'Reorganise');

      expect(pushed.changedFiles, 3);
      expect(collectionFiles(host, t.repo).keys.toSet(), {
        'apis/payments/collection.json',
        'apis/payments/accounts/_folder.json',
        'apis/payments/accounts/get-user.request.json',
        'apis/payments/admin/_folder.json',
        'apis/payments/admin/list-users.request.json',
        'apis/payments/health.request.json',
      });

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [1, 2, 0]);
      expect(applied.changedRequestIds, [t.b.store.requestId(t.bId, 'r-list')]);
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
    });

    test('a push is rejected when the remote branch moved, and nothing changes until the pull', () async {
      final t = await connectedPair(host);
      t.a.edit(t.aId, 'r-health', {'url': 'https://a.test/health'});
      t.b.edit(t.bId, 'r-get', {'url': 'https://b.test/get'});
      final aPush = await t.a.pushAll(t.aId);
      final linkBefore = await t.b.linkOf(t.bId);

      await expectLater(t.b.pushAll(t.bId), throwsA(isA<GitNotFastForwardException>()));

      expect(host.headOf(t.repo), aPush.commitSha);
      expect((await t.b.linkOf(t.bId)).lastSyncedSha, linkBefore.lastSyncedSha);
      expect((await t.b.statusOf(t.bId)).localChanges.map((c) => c.uid), ['r-get']);
      final status = await t.b.statusOf(t.bId, checkRemote: true);
      expect(status.behind, isTrue);
      expect(status.remoteHeadSha, aPush.commitSha);

      final applied = await t.b.pullAll(t.bId) as PullApplied;
      expect(applied.updated, 1);
      await t.b.pushAll(t.bId, 'Get');
      expect(host.headOf(t.repo), isNot(aPush.commitSha));
      await t.a.pullAll(t.aId);
      expect(t.a.docsOf(t.aId), t.b.docsOf(t.bId));
    });

    test('requests added and deleted by one teammate arrive at the other', () async {
      final t = await connectedPair(host);
      t.a.store.upsert(t.aId, requestDoc('r-new', 'Create user', parent: 'f-users', order: 2));
      t.a.store.remove(t.aId, 'r-health');
      await t.a.pushAll(t.aId);

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [1, 0, 1]);
      expect(applied.deletedRequestIds, [t.b.store.requestId(t.bId, 'r-health')]);
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
    });

    test('two requests with the same name in one folder both survive under distinct file names', () async {
      final t = await connectedPair(host);
      t.a.store.upsert(t.aId, requestDoc('r-x1', 'Create user', parent: 'f-users', order: 2));
      t.b.store.upsert(t.bId, requestDoc('r-x2', 'Create user', parent: 'f-users', order: 2));
      await t.a.pushAll(t.aId);

      await t.b.pullAll(t.bId);
      await t.b.pushAll(t.bId);
      await t.a.pullAll(t.aId);

      expect(collectionFiles(host, t.repo).keys, containsAll([
        'apis/payments/users/create-user.request.json',
        'apis/payments/users/create-user-r-x2.request.json',
      ]));
      expect(t.a.docsOf(t.aId).keys, containsAll(['r-x1', 'r-x2']));
      expect(t.a.docsOf(t.aId), t.b.docsOf(t.bId));
    });

    test('an unrelated commit moves the branch: the pull downloads nothing and applies nothing', () async {
      final t = await connectedPair(host);
      final newHead = host.commitFiles(t.repo, {'README.md': '# changed'});
      final before = await t.b.statusOf(t.bId, checkRemote: true);
      expect(before.behind, isTrue);
      expect(before.remoteHeadSha, newHead);
      host.blobReads = 0;

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [0, 0, 0]);
      expect(host.blobReads, 0);
      expect((await t.b.linkOf(t.bId)).lastSyncedSha, newHead);
      expect((await t.b.statusOf(t.bId, checkRemote: true)).behind, isFalse);
    });

    test('a read-only user cannot push and sees it in the status', () async {
      final t = await connectedPair(host);
      t.b.edit(t.bId, 'r-get', {'url': 'https://b.test/get'});
      host.canPush = false;

      await expectLater(t.b.pushAll(t.bId), throwsA(isA<GitReadOnlyException>()));
      final status = await t.b.statusOf(t.bId, checkRemote: true);
      expect(status.canPush, isFalse);
      expect(status.repoInfo!.canPush, isFalse);
      expect(status.hasLocalChanges, isTrue);
      expect((await t.b.statusOf(t.bId)).canPush, isTrue);
    });

    test('pushing with nothing changed says so', () async {
      final t = await connectedPair(host);
      await expectLater(t.b.pushAll(t.bId), throwsA(isA<GitNothingToCommitException>()));
    });

    test('discard resets the local collection to the last synced state', () async {
      final t = await connectedPair(host);
      t.b.edit(t.bId, 'r-list', {'url': 'https://b.test/users'});
      t.b.store.remove(t.bId, 'r-get');
      t.b.store.upsert(t.bId, requestDoc('r-new', 'Scratch'));

      final outcome = await t.b.discard(t.bId);

      expect([outcome.added, outcome.updated, outcome.deleted], [1, 1, 1]);
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
    });

    test('discard refuses to wipe a collection that was never pushed', () async {
      final repo = host.seedRepo(repoName);
      final a = Teammate(host);
      final id = a.store.addCollection();
      seedCollection(a, id);
      await a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'main'));

      await expectLater(a.discard(id), throwsA(isA<GitSyncException>()));
      expect(a.docsOf(id), hasLength(5));
    });
  });

  group('branches', () {
    test('a new branch starts at the synced commit, keeps local edits and receives the next push', () async {
      final t = await connectedPair(host);
      final synced = (await t.b.linkOf(t.bId)).lastSyncedSha;
      t.b.edit(t.bId, 'r-health', {'url': 'https://feature.test'});

      final link = await t.b.createBranch(GitBranchParams(collectionId: t.bId, branch: 'feature/x'));

      expect(link.branch, 'feature/x');
      expect(link.lastSyncedSha, synced);
      expect(host.headOf(t.repo, 'feature/x'), synced);
      expect(await t.b.listBranches(t.bId), ['feature/x', 'main']);
      expect((await t.b.statusOf(t.bId)).localChanges.map((c) => c.uid), ['r-health']);

      final pushed = await t.b.pushAll(t.bId, 'Feature work');

      expect(host.headOf(t.repo, 'feature/x'), pushed.commitSha);
      expect(host.headOf(t.repo), synced);
      final history = await t.b.history(GitHistoryParams(collectionId: t.bId));
      expect(history.first.title, 'Feature work');
    });

    test('rejects invalid and already existing branch names', () async {
      final t = await connectedPair(host);
      for (final name in ['', 'bad name', 'a..b', 'x.lock', '/lead', 'main']) {
        await expectLater(
          t.b.createBranch(GitBranchParams(collectionId: t.bId, branch: name)),
          throwsA(isA<GitSyncException>()),
          reason: 'branch "$name"',
        );
      }
      expect((await t.b.linkOf(t.bId)).branch, 'main');
    });

    test('switching is blocked by unpushed changes, then replaces the collection with the branch state', () async {
      final t = await connectedPair(host);
      await t.b.createBranch(GitBranchParams(collectionId: t.bId, branch: 'feature'));
      t.b.edit(t.bId, 'r-health', {'url': 'https://f1.test'});
      await t.b.pushAll(t.bId, 'f1');
      t.b.edit(t.bId, 'r-health', {'url': 'https://f2.test'});

      await expectLater(
        t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'main')),
        throwsA(isA<GitUncommittedChangesException>()),
      );
      expect((await t.b.linkOf(t.bId)).branch, 'feature');
      expect(t.b.doc(t.bId, 'r-health').data['url'], 'https://f2.test');

      await t.b.pushAll(t.bId, 'f2');
      final outcome = await t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'main'));

      expect(outcome.updated, 1);
      expect(outcome.changedRequestIds, [t.b.store.requestId(t.bId, 'r-health')]);
      final link = await t.b.linkOf(t.bId);
      expect(link.branch, 'main');
      expect(link.lastSyncedSha, host.headOf(t.repo));
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);

      await t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'feature'));
      expect(t.b.doc(t.bId, 'r-health').data['url'], 'https://f2.test');
    });

    test('switching to an unknown branch fails and switching to the current branch does nothing', () async {
      final t = await connectedPair(host);

      await expectLater(
        t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'nope')),
        throwsA(isA<GitBranchMissingException>()),
      );
      final outcome = await t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'main'));
      expect([outcome.added, outcome.updated, outcome.deleted], [0, 0, 0]);
      expect((await t.b.linkOf(t.bId)).branch, 'main');
    });
  });

  group('credentials', () {
    Map<String, Object?> collectionData() => {
          'variables': [
            {'key': 'api_token', 'value': 'VAR-SECRET', 'enabled': true},
            {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
          ],
          'auth': {'type': 'apiKey', 'apiKeyName': 'X-Key', 'apiKeyValue': 'KEY-SECRET'},
        };

    void seedSecure(Teammate a, int id) => a.store.upsert(
          id,
          requestDoc('r-secure', 'Secured', data: {
            'auth': {'type': 'bearer', 'bearerToken': 'SUPER-SECRET-TOKEN', 'basicUsername': 'me'},
          }),
        );

    const secrets = ['SUPER-SECRET-TOKEN', 'VAR-SECRET', 'KEY-SECRET'];

    test('are never written to the repository when the link excludes them', () async {
      final t = await connectedPair(host, collectionData: collectionData(), seed: seedSecure);

      final texts = host.filesAt(t.repo).values;
      for (final secret in secrets) {
        expect(texts.any((text) => text.contains(secret)), isFalse, reason: secret);
      }
      final files = collectionFiles(host, t.repo);
      final collection = jsonDecode(files['$basePath/collection.json']!) as Map<String, dynamic>;
      expect((collection['variables'] as List).map((v) => (v as Map)['value']), ['', 'https://api.test']);
      expect(files['$basePath/secured.request.json'], contains('basicUsername'));
      expect((t.a.doc(t.aId, 'r-secure').data['auth']! as Map)['bearerToken'], 'SUPER-SECRET-TOKEN');
      expect((await t.a.statusOf(t.aId)).localChanges, isEmpty);
    });

    test('a pull never erases local credentials and leaves no fake changes behind', () async {
      final t = await connectedPair(host, collectionData: collectionData(), seed: seedSecure);
      t.b.store.upsert(
        t.bId,
        edited(t.b.doc(t.bId, 'r-secure'), {
          'auth': {'type': 'bearer', 'bearerToken': 'B-TOKEN', 'basicUsername': 'me'},
        }),
      );
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
      t.a.edit(t.aId, 'r-secure', {'url': 'https://a.test/secure'});
      await t.a.pushAll(t.aId);

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect(applied.updated, 1);
      expect(t.b.doc(t.bId, 'r-secure').data['url'], 'https://a.test/secure');
      expect((t.b.doc(t.bId, 'r-secure').data['auth']! as Map)['bearerToken'], 'B-TOKEN');
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
      expect((t.a.doc(t.aId, 'r-secure').data['auth']! as Map)['bearerToken'], 'SUPER-SECRET-TOKEN');
    });

    test('are shared only with teammates whose link includes them', () async {
      final t = await connectedPair(
        host,
        collectionData: collectionData(),
        seed: seedSecure,
        includeSecrets: true,
        cloneWithSecrets: true,
      );
      final texts = host.filesAt(t.repo).values;
      for (final secret in secrets) {
        expect(texts.any((text) => text.contains(secret)), isTrue, reason: secret);
      }
      expect((t.b.doc(t.bId, 'r-secure').data['auth']! as Map)['bearerToken'], 'SUPER-SECRET-TOKEN');
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);

      final d = Teammate(host);
      final dLink = await d.clone(GitCloneParams(repo: t.repo, branch: 'main', basePath: basePath));
      expect((d.doc(dLink.collectionId, 'r-secure').data['auth']! as Map).containsKey('bearerToken'), isFalse);
      expect((await d.statusOf(dLink.collectionId)).localChanges, isEmpty);
    });

    test('switching sharing off creates no fake changes; switching it on offers them as edits', () async {
      final t = await connectedPair(
        host,
        collectionData: collectionData(),
        seed: seedSecure,
        includeSecrets: true,
      );

      final off = await t.a.updateSettings(GitLinkSettingsParams(collectionId: t.aId, includeSecrets: false));

      expect(off.includeSecrets, isFalse);
      expect((await t.a.statusOf(t.aId)).localChanges, isEmpty);
      await expectLater(t.a.pushAll(t.aId), throwsA(isA<GitNothingToCommitException>()));

      final same = await t.a.updateSettings(GitLinkSettingsParams(collectionId: t.aId, includeSecrets: false));
      expect(same.includeSecrets, isFalse);

      await t.a.updateSettings(GitLinkSettingsParams(collectionId: t.aId, includeSecrets: true));
      final changes = (await t.a.statusOf(t.aId)).localChanges;
      expect(changes.map((c) => c.uid), ['col', 'r-secure']);
      expect(changes.first.changedFields, ['auth', 'variables']);
      expect(changes.last.changedFields, ['auth']);

      await t.a.pushAll(t.aId, 'Share credentials');
      expect(host.filesAt(t.repo).values.any((text) => text.contains('SUPER-SECRET-TOKEN')), isTrue);
    });
  });

  group('determinism', () {
    test('status is empty right after a push, a second push has nothing to commit, files are byte-stable', () async {
      final t = await connectedPair(host);

      expect((await t.a.statusOf(t.aId)).localChanges, isEmpty);
      await expectLater(t.a.pushAll(t.aId), throwsA(isA<GitNothingToCommitException>()));

      final first = RepoLayout.toFiles(await t.a.store.readSnapshot(t.aId, includeSecrets: true), basePath: basePath);
      final second = RepoLayout.toFiles(await t.a.store.readSnapshot(t.aId, includeSecrets: true), basePath: basePath);
      expect(second.keys.toList(), first.keys.toList());
      expect(second.values.toList(), first.values.toList());
      expect(collectionFiles(host, t.repo), first);

      final fromB = RepoLayout.toFiles(await t.b.store.readSnapshot(t.bId, includeSecrets: true), basePath: basePath);
      expect(fromB.keys.toList(), first.keys.toList());
      expect(fromB.values.toList(), first.values.toList());
    });
  });

  group('robustness', () {
    test('a remote file that is no longer valid JSON does not delete the request locally', () async {
      final t = await connectedPair(host);
      host.commitFiles(t.repo, {'$basePath/users/list-users.request.json': '<<<<<<< HEAD\n'});

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [0, 0, 0]);
      expect(t.b.store.doc(t.bId, 'r-list'), isNotNull);
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);

      t.b.edit(t.bId, 'r-list', {'url': 'https://repaired.test'});
      await t.b.pushAll(t.bId, 'Repair');
      await t.a.pullAll(t.aId);
      expect(t.a.doc(t.aId, 'r-list').data['url'], 'https://repaired.test');
    });

    test('a remote without the collection is refused instead of wiping the local one', () async {
      final t = await connectedPair(host);
      host.commitFiles(t.repo, {for (final path in collectionFiles(host, t.repo).keys) path: null});
      final linkBefore = await t.b.linkOf(t.bId);

      await expectLater(t.b.pullAll(t.bId), throwsA(isA<GitNothingToCloneException>()));

      expect(t.b.docsOf(t.bId), hasLength(5));
      expect((await t.b.linkOf(t.bId)).lastSyncedSha, linkBefore.lastSyncedSha);
    });

    test('a hand-formatted remote file is read like any other', () async {
      final t = await connectedPair(host);
      final health = t.a.doc(t.aId, 'r-health');
      host.commitFiles(t.repo, {'$basePath/health.request.json': jsonEncode(health.toJson())});
      host.blobReads = 0;

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [0, 0, 0]);
      expect(host.blobReads, 1);
      expect((await t.b.statusOf(t.bId)).localChanges, isEmpty);
    });

    test('a collection of the same repository at another folder is not touched by a pull', () async {
      final t = await connectedPair(host);
      final other = Teammate(host);
      final otherId = other.store.addCollection(uid: 'col-o', name: 'Orders');
      other.store.upsert(otherId, requestDoc('o-1', 'List orders', parent: 'col-o'));
      await other.connect(GitConnectParams(collectionId: otherId, repo: t.repo, branch: 'main', basePath: 'apis/payments-v2'));
      await t.b.pullAll(t.bId);
      await other.pushAll(otherId, 'Orders');

      final applied = await t.b.pullAll(t.bId) as PullApplied;

      expect([applied.added, applied.updated, applied.deleted], [0, 0, 0]);
      expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId));
    });
  });

  group('random sessions', () {
    test('two teammates editing at random always converge on identical, clean collections', () async {
      final tally = SyncTally();
      for (var seed = 0; seed < 40; seed++) {
        final random = Random(seed);
        final host = FakeGitHost();
        final t = await connectedPair(host);
        final people = [(t.a, t.aId), (t.b, t.bId)];
        var counter = 0;

        for (var round = 0; round < 8; round++) {
          for (final (person, id) in people) {
            if (random.nextInt(3) == 0) continue;
            for (var edit = 0; edit < 1 + random.nextInt(3); edit++) {
              randomLocalEdit(random, person, id, 'e${counter++}');
            }
          }
          for (final (person, id) in random.nextBool() ? people : people.reversed) {
            if (random.nextBool()) await syncUp(person, id, random, tally);
          }
        }
        for (var pass = 0; pass < 3; pass++) {
          for (final (person, id) in people) {
            await syncUp(person, id, random, tally);
          }
        }

        final why = 'seed $seed';
        expect(t.b.docsOf(t.bId), t.a.docsOf(t.aId), reason: why);
        expect((await t.a.statusOf(t.aId)).localChanges, isEmpty, reason: why);
        expect((await t.b.statusOf(t.bId)).localChanges, isEmpty, reason: why);
        final settled = await t.a.store.readSnapshot(t.aId, includeSecrets: true);
        expect(collectionFiles(host, t.repo), RepoLayout.toFiles(settled, basePath: basePath), reason: why);
      }
      expect(tally.conflictedPulls, greaterThan(20));
      expect(tally.pullsThatChangedSomething, greaterThan(100));
      expect(tally.pushes, greaterThan(200));
    });
  });

  group('other use cases', () {
    test('discover lists the collections of a branch, root first, and skips files that are not collections', () async {
      final repo = host.seedRepo('acme/multi', files: {
        'README.md': '#',
        'collection.json': collectionDoc(uid: 'root', name: 'Root API').canonicalText,
        'apis/payments/collection.json': collectionDoc(uid: 'p', name: 'Payments').canonicalText,
        'apis/orders/collection.json': collectionDoc(uid: 'o', name: 'Orders').canonicalText,
        'tools/collection.json': '{ definitely not json',
        'other/collection.json': folderDoc('f', 'Not a collection').canonicalText,
        'apis/payments/users/notcollection.json': '{}',
      });
      final t = Teammate(host);

      final found = await t.discover(GitDiscoverParams(repo: repo, branch: 'main'));

      expect(found.map((c) => (c.basePath, c.name)), [('', 'Root API'), ('apis/orders', 'Orders'), ('apis/payments', 'Payments')]);
    });

    test('discover returns nothing for an empty repository or one without collections and fails for a missing branch', () async {
      final empty = host.seedRepo('acme/empty', files: {});
      final plain = host.seedRepo('acme/plain');
      final t = Teammate(host);

      expect(await t.discover(GitDiscoverParams(repo: empty, branch: 'main')), isEmpty);
      expect(await t.discover(GitDiscoverParams(repo: plain, branch: 'main')), isEmpty);
      await expectLater(t.discover(GitDiscoverParams(repo: plain, branch: 'nope')), throwsA(isA<GitBranchMissingException>()));
    });

    test('history shows only commits that touched the collection folder; contributors come from the host', () async {
      final t = await connectedPair(host);
      t.b.edit(t.bId, 'r-health', {'url': 'https://h.test'});
      await t.b.pushAll(t.bId, 'Tweak health');
      host.commitFiles(t.repo, {'docs/notes.md': 'unrelated'}, message: 'Docs only');

      final commits = await t.a.history(GitHistoryParams(collectionId: t.aId));

      expect(commits.map((c) => c.title), ['Tweak health', 'Initial']);
      expect((await t.a.history(GitHistoryParams(collectionId: t.aId, limit: 1))).single.title, 'Tweak health');
      expect((await t.a.contributors(t.aId)).map((c) => c.login).toSet(), {'alice', 'bob'});
    });

    test('saving a token stores it and returns the login; a rejected token is removed again', () async {
      final t = Teammate(host);
      host.login = 'octo';

      expect(await t.saveToken(const GitTokenParams(provider: GitProvider.github, token: '  ghp_good ')), 'octo');
      expect(t.credentials.tokens[GitProvider.github], 'ghp_good');

      t.credentials.tokens.clear();
      host.tokenValid = false;
      await expectLater(
        t.saveToken(const GitTokenParams(provider: GitProvider.github, token: 'ghp_bad')),
        throwsA(isA<GitAuthException>()),
      );
      expect(t.credentials.tokens, isEmpty);
    });

    test('a rejected token restores the one that was saved before; an empty token is refused up front', () async {
      final t = Teammate(host);
      t.credentials.tokens[GitProvider.github] = 'ghp_old';
      host.tokenValid = false;

      await expectLater(
        t.saveToken(const GitTokenParams(provider: GitProvider.github, token: 'ghp_bad')),
        throwsA(isA<GitAuthException>()),
      );
      expect(t.credentials.tokens[GitProvider.github], 'ghp_old');

      await expectLater(
        t.saveToken(const GitTokenParams(provider: GitProvider.github, token: '   ')),
        throwsA(isA<GitAuthException>()),
      );
      expect(t.credentials.tokens[GitProvider.github], 'ghp_old');
    });

    test('disconnecting removes the link and its base but keeps the local collection', () async {
      final t = await connectedPair(host);

      await t.b.disconnect(t.bId);

      expect(await t.b.links.findByCollection(t.bId), isNull);
      expect(t.b.links.bases, isEmpty);
      expect(t.b.docsOf(t.bId), hasLength(5));
      for (final call in <Future<Object?> Function()>[
        () => t.b.statusOf(t.bId),
        () => t.b.pushAll(t.bId),
        () => t.b.pullAll(t.bId),
        () => t.b.discard(t.bId),
        () => t.b.listBranches(t.bId),
        () => t.b.contributors(t.bId),
        () => t.b.history(GitHistoryParams(collectionId: t.bId)),
        () => t.b.createBranch(GitBranchParams(collectionId: t.bId, branch: 'x')),
        () => t.b.switchBranch(GitBranchParams(collectionId: t.bId, branch: 'x')),
        () => t.b.updateSettings(GitLinkSettingsParams(collectionId: t.bId, includeSecrets: true)),
      ]) {
        await expectLater(call(), throwsA(isA<GitNotLinkedException>()));
      }
    });
  });
}
