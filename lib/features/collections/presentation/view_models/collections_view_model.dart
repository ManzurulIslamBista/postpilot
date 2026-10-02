import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../domain/entities/collection_entity.dart';
import '../../domain/repositories/collection_repository.dart';

final class CollectionsViewModel with ChangeNotifier {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final ValueListenable<Set<int>?>? _requestIdFilter;

  /// [requestIdFilter] carries the ids of the requests to show (null = no
  /// filter); it narrows the tree like the search text does, and both apply.
  CollectionsViewModel(this._collectionRepository, this._requestRepository, {this._requestIdFilter}) {
    _collectionsSub = _collectionRepository.watchCollections().listen((value) {
      collections = value;
      _loadEveryCollectionWhileFiltering();
      notifyListeners();
    });
    _requestIdFilter?.addListener(_onFilterChanged);
  }

  List<CollectionEntity> collections = [];
  final Set<int> expandedCollectionIds = {};
  final Map<int, List<FolderEntity>> foldersByCollection = {};
  final Map<int, List<RequestSummaryEntity>> requestsByCollection = {};
  String searchQuery = '';

  late final StreamSubscription<List<CollectionEntity>> _collectionsSub;
  final Map<int, StreamSubscription<List<FolderEntity>>> _folderSubs = {};
  final Map<int, StreamSubscription<List<RequestSummaryEntity>>> _requestSubs = {};

  bool isExpanded(int collectionId) => expandedCollectionIds.contains(collectionId);

  Set<int>? get _tagFilter => _requestIdFilter?.value;

  bool get isFiltering => searchQuery.isNotEmpty || _tagFilter != null;

  /// While filtering, a collection holding a match opens by itself so the
  /// match is visible without expanding every collection by hand.
  bool isCollectionExpanded(CollectionEntity collection) =>
      isExpanded(collection.id) || (isFiltering && _hasMatchingDescendant(collection.id, null));

  /// Opens [collectionId] in the sidebar if it is closed (a no-op when it is already open).
  void expandCollection(int collectionId) {
    if (!expandedCollectionIds.contains(collectionId)) toggleExpand(collectionId);
  }

  /// The first request of [collectionId] (root first), e.g. to open a freshly added template.
  Future<int?> firstRequestId(int collectionId) async {
    final requests = await _requestRepository.watchByCollection(collectionId).first;
    return requests.firstOrNull?.id;
  }

  void toggleExpand(int collectionId) {
    if (!expandedCollectionIds.add(collectionId)) {
      expandedCollectionIds.remove(collectionId);
      // A filter keeps the collection open, so it still needs its live data.
      if (!isFiltering) {
        _folderSubs.remove(collectionId)?.cancel();
        _requestSubs.remove(collectionId)?.cancel();
      }
      notifyListeners();
      return;
    }

    _subscribeToContents(collectionId);
    notifyListeners();
  }

  void _subscribeToContents(int collectionId) {
    if (_folderSubs.containsKey(collectionId)) return;
    _folderSubs[collectionId] = _collectionRepository.watchFolders(collectionId).listen((value) {
      foldersByCollection[collectionId] = value;
      notifyListeners();
    });
    _requestSubs[collectionId] = _requestRepository.watchByCollection(collectionId).listen((value) {
      requestsByCollection[collectionId] = value;
      notifyListeners();
    });
  }

  /// Updates the search text.
  void setSearchQuery(String query) {
    searchQuery = query;
    _loadEveryCollectionWhileFiltering();
    notifyListeners();
  }

  void _onFilterChanged() {
    _loadEveryCollectionWhileFiltering();
    notifyListeners();
  }

  /// Finding descendant matches needs every collection's folders/requests
  /// loaded (not just expanded ones), so a filter subscribes to any
  /// collection not yet loaded.
  void _loadEveryCollectionWhileFiltering() {
    if (!isFiltering) return;
    for (final collection in collections) {
      _subscribeToContents(collection.id);
    }
  }

  bool isCollectionVisible(CollectionEntity collection) =>
      !isFiltering || _nameMatches(collection.name) || _hasMatchingDescendant(collection.id, null);

  bool isFolderVisible(int collectionId, FolderEntity folder) =>
      !isFiltering || _nameMatches(folder.name) || _hasMatchingDescendant(collectionId, folder.id);

  bool isRequestVisible(RequestSummaryEntity request) => _requestPasses(request);

  bool _matchesQuery(String name) => name.toLowerCase().contains(searchQuery.toLowerCase());

  /// A collection or folder name only counts as a match under the search text
  /// alone: with a tag filter on, a container shows for the requests it holds.
  bool _nameMatches(String name) => _tagFilter == null && _matchesQuery(name);

  bool _requestPasses(RequestSummaryEntity request) =>
      (_tagFilter?.contains(request.id) ?? true) && (searchQuery.isEmpty || _matchesQuery(request.name));

  bool _hasMatchingDescendant(int collectionId, int? parentFolderId) {
    final requests = requestsByCollection[collectionId] ?? const [];
    if (requests.any((r) => r.folderId == parentFolderId && _requestPasses(r))) return true;
    final folders = foldersByCollection[collectionId] ?? const [];
    for (final folder in folders.where((f) => f.parentFolderId == parentFolderId)) {
      if (_nameMatches(folder.name) || _hasMatchingDescendant(collectionId, folder.id)) return true;
    }
    return false;
  }

  Future<void> createCollection(String name) => _collectionRepository.createCollection(name);

  Future<void> renameCollection(int id, String name) => _collectionRepository.renameCollection(id, name);

  Future<void> deleteCollection(int id) => _collectionRepository.deleteCollection(id);

  Future<void> duplicateCollection(int id) => _collectionRepository.duplicateCollection(id);

  Future<void> createFolder(int collectionId, String name, {int? parentFolderId}) => _collectionRepository
      .createFolder(collectionId: collectionId, parentFolderId: parentFolderId, name: name);

  Future<void> renameFolder(int id, String name) => _collectionRepository.renameFolder(id, name);

  Future<void> deleteFolder(int id) => _collectionRepository.deleteFolder(id);

  Future<void> duplicateFolder(int id) => _collectionRepository.duplicateFolder(id);

  Future<int> createRequest(int collectionId, {int? folderId, String name = 'New Request'}) =>
      _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: name);

  /// Adds a request holding [template]'s content (its own id and collection
  /// are ignored) to the top level of [collectionId]; returns the new id.
  Future<int> createRequestFrom(int collectionId, ApiRequestEntity template) async {
    final id = await _requestRepository.createRequest(collectionId: collectionId, name: template.name);
    await _requestRepository.saveRequest(ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: null,
      name: template.name,
      method: template.method,
      url: template.url,
      headers: template.headers,
      queryParams: template.queryParams,
      body: template.body,
      auth: template.auth,
    ));
    return id;
  }

  Future<void> renameRequest(int id, String name) async {
    final request = await _requestRepository.findById(id);
    if (request != null) await _requestRepository.saveRequest(request.copyWith(name: name));
  }

  Future<void> deleteRequest(int id) => _requestRepository.deleteRequest(id);

  Future<void> duplicateRequest(int id) => _collectionRepository.duplicateRequest(id);

  @override
  void dispose() {
    _requestIdFilter?.removeListener(_onFilterChanged);
    _collectionsSub.cancel();
    for (final sub in _folderSubs.values) {
      sub.cancel();
    }
    for (final sub in _requestSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
