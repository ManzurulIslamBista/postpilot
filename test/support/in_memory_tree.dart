import 'dart:async';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/move_receipt.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_order_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';

final class _Node {
  final OrderRef ref;
  String name;
  int collectionId;
  int? parentId;
  int order;
  HttpMethod method;
  _Node(this.ref, this.name, this.collectionId, this.parentId, this.order, [this.method = HttpMethod.get]);
}

/// Collections, folders and requests in memory, with live streams and moves that follow the same rules as the
/// database (dense renumbering of both levels, cycle guard, a folder taking its subtree along to another
/// collection). For widget tests, where a real database does not mix with fake async.
final class InMemoryTree implements CollectionRepository, RequestRepository, CollectionOrderRepository {
  final List<CollectionEntity> collections;
  final List<_Node> _nodes = [];
  final _changes = StreamController<void>.broadcast(sync: true);
  int _nextFolder = 100;
  int _nextRequest = 1000;

  /// Every move asked for, as `request:7 -> 1/10 before request:8`, so a test can see a refused drop never got here.
  final List<String> moveCalls = [];

  InMemoryTree(this.collections);

  int addFolder(int collectionId, String name, {int? parent, int? id}) {
    final folderId = id ?? _nextFolder++;
    _nodes.add(_Node(OrderRef.folder(folderId), name, collectionId, parent, _nextOrder(collectionId, parent)));
    return folderId;
  }

  int addRequest(int collectionId, String name, {int? folder, int? id, HttpMethod method = HttpMethod.get}) {
    final requestId = id ?? _nextRequest++;
    _nodes.add(_Node(OrderRef.request(requestId), name, collectionId, folder, _nextOrder(collectionId, folder), method));
    return requestId;
  }

