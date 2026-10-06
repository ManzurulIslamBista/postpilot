import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../../core/errors/app_exception.dart';
import '../../domain/entities/collection_entity.dart';
import '../../domain/entities/move_receipt.dart';
import '../../domain/repositories/collection_order_repository.dart';
import '../../domain/repositories/collection_repository.dart';
import '../../domain/services/collection_order.dart';

/// A folder or request of the tree with its place in the canonical order.
typedef TreeItem = ({OrderEntry entry, FolderEntity? folder, RequestSummaryEntity? request});

/// A place a folder or request can be moved to: a collection's top level or one of its folders.
final class MoveDestination {
  final int collectionId;

  /// Null = the collection's top level.
  final int? folderId;

  /// The collection name, or the folder name.
  final String label;

  /// 0 for a collection, 1 for a folder at its top level, and so on.
  final int depth;

  /// False for places that would put a folder inside itself.
  final bool enabled;

  const MoveDestination({
    required this.collectionId,
    required this.folderId,
    required this.label,
    required this.depth,
    this.enabled = true,
  });
}

/// How a move ended: [receipt] when it was done (and can be undone), [error] when it was refused or failed.
final class MoveOutcome {
  final MoveReceipt? receipt;
  final String? error;

  const MoveOutcome.done(MoveReceipt this.receipt) : error = null;
  const MoveOutcome.failed(String this.error) : receipt = null;

  /// Something really changed place.
  bool get moved => receipt != null && !receipt!.isNoop;
}

final class CollectionsViewModel with ChangeNotifier {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final ValueListenable<Set<int>?>? _requestIdFilter;
  final CollectionOrderRepository? _orderRepository;

  /// [requestIdFilter] carries the ids of the requests to show (null = no
  /// filter); it narrows the tree like the search text does, and both apply.
  /// [orderRepository] turns moving and reordering on; without it the tree can only be read.
  CollectionsViewModel(
    this._collectionRepository,
    this._requestRepository, {
    this._requestIdFilter,
    this._orderRepository,
  }) {
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

  /// Folders the user closed; every other folder shows its content. Kept here, not in the row, so a folder that
  /// moves to another parent keeps its state.
  final Set<int> collapsedFolderIds = {};

  /// Collections whose levels were checked for equal indexes since the app started.
  final Set<int> _normalized = {};
  final Map<int, ({List<FolderEntity> folders, List<RequestSummaryEntity> requests, CollectionOrder order})> _orders = {};

  /// Whether folders and requests can be moved and reordered.
  bool get canMove => _orderRepository != null;

  bool isFolderExpanded(int folderId) => !collapsedFolderIds.contains(folderId);

  void toggleFolder(int folderId) {
    if (!collapsedFolderIds.remove(folderId)) collapsedFolderIds.add(folderId);
    notifyListeners();
  }

  /// Opens [folderId] if it is closed (a no-op when it is already open).
  void expandFolder(int folderId) {
    if (collapsedFolderIds.remove(folderId)) notifyListeners();
  }

  /// The canonical order of [collectionId]'s loaded folders and requests: what the tree below shows.
  CollectionOrder orderOf(int collectionId) {
    final folders = foldersByCollection[collectionId] ?? const <FolderEntity>[];
    final requests = requestsByCollection[collectionId] ?? const <RequestSummaryEntity>[];
    final cached = _orders[collectionId];
    if (cached != null && identical(cached.folders, folders) && identical(cached.requests, requests)) {
      return cached.order;
    }
    final order = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    );
    _orders[collectionId] = (folders: folders, requests: requests, order: order);
    return order;
  }

