import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_exceptions.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_credentials_store.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_link_repository.dart';
import 'package:postpilot/features/git_sync/domain/repositories/local_collection_store.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_commit_push_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_create_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discover_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_history_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_pull_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_save_token_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_status_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_update_link_settings_usecase.dart';
import 'package:postpilot/features/git_sync/presentation/git_formatting.dart';
import 'package:postpilot/features/git_sync/presentation/reopen_replaced_requests.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_clone_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_operation_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_sync_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/linked_collections_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/widgets/git_clone_panel.dart';
import 'package:postpilot/features/git_sync/presentation/widgets/git_link_badge.dart';
import 'package:postpilot/features/git_sync/presentation/widgets/git_sync_panel.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:provider/provider.dart';

const _repo = RepoRef(provider: GitProvider.github, owner: 'acme', repo: 'api');

GitLink _link({String branch = 'main', String basePath = '', bool includeSecrets = false, int collectionId = 7}) =>
    GitLink(
      id: 1,
      collectionId: collectionId,
      repo: _repo,
      branch: branch,
      basePath: basePath,
      lastSyncedSha: 'abc1234def56',
      lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      includeSecrets: includeSecrets,
    );

const _listUsers = DocChange(
  uid: 'r1',
  kind: SyncKind.request,
  name: 'List users',
  type: DocChangeType.modified,
  changedFields: ['url', 'headers'],
);
const _newFolder = DocChange(uid: 'f1', kind: SyncKind.folder, name: 'Admin', type: DocChangeType.added);
const _deleteUser = DocChange(uid: 'r2', kind: SyncKind.request, name: 'Delete user', type: DocChangeType.deleted);

const _pushed = PushResult(
  commitSha: 'abcdef1234567',
  commitUrl: 'https://github.com/acme/api/commit/abcdef1234567',
  changedFiles: 1,
);

// The messages the GitHub client really produces: they carry the specifics the UI has to show.
const _rejectedToken = GitAuthException('GitHub rejected the saved token: Bad credentials');
const _rateLimited = GitRateLimitException(
  'GitHub rate limit reached. It resets at 14:05. Saving a GitHub token raises the limit.',
);

const _readOnlyRepo = GitRepoInfo(defaultBranch: 'main', canPush: false, isPrivate: true, isEmpty: false);
const _writableRepo = GitRepoInfo(defaultBranch: 'main', canPush: true, isPrivate: false, isEmpty: false);

const _bothModified = SyncConflict(
  uid: 'r1',
  kind: SyncKind.request,
  name: 'List users',
  type: ConflictKind.bothModified,
  fields: [FieldConflict(field: 'url', base: '/v1/users', local: '/v2/users', remote: '/users')],
);
const _deletedHere = SyncConflict(
  uid: 'r2',
  kind: SyncKind.request,
  name: 'Delete user',
  type: ConflictKind.deletedLocallyModifiedRemotely,
);

/// A use case whose behaviour each test sets; every call is recorded.
final class _Fake<Out, Params> implements UseCase<Out, Params> {
  final String name;
  late Future<Out> Function(Params params) handler = (_) => throw StateError('$name was not expected to run');
  final calls = <Params>[];

  _Fake(this.name);

  @override
  Future<Out> call(Params params) {
    calls.add(params);
    return handler(params);
  }
}

final class _FakeLinks implements GitLinkRepository {
  GitLink? link;
  final ids = StreamController<Set<int>>.broadcast();

  @override
  Future<GitLink?> findByCollection(int collectionId) async => link;

  @override
  Future<List<GitLink>> findAll() async => [?link];

  @override
  Stream<GitLink?> watchByCollection(int collectionId) => Stream.value(link);

  @override
  Stream<Set<int>> watchLinkedCollectionIds() => ids.stream;

  @override
  Future<GitLink> save(GitLink link) async => link;

  @override
  Future<void> remove(int collectionId) async {}

  @override
  Future<Map<String, BaseEntry>> readBase(int linkId) async => {};

  @override
  Future<void> writeBase(int linkId, Map<String, BaseEntry> entries) async {}
}

final class _FakeCredentials implements GitCredentialsStore {
  String? token = 'ghp_saved';
  Object? readError;

  @override
  Future<String?> readToken(GitProvider provider) async {
    final error = readError;
    if (error != null) throw error;
    return token;
  }

  @override
  Future<void> saveToken(GitProvider provider, String token) async => this.token = token;

  @override
  Future<void> deleteToken(GitProvider provider) async => token = null;
}

final class _FakeRequests implements RequestRepository {
  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => const Stream.empty();

  @override
  Stream<ApiRequestEntity?> watchById(int id) => const Stream.empty();

  @override
  Future<ApiRequestEntity?> findById(int id) async => null;

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) async => 0;

  @override
  Future<void> saveRequest(ApiRequestEntity request) async {}

  @override
  Future<void> deleteRequest(int id) async {}
}

/// A [GitSyncViewModel] wired to fakes that behave like a healthy linked collection until a test says otherwise.
final class _Harness {
  final links = _FakeLinks();
  final credentials = _FakeCredentials();
  final status = _Fake<GitStatus, GitStatusParams>('status');
  final connect = _Fake<GitLink, GitConnectParams>('connect');
  final commit = _Fake<PushResult, GitCommitPushParams>('commit');
  final pull = _Fake<PullResult, GitPullParams>('pull');
  final discard = _Fake<ApplyOutcome, int>('discard');
  final history = _Fake<List<GitCommitInfo>, GitHistoryParams>('history');
  final listBranches = _Fake<List<String>, int>('listBranches');
  final createBranch = _Fake<GitLink, GitBranchParams>('createBranch');
  final switchBranch = _Fake<ApplyOutcome, GitBranchParams>('switchBranch');
  final contributors = _Fake<List<GitContributor>, int>('contributors');
  final updateSettings = _Fake<GitLink, GitLinkSettingsParams>('updateSettings');
  final disconnect = _Fake<void, int>('disconnect');
  final saveToken = _Fake<String, GitTokenParams>('saveToken');

  final opened = <Uri>[];
  final replaced = <List<List<int>>>[];
  bool browserWorks = true;

  GitLink? linked = _link();
  List<DocChange> changes = const [];
  GitRepoInfo? remoteInfo;
  bool? remoteBehind = false;

  late final GitSyncViewModel vm;

  _Harness({bool autoDispose = true}) {
    links.link = linked;
    status.handler = (params) async => GitStatus(
          link: linked ?? _link(),
          localChanges: changes,
          repoInfo: params.checkRemote ? remoteInfo : null,
          behind: params.checkRemote ? remoteBehind : null,
        );
    saveToken.handler = (_) async => 'octocat';
    vm = GitSyncViewModel(
      credentials: credentials,
      saveTokenUseCase: saveToken,
      openUri: (uri) async {
        opened.add(uri);
        return browserWorks;
      },
      links: links,
      statusUseCase: status,
      connectUseCase: connect,
      commitPushUseCase: commit,
      pullUseCase: pull,
      discardUseCase: discard,
      historyUseCase: history,
      listBranchesUseCase: listBranches,
      createBranchUseCase: createBranch,
      switchBranchUseCase: switchBranch,
      contributorsUseCase: contributors,
      updateLinkSettingsUseCase: updateSettings,
      disconnectUseCase: disconnect,
    )..onRequestsReplaced = (changed, deleted) => replaced.add([changed, deleted]);
    if (autoDispose) addTearDown(vm.dispose);
  }

  Future<void> load() => vm.load(7, collectionName: 'Users API');
}

final class _CloneHarness {
  final credentials = _FakeCredentials();
  final saveToken = _Fake<String, GitTokenParams>('saveToken')..handler = ((_) async => 'octocat');
  final discover = _Fake<List<DiscoveredCollection>, GitDiscoverParams>('discover');
  final clone = _Fake<GitLink, GitCloneParams>('clone');
  late final GitCloneViewModel vm;

