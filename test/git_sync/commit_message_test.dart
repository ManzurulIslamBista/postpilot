import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/commit_message.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'fakes/fake_git_host.dart';
import 'fakes/sync_fixtures.dart';
import 'fakes/teammate.dart';

DocChange _change(String name, DocChangeType type, {SyncKind kind = SyncKind.request}) =>
    DocChange(uid: 'u-$name', kind: kind, name: name, type: type);

void main() {
  group('CommitMessage.fromChanges', () {
    test('counts what changed and names it', () {
      expect(
        CommitMessage.fromChanges('Users API', [_change('List users', DocChangeType.modified)]),
        'Change 1 request in Users API\n\n- List users',
      );
    });

    test('says add, change and remove in that order, folders after requests', () {
      final message = CommitMessage.fromChanges('API', [
        _change('Admin', DocChangeType.added, kind: SyncKind.folder),
        _change('New user', DocChangeType.added),
        _change('Get user', DocChangeType.added),
        _change('List users', DocChangeType.modified),
        _change('Delete user', DocChangeType.deleted),
      ]);

      expect(message.split('\n').first, 'Add 2 requests and 1 folder, change 1 request, remove 1 request in API');
      expect(message, endsWith('\n\n- Admin\n- New user\n- Get user\n- …'), reason: 'three names, then a mark that there are more');
    });

    test('a change to the collection itself is "the collection settings"', () {
      expect(
        CommitMessage.fromChanges('Users API', [_change('Users API', DocChangeType.modified, kind: SyncKind.collection)]),
        'Update the collection settings in Users API',
      );
      final both = CommitMessage.fromChanges('Users API', [
        _change('Users API', DocChangeType.modified, kind: SyncKind.collection),
        _change('List users', DocChangeType.modified),
      ]);
      expect(both, 'Change 1 request, update the collection settings in Users API\n\n- List users');
    });

    test('without changes, or without a collection name, it still reads well', () {
      expect(CommitMessage.fromChanges('Users API', const []), 'Update Users API');
      expect(CommitMessage.fromChanges('  ', const []), 'Update collection');
      expect(CommitMessage.fromChanges('', [_change('List users', DocChangeType.deleted)]), 'Remove 1 request\n\n- List users');
    });

    test('a long subject is cut to 72 characters', () {
      final long = 'A collection with a name that goes on and on and on and on and on';
      final first = CommitMessage.fromChanges(long, [_change('x', DocChangeType.added)]).split('\n').first;
      expect(first.length, 72);
      expect(first, endsWith('...'));
      expect(first, startsWith('Add 1 request in A collection with a name'));
    });
  });

  test('a push without a message is written from the changes, not just counted', () async {
    final host = FakeGitHost();
    final repo = host.seedRepo('acme/payments');
    final a = Teammate(host);
    final id = a.store.addCollection(name: 'Payments');
    a.store.upsert(id, requestDoc('r-list', 'List users'));
    await a.connect(GitConnectParams(collectionId: id, repo: repo, branch: 'main', basePath: 'apis'));
    await a.pushAll(id, 'Initial');

    a.edit(id, 'r-list', {'note': 'changed'});
    a.store.upsert(id, requestDoc('r-new', 'Create user'));
    await a.pushAll(id, '  ');

    final message = (await host.listCommits(repo, branch: 'main')).first.message;
    expect(message, 'Add 1 request, change 1 request\n\n- Create user\n- List users');
  });
}
