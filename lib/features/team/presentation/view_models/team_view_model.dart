import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../domain/entities/cloud_collection_entity.dart';
import '../../domain/entities/cloud_folder_entity.dart';
import '../../domain/entities/cloud_request_entity.dart';
import '../../domain/entities/collection_invite_entity.dart';
import '../../domain/entities/collection_member_entity.dart';
import '../../domain/entities/member_role.dart';
import '../../domain/repositories/team_repository.dart';
import '../../domain/services/cloud_request_mapper.dart';
import '../../domain/services/send_error_message.dart';
import '../../domain/usecases/copy_cloud_collection_usecase.dart';

enum RequestSaveStatus { idle, saving, saved, failed }

enum _CollectionStream { members, folders, requests }

/// What the Send button needs. `SendRequestUseCase.call` fits it as is; its
/// extra named cancel-token parameter rules out the plain `UseCase` interface.
typedef SendRequest = Future<ApiResponseEntity> Function(ApiRequestEntity request, {ApiCancelToken? cancelToken});

final class TeamViewModel with ChangeNotifier {
  static const _autoSaveDelay = Duration(milliseconds: 500);

  final TeamRepository _repository;
  final SendRequest? _sendRequest;
  final UseCase<CopiedCollection, CopyCloudCollectionParams>? _copyCollection;

  /// [sendRequest] and [copyCollection] enable the Send button and "Copy to my
  /// collections"; without them those controls stay hidden.
  TeamViewModel(this._repository, {this._sendRequest, this._copyCollection});

  bool isLoading = false;
  bool loadFailed = false;
  String? errorMessage;

  List<CloudCollectionEntity> collections = [];
  List<CollectionInviteEntity> pendingInvites = [];

  int? selectedCollectionId;
  List<CollectionMemberEntity> members = [];
  List<CollectionInviteEntity> collectionInvites = [];
  List<CloudFolderEntity> folders = [];
  List<CloudRequestEntity> requests = [];

  RequestSaveStatus saveStatus = RequestSaveStatus.idle;

  /// State of the Send button of the open request editor.
  bool isSendingRequest = false;

  /// The last response of the open editor's request; null before the first
  /// send and after a failed one.
  ApiResponseEntity? sendResponse;

  /// Friendly text for the last failed send.
  String? sendError;
  ApiCancelToken? _sendToken;

  /// Bumped whenever an editor opens, so a send that outlives its editor can't
  /// show its result on the next request.
  int _sendGeneration = 0;

  bool isCopyingCollection = false;

  bool get canSendRequests => _sendRequest != null;
  bool get canCopyCollection => _copyCollection != null;

  /// Whether the editor has anything to show under the form.
  bool get hasSendResult => isSendingRequest || sendResponse != null || sendError != null;

  final Map<int, CloudRequestEntity> _pendingDrafts = {};
  final Map<int, CloudRequestEntity> _failedDrafts = {};

  /// Per request, the last state this editor knows the server holds. Saves
  /// send only the fields that differ from it, so a stale editor can't
  /// overwrite a teammate's edit to a field it never touched.
  final Map<int, CloudRequestEntity> _savedBases = {};
  Timer? _saveTimer;
  Future<void>? _saveInFlight;
  bool _disposed = false;

  StreamSubscription<List<CollectionMemberEntity>>? _membersSub;
  StreamSubscription<List<CloudFolderEntity>>? _foldersSub;
  StreamSubscription<List<CloudRequestEntity>>? _requestsSub;
  final Set<_CollectionStream> _loadedStreams = {};
  final Set<_CollectionStream> _failedStreams = {};

  /// Whether each live stream has delivered its first snapshot, so the UI can
  /// tell "still loading" from "genuinely empty".
  bool get membersLoaded => _loadedStreams.contains(_CollectionStream.members);
  bool get treeLoaded =>
      _loadedStreams.contains(_CollectionStream.folders) && _loadedStreams.contains(_CollectionStream.requests);

  /// True while any live stream of the selected collection is errored or
  /// closed; cleared when it delivers again or the collection is reloaded.
  bool get collectionSyncFailed => _failedStreams.isNotEmpty;

