import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/git_hash.dart';
import 'package:postpilot/features/git_sync/domain/services/repo_layout.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/git_sync/domain/services/sync_engine.dart';

import 'fakes/fake_git_host.dart';
import 'fakes/fake_local_store.dart';
import 'fakes/sync_fixtures.dart';

SyncSnapshot sampleTree() => snapshotOf([
      collectionDoc(),
      folderDoc('f-users', 'Users'),
      requestDoc('r-list', 'List users', parent: 'f-users', order: 1),
      requestDoc('r-get', 'Get user', parent: 'f-users'),
      requestDoc('r-health', 'Health'),
    ]);

GitLink linkFor(RepoRef repo, {String basePath = '', bool includeSecrets = false}) => GitLink(
      id: 1,
      collectionId: 1,
      repo: repo,
      branch: 'main',
      basePath: basePath,
      includeSecrets: includeSecrets,
    );

void main() {
  late FakeGitHost host;
  late FakeLocalStore store;
  late SyncEngine engine;

  setUp(() {
    host = FakeGitHost();
    store = FakeLocalStore();
    engine = SyncEngine(host, store);
  });

  group('diff', () {
    test('reports added, modified (with the fields that differ) and deleted entities', () {
      final base = sampleTree();
      final local = changed(base,
          docs: [
            edited(base.docs['r-list']!, {'url': 'https://new.test', 'name': 'List all users'}),
            requestDoc('r-new', 'Brand new'),
          ],
          drop: ['r-health']);

      final changes = engine.diff(base, local);

      final byUid = {for (final c in changes) c.uid: c};
      expect(byUid.keys.toSet(), {'r-list', 'r-new', 'r-health'});
      expect(byUid['r-new']!.type, DocChangeType.added);
      expect(byUid['r-new']!.changedFields, isEmpty);
      expect(byUid['r-health']!.type, DocChangeType.deleted);
      expect(byUid['r-health']!.name, 'Health');
      expect(byUid['r-list']!.type, DocChangeType.modified);
      expect(byUid['r-list']!.name, 'List all users');
      expect(byUid['r-list']!.changedFields, ['name', 'url']);
    });

    test('is empty when nothing differs', () {
      expect(engine.diff(sampleTree(), sampleTree()), isEmpty);
    });

    test('orders the collection first, then folders, then requests, alphabetically', () {
      final base = snapshotOf([collectionDoc()]);
      final local = snapshotOf([
        collectionDoc(name: 'Renamed'),
        requestDoc('r2', 'beta'),
        requestDoc('r1', 'Alpha'),
        folderDoc('f2', 'Zulu'),
        folderDoc('f1', 'Yankee'),
      ]);

      expect(engine.diff(base, local).map((c) => c.uid), ['col', 'f1', 'f2', 'r1', 'r2']);
    });

    test('changed fields list name, parentUid and order first and treat an absent key as different from null', () {
      final base = snapshotOf([
        collectionDoc(),
        folderDoc('f1', 'Users'),
        requestDoc('r1', 'One', data: {'note': 'x', 'zeta': 1, 'alpha': 1}),
      ]);
      final local = changed(base, docs: [
        edited(without(base.docs['r1']!, 'note'), {'zeta': 2, 'order': 5, 'parentUid': 'f1', 'alpha': null, 'extra': true}),
      ]);

      expect(engine.diff(base, local).single.changedFields, ['parentUid', 'order', 'alpha', 'extra', 'note', 'zeta']);
    });

    test('a field that only turns from absent to null is a change', () {
      final base = snapshotOf([collectionDoc(), requestDoc('r1', 'One')]);
      final local = changed(base, docs: [edited(base.docs['r1']!, {'note': null})]);
      expect(engine.diff(base, local).single.changedFields, ['note']);
    });
  });

  group('base entries', () {
    test('carry exactly the path and blob sha a push writes', () {
      final tree = sampleTree();
      final files = RepoLayout.toFiles(tree, basePath: 'team/apis');

      final entries = engine.toBaseEntries(tree, 'team/apis');

      expect(entries.keys.toSet(), tree.docs.keys.toSet());
      expect({for (final e in entries.values) e.path: e.blobSha}, {
        for (final f in files.entries) f.key: GitHash.blobSha(f.value),
      });
      expect(entries['r-list']!.path, 'team/apis/users/list-users.request.json');
    });

    test('baseSnapshot gives back the docs', () {
      final tree = sampleTree();
      expect(engine.baseSnapshot(engine.toBaseEntries(tree, '')).docs, tree.docs);
    });
  });

  group('pushChanges', () {
    test('an empty base writes every file', () {
      final tree = sampleTree();
      expect(engine.pushChanges(tree, const {}, ''), RepoLayout.toFiles(tree, basePath: ''));
    });

    test('an unchanged collection writes nothing', () {
      final tree = sampleTree();
      expect(engine.pushChanges(tree, engine.toBaseEntries(tree, 'x'), 'x'), isEmpty);
    });

    test('an edit writes only that file, a delete removes only that file', () {
      final tree = sampleTree();
      final base = engine.toBaseEntries(tree, '');

      final edit = changed(tree, docs: [edited(tree.docs['r-get']!, {'url': 'https://changed.test'})]);
      expect(engine.pushChanges(edit, base, '').keys, ['users/get-user.request.json']);

      final delete = changed(tree, drop: ['r-health']);
      expect(engine.pushChanges(delete, base, ''), {'health.request.json': null});
    });

    test('renaming a folder moves the files of its unchanged children as well', () {
      final tree = sampleTree();
      final base = engine.toBaseEntries(tree, '');
      final renamed = changed(tree, docs: [edited(tree.docs['f-users']!, {'name': 'Accounts'})]);

      final changes = engine.pushChanges(renamed, base, '');

      expect(changes.keys.toSet(), {
        'users/_folder.json',
        'users/list-users.request.json',
        'users/get-user.request.json',
        'accounts/_folder.json',
        'accounts/list-users.request.json',
        'accounts/get-user.request.json',
      });
      expect(changes['users/_folder.json'], isNull);
      expect(changes['accounts/list-users.request.json'], tree.docs['r-list']!.canonicalText);
    });

    test('moving a request deletes the old path and writes the new one', () {
      final tree = sampleTree();
      final base = engine.toBaseEntries(tree, '');
      final moved = changed(tree, docs: [edited(tree.docs['r-get']!, {'parentUid': 'col'})]);

      final changes = engine.pushChanges(moved, base, '');

      expect(changes.keys.toSet(), {'users/get-user.request.json', 'get-user.request.json'});
      expect(changes['users/get-user.request.json'], isNull);
      expect(changes['get-user.request.json'], isNotNull);
    });
  });

  group('fetchRemoteSnapshot', () {
    late RepoRef repo;
    late SyncSnapshot tree;

    Future<String> seed({String basePath = '', Map<String, String> extraFiles = const {}}) async {
      repo = host.seedRepo('acme/api', files: {
        'README.md': '# readme',
        ...extraFiles,
        ...RepoLayout.toFiles(tree, basePath: basePath),
      });
      return host.headOf(repo)!;
    }

    setUp(() => tree = sampleTree());

    test('downloads only collection files, and only those that differ from the base', () async {
      final head = await seed();
      final link = linkFor(repo);

      final full = await engine.fetchRemoteSnapshot(link, commitSha: head, base: const {});
      expect(full.docs, tree.docs);
      expect(host.blobReads, tree.docs.length);

      host.blobReads = 0;
      final base = engine.toBaseEntries(tree, '');
      final unchanged = await engine.fetchRemoteSnapshot(link, commitSha: head, base: base);
      expect(unchanged.docs, tree.docs);
      expect(host.blobReads, 0);

      final edit = edited(tree.docs['r-list']!, {'url': 'https://teammate.test'});
      final newHead = host.commitFiles(repo, {'users/list-users.request.json': edit.canonicalText});
      final after = await engine.fetchRemoteSnapshot(link, commitSha: newHead, base: base);
      expect(host.blobReads, 1);
      expect(after.docs['r-list']!.data['url'], 'https://teammate.test');
      expect(after.docs['r-get'], tree.docs['r-get']);
    });

    test('never has more than 8 downloads in flight', () async {
      tree = snapshotOf([collectionDoc(), for (var i = 0; i < 30; i++) requestDoc('r$i', 'Request $i')]);
      final head = await seed();

      final snapshot = await engine.fetchRemoteSnapshot(linkFor(repo), commitSha: head, base: const {});

      expect(snapshot.docs.length, 31);
      expect(host.blobReads, 31);
      expect(host.peakConcurrentBlobReads, 8);
    });

    test('reads only the base path folder, not a folder that merely shares its prefix', () async {
      final other = snapshotOf([collectionDoc(uid: 'other', name: 'Other'), requestDoc('r-other', 'X', parent: 'other')]);
      final head = await seed(
        basePath: 'a',
        extraFiles: RepoLayout.toFiles(other, basePath: 'ab'),
      );

      final snapshot = await engine.fetchRemoteSnapshot(linkFor(repo, basePath: 'a'), commitSha: head, base: const {});

      expect(snapshot.docs.keys.toSet(), tree.docs.keys.toSet());
      expect(host.blobReads, tree.docs.length);
    });

    test('a repository folder without a collection gives an empty snapshot', () async {
      final head = await seed(basePath: 'a');
      final snapshot = await engine.fetchRemoteSnapshot(linkFor(repo, basePath: 'nothing-here'), commitSha: head, base: const {});
      expect(snapshot.isEmpty, isTrue);
    });

    test('a changed file that is no longer valid JSON keeps its base version instead of looking deleted', () async {
      await seed();
      final base = engine.toBaseEntries(tree, '');
      final broken = host.commitFiles(repo, {'users/list-users.request.json': '<<<<<<< HEAD\n{}\n=======\n'});

      final withBase = await engine.fetchRemoteSnapshot(linkFor(repo), commitSha: broken, base: base);
      expect(withBase.docs['r-list'], tree.docs['r-list']);
      expect(withBase.docs.length, tree.docs.length);

      final withoutBase = await engine.fetchRemoteSnapshot(linkFor(repo), commitSha: broken, base: const {});
      expect(withoutBase.docs.containsKey('r-list'), isFalse);
    });

    test('credentials in remote files are dropped unless the link includes secrets', () async {
      tree = snapshotOf([
        collectionDoc(),
        requestDoc('r1', 'Secured', data: {
          'auth': {'type': 'bearer', 'bearerToken': 'tok-123', 'basicUsername': 'me'},
        }),
      ]);
      final head = await seed();

      final stripped = await engine.fetchRemoteSnapshot(linkFor(repo), commitSha: head, base: const {});
      final kept = await engine.fetchRemoteSnapshot(linkFor(repo, includeSecrets: true), commitSha: head, base: const {});

      expect(stripped.docs['r1']!.data['auth'], {'type': 'bearer', 'basicUsername': 'me'});
      expect((kept.docs['r1']!.data['auth']! as Map)['bearerToken'], 'tok-123');
    });
  });

  group('readLocal', () {
    final variables = [
      {'key': 'api_token', 'value': 's3cret', 'enabled': true},
      {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
    ];

    test('strips credentials unless the link includes secrets', () async {
      final id = store.addCollection(data: {
        'variables': variables,
        'auth': {'type': 'bearer', 'bearerToken': 'tok'},
      });
      final repo = host.seedRepo('acme/api');
      final link = GitLink(id: 1, collectionId: id, repo: repo, branch: 'main', basePath: '');

      final stripped = (await engine.readLocal(link)).root!;
      expect(stripped.data['auth'], {'type': 'bearer'});
      expect((stripped.data['variables']! as List).cast<Map>().map((v) => v['value']), ['', 'https://api.test']);

      final full = (await engine.readLocal(GitLink(
        id: 1,
        collectionId: id,
        repo: repo,
        branch: 'main',
        basePath: '',
        includeSecrets: true,
      )))
          .root!;
      expect((full.data['auth']! as Map)['bearerToken'], 'tok');
      expect((full.data['variables']! as List).cast<Map>().map((v) => v['value']), ['s3cret', 'https://api.test']);
    });
  });

  group('SecretFields', () {
    test('stripDoc drops auth credentials and blanks secret-looking collection variables', () {
      final doc = collectionDoc(data: {
        'variables': [
          {'key': 'X-Api-Key', 'value': 'k', 'enabled': true},
          {'key': 'PASSWORD', 'value': 'p', 'enabled': false},
          {'key': 'host', 'value': 'localhost', 'enabled': true},
        ],
        'auth': {'type': 'oauth2', 'oauth2ClientId': 'id', 'oauth2ClientSecret': 's', 'oauth2AccessToken': 't'},
      });

      final stripped = SecretFields.stripDoc(doc);

      expect(stripped.data['auth'], {'type': 'oauth2', 'oauth2ClientId': 'id'});
      expect((stripped.data['variables']! as List).cast<Map>().map((v) => v['value']), ['', '', 'localhost']);
      expect((stripped.data['variables']! as List).cast<Map>().map((v) => v['enabled']), [true, false, true]);
    });

    test('also blanks secret-looking variables stored as a map', () {
      final doc = collectionDoc(data: {
        'variables': {
          'apiKey': 'k',
          'host': 'localhost',
          'token': {'value': 't', 'enabled': true},
        },
      });

      expect(SecretFields.stripDoc(doc).data['variables'], {
        'apiKey': '',
        'host': 'localhost',
        'token': {'value': '', 'enabled': true},
      });
    });

    test('is idempotent and leaves docs without credentials untouched', () {
      final doc = collectionDoc(data: {
        'variables': [{'key': 'token', 'value': 'v'}],
        'auth': {'type': 'bearer', 'bearerToken': 'x'},
      });
      final once = SecretFields.stripDoc(doc);
      expect(SecretFields.stripDoc(once), once);

      final plain = requestDoc('r1', 'Plain', data: {'variables': [{'key': 'token', 'value': 'kept'}]});
      expect(SecretFields.stripDoc(plain), plain);
    });

    test('applyPolicy passes the snapshot through when secrets are included', () {
      final tree = snapshotOf([collectionDoc(data: {'auth': {'type': 'bearer', 'bearerToken': 'x'}})]);
      expect(SecretFields.applyPolicy(tree, includeSecrets: true), same(tree));
      expect(SecretFields.applyPolicy(tree, includeSecrets: false).root!.data['auth'], {'type': 'bearer'});
    });
  });
}
