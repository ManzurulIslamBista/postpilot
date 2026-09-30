import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_exceptions.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_create_branch_usecase.dart';

import 'fakes/fake_git_host.dart';
import 'fakes/sync_fixtures.dart';
import 'fakes/teammate.dart';

const _repoName = 'acme/payments';
const _basePath = 'apis/payments';

/// What the user can do to the local collection while a pull or a branch switch waits on the network.
class _Change {
  final String name;
  final void Function(Teammate t, int id) apply;
  final void Function(Teammate t, int id) expectSurvived;

  const _Change(this.name, this.apply, this.expectSurvived);
}

final _changes = [
  _Change(
    'a request created',
    (t, id) => t.store.upsert(id, requestDoc('r-new', 'Created meanwhile')),
    (t, id) => expect(t.store.doc(id, 'r-new')?.name, 'Created meanwhile'),
  ),
  _Change(
    'a request edited',
    (t, id) => t.edit(id, 'r-list', {'name': 'List everyone'}),
    (t, id) => expect(t.doc(id, 'r-list').name, 'List everyone'),
  ),
  _Change(
    'a folder deleted',
    (t, id) => t.store.remove(id, 'f-users'),
    (t, id) {
      expect(t.store.doc(id, 'f-users'), isNull);
      expect(t.store.doc(id, 'r-list'), isNull);
    },
  ),
  _Change(
    'the collection described',
    (t, id) => t.edit(id, 'col', {'description': 'Payments API'}),
    (t, id) => expect(t.doc(id, 'col').data['description'], 'Payments API'),
  ),
];

/// Alice and Bob share one collection through one repository, in sync on main.
class _Session {
  final FakeGitHost host;
  final RepoRef repo;
  final Teammate alice;
  final Teammate bob;
  final int aliceId;
  final int bobId;

  const _Session(this.host, this.repo, this.alice, this.bob, this.aliceId, this.bobId);
}

Future<_Session> _connected() async {
  final host = FakeGitHost();
  final repo = host.seedRepo(_repoName);
  final alice = Teammate(host);
  final bob = Teammate(host);
  final aliceId = alice.store.addCollection(name: 'Payments');
  alice.store.upsert(aliceId, folderDoc('f-users', 'Users'));
  alice.store.upsert(aliceId, requestDoc('r-list', 'List users', parent: 'f-users'));
  alice.store.upsert(aliceId, requestDoc('r-health', 'Health'));
  await alice.connect(GitConnectParams(collectionId: aliceId, repo: repo, branch: 'main', basePath: _basePath));
  await alice.pushAll(aliceId, 'Initial');
  final clone = await bob.clone(GitCloneParams(repo: repo, branch: 'main', basePath: _basePath));
  return _Session(host, repo, alice, bob, aliceId, clone.collectionId);
}

/// Runs [edit] once, the first time the host is asked for something: while the operation waits on the network.
void _duringFetch(FakeGitHost host, void Function() edit) {
  host.whileFetching = () {
    host.whileFetching = null;
    edit();
  };
}

Matcher _changedWhile(String operation) => throwsA(
      isA<GitSyncException>().having(
        (e) => e.message,
        'message',
        'Your collection changed while $operation. Nothing was applied — try again.',
      ),
    );

/// Bob moves main on by editing a request Alice has not touched.
Future<void> _bobPushesToMain(_Session s) async {
  s.bob.edit(s.bobId, 'r-health', {'note': 'from bob'});
  await s.bob.pushAll(s.bobId, 'Bob edit');
}

/// Bob branches off main, and puts one more change on the new branch.
Future<void> _bobPushesToFeature(_Session s) async {
  await s.bob.createBranch(GitBranchParams(collectionId: s.bobId, branch: 'feature'));
  s.bob.edit(s.bobId, 'r-health', {'note': 'feature work'});
  await s.bob.pushAll(s.bobId, 'On feature');
}

