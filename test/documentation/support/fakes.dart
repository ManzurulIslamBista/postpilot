import 'dart:async';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/documentation/domain/services/tag_normalizer.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';

/// A tag store that behaves like the real one: setTags normalises, reads are
/// sorted, and every watcher hears about every change.
class FakeTagRepository implements TagRepository {
  final Map<(EntityKind, int), List<String>> _tags = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  final List<(EntityKind, int, List<String>)> writes = [];
  Object? failWith;

  void seed(EntityKind kind, int id, List<String> tags) => _tags[(kind, id)] = TagNormalizer.normalise(tags);

  List<String> tagsFor(EntityKind kind, int id) => _tags[(kind, id)] ?? const [];

  Stream<T> _watch<T>(T Function() read) => liveStream(read, _changes.stream);

  Map<int, List<String>> _byId(EntityKind kind) => {
        for (final entry in _tags.entries)
          if (entry.key.$1 == kind && entry.value.isNotEmpty) entry.key.$2: entry.value,
      };

  @override
  Stream<List<String>> watchTags(EntityKind kind, int id) => _watch(() => tagsFor(kind, id));

  @override
  Future<void> setTags(EntityKind kind, int id, List<String> tags) async {
    final failure = failWith;
    if (failure != null) throw failure;
    writes.add((kind, id, tags));
    _tags[(kind, id)] = TagNormalizer.normalise(tags);
    _changes.add(null);
  }

  @override
  Stream<List<String>> watchAllTags() => _watch(() => TagNormalizer.normalise([for (final tags in _tags.values) ...tags]));

  @override
  Future<Map<int, List<String>>> tagsByLocalId(EntityKind kind) async => _byId(kind);

  @override
  Stream<Map<int, List<String>>> watchTagsByLocalId(EntityKind kind) => _watch(() => _byId(kind));

  Future<void> close() => _changes.close();
}

class FakeDocumentationRepository implements DocumentationRepository {
  final Map<(EntityKind, int), String> _docs = {};
  final List<(EntityKind, int, String)> writes = [];
  Completer<void>? holdWrites;
  Object? failWith;

  void seed(EntityKind kind, int id, String markdown) => _docs[(kind, id)] = markdown;

  String? stored(EntityKind kind, int id) => _docs[(kind, id)];

  @override
  Future<String> markdownOf(EntityKind kind, int id) async => _docs[(kind, id)] ?? '';

  @override
  Future<void> setMarkdown(EntityKind kind, int id, String text) async {
    writes.add((kind, id, text));
    await holdWrites?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    if (text.isEmpty) {
      _docs.remove((kind, id));
    } else {
      _docs[(kind, id)] = text;
    }
  }

  @override
  Future<Map<int, String>> markdownByLocalId(EntityKind kind) async => {
        for (final entry in _docs.entries)
          if (entry.key.$1 == kind) entry.key.$2: entry.value,
      };
}

/// A stream that starts with `read()` and repeats it on every event of
/// [changes]. `onCancel` must not return the future of the inner cancel: that
/// future lives in the root zone, and `Stream.first` waits for it, so under the
/// widget tester's fake-async zone `first` would never complete.
Stream<T> liveStream<T>(T Function() read, Stream<void> changes) {
  late final StreamController<T> controller;
  StreamSubscription<void>? subscription;
  controller = StreamController<T>(
    onListen: () {
      controller.add(read());
      subscription = changes.listen((_) => controller.add(read()));
    },
    onCancel: () {
      subscription?.cancel();
    },
  );
  return controller.stream;
}

Stream<void> _signalFor(Map<int, StreamController<void>> signals, int key) =>
    signals.putIfAbsent(key, () => StreamController<void>.broadcast(sync: true)).stream;

class FakeCollectionRepository implements CollectionRepository {
  final List<CollectionEntity> collections;
  final Map<int, List<FolderEntity>> folders;
  final _folderChanges = <int, StreamController<void>>{};

  FakeCollectionRepository({this.collections = const [], Map<int, List<FolderEntity>>? folders})
      : folders = folders ?? {};

  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value(collections);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) =>
      liveStream(() => folders[collectionId] ?? const [], _signalFor(_folderChanges, collectionId));

  void setFolders(int collectionId, List<FolderEntity> value) {
    folders[collectionId] = value;
    _folderChanges[collectionId]?.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeRequestRepository implements RequestRepository {
  final Map<int, List<ApiRequestEntity>> byCollection;
  final _changes = <int, StreamController<void>>{};

  FakeRequestRepository([Map<int, List<ApiRequestEntity>>? byCollection]) : byCollection = byCollection ?? {};

  static RequestSummaryEntity summaryOf(ApiRequestEntity r) =>
      RequestSummaryEntity(id: r.id, folderId: r.folderId, name: r.name, method: r.method);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => liveStream(
        () => [for (final r in byCollection[collectionId] ?? const <ApiRequestEntity>[]) summaryOf(r)],
        _signalFor(_changes, collectionId),
      );

  void setRequests(int collectionId, List<ApiRequestEntity> value) {
    byCollection[collectionId] = value;
    _changes[collectionId]?.add(null);
  }

  @override
  Future<ApiRequestEntity?> findById(int id) async {
    for (final requests in byCollection.values) {
      for (final request in requests) {
        if (request.id == id) return request;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeResponseExampleRepository implements ResponseExampleRepository {
  final Map<int, List<ResponseExampleEntity>> newestFirst;
  const FakeResponseExampleRepository([this.newestFirst = const {}]);

  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(newestFirst[requestId] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeCollectionVariableRepository implements CollectionVariableRepository {
  final Map<int, List<CollectionVariableEntity>> byCollection;
  const FakeCollectionVariableRepository([this.byCollection = const {}]);

  @override
  Stream<List<CollectionVariableEntity>> watchByCollection(int collectionId) =>
      Stream.value(byCollection[collectionId] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeCollectionAuthRepository implements CollectionAuthRepository {
  final Map<int, String> json;
  const FakeCollectionAuthRepository([this.json = const {}]);

  @override
  Future<String?> getAuthJson(int collectionId) async => json[collectionId];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

ApiRequestEntity requestEntity(
  int id, {
  int collectionId = 1,
  int? folderId,
  String? name,
  HttpMethod method = HttpMethod.get,
  String url = '',
  List<KeyValueItem> headers = const [],
  List<KeyValueItem> queryParams = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = RequestAuth.none,
}) =>
    ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: folderId,
      name: name ?? 'Request $id',
      method: method,
      url: url,
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: auth,
    );

FolderEntity folderEntity(int id, {int collectionId = 1, int? parent, String? name}) =>
    FolderEntity(id: id, collectionId: collectionId, parentFolderId: parent, name: name ?? 'Folder $id');