  bool get hasUnsavedRequestEdits => _pendingDrafts.isNotEmpty || _failedDrafts.isNotEmpty || _saveInFlight != null;

  Future<void> load() async {
    isLoading = true;
    loadFailed = false;
    errorMessage = null;
    notifyListeners();
    try {
      collections = await _repository.listMyCollections();
      pendingInvites = await _repository.listMyPendingInvites();
    } catch (e) {
      loadFailed = true;
      errorMessage = 'Failed to load teams';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<bool> createCollection(String name) async {
    try {
      final created = await _repository.createCollection(name);
      collections = [...collections, created];
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to create collection';
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameCollection(int collectionId, String name) async {
    try {
      await _repository.renameCollection(collectionId, name);
      collections = [
        for (final c in collections) if (c.id == collectionId) CloudCollectionEntity(id: c.id, name: name, ownerId: c.ownerId) else c,
      ];
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to rename collection';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCollection(int collectionId) async {
    try {
      await _repository.deleteCollection(collectionId);
      collections = collections.where((c) => c.id != collectionId).toList();
      if (selectedCollectionId == collectionId) selectCollection(null);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to delete collection';
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptInvite(int inviteId) async {
    try {
      await _repository.acceptInvite(inviteId);
      pendingInvites = pendingInvites.where((i) => i.id != inviteId).toList();
      collections = await _repository.listMyCollections();
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to accept invite';
      notifyListeners();
      return false;
    }
  }

  /// Selects a collection and starts live-streaming its members, folders
  /// and requests. Passing `null` clears the selection and cancels the
  /// streams. Any unsaved request draft is flushed first so switching
  /// collections never drops an edit.
  void selectCollection(int? collectionId) {
    unawaited(flushRequestSave());
    selectedCollectionId = collectionId;
    members = [];
    collectionInvites = [];
    folders = [];
    requests = [];
    _loadedStreams.clear();
    _failedStreams.clear();
    unawaited(_membersSub?.cancel());
    unawaited(_foldersSub?.cancel());
    unawaited(_requestsSub?.cancel());
    _membersSub = null;
    _foldersSub = null;
    _requestsSub = null;
    if (collectionId != null) {
      _membersSub = _watch(_CollectionStream.members, _repository.watchMembers(collectionId), (value) => members = value);
      _foldersSub = _watch(_CollectionStream.folders, _repository.watchFolders(collectionId), (value) => folders = value);
      _requestsSub = _watch(_CollectionStream.requests, _repository.watchRequests(collectionId), (value) => requests = value);
      unawaited(_loadCollectionInvites(collectionId));
    }
    notifyListeners();
  }

  /// Re-subscribes the selected collection after a stream failure.
  void reloadCollection() => selectCollection(selectedCollectionId);

  /// supabase-dart's `stream()` needs `onError`/`onDone`: a failed first
  /// fetch errors and closes the stream, and a dropped realtime channel
  /// errors it until it recovers and emits again.
  StreamSubscription<List<T>> _watch<T>(_CollectionStream which, Stream<List<T>> stream, void Function(List<T>) onData) {
    return stream.listen(
      (value) {
        _failedStreams.remove(which);
        _loadedStreams.add(which);
        onData(value);
        _notify();
      },
      onError: (Object _) {
        _failedStreams.add(which);
        _notify();
      },
      onDone: () {
        _failedStreams.add(which);
        _notify();
      },
    );
  }

  Future<void> _loadCollectionInvites(int collectionId) async {
    try {
      final invites = await _repository.listCollectionInvites(collectionId);
      if (selectedCollectionId != collectionId) return;
      collectionInvites = invites;
      _notify();
    } catch (e) {
      // Non-owners are denied by RLS; the members list stands on its own.
    }
  }

  /// The current user's role in the currently-selected collection, derived
  /// from the live [members] list (`null` before it has loaded).
  MemberRole? myRole(String currentUserId) {
    for (final m in members) {
      if (m.userId == currentUserId) return m.role;
    }
    return null;
  }

  List<CloudFolderEntity> childFolders(int? parentFolderId) =>
      folders.where((f) => f.parentFolderId == parentFolderId).toList();

  List<CloudRequestEntity> requestsIn(int? folderId) => requests.where((r) => r.folderId == folderId).toList();

  Future<bool> inviteMember(int collectionId, String email, MemberRole role) async {
    try {
      await _repository.inviteMember(collectionId, email, role);
      await _loadCollectionInvites(collectionId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to send invite';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeMember(int collectionId, String userId) async {
    try {
      await _repository.removeMember(collectionId, userId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to remove member';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateMemberRole(int collectionId, String userId, MemberRole role) async {
    try {
      await _repository.updateMemberRole(collectionId, userId, role);
      return true;
    } catch (e) {
      errorMessage = 'Failed to update role';
      notifyListeners();
      return false;
    }
  }

  Future<bool> createFolder(int collectionId, String name, {int? parentFolderId}) async {
    try {
      await _repository.createFolder(collectionId, name, parentFolderId: parentFolderId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to create folder';
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameFolder(int folderId, String name) async {
    try {
      await _repository.renameFolder(folderId, name);
      return true;
    } catch (e) {
      errorMessage = 'Failed to rename folder';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteFolder(int folderId) async {
    try {
      await _repository.deleteFolder(folderId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to delete folder';
      notifyListeners();
      return false;
    }
  }

  /// Returns the stored request (with its real id) so the caller can open it
  /// for editing immediately; `null` on failure.
  Future<CloudRequestEntity?> createRequest(int collectionId, String name, {int? folderId}) async {
    try {
      return await _repository.createRequest(collectionId, name, folderId: folderId);
    } catch (e) {
      errorMessage = 'Failed to create request';
      notifyListeners();
      return null;
    }
  }

  Future<bool> moveRequest(int requestId, int? folderId) async {
    try {
      await _repository.moveRequest(requestId, folderId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to move request';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteRequest(int requestId) async {
    try {
      await _repository.deleteRequest(requestId);
      return true;
    } catch (e) {
      errorMessage = 'Failed to delete request';
      notifyListeners();
      return false;
    }
  }

  /// Call when a request editor opens with [request] as its starting point,
  /// so a stale "Saved"/"Save failed" from the previous one isn't shown and
  /// later saves send only what differs from [request]. Deliberately silent:
  /// it runs from the editor's `initState`, i.e. mid-build, where notifying
  /// would throw.
  void startRequestEdit(CloudRequestEntity request) {
    _failedDrafts.clear();
    _savedBases[request.id] = request;
    if (_pendingDrafts.isEmpty && _saveInFlight == null) saveStatus = RequestSaveStatus.idle;
    _resetSend();
  }

  void _resetSend() {
    _sendGeneration++;
    _sendToken?.cancel();
    _sendToken = null;
    isSendingRequest = false;
    sendResponse = null;
    sendError = null;
  }

  /// Sends [request] as it is right now (unsaved edits included) and keeps the
  /// outcome in [sendResponse] / [sendError]. It is sent as a request of no
  /// local collection: see [CloudRequestMapper.toSendable].
  Future<void> sendRequest(CloudRequestEntity request) async {
    final send = _sendRequest;
    if (send == null || isSendingRequest) return;
    final generation = _sendGeneration;
    final token = _sendToken = ApiCancelToken();
    isSendingRequest = true;
    sendError = null;
    notifyListeners();
    try {
      final response = await send(CloudRequestMapper.toSendable(request), cancelToken: token);
      if (generation != _sendGeneration) return;
      sendResponse = response;
    } catch (e) {
      if (generation != _sendGeneration) return;
      // A failed send has no response of its own; the previous one would show
      // a result this send never produced. A cancelled one leaves things as they were.
      if (!token.isCancelled) {
        sendResponse = null;
        sendError = SendErrorMessage.of(e);
      }
    }
    _sendToken = null;
    isSendingRequest = false;
    _notify();
  }

  /// Abandons the send in flight; [sendRequest] then finishes without an error.
  void cancelSend() => _sendToken?.cancel();

  /// Copies the selected collection, with every folder and request currently
  /// loaded, into a new local collection. Null on failure (see [errorMessage]).
  Future<CopiedCollection?> copyCollectionToLocal(CloudCollectionEntity collection) async {
    final copy = _copyCollection;
    if (copy == null || isCopyingCollection) return null;
    if (selectedCollectionId != collection.id || !treeLoaded) {
      errorMessage = 'Wait until the collection has finished loading';
      notifyListeners();
      return null;
    }
    isCopyingCollection = true;
    errorMessage = null;
    notifyListeners();
    try {
      // The tree below is what the server holds; an edit still waiting to be saved would be missing from the copy.
      await flushRequestSave();
      final copied = await copy(CopyCloudCollectionParams(name: collection.name, folders: folders, requests: requests));
      isCopyingCollection = false;
      _notify();
      return copied;
    } catch (e) {
      isCopyingCollection = false;
      errorMessage = 'Failed to copy collection';
      _notify();
      return null;
    }
  }

  /// Auto-save entry point: each call replaces the previous draft of that
  /// request and restarts the [_autoSaveDelay] timer, so a burst of keystrokes
  /// results in one `updateRequest` — mirrors the local builder's
  /// persist-on-edit.
  void editRequest(CloudRequestEntity draft) {
    _pendingDrafts[draft.id] = draft;
    _failedDrafts.remove(draft.id);
    _saveTimer?.cancel();
    _saveTimer = Timer(_autoSaveDelay, () => unawaited(flushRequestSave()));
    if (saveStatus != RequestSaveStatus.saving) {
      saveStatus = RequestSaveStatus.saving;
      notifyListeners();
    }
  }

  /// Writes every pending draft now. Saves are serialised so two in-flight
  /// updates can't land out of order.
  Future<void> flushRequestSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final inFlight = _saveInFlight;
    if (inFlight != null) return inFlight;
    if (_pendingDrafts.isEmpty) return Future.value();
    final run = _drainDrafts().whenComplete(() => _saveInFlight = null);
    _saveInFlight = run;
    return run;
  }

  Future<void> _drainDrafts() async {
    while (_pendingDrafts.isNotEmpty) {
      final id = _pendingDrafts.keys.first;
      final draft = _pendingDrafts.remove(id)!;
      saveStatus = RequestSaveStatus.saving;
      _notify();
      try {
        await _repository.updateRequest(draft, base: _savedBases[id]);
        _savedBases[id] = draft;
      } catch (e) {
        if (!_pendingDrafts.containsKey(id)) {
          _failedDrafts[id] = draft;
          errorMessage = e is AppException ? e.message : 'Failed to save request';
        }
      }
      if (_pendingDrafts.isEmpty) {
        saveStatus = _failedDrafts.isEmpty ? RequestSaveStatus.saved : RequestSaveStatus.failed;
      }
      _notify();
    }
  }

  /// Re-queues the drafts whose save failed and writes everything unsaved now.
  Future<void> retryRequestSave() {
    for (final entry in _failedDrafts.entries) {
      _pendingDrafts.putIfAbsent(entry.key, () => entry.value);
    }
    _failedDrafts.clear();
    return flushRequestSave();
  }

  /// Drops every unsaved draft, for when the user chose to abandon edits
  /// that could not be saved.
  void discardRequestEdits() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingDrafts.clear();
    _failedDrafts.clear();
    saveStatus = RequestSaveStatus.idle;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sendToken?.cancel();
    _saveTimer?.cancel();
    if (_saveInFlight == null) {
      for (final entry in _pendingDrafts.entries) {
        unawaited(_repository.updateRequest(entry.value, base: _savedBases[entry.key]).catchError((_) {}));
      }
      _pendingDrafts.clear();
    }
    unawaited(_membersSub?.cancel());
    unawaited(_foldersSub?.cancel());
    unawaited(_requestsSub?.cancel());
    super.dispose();
  }
}