  int _nextOrder(int collectionId, int? parent) {
    final level = _level(collectionId, parent).toList();
    return level.isEmpty ? 0 : level.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  Iterable<_Node> _level(int collectionId, int? parent) =>
      _nodes.where((n) => n.collectionId == collectionId && n.parentId == parent);

  /// The collection as the sidebar should draw it: indented names, folders in brackets.
  List<String> outline(int collectionId) {
    final folders = _nodes.where((n) => n.collectionId == collectionId && n.ref.isFolder).toList();
    final requests = _nodes.where((n) => n.collectionId == collectionId && !n.ref.isFolder).toList();
    final order = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.ref.id, parentId: f.parentId, orderIndex: f.order)],
      requests: [for (final r in requests) (id: r.ref.id, folderId: r.parentId, orderIndex: r.order)],
    );
    return [
      for (final e in order.entries)
        '${'  ' * e.depth}${e.isFolder ? '[${folders[e.index].name}]' : requests[e.index].name}',
    ];
  }

  /// Where a request is now.
  ({int collectionId, int? folderId}) locationOf(int requestId) {
    final node = _nodes.firstWhere((n) => n.ref == OrderRef.request(requestId));
    return (collectionId: node.collectionId, folderId: node.parentId);
  }

  // ---- CollectionRepository ----

  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value(collections);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) => _live(
    () => [
      for (final n in _nodes)
        if (n.collectionId == collectionId && n.ref.isFolder)
          FolderEntity(
            id: n.ref.id,
            collectionId: n.collectionId,
            parentFolderId: n.parentId,
            name: n.name,
            orderIndex: n.order,
          ),
    ],
  );

  // ---- RequestRepository ----

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => _live(
    () => [
      for (final n in _nodes)
        if (n.collectionId == collectionId && !n.ref.isFolder)
          RequestSummaryEntity(id: n.ref.id, folderId: n.parentId, name: n.name, method: n.method, orderIndex: n.order),
    ],
  );

  @override
  Stream<ApiRequestEntity?> watchById(int id) => _live(() => _entity(id));

  @override
  Future<ApiRequestEntity?> findById(int id) async => _entity(id);

  ApiRequestEntity? _entity(int id) {
    final node = _nodes.where((n) => n.ref == OrderRef.request(id)).firstOrNull;
    if (node == null) return null;
    return ApiRequestEntity(
      id: id,
      collectionId: node.collectionId,
      folderId: node.parentId,
      name: node.name,
      method: node.method,
      url: 'https://api.test/$id',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(),
      orderIndex: node.order,
    );
  }

  Stream<T> _live<T>(T Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        subscription = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () {
        subscription?.cancel();
      },
    );
    return controller.stream;
  }

  // ---- CollectionOrderRepository ----

  @override
  Future<MoveReceipt> moveRequest(int requestId, {required int collectionId, int? folderId, OrderRef? before}) async {
    moveCalls.add('request:$requestId -> $collectionId/${folderId ?? '-'} before ${before ?? 'end'}');
    return _move(OrderRef.request(requestId), collectionId, folderId, before);
  }

  @override
  Future<MoveReceipt> moveFolder(int folderId, {required int collectionId, int? parentFolderId, OrderRef? before}) async {
    moveCalls.add('folder:$folderId -> $collectionId/${parentFolderId ?? '-'} before ${before ?? 'end'}');
    return _move(OrderRef.folder(folderId), collectionId, parentFolderId, before);
  }

  MoveReceipt _move(OrderRef ref, int collectionId, int? parent, OrderRef? before) {
    final node = _nodes.firstWhere((n) => n.ref == ref);
    final subtree = ref.isFolder ? _subtree(ref.id) : <int>{};
    if (parent != null && subtree.contains(parent)) {
      throw const MoveRefusedException('A folder cannot be moved into itself or one of its own sub-folders.');
    }
    final replaced = <Placement>[];
    void remember(_Node n) {
      if (replaced.every((p) => p.ref != n.ref)) {
        replaced.add(Placement(ref: n.ref, collectionId: n.collectionId, parentId: n.parentId, orderIndex: n.order));
      }
    }

    final fromCollection = node.collectionId;
    final fromParent = node.parentId;
    final sameLevel = fromCollection == collectionId && fromParent == parent;
    final source = _level(fromCollection, fromParent).toList();
    final target = sameLevel ? source : _level(collectionId, parent).toList();

    final next = <_Node, (int, int?, int)>{};
    if (!sameLevel) {
      final rest = CollectionOrder.sortLevel([for (final n in source) (ref: n.ref, orderIndex: n.order)]);
      var i = 0;
      for (final item in rest) {
        if (item.ref == ref) continue;
        next[_nodes.firstWhere((n) => n.ref == item.ref)] = (fromCollection, fromParent, i++);
      }
    }
    final placed = CollectionOrder.placed([for (final n in target) (ref: n.ref, orderIndex: n.order)], ref, before: before);
    for (final (i, r) in placed.indexed) {
      next[_nodes.firstWhere((n) => n.ref == r)] = (collectionId, parent, i);
    }

    var changedCollection = false;
    for (final entry in next.entries) {
      final n = entry.key;
      final (c, p, o) = entry.value;
      if (n.collectionId == c && n.parentId == p && n.order == o) continue;
      remember(n);
      if (n.ref == ref && n.collectionId != c) changedCollection = true;
      n
        ..collectionId = c
        ..parentId = p
        ..order = o;
    }
    if (ref.isFolder && fromCollection != collectionId) {
      for (final n in _nodes) {
        final inside = n.ref.isFolder ? subtree.contains(n.ref.id) && n.ref != ref : subtree.contains(n.parentId);
        if (inside && n.collectionId != collectionId) {
          remember(n);
          n.collectionId = collectionId;
        }
      }
    }
    if (replaced.isNotEmpty) _changes.add(null);
    return MoveReceipt(replaced: replaced, changedCollection: changedCollection);
  }

  Set<int> _subtree(int folderId) {
    final ids = {folderId};
    for (var added = true; added;) {
      added = false;
      for (final n in _nodes) {
        if (n.ref.isFolder && n.parentId != null && ids.contains(n.parentId) && ids.add(n.ref.id)) added = true;
      }
    }
    return ids;
  }

  @override
  Future<void> undo(MoveReceipt receipt) async {
    for (final p in receipt.replaced) {
      final node = _nodes.where((n) => n.ref == p.ref).firstOrNull;
      if (node == null) continue;
      node
        ..collectionId = p.collectionId
        ..parentId = p.parentId
        ..order = p.orderIndex;
    }
    _changes.add(null);
  }

  @override
  Future<int> normalize(int collectionId) async => 0;

  Future<void> close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}
