import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/sync_engine.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_commit_push_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_contributors_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_create_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discard_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_disconnect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discover_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_history_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_list_branches_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_pull_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_save_token_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_status_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_switch_branch_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_update_link_settings_usecase.dart';

import 'fake_credentials_store.dart';
import 'fake_git_host.dart';
import 'fake_link_repository.dart';
import 'fake_local_store.dart';
import 'sync_fixtures.dart';

/// One user of the app: a private local database and link store, real use
/// cases, and a [FakeGitHost] shared with the other teammates.
class Teammate {
  final FakeGitHost host;
  final store = FakeLocalStore();
  final links = FakeLinkRepository();
  final credentials = FakeCredentialsStore();

  late final engine = SyncEngine(host, store);
  late final connect = GitConnectUseCase(links, host);
  late final clone = GitCloneUseCase(host, store, links, engine);
  late final discover = GitDiscoverUseCase(host, engine);
  late final status = GitStatusUseCase(links, host, engine);
  late final push = GitCommitPushUseCase(links, host, engine);
  late final pull = GitPullUseCase(links, store, host, engine);
  late final discard = GitDiscardUseCase(links, store, engine);
  late final listBranches = GitListBranchesUseCase(links, host);
  late final createBranch = GitCreateBranchUseCase(links, host);
  late final switchBranch = GitSwitchBranchUseCase(links, store, host, engine);
  late final contributors = GitContributorsUseCase(links, host);
  late final history = GitHistoryUseCase(links, host);
  late final updateSettings = GitUpdateLinkSettingsUseCase(links);
  late final disconnect = GitDisconnectUseCase(links);
  late final saveToken = GitSaveTokenUseCase(credentials, host);

  Teammate(this.host);

  Future<PushResult> pushAll(int collectionId, [String message = 'Update']) =>
      push(GitCommitPushParams(collectionId: collectionId, message: message));

  Future<PullResult> pullAll(int collectionId, [ConflictResolutions? resolutions]) =>
      pull(GitPullParams(collectionId: collectionId, resolutions: resolutions));

  Future<GitStatus> statusOf(int collectionId, {bool checkRemote = false}) =>
      status(GitStatusParams(collectionId: collectionId, checkRemote: checkRemote));

  Future<GitLink> linkOf(int collectionId) async => (await links.findByCollection(collectionId))!;

  SyncDoc doc(int collectionId, String uid) => store.doc(collectionId, uid)!;

  /// A local edit of some fields of a doc.
  void edit(int collectionId, String uid, Map<String, Object?> changes) =>
      store.upsert(collectionId, edited(doc(collectionId, uid), changes));

  Map<String, SyncDoc> docsOf(int collectionId) => store.collections[collectionId]!;
}