  /// The folders and requests directly in [parentFolderId] (null = the collection's top level), in canonical
  /// order, whatever the search or tag filter hides.
  List<TreeItem> childrenOf(int collectionId, int? parentFolderId) {
    final folders = foldersByCollection[collectionId] ?? const <FolderEntity>[];
    final requests = requestsByCollection[collectionId] ?? const <RequestSummaryEntity>[];
    return [
      for (final entry in orderOf(collectionId).childrenOf(parentFolderId))
        (
          entry: entry,
          folder: entry.isFolder ? folders[entry.index] : null,
          request: entry.isFolder ? null : requests[entry.index],
        ),
    ];
  }

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
    _normalizeOnce(collectionId);
    _folderSubs[collectionId] = _collectionRepository.watchFolders(collectionId).listen((value) {
      foldersByCollection[collectionId] = value;
      notifyListeners();
    });
    _requestSubs[collectionId] = _requestRepository.watchByCollection(collectionId).listen((value) {
      requestsByCollection[collectionId] = value;
      notifyListeners();
    });
  }

  /// A collection made before ordering existed has siblings that share an index and are listed by creation order
  /// alone. The first time one is used its levels get distinct indexes in exactly that order, so what the sidebar
  /// shows, what the runner and the CLI run and what Git carries are stored the same way. Does nothing for a
  /// collection that is already in order, and a failure only leaves the stored indexes as they were.
  void _normalizeOnce(int collectionId) {
    final repository = _orderRepository;
    if (repository == null || !_normalized.add(collectionId)) return;
    unawaited(repository.normalize(collectionId).then<void>((_) {}, onError: (Object _) {}));
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

  Future<int> createCollection(String name) => _collectionRepository.createCollection(name);

  /// What a first request is created in on a fresh install, when there is no collection to put it in.
  static const defaultCollectionName = 'My collection';

  /// The id of the first collection, creating [defaultCollectionName] when there is none yet: "New request" and
  /// opening a history entry then do the useful thing instead of asking the user to create a collection first.
  /// Reads the repository, not [collections], which is still empty until its first emission lands.
  ///
  /// Two quick calls (Ctrl+N pressed twice) share one run, so they cannot both create the default collection.
  Future<({int id, bool created})> ensureCollection() => _ensuring ??= _ensureCollection().whenComplete(() => _ensuring = null);

  Future<({int id, bool created})>? _ensuring;

  Future<({int id, bool created})> _ensureCollection() async {
    final existing = await _collectionRepository.watchCollections().first;
    if (existing.isNotEmpty) return (id: existing.first.id, created: false);
    return (id: await createCollection(defaultCollectionName), created: true);
  }

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

  /// Returns the copy's id.
  Future<int> duplicateRequest(int id) => _collectionRepository.duplicateRequest(id);

  /// Moves a request into [folderId] of [collectionId] (null = its top level), in front of [before] (the end when
  /// null). The target opens so the request stays in view.
  Future<MoveOutcome> moveRequest(int requestId, {required int collectionId, int? folderId, OrderRef? before}) =>
      _move(
        collectionId,
        folderId,
        (repository) => repository.moveRequest(requestId, collectionId: collectionId, folderId: folderId, before: before),
      );

  /// Moves a folder with everything in it; see [moveRequest].
  Future<MoveOutcome> moveFolder(int folderId, {required int collectionId, int? parentFolderId, OrderRef? before}) =>
      _move(
        collectionId,
        parentFolderId,
        (repository) => repository.moveFolder(
          folderId,
          collectionId: collectionId,
          parentFolderId: parentFolderId,
          before: before,
        ),
      );

  /// Whether [item] has a sibling to swap with in direction [delta] (-1 up, +1 down).
  bool canStep(OrderRef item, {required int collectionId, required int delta}) =>
      canMove && _step(item, collectionId, delta) != null;

  /// Moves [item] one place up ([delta] -1) or down (+1) among its siblings.
  Future<MoveOutcome> moveStep(OrderRef item, {required int collectionId, required int delta}) async {
    final step = _step(item, collectionId, delta);
    if (step == null) return MoveOutcome.done(const MoveReceipt(replaced: []));
    return item.isFolder
        ? moveFolder(item.id, collectionId: collectionId, parentFolderId: step.parent, before: step.before)
        : moveRequest(item.id, collectionId: collectionId, folderId: step.parent, before: step.before);
  }

  ({int? parent, OrderRef? before})? _step(OrderRef item, int collectionId, int delta) {
    final siblings = orderOf(collectionId).siblingsOf(item);
    if (siblings.isEmpty) return null;
    final step = CollectionOrder.step([for (final s in siblings) s.ref], item, delta);
    return step.canMove ? (parent: siblings.first.parentId, before: step.before) : null;
  }

  /// Puts back what a move changed. False when that was no longer possible.
  Future<bool> undoMove(MoveReceipt receipt) async {
    final repository = _orderRepository;
    if (repository == null || receipt.isNoop) return false;
    try {
      await repository.undo(receipt);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Every collection and folder [moving] could be moved to, in tree order. For a folder, the places inside it
  /// are listed but disabled.
  Future<List<MoveDestination>> moveDestinations({OrderRef? moving}) async {
    final all = <MoveDestination>[];
    for (final collection in collections) {
      final folders = await _collectionRepository.watchFolders(collection.id).first;
      final order = CollectionOrder.of(
        folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      );
      final blocked = moving != null && moving.isFolder ? order.folderSubtree(moving.id) : const <int>{};
      all.add(MoveDestination(collectionId: collection.id, folderId: null, label: collection.name, depth: 0));
      for (final entry in order.folders) {
        all.add(
          MoveDestination(
            collectionId: collection.id,
            folderId: entry.id,
            label: folders[entry.index].name,
            depth: entry.depth + 1,
            enabled: !blocked.contains(entry.id),
          ),
        );
      }
    }
    return all;
  }

  Future<MoveOutcome> _move(
    int collectionId,
    int? folderId,
    Future<MoveReceipt> Function(CollectionOrderRepository repository) action,
  ) async {
    final repository = _orderRepository;
    if (repository == null) return const MoveOutcome.failed('Moving is not available here.');
    try {
      final receipt = await action(repository);
      if (!receipt.isNoop) {
        expandCollection(collectionId);
        if (folderId != null) expandFolder(folderId);
      }
      return MoveOutcome.done(receipt);
    } on MoveRefusedException catch (e) {
      return MoveOutcome.failed(e.message);
    } on AppException catch (e) {
      return MoveOutcome.failed(e.message);
    } catch (e) {
      return MoveOutcome.failed("Couldn't move it: $e");
    }
  }

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