  _CloneHarness() {
    vm = GitCloneViewModel(
      credentials: credentials,
      saveTokenUseCase: saveToken,
      openUri: (_) async => true,
      discoverUseCase: discover,
      cloneUseCase: clone,
    );
    addTearDown(vm.dispose);
  }
}

void main() {
  group('GitSyncViewModel', () {
    test('load reads the link, then the local status, then asks the remote', () async {
      final h = _Harness();

      await h.load();

      expect(h.vm.isLoaded, isTrue);
      expect(h.vm.isBusy, isFalse);
      expect(h.vm.link?.repo.fullName, 'acme/api');
      expect(h.status.calls.map((c) => c.checkRemote), [false, true]);
      expect(h.status.calls.every((c) => c.collectionId == 7), isTrue);
      expect(h.vm.commitMessage, 'Update Users API');
      expect(h.vm.hasToken, isTrue);
    });

    test('load of an unlinked collection has no link and does not ask for a status', () async {
      final h = _Harness()..links.link = null;

      await h.load();

      expect(h.vm.isLoaded, isTrue);
      expect(h.vm.link, isNull);
      expect(h.status.calls, isEmpty);
    });

    test('a failing remote check keeps the local status on screen and explains itself', () async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.status.handler = (params) async {
        if (params.checkRemote) throw _rejectedToken;
        return GitStatus(link: _link(), localChanges: h.changes);
      };

      await h.load();

      expect(h.vm.isLoaded, isTrue);
      expect(h.vm.localChanges, [_listUsers]);
      expect(h.vm.errorMessage, startsWith('GitHub rejected the saved token'));
    });

    test('a failing load leaves isLoaded false so the dialog can offer a retry', () async {
      final h = _Harness();
      h.status.handler = (_) => throw StateError('database is locked');

      await h.load();

      expect(h.vm.isLoaded, isFalse);
      expect(h.vm.errorMessage, 'Something went wrong — please try again.');
    });

    group('error messages', () {
      final cases = <String, (Object, Matcher)>{
        'auth': (
          const GitAuthException('token ghp_SECRET revoked'),
          equals('token … revoked. It may have expired or lack access — update it under Settings.'),
        ),
        'auth without a message': (
          const GitAuthException(' '),
          equals('GitHub rejected your token — it may have expired or lack access. Update it under Settings.'),
        ),
        'SSO enforcement': (
          const GitAuthException(
            'GitHub rejected the saved token: Resource protected by organization SAML enforcement. '
            'You must grant your Personal Access token access to this organization.',
          ),
          allOf(contains('SAML enforcement'), contains('grant your Personal Access token access')),
        ),
        'missing token': (
          const GitMissingTokenException(),
          equals('Save a GitHub token first: paste one into the token field, then try again.'),
        ),
        'not fast-forward': (
          const GitNotFastForwardException('ref moved'),
          equals('Someone pushed since you last pulled. Pull first, then push again.'),
        ),
        'rate limit': (
          _rateLimited,
          equals('GitHub rate limit reached. It resets at 14:05. Saving a GitHub token raises the limit.'),
        ),
        'rate limit without a message': (
          const GitRateLimitException(''),
          contains('limiting requests'),
        ),
        'read-only': (const GitReadOnlyException(), contains('read access')),
        'nothing to commit': (const GitNothingToCommitException(), contains('nothing to commit')),
        'path occupied': (const GitPathOccupiedException('apis/users'), contains('apis/users')),
        'uncommitted changes': (const GitUncommittedChangesException(), contains('Push or discard them first')),
        'not found names what was not found': (
          const GitNotFoundException('Branch "dev" of acme/api not found, or your token cannot see it'),
          equals('Branch "dev" of acme/api not found, or your token cannot see it.'),
        ),
        'not found without a message': (const GitNotFoundException(' '), contains("couldn't find that repository")),
        'sync exception': (const GitSyncException('Sync said no.'), equals('Sync said no.')),
        'host exception': (const GitHostException('Host said no.'), equals('Host said no.')),
        'anything else': (StateError('boom'), equals('Something went wrong — please try again.')),
      };

      for (final entry in cases.entries) {
        test('${entry.key} becomes plain language', () async {
          final h = _Harness();
          h.changes = const [_listUsers];
          h.commit.handler = (_) => throw entry.value.$1;
          await h.load();

          final pushed = await h.vm.commitPush();

          expect(pushed, isFalse);
          expect(h.vm.errorMessage, entry.value.$2);
          expect(h.vm.errorMessage, isNot(contains('boom')));
          expect(h.vm.errorMessage, isNot(contains('ghp_SECRET')));
          expect(h.vm.isBusy, isFalse);
        });
      }

      test('an exception with an empty message still gets readable text', () async {
        final h = _Harness();
        h.commit.handler = (_) => throw const GitHostException('  ');
        await h.load();
        h.changes = const [_listUsers];
        await h.vm.refresh();

        await h.vm.commitPush();

        expect(h.vm.errorMessage, 'Something went wrong — please try again.');
      });

      test('the next action clears the previous error', () async {
        final h = _Harness();
        h.commit.handler = (_) => throw const GitReadOnlyException();
        await h.load();
        await h.vm.commitPush();
        expect(h.vm.errorMessage, isNotNull);

        await h.vm.refresh();

        expect(h.vm.errorMessage, isNull);
      });
    });

    group('needsPull', () {
      test('is set when a push is rejected because the remote moved', () async {
        final h = _Harness();
        h.commit.handler = (_) => throw const GitNotFastForwardException('ref moved');
        await h.load();
        expect(h.vm.needsPull, isFalse);

        await h.vm.commitPush();

        expect(h.vm.needsPull, isTrue);
        expect(h.vm.errorMessage, 'Someone pushed since you last pulled. Pull first, then push again.');
      });

      test('follows the remote check, survives local refreshes and clears after a pull', () async {
        final h = _Harness()..remoteBehind = true;
        h.pull.handler = (_) async => const PullApplied(added: 1, updated: 0, deleted: 0);
        await h.load();
        expect(h.vm.needsPull, isTrue);

        await h.vm.refresh();
        expect(h.vm.needsPull, isTrue);

        await h.vm.pull();
        expect(h.vm.needsPull, isFalse);
      });

      test('remoteChecked turns true only once the host answered, or after we synced with it ourselves', () async {
        final h = _Harness();
        h.status.handler = (params) async {
          if (params.checkRemote) throw _rateLimited;
          return GitStatus(link: _link(), localChanges: const []);
        };
        h.pull.handler = (_) async => const PullUpToDate();
        await h.load();
        expect(h.vm.remoteChecked, isFalse);

        await h.vm.pull();

        expect(h.vm.remoteChecked, isTrue);
        expect(h.vm.needsPull, isFalse);
      });

      test('a remote check that finds nothing new clears it', () async {
        final h = _Harness()..remoteBehind = true;
        await h.load();
        h.remoteBehind = false;

        await h.vm.refresh(checkRemote: true);

        expect(h.vm.needsPull, isFalse);
      });
    });

    group('pull and conflicts', () {
      test('conflicts are listed with "keep mine" chosen, and applyResolutions sends the decisions', () async {
        final h = _Harness();
        h.pull.handler = (params) async => params.resolutions == null
            ? const PullConflicts([_bothModified, _deletedHere])
            : const PullApplied(added: 0, updated: 1, deleted: 1, changedRequestIds: [11], deletedRequestIds: [12]);
        await h.load();

        expect(await h.vm.pull(), isTrue);

        expect(h.vm.conflicts, [_bothModified, _deletedHere]);
        expect(h.vm.choices, {'r1': ConflictChoice.local, 'r2': ConflictChoice.local});
        expect(h.pull.calls.single.resolutions, isNull);
        expect(h.replaced, isEmpty);

        h.vm.setChoice('r2', ConflictChoice.remote);
        expect(h.vm.choiceFor('r2'), ConflictChoice.remote);
        expect(await h.vm.applyResolutions(), isTrue);

        expect(h.pull.calls, hasLength(2));
        expect(h.pull.calls.last.collectionId, 7);
        expect(h.pull.calls.last.resolutions, {'r1': ConflictChoice.local, 'r2': ConflictChoice.remote});
        expect(h.vm.conflicts, isEmpty);
        expect(h.vm.choices, isEmpty);
        expect(h.vm.infoMessage, 'Pulled from GitHub: 1 updated, 1 deleted.');
      });

      test('applying resolutions that reveal new conflicts keeps asking', () async {
        final h = _Harness();
        h.pull.handler = (_) async => const PullConflicts([_bothModified]);
        await h.load();
        await h.vm.pull();
        h.vm.setChoice('r1', ConflictChoice.remote);

        await h.vm.applyResolutions();

        expect(h.vm.conflicts, [_bothModified]);
        expect(h.vm.choiceFor('r1'), ConflictChoice.local);
      });

      test('cancelling drops the conflicts without pulling again', () async {
        final h = _Harness();
        h.pull.handler = (_) async => const PullConflicts([_bothModified]);
        await h.load();
        await h.vm.pull();

        h.vm.cancelConflicts();

        expect(h.vm.conflicts, isEmpty);
        expect(h.vm.choices, isEmpty);
        expect(h.pull.calls, hasLength(1));
        expect(h.replaced, isEmpty);
      });

      test('an up-to-date pull says so and touches no tabs', () async {
        final h = _Harness();
        h.pull.handler = (_) async => const PullUpToDate();
        await h.load();

        await h.vm.pull();

        expect(h.vm.infoMessage, 'Already up to date.');
        expect(h.replaced, isEmpty);
      });
    });

    group('onRequestsReplaced', () {
      test('fires with the changed and deleted ids after a pull applied changes', () async {
        final h = _Harness();
        h.pull.handler = (_) async => const PullApplied(
              added: 0,
              updated: 2,
              deleted: 1,
              changedRequestIds: [4, 5],
              deletedRequestIds: [6],
            );
        await h.load();

        await h.vm.pull();

        expect(h.replaced, [
          [[4, 5], [6]],
        ]);
      });

      test('fires after a discard and after a branch switch', () async {
        final h = _Harness();
        h.discard.handler = (_) async => const ApplyOutcome(collectionId: 7, changedRequestIds: [1], deletedRequestIds: [2]);
        h.switchBranch.handler = (params) async {
          h.linked = _link(branch: params.branch);
          return const ApplyOutcome(collectionId: 7, changedRequestIds: [3], deletedRequestIds: [4]);
        };
        await h.load();

        await h.vm.discard();
        await h.vm.switchBranch('develop');

        expect(h.replaced, [
          [[1], [2]],
          [[3], [4]],
        ]);
        expect(h.vm.link?.branch, 'develop');
        expect(h.vm.infoMessage, 'Switched to develop.');
      });

      test('stays quiet when a branch switch is refused', () async {
        final h = _Harness();
        h.switchBranch.handler = (_) => throw const GitUncommittedChangesException();
        await h.load();

        expect(await h.vm.switchBranch('develop'), isFalse);

        expect(h.replaced, isEmpty);
        expect(h.vm.errorMessage, contains('Push or discard them first'));
        expect(h.vm.link?.branch, 'main');
      });

      test('still fires when the dialog closed while the pull was running', () async {
        final h = _Harness(autoDispose: false);
        final gate = Completer<PullResult>();
        h.pull.handler = (_) => gate.future;
        await h.load();

        final pending = h.vm.pull();
        h.vm.dispose();
        gate.complete(const PullApplied(added: 0, updated: 1, deleted: 0, changedRequestIds: [5]));
        await pending;

        expect(h.replaced, [
          [[5], <int>[]],
        ]);
      });
    });

    group('commit and push', () {
      test('sends the trimmed message, remembers the push and resets the message', () async {
        final h = _Harness();
        h.changes = const [_listUsers, _newFolder];
        h.commit.handler = (_) async {
          h.changes = const [];
          return _pushed;
        };
        await h.load();
        expect(h.vm.canCommit, isTrue);
        h.vm.commitMessage = '  Point users at v2  ';

        expect(await h.vm.commitPush(), isTrue);

        expect(h.commit.calls.single.collectionId, 7);
        expect(h.commit.calls.single.message, 'Point users at v2');
        expect(h.vm.lastPush?.commitSha, 'abcdef1234567');
        expect(h.vm.commitMessage, 'Update Users API');
        expect(h.vm.localChanges, isEmpty);
        expect(h.vm.canCommit, isFalse);
        expect(h.vm.needsPull, isFalse);
      });

      test('falls back to the default message when it was cleared', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        h.commit.handler = (_) async => _pushed;
        await h.load();
        h.vm.commitMessage = '   ';

        await h.vm.commitPush();

        // The default is written from what changed (before, it was only "Update <collection>").
        expect(h.commit.calls.single.message, 'Change 1 request in Users API\n\n- List users');
      });

      test('the default message follows the changes until the person edits it', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        h.commit.handler = (_) async => _pushed;
        await h.load();
        expect(h.vm.commitMessage, 'Change 1 request in Users API\n\n- List users');

        h.changes = const [_listUsers, _newFolder, _deleteUser];
        await h.vm.refresh();
        expect(
          h.vm.commitMessage,
          'Add 1 folder, change 1 request, remove 1 request in Users API\n\n- List users\n- Admin\n- Delete user',
          reason: 'untouched, so it keeps up with the changes',
        );

        h.vm.commitMessage = 'Point users at v2';
        h.changes = const [_listUsers];
        await h.vm.refresh();
        expect(h.vm.commitMessage, 'Point users at v2', reason: 'what the person wrote is theirs');

        h.vm.commitMessage = '';
        await h.vm.commitPush();
        expect(h.commit.calls.single.message, 'Change 1 request in Users API\n\n- List users', reason: 'cleared: back to the default');
      });

      test('cannot commit without changes, without write access or while busy', () async {
        final h = _Harness();
        await h.load();
        expect(h.vm.canCommit, isFalse);

        h.changes = const [_listUsers];
        h.remoteInfo = _readOnlyRepo;
        await h.vm.refresh(checkRemote: true);
        expect(h.vm.hasLocalChanges, isTrue);
        expect(h.vm.canPush, isFalse);
        expect(h.vm.canCommit, isFalse);

        h.remoteInfo = _writableRepo;
        await h.vm.refresh(checkRemote: true);
        expect(h.vm.canCommit, isTrue);

        final gate = Completer<PullResult>();
        h.pull.handler = (_) => gate.future;
        final pulling = h.vm.pull();
        expect(h.vm.canCommit, isFalse);
        gate.complete(const PullUpToDate());
        await pulling;
      });

      test('the known read-only answer survives a local-only refresh', () async {
        final h = _Harness()..remoteInfo = _readOnlyRepo;
        await h.load();
        expect(h.vm.canPush, isFalse);

        await h.vm.refresh();

        expect(h.vm.canPush, isFalse);
        expect(h.vm.repoInfo?.isPrivate, isTrue);
      });
    });

    group('busy state', () {
      test('is on with a label while an action runs, and a second action is refused', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        final gate = Completer<PullResult>();
        h.pull.handler = (_) => gate.future;
        await h.load();

        final pulling = h.vm.pull();
        expect(h.vm.isBusy, isTrue);
        expect(h.vm.busyLabel, 'Pulling…');

        expect(await h.vm.commitPush(), isFalse);
        expect(h.commit.calls, isEmpty);

        gate.complete(const PullUpToDate());
        await pulling;
        expect(h.vm.isBusy, isFalse);
        expect(h.vm.busyLabel, isNull);
      });

      test('a list load may run next to another action', () async {
        final h = _Harness();
        final gate = Completer<PullResult>();
        h.pull.handler = (_) => gate.future;
        h.history.handler = (_) async => const [];
        await h.load();

        final pulling = h.vm.pull();
        expect(await h.vm.loadHistory(), isTrue);
        expect(h.vm.isBusy, isTrue);

        gate.complete(const PullUpToDate());
        await pulling;
        expect(h.vm.isBusy, isFalse);
      });

      test('notifies listeners when it starts and when it ends', () async {
        final h = _Harness();
        await h.load();
        final busyStates = <bool>[];
        h.vm.addListener(() => busyStates.add(h.vm.isBusy));

        await h.vm.refresh();

        expect(busyStates.first, isTrue);
        expect(busyStates.last, isFalse);
      });
    });

    group('connect', () {
      test('normalises the folder, trims the branch and hands a parsed repository to the use case', () async {
        final h = _Harness()..links.link = null;
        h.connect.handler = (params) async {
          h.linked = _link(branch: params.branch, basePath: params.basePath);
          return h.linked!;
        };
        await h.load();

        final ok = await h.vm.connect(
          repository: 'https://github.com/acme/api.git',
          branch: '  develop  ',
          basePath: ' /apis\\billing/ ',
        );

        expect(ok, isTrue);
        final params = h.connect.calls.single;
        expect(params.collectionId, 7);
        expect(params.repo, _repo);
        expect(params.branch, 'develop');
        expect(params.basePath, 'apis/billing');
        expect(params.includeSecrets, isFalse);
        expect(h.vm.link?.basePath, 'apis/billing');
        expect(h.vm.infoMessage, 'Connected to acme/api.');
      });

      test('an empty branch is left for the use case to replace with the repository default', () async {
        final h = _Harness()..links.link = null;
        h.connect.handler = (_) async => _link();
        await h.load();

        await h.vm.connect(repository: 'acme/api', branch: '   ');

        expect(h.connect.calls.single.branch, isEmpty);
      });

      test('passes the credentials switch through', () async {
        final h = _Harness()..links.link = null;
        h.connect.handler = (_) async => _link(includeSecrets: true);
        await h.load();

        await h.vm.connect(repository: 'acme/api', includeSecrets: true);

        expect(h.connect.calls.single.includeSecrets, isTrue);
      });

      test('refuses an unusable repository without calling the use case', () async {
        final h = _Harness()..links.link = null;
        await h.load();

        expect(await h.vm.connect(repository: 'not a repo'), isFalse);

        expect(h.connect.calls, isEmpty);
        expect(h.vm.errorMessage, 'Enter the repository as owner/repo or paste its GitHub URL.');
      });

      test('explains an occupied folder in plain language', () async {
        final h = _Harness()..links.link = null;
        h.connect.handler = (_) => throw const GitPathOccupiedException('apis/users');
        await h.load();

        await h.vm.connect(repository: 'acme/api', basePath: 'apis/users');

        expect(h.vm.errorMessage, contains('apis/users'));
        expect(h.vm.errorMessage, contains('Clone it instead'));
        expect(h.vm.link, isNull);
      });

      test('repositoryError only complains about non-empty invalid input', () {
        expect(GitOperationViewModel.repositoryError(''), isNull);
        expect(GitOperationViewModel.repositoryError('acme/api'), isNull);
        expect(GitOperationViewModel.repositoryError('git@github.com:acme/api.git'), isNull);
        expect(GitOperationViewModel.repositoryError('acme'), isNotNull);
      });
    });

    group('token', () {
      test('saveToken trims it, verifies it and remembers who it belongs to', () async {
        final h = _Harness();
        h.credentials.token = null;
        await h.load();
        expect(h.vm.hasToken, isFalse);

        expect(await h.vm.saveToken('  ghp_new  '), isTrue);

        expect(h.saveToken.calls.single.token, 'ghp_new');
        expect(h.saveToken.calls.single.provider, GitProvider.github);
        expect(h.vm.verifiedLogin, 'octocat');
        expect(h.vm.hasToken, isTrue);
      });

      test('a rejected token is reported and not remembered', () async {
        final h = _Harness();
        h.credentials.token = null;
        h.saveToken.handler = (_) => throw _rejectedToken;
        await h.load();

        expect(await h.vm.saveToken('ghp_bad'), isFalse);

        expect(h.vm.errorMessage, startsWith('GitHub rejected the saved token'));
        expect(h.vm.verifiedLogin, isNull);
        expect(h.vm.hasToken, isFalse);
      });

      test('what is saved is read back after a rejection: gone when it was removed', () async {
        final h = _Harness();
        h.saveToken.handler = (_) async {
          h.credentials.token = null;
          throw _rejectedToken;
        };
        await h.load();
        expect(h.vm.hasToken, isTrue);

        await h.vm.saveToken('ghp_bad');

        expect(h.vm.hasToken, isFalse);
        expect(h.vm.verifiedLogin, isNull);
      });

      test('what is saved is read back after a rejection: kept when the previous token was restored', () async {
        final h = _Harness();
        h.saveToken.handler = (_) => throw _rejectedToken;
        await h.load();

        await h.vm.saveToken('ghp_bad');

        expect(h.vm.hasToken, isTrue);
        expect(h.vm.verifiedLogin, isNull);
      });

      test('an empty token never reaches the use case', () async {
        final h = _Harness();

        expect(await h.vm.saveToken('   '), isFalse);

        expect(h.saveToken.calls, isEmpty);
        expect(h.vm.errorMessage, 'Paste your GitHub token first.');
      });

      test('replacing the token of a linked collection checks the remote again', () async {
        final h = _Harness();
        await h.load();
        h.status.calls.clear();
        h.remoteInfo = _readOnlyRepo;

        await h.vm.saveToken('ghp_new');

        expect(h.status.calls.map((c) => c.checkRemote), [true]);
        expect(h.vm.canPush, isFalse);
      });

      test('an unreadable credential store counts as no token', () async {
        final h = _Harness();
        h.credentials.readError = StateError('secure storage is blocked');

        await h.load();

        expect(h.vm.hasToken, isFalse);
        expect(h.vm.errorMessage, isNull);
      });
    });

    group('branches', () {
      test('an empty name never reaches the use case', () async {
        final h = _Harness();
        await h.load();

        expect(await h.vm.createBranch('   '), isFalse);

        expect(h.createBranch.calls, isEmpty);
        expect(h.vm.errorMessage, 'Enter a branch name.');
      });

      test('a name the use case refuses is explained in its own words', () async {
        final h = _Harness();
        h.createBranch.handler = (_) => throw const GitSyncException('"a b" is not a valid branch name.');
        await h.load();

        expect(await h.vm.createBranch('a b'), isFalse);

        expect(h.vm.errorMessage, '"a b" is not a valid branch name.');
        expect(h.vm.link?.branch, 'main');
      });

      test('a new branch is created from the current one and adopted', () async {
        final h = _Harness();
        h.listBranches.handler = (_) async => ['main'];
        h.createBranch.handler = (params) async {
          h.linked = _link(branch: params.branch);
          return h.linked!;
        };
        await h.load();
        await h.vm.loadBranches();

        expect(await h.vm.createBranch(' feature/login '), isTrue);

        expect(h.createBranch.calls.single.branch, 'feature/login');
        expect(h.createBranch.calls.single.collectionId, 7);
        expect(h.vm.link?.branch, 'feature/login');
        expect(h.vm.branches, ['main', 'feature/login']);
        expect(h.replaced, isEmpty);
      });

      test('lists are loaded once by ensure and again by load', () async {
        final h = _Harness();
        h.history.handler = (_) async => [
              GitCommitInfo(sha: 'abcdef123456', message: 'Fix\n\nbody', authorName: 'Ann', date: DateTime(2026, 1, 1)),
            ];
        h.listBranches.handler = (_) async => ['main', 'develop'];
        h.contributors.handler = (_) async => const [GitContributor(login: 'ann', contributions: 3)];
        await h.load();

        await h.vm.ensureHistory();
        await h.vm.ensureHistory();
        await h.vm.ensureBranches();
        await h.vm.ensureContributors();
        await h.vm.loadHistory();

        expect(h.history.calls, hasLength(2));
        expect(h.history.calls.first.collectionId, 7);
        expect(h.vm.history.single.title, 'Fix');
        expect(h.listBranches.calls, hasLength(1));
        expect(h.vm.branches, ['main', 'develop']);
        expect(h.contributors.calls, hasLength(1));
        expect(h.vm.contributors.single.login, 'ann');
      });

      test('a list that is already on its way is not requested twice', () async {
        final h = _Harness();
        final gate = Completer<List<GitCommitInfo>>();
        h.history.handler = (_) => gate.future;
        await h.load();

        final first = h.vm.ensureHistory();
        final second = h.vm.ensureHistory();
        gate.complete(const []);
        await Future.wait([first, second]);

        expect(h.history.calls, hasLength(1));
        expect(h.vm.historyLoaded, isTrue);
      });

      test('a failed list load is tried again on the next visit', () async {
        final h = _Harness();
        h.history.handler = (_) => throw _rateLimited;
        await h.load();

        await h.vm.ensureHistory();
        expect(h.vm.errorMessage, contains('rate limit reached'));
        expect(h.vm.historyLoaded, isFalse);

        h.history.handler = (_) async => const [];
        await h.vm.ensureHistory();

        expect(h.history.calls, hasLength(2));
        expect(h.vm.historyLoaded, isTrue);
      });

      test('a pushed commit makes the history stale so the next visit reloads it', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        h.commit.handler = (_) async => _pushed;
        h.history.handler = (_) async => const [];
        await h.load();
        await h.vm.ensureHistory();

        await h.vm.commitPush();
        await h.vm.ensureHistory();

        expect(h.history.calls, hasLength(2));
      });
    });

    group('settings and disconnect', () {
      test('setIncludeSecrets updates the link', () async {
        final h = _Harness();
        h.updateSettings.handler = (params) async {
          h.linked = _link(includeSecrets: params.includeSecrets);
          return h.linked!;
        };
        await h.load();

        expect(await h.vm.setIncludeSecrets(true), isTrue);

        expect(h.updateSettings.calls.single.collectionId, 7);
        expect(h.updateSettings.calls.single.includeSecrets, isTrue);
        expect(h.vm.link?.includeSecrets, isTrue);
      });

      test('disconnect forgets the link and everything loaded for it', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        h.disconnect.handler = (_) async {};
        h.history.handler = (_) async => const [];
        await h.load();
        await h.vm.ensureHistory();

        expect(await h.vm.disconnect(), isTrue);

        expect(h.disconnect.calls.single, 7);
        expect(h.vm.link, isNull);
        expect(h.vm.status, isNull);
        expect(h.vm.localChanges, isEmpty);
        expect(h.vm.historyLoaded, isFalse);
        expect(h.vm.needsPull, isFalse);
        expect(h.vm.infoMessage, startsWith('Disconnected.'));
      });

      test('discard reloads the status and confirms', () async {
        final h = _Harness();
        h.changes = const [_listUsers];
        h.discard.handler = (_) async {
          h.changes = const [];
          return const ApplyOutcome(collectionId: 7);
        };
        await h.load();

        expect(await h.vm.discard(), isTrue);

        expect(h.discard.calls.single, 7);
        expect(h.vm.localChanges, isEmpty);
        expect(h.vm.infoMessage, 'Local changes discarded.');
      });
    });

    group('links', () {
      test('are handed to the browser, and a failure is reported inline', () async {
        final h = _Harness();

        await h.vm.openUrl('https://github.com/acme/api');
        expect(h.opened.single.toString(), 'https://github.com/acme/api');
        expect(h.vm.errorMessage, isNull);

        h.browserWorks = false;
        await h.vm.openUrl('https://github.com/acme/api/settings/access');
        expect(h.vm.errorMessage, contains('https://github.com/acme/api/settings/access'));
      });
    });
  });

  group('GitCloneViewModel', () {
    const users = DiscoveredCollection(basePath: 'apis/users', name: 'Users API');
    const billing = DiscoveredCollection(basePath: 'apis/billing', name: 'Billing');

    test('a single result is selected for the user', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [users];

      expect(await h.vm.discover(repository: 'acme/api'), isTrue);

      expect(h.discover.calls.single.repo, _repo);
      expect(h.discover.calls.single.branch, 'main');
      expect(h.vm.hasSearched, isTrue);
      expect(h.vm.found, [users]);
      expect(h.vm.selected, users);
    });

    test('several results wait for a choice; cloning uses the searched repository and folder', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [users, billing];
      h.clone.handler = (_) async => _link(collectionId: 42, basePath: 'apis/billing');

      await h.vm.discover(repository: 'https://github.com/acme/api', branch: 'develop');
      expect(h.vm.selected, isNull);
      expect(h.vm.canClone, isFalse);
      expect(await h.vm.clone(), isNull);
      expect(h.clone.calls, isEmpty);

      h.vm.select(billing);
      expect(h.vm.canClone, isTrue);
      final id = await h.vm.clone();

      expect(id, 42);
      final params = h.clone.calls.single;
      expect(params.repo, _repo);
      expect(params.branch, 'develop');
      expect(params.basePath, 'apis/billing');
      expect(params.includeSecrets, isFalse);
    });

    test('an empty repository is a result, not an error', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [];

      await h.vm.discover(repository: 'acme/api');

      expect(h.vm.hasSearched, isTrue);
      expect(h.vm.found, isEmpty);
      expect(h.vm.errorMessage, isNull);
    });

    test('editing the repository drops the results', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [users, billing];
      await h.vm.discover(repository: 'acme/api');
      h.vm.select(users);

      h.vm.resetSearch();

      expect(h.vm.found, isEmpty);
      expect(h.vm.selected, isNull);
      expect(h.vm.hasSearched, isFalse);
      expect(await h.vm.clone(), isNull);
    });

    test('failures become plain language and a failed search shows no results', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) => throw const GitNotFoundException('Repository acme/api not found, or your token cannot see it');

      expect(await h.vm.discover(repository: 'acme/api'), isFalse);

      expect(h.vm.errorMessage, 'Repository acme/api not found, or your token cannot see it.');
      expect(h.vm.hasSearched, isFalse);
    });

    test('a nothing-to-clone failure keeps the selection and reports itself', () async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [users];
      h.clone.handler = (_) => throw const GitNothingToCloneException('apis/users');
      await h.vm.discover(repository: 'acme/api');

      expect(await h.vm.clone(), isNull);

      expect(h.vm.errorMessage, 'No PostPilot collection found in "apis/users".');
      expect(h.vm.selected, users);
      expect(h.vm.isBusy, isFalse);
    });

    test('an unusable repository is refused before any request', () async {
      final h = _CloneHarness();

      expect(await h.vm.discover(repository: 'nope'), isFalse);

      expect(h.discover.calls, isEmpty);
      expect(h.vm.errorMessage, isNotNull);
    });

    test('a token can be saved from here too', () async {
      final h = _CloneHarness();
      h.credentials.token = null;
      await h.vm.load();
      expect(h.vm.hasToken, isFalse);

      await h.vm.saveToken('ghp_abc');

      expect(h.vm.hasToken, isTrue);
      expect(h.vm.verifiedLogin, 'octocat');
    });
  });

  group('LinkedCollectionsViewModel', () {
    test('mirrors the linked collection ids of the repository', () async {
      final links = _FakeLinks();
      final vm = LinkedCollectionsViewModel(links);
      addTearDown(vm.dispose);
      var notified = 0;
      vm.addListener(() => notified++);
      expect(vm.isLinked(3), isFalse);

      links.ids.add({3, 5});
      await pumpEventQueue();

      expect(vm.linkedIds, {3, 5});
      expect(vm.isLinked(3), isTrue);
      expect(vm.isLinked(4), isFalse);
      expect(notified, 1);

      links.ids.add({5});
      await pumpEventQueue();
      expect(vm.isLinked(3), isFalse);
    });
  });

  group('formatting', () {
    final now = DateTime(2026, 6, 15, 12);

    test('relativeTime speaks in the unit that fits', () {
      String at(Duration ago) => relativeTime(now.subtract(ago), now: now);

      expect(at(const Duration(seconds: 10)), 'just now');
      expect(at(const Duration(seconds: -30)), 'just now');
      expect(at(const Duration(seconds: 50)), '1 min ago');
      expect(at(const Duration(minutes: 5)), '5 min ago');
      expect(at(const Duration(minutes: 59)), '59 min ago');
      expect(at(const Duration(hours: 3)), '3 h ago');
      expect(at(const Duration(hours: 30)), 'yesterday');
      expect(at(const Duration(days: 3)), '3 days ago');
      expect(at(const Duration(days: 10)), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('formatConflictValue shows absent, empty, structured and long values readably', () {
      expect(formatConflictValue(null), '(not set)');
      expect(formatConflictValue(''), '(empty)');
      expect(formatConflictValue('GET'), 'GET');
      expect(formatConflictValue(42), '42');
      expect(formatConflictValue(true), 'true');
      expect(formatConflictValue({'a': 1, 'b': [1, 2]}), '{"a":1,"b":[1,2]}');
      expect(formatConflictValue('x' * 300), '${'x' * 160}…');
      expect(formatConflictValue('abcdef', maxLength: 3), 'abc…');
    });

    test('formatConflictValue never cuts an emoji in half', () {
      final text = '${'a' * 159}😀tail';

      expect(formatConflictValue(text), '${'a' * 159}…');
    });

    test('shortSha keeps seven characters', () {
      expect(shortSha('abcdef1234567'), 'abcdef1');
      expect(shortSha('abc'), 'abc');
    });
  });

  group('sync dialog', () {
    testWidgets('an unlinked collection shows the connect form and connects', (tester) async {
      final h = _Harness()..links.link = null;
      h.connect.handler = (params) async {
        h.linked = _link(branch: params.branch);
        return h.linked!;
      };
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('Git sync'), findsOneWidget);
      expect(find.text('Users API'), findsOneWidget);
      expect(find.text('GitHub access token'), findsOneWidget);
      expect(find.text('A token is saved on this device'), findsOneWidget);
      expect(find.text('Create a token'), findsOneWidget);
      expect(find.textContaining('Contents: Read and write'), findsOneWidget);
      expect(_button(tester, 'Connect').onPressed, isNull);
      await _scrollTo(tester, find.textContaining('would be visible to everyone'));
      expect(find.textContaining('would be visible to everyone'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'nope');
      await tester.pump();
      expect(find.text('Enter the repository as owner/repo or paste its GitHub URL.'), findsOneWidget);
      expect(_button(tester, 'Connect').onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/api');
      await tester.enterText(find.widgetWithText(TextField, 'Folder in repository (optional)'), 'apis/users');
      await tester.pump();
      expect(_button(tester, 'Connect').onPressed, isNotNull);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final params = h.connect.calls.single;
      expect(params.repo.fullName, 'acme/api');
      expect(params.branch, 'main');
      expect(params.basePath, 'apis/users');
      expect(params.includeSecrets, isFalse);
      expect(find.text('acme/api'), findsOneWidget);
      expect(find.text('Connected to acme/api.'), findsOneWidget);
      expect(find.text('Changes'), findsOneWidget);
    });

    testWidgets('saving a token shows who it belongs to', (tester) async {
      final h = _Harness()
        ..links.link = null
        ..credentials.token = null;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      expect(find.text('No token saved yet'), findsOneWidget);
      expect(_button(tester, 'Save token').onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'ghp_pasted');
      await tester.pump();
      await tester.tap(find.text('Save token'));
      await tester.pumpAndSettle();

      expect(h.saveToken.calls.single.token, 'ghp_pasted');
      expect(find.text('Signed in to GitHub as octocat'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    });

    testWidgets('a rejected token is explained inline', (tester) async {
      final h = _Harness()..links.link = null;
      h.saveToken.handler = (_) => throw _rejectedToken;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.enterText(find.byType(TextField).first, 'ghp_bad');
      await tester.pump();
      await tester.tap(find.text('Save token'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GitHub rejected the saved token'), findsOneWidget);
      expect(find.text('Bad credentials'), findsNothing);
    });

    testWidgets('a failed first load offers a retry instead of the connect form', (tester) async {
      final h = _Harness();
      h.status.handler = (_) => throw StateError('locked');
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Repository'), findsNothing);
      expect(find.text('Something went wrong — please try again.'), findsOneWidget);

      h.status.handler = (_) async => GitStatus(link: _link(), localChanges: const []);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('acme/api'), findsOneWidget);
    });

    testWidgets('a linked collection shows the repository, branch, status and the changes', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers, _newFolder, _deleteUser];
      h.remoteInfo = _writableRepo;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('acme/api'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('3 local changes'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Synced 5 min ago'), findsOneWidget);
      expect(find.text('Changes (3)'), findsOneWidget);
      for (final tab in ['History', 'Branches', 'Team', 'Settings']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('List users'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);
      expect(find.text('Request · url, headers'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      // The prefilled commit message is written from the changes shown above it.
      expect(
        find.widgetWithText(TextField, 'Add 1 folder, change 1 request, remove 1 request in Users API\n\n- List users\n- Admin\n- Delete user'),
        findsOneWidget,
      );
      expect(_button(tester, 'Commit & push').onPressed, isNotNull);
      expect(_button(tester, 'Discard changes').onPressed, isNotNull);
      expect(find.textContaining('read-only access'), findsNothing);
    });

    testWidgets('an unchanged collection is "Up to date" and cannot be committed', (tester) async {
      final h = _Harness();
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('Up to date'), findsOneWidget);
      expect(find.textContaining('Everything is in sync'), findsOneWidget);
      expect(_button(tester, 'Commit & push').onPressed, isNull);
      expect(_button(tester, 'Discard changes').onPressed, isNull);
      expect(_button(tester, 'Pull').onPressed, isNotNull);
    });

    testWidgets('"Up to date" is only claimed once GitHub has answered', (tester) async {
      final h = _Harness();
      h.status.handler = (params) async {
        if (params.checkRemote) throw _rateLimited;
        return GitStatus(link: _link(), localChanges: const []);
      };
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('Up to date'), findsNothing);
      expect(find.text('No local changes'), findsOneWidget);
      expect(find.textContaining('rate limit reached'), findsOneWidget);
    });

    testWidgets('a viewer gets a banner and cannot push', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.remoteInfo = _readOnlyRepo;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.textContaining('read-only access to this repository'), findsOneWidget);
      expect(_button(tester, 'Commit & push').onPressed, isNull);
    });

    testWidgets('a moved remote shows "Behind remote" and the pull banner', (tester) async {
      final h = _Harness()..remoteBehind = true;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      expect(find.text('Behind remote — pull'), findsOneWidget);
      expect(find.textContaining('The remote branch has new commits'), findsOneWidget);
    });

    testWidgets('commit & push sends the message and shows the short sha', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.commit.handler = (_) async {
        h.changes = const [];
        return _pushed;
      };
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.enterText(find.widgetWithText(TextField, 'Change 1 request in Users API\n\n- List users'), 'Point users at v2');
      await tester.pump();
      await tester.tap(find.text('Commit & push'));
      await tester.pumpAndSettle();

      expect(h.commit.calls.single.message, 'Point users at v2');
      expect(find.text('abcdef1'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Update Users API'), findsOneWidget);

      await tester.tap(find.text('abcdef1'));
      await tester.pump();
      expect(h.opened.single.toString(), 'https://github.com/acme/api/commit/abcdef1234567');
    });

    testWidgets('a rejected push explains it and the pull banner appears', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.commit.handler = (_) => throw const GitNotFastForwardException('ref moved');
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.tap(find.text('Commit & push'));
      await tester.pumpAndSettle();

      expect(find.text('Someone pushed since you last pulled. Pull first, then push again.'), findsOneWidget);
      expect(find.text('Behind remote — pull'), findsOneWidget);
    });

    testWidgets('discard asks first', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.discard.handler = (_) async {
        h.changes = const [];
        return const ApplyOutcome(collectionId: 7, changedRequestIds: [9]);
      };
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Discard local changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.discard.calls, isEmpty);

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(h.discard.calls.single, 7);
      expect(h.replaced.single, [[9], <int>[]]);
      expect(find.text('Local changes discarded.'), findsOneWidget);
    });

    testWidgets('pull conflicts open the resolver; the choices are applied on "Apply merge"', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers];
      h.pull.handler = (params) async => params.resolutions == null
          ? const PullConflicts([_bothModified, _deletedHere])
          : const PullApplied(added: 0, updated: 1, deleted: 0, changedRequestIds: [3]);
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.tap(find.text('Pull'));
      await tester.pumpAndSettle();

      expect(find.text('Resolve conflicts'), findsOneWidget);
      expect(find.text('2 items were changed both here and on GitHub. Choose which version to keep for each.'),
          findsOneWidget);
      expect(find.text('List users'), findsWidgets);
      expect(find.text('url'), findsOneWidget);
      expect(find.text('/v1/users'), findsOneWidget);
      expect(find.text('/v2/users'), findsOneWidget);
      expect(find.text('/users'), findsOneWidget);
      expect(find.text('You deleted this here, but it was changed on GitHub.'), findsOneWidget);
      expect(find.text('Every field above keeps your value.'), findsOneWidget);
      expect(find.text('The item stays deleted.'), findsOneWidget);

      await tester.tap(find.text('Keep theirs').at(1));
      await tester.pump();
      expect(find.text('The item is restored with their changes.'), findsOneWidget);
      expect(h.vm.choiceFor('r2'), ConflictChoice.remote);
      expect(h.vm.choiceFor('r1'), ConflictChoice.local);

      await tester.tap(find.text('Apply merge'));
      await tester.pumpAndSettle();

      expect(h.pull.calls.last.resolutions, {'r1': ConflictChoice.local, 'r2': ConflictChoice.remote});
      expect(find.text('Resolve conflicts'), findsNothing);
      expect(find.text('Pulled from GitHub: 1 updated.'), findsOneWidget);
      expect(h.replaced.single, [[3], <int>[]]);
    });

    testWidgets('cancelling the resolver leaves everything untouched', (tester) async {
      final h = _Harness();
      h.pull.handler = (_) async => const PullConflicts([_bothModified]);
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);

      await tester.tap(find.text('Pull'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Resolve conflicts'), findsNothing);
      expect(h.vm.conflicts, isEmpty);
      expect(h.pull.calls, hasLength(1));
      expect(h.replaced, isEmpty);
    });

    testWidgets('the history tab loads on first visit and opens a commit', (tester) async {
      final h = _Harness();
      h.history.handler = (_) async => [
            GitCommitInfo(
              sha: '1234567890abcdef',
              message: 'Point users at v2\n\nlonger text',
              authorName: 'Ann',
              date: DateTime.now().subtract(const Duration(hours: 2)),
            ),
          ];
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      expect(h.history.calls, isEmpty);

      await _openTab(tester, 'History');

      expect(h.history.calls, hasLength(1));
      expect(find.text('1234567'), findsOneWidget);
      expect(find.text('Point users at v2'), findsOneWidget);
      expect(find.text('Ann · 2 h ago'), findsOneWidget);

      await tester.tap(find.text('Point users at v2'));
      await tester.pump();
      expect(h.opened.single.toString(), 'https://github.com/acme/api/commit/1234567890abcdef');

      await _openTab(tester, 'Changes');
      await _openTab(tester, 'History');
      expect(h.history.calls, hasLength(1));
    });

    testWidgets('the branches tab switches and creates branches', (tester) async {
      final h = _Harness();
      h.listBranches.handler = (_) async => ['main', 'develop'];
      h.switchBranch.handler = (params) async {
        h.linked = _link(branch: params.branch);
        return const ApplyOutcome(collectionId: 7);
      };
      h.createBranch.handler = (params) async {
        h.linked = _link(branch: params.branch);
        return h.linked!;
      };
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      await _openTab(tester, 'Branches');

      expect(find.text('Current branch'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('develop'), findsOneWidget);

      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(h.switchBranch.calls.single.branch, 'develop');
      expect(find.text('Switched to develop.'), findsOneWidget);

      await tester.tap(find.text('New branch from current'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'feature/x');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(h.createBranch.calls.single.branch, 'feature/x');
    });

    testWidgets('a branch switch blocked by local changes says so', (tester) async {
      final h = _Harness();
      h.listBranches.handler = (_) async => ['main', 'develop'];
      h.switchBranch.handler = (_) => throw const GitUncommittedChangesException();
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      await _openTab(tester, 'Branches');

      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Push or discard them first'), findsOneWidget);
    });

    testWidgets('the team tab explains access, links to GitHub and lists contributors', (tester) async {
      final h = _Harness();
      h.remoteInfo = _readOnlyRepo;
      h.contributors.handler = (_) async => const [
            GitContributor(login: 'ann', contributions: 12),
            GitContributor(login: 'bob', contributions: 1, profileUrl: 'https://github.com/bob'),
          ];
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      await _openTab(tester, 'Team');

      expect(find.text('Access to this collection is managed on GitHub'), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);
      expect(find.text('Private repository'), findsOneWidget);
      expect(find.text('ann'), findsOneWidget);
      expect(find.text('12 commits'), findsOneWidget);
      expect(find.text('1 commit'), findsOneWidget);

      await tester.tap(find.text('Manage access on GitHub'));
      await tester.pump();
      expect(h.opened.last.toString(), 'https://github.com/acme/api/settings/access');

      await tester.tap(find.text('ann'));
      await tester.pump();
      expect(h.opened.last.toString(), 'https://github.com/ann');
    });

    testWidgets('the settings tab toggles credentials after a warning and disconnects after a confirmation',
        (tester) async {
      final h = _Harness();
      h.updateSettings.handler = (params) async {
        h.linked = _link(includeSecrets: params.includeSecrets);
        return h.linked!;
      };
      h.disconnect.handler = (_) async {};
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      await _openTab(tester, 'Settings');

      expect(find.text('Repository root'), findsOneWidget);
      expect(find.text('Update token'), findsOneWidget);
      expect(find.textContaining('would be visible to everyone'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Include credentials?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.updateSettings.calls, isEmpty);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Include credentials'));
      await tester.pumpAndSettle();
      expect(h.updateSettings.calls.single.includeSecrets, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // The settings list builds lazily, so Disconnect may sit below the built
      // range until it is scrolled to, as it is for a user.
      await tester.scrollUntilVisible(
        find.text('Disconnect'),
        200,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect from Git'), findsOneWidget);
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();

      expect(h.disconnect.calls.single, 7);
      expect(find.text('Repository'), findsOneWidget);
      expect(find.textContaining('Disconnected.'), findsOneWidget);
    });

    testWidgets('updating the token from the settings tab verifies it', (tester) async {
      final h = _Harness();
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm);
      await _openTab(tester, 'Settings');

      await tester.enterText(find.byType(TextField).first, 'ghp_rotated');
      await tester.pump();
      await _tapText(tester, 'Save token');

      expect(h.saveToken.calls.single.token, 'ghp_rotated');
      expect(find.text('Signed in to GitHub as octocat'), findsOneWidget);
    });

    testWidgets('everything fits a phone-sized dialog', (tester) async {
      final h = _Harness();
      h.changes = const [_listUsers, _newFolder, _deleteUser];
      h.remoteInfo = _writableRepo;
      h.listBranches.handler = (_) async => ['main', 'a-rather-long-branch-name/with/segments'];
      h.history.handler = (_) async => [
            GitCommitInfo(
              sha: '1234567890abcdef',
              message: 'A very long commit title that will not fit on one line of a phone screen',
              authorName: 'Ann with a long name',
              date: DateTime.now(),
            ),
          ];
      h.contributors.handler = (_) async => const [GitContributor(login: 'ann-with-a-long-login', contributions: 12)];
      h.pull.handler = (_) async => const PullConflicts([_bothModified, _deletedHere]);
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm, size: const Size(360, 640));

      for (final tab in ['History', 'Branches', 'Team', 'Settings', 'Changes (3)']) {
        await _openTab(tester, tab);
      }
      await _tapText(tester, 'Pull');
      expect(find.text('Resolve conflicts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the connect form and the clone panel fit a phone-sized dialog', (tester) async {
      final h = _Harness()..links.link = null;
      await tester.runAsync(h.load);
      await _pumpSync(tester, h.vm, size: const Size(360, 640));
      await _scrollTo(tester, find.widgetWithText(TextField, 'Repository'));
      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'nope');
      await tester.pump();
      expect(tester.takeException(), isNull);

      final clone = _CloneHarness();
      clone.discover.handler = (_) async => const [
            DiscoveredCollection(basePath: 'apis/users/with/a/long/path', name: 'Users API with a long name'),
            DiscoveredCollection(basePath: '', name: 'Root'),
          ];
      await _pumpClone(tester, clone.vm, size: const Size(360, 640), onCloned: (_) {});
      await _scrollTo(tester, find.widgetWithText(TextField, 'Repository'));
      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/api');
      await tester.pump();
      await _tapText(tester, 'Find collections');
      await _scrollTo(tester, find.text('Users API with a long name'));
      expect(find.text('Users API with a long name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('clone dialog', () {
    testWidgets('finds the collections of a repository and clones the chosen one', (tester) async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [
            DiscoveredCollection(basePath: 'apis/users', name: 'Users API'),
            DiscoveredCollection(basePath: 'apis/billing', name: 'Billing'),
          ];
      h.clone.handler = (_) async => _link(collectionId: 42, basePath: 'apis/billing');
      await tester.runAsync(h.vm.load);
      int? cloned;
      await _pumpClone(tester, h.vm, onCloned: (id) => cloned = id);

      expect(find.text('Clone from Git'), findsOneWidget);
      expect(find.text('A token is saved on this device'), findsOneWidget);
      expect(_button(tester, 'Find collections').onPressed, isNull);
      expect(_button(tester, 'Clone').onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/api');
      await tester.pump();
      await tester.tap(find.text('Find collections'));
      await tester.pumpAndSettle();

      expect(h.discover.calls.single.repo.fullName, 'acme/api');
      expect(find.text('2 collections found'), findsOneWidget);
      expect(find.text('Users API'), findsOneWidget);
      expect(find.text('apis/billing'), findsOneWidget);
      expect(_button(tester, 'Clone').onPressed, isNull);

      await _tapText(tester, 'Billing');
      expect(_button(tester, 'Clone').onPressed, isNotNull);

      await _tapText(tester, 'Clone');

      expect(cloned, 42);
      expect(h.clone.calls.single.basePath, 'apis/billing');
    });

    testWidgets('an empty repository says so, and editing the repository hides stale results', (tester) async {
      final h = _CloneHarness();
      h.discover.handler = (_) async => const [];
      await tester.runAsync(h.vm.load);
      await _pumpClone(tester, h.vm, onCloned: (_) {});

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/api');
      await tester.pump();
      await tester.tap(find.text('Find collections'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No PostPilot collections were found'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/other');
      await tester.pump();
      expect(find.textContaining('No PostPilot collections were found'), findsNothing);
    });

    testWidgets('a failure is shown inline and nothing is cloned', (tester) async {
      final h = _CloneHarness();
      h.discover.handler = (_) => throw _rateLimited;
      await tester.runAsync(h.vm.load);
      await _pumpClone(tester, h.vm, onCloned: (_) {});

      await tester.enterText(find.widgetWithText(TextField, 'Repository'), 'acme/api');
      await tester.pump();
      await tester.tap(find.text('Find collections'));
      await tester.pumpAndSettle();

      expect(find.textContaining('rate limit reached'), findsOneWidget);
      expect(_button(tester, 'Clone').onPressed, isNull);
    });
  });

  group('link badge', () {
    testWidgets('appears only for linked collections', (tester) async {
      final links = _FakeLinks();
      final vm = LinkedCollectionsViewModel(links);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<LinkedCollectionsViewModel>.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Row(children: [GitLinkBadge(1), GitLinkBadge(2)])),
          ),
        ),
      );
      expect(find.byIcon(Icons.merge_type), findsNothing);

      links.ids.add({2});
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.merge_type), findsOneWidget);
      expect(find.byTooltip('Synced with Git'), findsOneWidget);
    });

    testWidgets('stays hidden when nothing provides the view model', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const Scaffold(body: GitLinkBadge(1))),
      );

      expect(find.byIcon(Icons.merge_type), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('reopenReplacedRequests', () {
    testWidgets('closes deleted tabs now and reopens changed ones after the next frame', (tester) async {
      final shell = ShellViewModel(_FakeRequests());
      addTearDown(shell.dispose);
      for (final id in [1, 2, 3, 4]) {
        shell.selectRequest(id);
      }
      shell.selectRequest(3);

      reopenReplacedRequests(shell, [2, 9], [1]);

      expect(shell.openRequestIds, [3, 4]);
      await tester.pump();
      expect(shell.openRequestIds, [3, 4, 2]);
      expect(shell.selectedRequestId, 3);
    });

    testWidgets('does nothing for requests that are not open', (tester) async {
      final shell = ShellViewModel(_FakeRequests());
      addTearDown(shell.dispose);
      shell.selectRequest(5);

      reopenReplacedRequests(shell, [7], [8]);
      await tester.pump();

      expect(shell.openRequestIds, [5]);
      expect(shell.selectedRequestId, 5);
    });

    testWidgets('a deleted active tab is not selected again', (tester) async {
      final shell = ShellViewModel(_FakeRequests());
      addTearDown(shell.dispose);
      shell.selectRequest(1);
      shell.selectRequest(2);

      reopenReplacedRequests(shell, [1], [2]);
      await tester.pump();

      expect(shell.openRequestIds, [1]);
      expect(shell.selectedRequestId, 1);
    });
  });
}

ButtonStyleButton _button(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton)),
    );

Future<void> _openTab(WidgetTester tester, String label) => _tapText(tester, label);

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);

/// Scrolls [label] into view first: on a phone the tab bar and the forms scroll.
Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _pumpSync(WidgetTester tester, GitSyncViewModel vm, {Size size = const Size(1000, 900)}) =>
    _pumpDialog(
      tester,
      size,
      ChangeNotifierProvider<GitSyncViewModel>.value(
        value: vm,
        child: const GitSyncPanel(collectionId: 7, collectionName: 'Users API'),
      ),
    );

Future<void> _pumpClone(
  WidgetTester tester,
  GitCloneViewModel vm, {
  required ValueChanged<int> onCloned,
  Size size = const Size(1000, 900),
}) =>
    _pumpDialog(
      tester,
      size,
      ChangeNotifierProvider<GitCloneViewModel>.value(value: vm, child: GitClonePanel(onCloned: onCloned)),
    );

Future<void> _pumpDialog(WidgetTester tester, Size size, Widget content) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: Dialog(child: SizedBox(width: 760, height: 600, child: content))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