void main() {
  group('a pull while the collection is edited', () {
    for (final change in _changes) {
      test('throws and applies nothing when ${change.name} meanwhile', () async {
        final s = await _connected();
        await _bobPushesToMain(s);
        final linkBefore = await s.alice.linkOf(s.aliceId);
        final baseBefore = await s.alice.links.readBase(linkBefore.id);
        _duringFetch(s.host, () => change.apply(s.alice, s.aliceId));

        await expectLater(s.alice.pullAll(s.aliceId), _changedWhile('pulling'));

        change.expectSurvived(s.alice, s.aliceId);
        expect(s.alice.doc(s.aliceId, 'r-health').data['note'], isNull, reason: "Bob's edit was not applied");
        final linkAfter = await s.alice.linkOf(s.aliceId);
        expect(linkAfter.lastSyncedSha, linkBefore.lastSyncedSha);
        expect((await s.alice.links.readBase(linkAfter.id)).keys, baseBefore.keys);
      });

      test('succeeds on the next try, keeping the change made meanwhile (${change.name})', () async {
        final s = await _connected();
        await _bobPushesToMain(s);
        _duringFetch(s.host, () => change.apply(s.alice, s.aliceId));
        await expectLater(s.alice.pullAll(s.aliceId), _changedWhile('pulling'));

        final second = await s.alice.pullAll(s.aliceId);

        expect(second, isA<PullApplied>());
        change.expectSurvived(s.alice, s.aliceId);
        expect(s.alice.doc(s.aliceId, 'r-health').data['note'], 'from bob');
        expect((await s.alice.linkOf(s.aliceId)).lastSyncedSha, s.host.headOf(s.repo));
      });
    }

    test('a request created meanwhile reaches the team once the pull is retried and pushed', () async {
      final s = await _connected();
      await _bobPushesToMain(s);
      _duringFetch(s.host, () => s.alice.store.upsert(s.aliceId, requestDoc('r-new', 'Created meanwhile')));
      await expectLater(s.alice.pullAll(s.aliceId), _changedWhile('pulling'));

      await s.alice.pullAll(s.aliceId);
      await s.alice.pushAll(s.aliceId, 'Add the new request');
      await s.bob.pullAll(s.bobId);

      expect(s.bob.store.doc(s.bobId, 'r-new')?.name, 'Created meanwhile');
    });

    test('an edit made before the pull started is merged as usual, not mistaken for one made during it', () async {
      final s = await _connected();
      await _bobPushesToMain(s);
      s.alice.edit(s.aliceId, 'r-list', {'name': 'List everyone'});
      var fetches = 0;
      s.host.whileFetching = () => fetches++;

      final result = await s.alice.pullAll(s.aliceId);

      expect(fetches, greaterThan(0));
      expect(result, isA<PullApplied>());
      expect(s.alice.doc(s.aliceId, 'r-list').name, 'List everyone');
      expect(s.alice.doc(s.aliceId, 'r-health').data['note'], 'from bob');
    });

    test('still reports conflicts as before, since applying nothing needs no guard', () async {
      final s = await _connected();
      s.alice.edit(s.aliceId, 'r-health', {'note': 'from alice'});
      await _bobPushesToMain(s);

      final first = await s.alice.pullAll(s.aliceId);

      expect(first, isA<PullConflicts>());
      expect(s.alice.doc(s.aliceId, 'r-health').data['note'], 'from alice');
    });
  });

  group('a branch switch while the collection is edited', () {
    for (final change in _changes) {
      test('throws and applies nothing when ${change.name} meanwhile', () async {
        final s = await _connected();
        await _bobPushesToFeature(s);
        final linkBefore = await s.alice.linkOf(s.aliceId);
        _duringFetch(s.host, () => change.apply(s.alice, s.aliceId));

        await expectLater(
          s.alice.switchBranch(GitBranchParams(collectionId: s.aliceId, branch: 'feature')),
          _changedWhile('switching branches'),
        );

        change.expectSurvived(s.alice, s.aliceId);
        expect(s.alice.doc(s.aliceId, 'r-health').data['note'], isNull, reason: "the feature branch was not applied");
        final linkAfter = await s.alice.linkOf(s.aliceId);
        expect(linkAfter.branch, 'main');
        expect(linkAfter.lastSyncedSha, linkBefore.lastSyncedSha);
      });
    }

    test('a second attempt is refused for the new local change until it is pushed, then the switch succeeds', () async {
      final s = await _connected();
      await _bobPushesToFeature(s);
      _duringFetch(s.host, () => s.alice.store.upsert(s.aliceId, requestDoc('r-new', 'Created meanwhile')));
      await expectLater(
        s.alice.switchBranch(GitBranchParams(collectionId: s.aliceId, branch: 'feature')),
        _changedWhile('switching branches'),
      );

      await expectLater(
        s.alice.switchBranch(GitBranchParams(collectionId: s.aliceId, branch: 'feature')),
        throwsA(isA<GitUncommittedChangesException>()),
      );
      await s.alice.pushAll(s.aliceId, 'Save the new request on main');
      await s.alice.switchBranch(GitBranchParams(collectionId: s.aliceId, branch: 'feature'));

      expect((await s.alice.linkOf(s.aliceId)).branch, 'feature');
      expect(s.alice.doc(s.aliceId, 'r-health').data['note'], 'feature work');
      expect(s.host.filesAt(s.repo).values.any((text) => text.contains('r-new')), isTrue, reason: 'safe on main');
    });

    test('with nothing edited meanwhile the switch replaces the collection with the branch', () async {
      final s = await _connected();
      await _bobPushesToFeature(s);
      var fetches = 0;
      s.host.whileFetching = () => fetches++;

      await s.alice.switchBranch(GitBranchParams(collectionId: s.aliceId, branch: 'feature'));

      expect(fetches, greaterThan(0));
      expect((await s.alice.linkOf(s.aliceId)).branch, 'feature');
      expect(s.alice.doc(s.aliceId, 'r-health').data['note'], 'feature work');
    });
  });
}
