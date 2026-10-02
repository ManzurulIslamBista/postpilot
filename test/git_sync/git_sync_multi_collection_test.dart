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

/// Several collections on one device, each linked on its own, sometimes into the
/// same repository: they must neither disturb nor block one another.
void main() {
  late FakeGitHost host;
  late RepoRef repo;

  setUp(() {
    host = FakeGitHost();
    repo = host.seedRepo('acme/apis');
  });

  /// A collection named [name] with one request, connected at [path] and pushed.
  Future<int> linkedCollection(Teammate t, String name, String path, {String branch = 'main', RepoRef? into}) async {
    final id = t.store.addCollection(name: name, uid: 'col-$name');
    t.store.upsert(id, requestDoc('req-$name', '$name request', parent: 'col-$name'));
    await t.connect(GitConnectParams(collectionId: id, repo: into ?? repo, branch: branch, basePath: path));
    await t.pushAll(id, 'Add $name');
    return id;
  }

  group('collections sharing a repository and branch', () {
    test("pushing one does not make a sibling behind, and the sibling can still push on top", () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      final blog = await linkedCollection(alice, 'Blog', 'apis/blog');
      // Blog's push moved the branch after Shop's link recorded it.
      expect((await alice.linkOf(shop)).lastSyncedSha, isNot(host.headOf(repo)));

      final status = await alice.statusOf(shop, checkRemote: true);
      expect(status.behind, isFalse, reason: "the branch moved, but not in Shop's folder");

      alice.edit(shop, 'req-Shop', {'note': 'edited'});
      final pushed = await alice.pushAll(shop, 'Edit Shop');

      expect(pushed.changedFiles, 1);
      expect(host.filesAt(repo).keys, containsAll(['apis/shop/collection.json', 'apis/blog/collection.json']));
      expect((await alice.statusOf(blog, checkRemote: true)).behind, isFalse);
    });

    test('a pull of a sibling-only change applies nothing, downloads nothing and moves the link forward', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      await linkedCollection(alice, 'Blog', 'apis/blog');
      host.blobReads = 0;

      final result = await alice.pullAll(shop) as PullApplied;

      expect([result.added, result.updated, result.deleted], [0, 0, 0]);
      expect(host.blobReads, 0);
      expect((await alice.linkOf(shop)).lastSyncedSha, host.headOf(repo));
      expect((await alice.statusOf(shop, checkRemote: true)).behind, isFalse);
    });

    test("a real change in the collection's own folder is still behind, and still has to be pulled", () async {
      final alice = Teammate(host);
      final bob = Teammate(host);
      await linkedCollection(alice, 'Shop', 'apis/shop');
      final blog = await linkedCollection(alice, 'Blog', 'apis/blog');
      final bobsBlog = (await bob.clone(GitCloneParams(repo: repo, branch: 'main', basePath: 'apis/blog'))).collectionId;
      bob.edit(bobsBlog, 'req-Blog', {'note': 'from bob'});
      await bob.pushAll(bobsBlog, 'Bob edits Blog');

      expect((await alice.statusOf(blog, checkRemote: true)).behind, isTrue);
      alice.edit(blog, 'req-Blog', {'note': 'from alice'});
      await expectLater(alice.pushAll(blog), throwsA(isA<GitNotFastForwardException>()));
    });

    test("an external commit that touches only another collection's folder does not block a push either", () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      host.commitFiles(repo, {'apis/other/collection.json': '{"uid":"x","kind":"collection","name":"Other"}'});

      alice.edit(shop, 'req-Shop', {'note': 'edited'});
      final pushed = await alice.pushAll(shop);

      expect(pushed.changedFiles, 1);
    });

    test('a file added or removed inside the collection folder by someone else is a real change', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      host.commitFiles(repo, {
        'apis/shop/new.request.json': '{"uid":"r-new","kind":"request","name":"New","parent":"col-Shop","order":5}',
      });

      expect((await alice.statusOf(shop, checkRemote: true)).behind, isTrue);
    });
  });

  group('two collections must never claim overlapping repository folders', () {
    test('a folder above, below or equal to another collection\'s is refused', () async {
      final alice = Teammate(host);
      await linkedCollection(alice, 'Shop', 'apis/shop');
      final other = alice.store.addCollection(name: 'Other', uid: 'col-other');

      for (final path in ['apis', '', 'apis/shop', 'apis/shop/inner', 'APIS/SHOP/', './apis/shop']) {
        await expectLater(
          alice.connect(GitConnectParams(collectionId: other, repo: repo, branch: 'main', basePath: path)),
          throwsA(isA<GitPathOverlapException>()),
          reason: '"$path"',
        );
      }
    });

    test('a sibling folder, another branch, or another repository are fine', () async {
      final alice = Teammate(host);
      await linkedCollection(alice, 'Shop', 'apis/shop');
      final elsewhere = host.seedRepo('acme/other');
      final a = alice.store.addCollection(name: 'A', uid: 'col-a');
      final b = alice.store.addCollection(name: 'B', uid: 'col-b');
      final c = alice.store.addCollection(name: 'C', uid: 'col-c');
      await host.createBranch(repo, 'dev', fromSha: host.headOf(repo)!);

      await alice.connect(GitConnectParams(collectionId: a, repo: repo, branch: 'main', basePath: 'apis/shop-two'));
      // Same folder as another collection, but on another branch: separate files.
      final zoneMain = alice.store.addCollection(name: 'Zone main', uid: 'col-zm');
      await alice.connect(GitConnectParams(collectionId: zoneMain, repo: repo, branch: 'main', basePath: 'zone'));
      await alice.connect(GitConnectParams(collectionId: b, repo: repo, branch: 'dev', basePath: 'zone'));
      await alice.connect(GitConnectParams(collectionId: c, repo: elsewhere, branch: 'main', basePath: ''));

      expect((await alice.linkOf(a)).basePath, 'apis/shop-two');
      expect((await alice.linkOf(b)).branch, 'dev');
      expect((await alice.linkOf(b)).basePath, (await alice.linkOf(zoneMain)).basePath);
      expect((await alice.linkOf(c)).repo, elsewhere);
    });

    test('reconnecting the same collection with other settings is not an overlap with itself', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');

      await alice.connect(GitConnectParams(collectionId: shop, repo: repo, branch: 'main', basePath: 'apis/shop', includeSecrets: true));

      expect((await alice.linkOf(shop)).includeSecrets, isTrue);
    });

    test('cloning into a folder another local collection already syncs is refused too', () async {
      final alice = Teammate(host);
      await linkedCollection(alice, 'Shop', 'apis/shop');
      final bob = Teammate(host);
      await bob.clone(GitCloneParams(repo: repo, branch: 'main', basePath: 'apis/shop'));

      await expectLater(
        bob.clone(GitCloneParams(repo: repo, branch: 'main', basePath: 'apis')),
        throwsA(isA<GitPathOverlapException>()),
      );
    });
  });

  group('connecting again after a disconnect', () {
    test('adopts the same collection that is already in the repository instead of dead-ending', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      await alice.disconnect(shop);

      final link = await alice.connect(GitConnectParams(collectionId: shop, repo: repo, branch: 'main', basePath: 'apis/shop'));

      expect(link.lastSyncedSha, isNull, reason: 'nothing is shared yet, so the first move has to be a pull');
      await expectLater(alice.pushAll(shop), throwsA(isA<GitNotFastForwardException>()), reason: 'no blind overwrite of the remote');
      final pulled = await alice.pullAll(shop);
      expect(pulled, isNot(isA<PullConflicts>()));
      expect((await alice.linkOf(shop)).lastSyncedSha, host.headOf(repo));
      expect((await alice.statusOf(shop)).localChanges, isEmpty);
    });

    test('keeps local edits made while it was disconnected, merged with what the repository has', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      await alice.disconnect(shop);
      alice.edit(shop, 'req-Shop', {'note': 'edited offline'});

      await alice.connect(GitConnectParams(collectionId: shop, repo: repo, branch: 'main', basePath: 'apis/shop'));
      final pulled = await alice.pullAll(shop);
      if (pulled is PullConflicts) {
        await alice.pullAll(shop, {for (final c in pulled.conflicts) c.uid: ConflictChoice.local});
      }
      await alice.pushAll(shop, 'Offline edit');

      expect(host.filesAt(repo).values.join(), contains('edited offline'));
    });

    test('a different collection at an occupied folder is still refused', () async {
      final alice = Teammate(host);
      await linkedCollection(alice, 'Shop', 'apis/shop');
      // Bob's collection has another root uid, so only that tells it apart from Alice's.
      final bob = Teammate(host);
      final bobsStranger = bob.store.addCollection(name: 'Stranger', uid: 'col-stranger');

      await expectLater(
        bob.connect(GitConnectParams(collectionId: bobsStranger, repo: repo, branch: 'main', basePath: 'apis/shop')),
        throwsA(isA<GitPathOccupiedException>()),
      );
    });
  });

  group('errors that used to point at the wrong cause', () {
    test('a repository that cannot be seen any more is reported as such, not as a missing branch', () async {
      final alice = Teammate(host);
      final shop = await linkedCollection(alice, 'Shop', 'apis/shop');
      final blind = Teammate(_InvisibleRepoHost(host));
      blind.links.links.addAll(alice.links.links);
      blind.links.bases.addAll(alice.links.bases);
      blind.store.collections.addAll(alice.store.collections);

      await expectLater(blind.pullAll(shop), throwsA(isA<GitNotFoundException>()));
    });

    test('creating a branch before anything was pulled or pushed is refused, so it cannot start from a moved head', () async {
      final bob = Teammate(host);
      final alice = Teammate(host);
      final empty = host.seedRepo('acme/empty', files: const {});
      final shop = alice.store.addCollection(name: 'Shop', uid: 'col-Shop');
      alice.store.upsert(shop, requestDoc('req-Shop', 'Shop request'));
      await alice.connect(GitConnectParams(collectionId: shop, repo: empty, branch: 'main', basePath: ''));
      final theirs = bob.store.addCollection(name: 'Theirs', uid: 'col-theirs');
      bob.store.upsert(theirs, requestDoc('req-theirs', 'Theirs'));
      await bob.connect(GitConnectParams(collectionId: theirs, repo: empty, branch: 'main', basePath: ''));
      await bob.pushAll(theirs);

      await expectLater(
        alice.createBranch(GitBranchParams(collectionId: shop, branch: 'feature')),
        throwsA(isA<GitSyncException>().having((e) => e.message, 'message', contains('pull'))),
      );
    });
  });
}

/// A host that hides the repository: the branch lookup answers "not found" like GitHub does for a repo
/// the token cannot see, while asking for the repository itself reveals the real reason.
final class _InvisibleRepoHost extends FakeGitHost {
  _InvisibleRepoHost(FakeGitHost real) : super(login: real.login);

  @override
  Future<String?> getBranchHead(RepoRef repo, String branch) async => null;

  @override
  Future<GitRepoInfo> getRepo(RepoRef repo) async => throw const GitNotFoundException('Repository not found, or the token cannot see it');
}
