import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/team/domain/entities/cloud_collection_entity.dart';
import 'package:postpilot/features/team/domain/entities/cloud_folder_entity.dart';
import 'package:postpilot/features/team/domain/entities/cloud_request_entity.dart';
import 'package:postpilot/features/team/domain/entities/collection_invite_entity.dart';
import 'package:postpilot/features/team/domain/entities/collection_member_entity.dart';
import 'package:postpilot/features/team/domain/entities/member_role.dart';
import 'package:postpilot/features/team/domain/repositories/team_repository.dart';
import 'package:postpilot/features/team/domain/services/cloud_request_mapper.dart';
import 'package:postpilot/features/team/domain/services/send_error_message.dart';
import 'package:postpilot/features/team/domain/usecases/copy_cloud_collection_usecase.dart';
import 'package:postpilot/features/team/presentation/view_models/team_view_model.dart';
import 'support/in_memory_import_export_fakes.dart';

CloudRequestEntity _cloud({
  int id = 7,
  int? folderId = 2,
  String name = 'Create user',
  String method = 'POST',
  String url = 'https://api.example.com/users',
  List<KeyValueItem>? headers,
  String body = '',
}) =>
    CloudRequestEntity(
      id: id,
      collectionId: 3,
      folderId: folderId,
      name: name,
      method: method,
      url: url,
      headers: headers ?? [KeyValueItem(key: 'X-Team', value: 'blue', enabled: false)],
      body: body,
      updatedAt: DateTime(2026),
    );

const _collection = CloudCollectionEntity(id: 3, name: 'Team API', ownerId: 'owner');

ApiResponseEntity _response(int status) => ApiResponseEntity(
      statusCode: status,
      statusMessage: status == 200 ? 'OK' : 'Error',
      headers: const {'content-type': 'application/json'},
      bodyBytes: Uint8List.fromList('{"ok":true}'.codeUnits),
      duration: const Duration(milliseconds: 12),
    );

void main() {
  group('CloudRequestMapper.toSendable', () {
    test('has no local identity, so no collection variables or auth can apply to it', () {
      final sendable = CloudRequestMapper.toSendable(_cloud());

      expect(sendable.id, 0);
      expect(sendable.collectionId, 0);
      expect(sendable.folderId, isNull);
      expect(sendable.auth.type, AuthType.none);
      expect(sendable.queryParams, isEmpty);
    });

    test('carries name, method, url and headers, disabled ones included', () {
      final sendable = CloudRequestMapper.toSendable(_cloud());

      expect(sendable.name, 'Create user');
      expect(sendable.method, HttpMethod.post);
      expect(sendable.url, 'https://api.example.com/users');
      expect(sendable.headers.single.key, 'X-Team');
      expect(sendable.headers.single.enabled, isFalse);
    });

    test('an unknown method falls back to GET', () {
      expect(CloudRequestMapper.toSendable(_cloud(method: 'BREW')).method, HttpMethod.get);
    });

    test('no body text means no body', () {
      expect(CloudRequestMapper.toSendable(_cloud()).body.type, BodyType.none);
    });

    test('the body type is read from the text instead of always claiming JSON', () {
      RawContentType typeOf(String body) => CloudRequestMapper.toSendable(_cloud(body: body)).body.rawContentType;

      expect(typeOf('{"name":"John"}'), RawContentType.json);
      expect(typeOf('  [1, 2]'), RawContentType.json);
      expect(typeOf('{{payload}}'), RawContentType.json);
      expect(typeOf('<?xml version="1.0"?><a/>'), RawContentType.xml);
      expect(typeOf('<order id="1"/>'), RawContentType.xml);
      expect(typeOf('<!DOCTYPE html><html></html>'), RawContentType.html);
      expect(typeOf('<html><body/></html>'), RawContentType.html);
      expect(typeOf('just some words'), RawContentType.text);
      expect(CloudRequestMapper.toSendable(_cloud(body: 'x')).body.type, BodyType.raw);
      expect(CloudRequestMapper.toSendable(_cloud(body: '{"a":1}')).body.rawText, '{"a":1}');
    });

    test('a Content-Type header in any letter case gets the exact spelling the request sender looks for', () {
      final sendable = CloudRequestMapper.toSendable(_cloud(headers: [
        KeyValueItem(key: 'content-type', value: 'application/xml'),
        KeyValueItem(key: 'X-Other', value: '1'),
        KeyValueItem(key: 'CONTENT-TYPE', value: 'text/plain', enabled: false),
      ]));

      expect(sendable.headers.map((h) => (h.key, h.value, h.enabled)), [
        ('Content-Type', 'application/xml', true),
        ('X-Other', '1', true),
        ('Content-Type', 'text/plain', false),
      ]);
    });

    test('the input is left untouched', () {
      final cloud = _cloud(headers: [KeyValueItem(key: 'content-type', value: 'x')], body: '{}');

      CloudRequestMapper.toSendable(cloud);

      expect(cloud.headers.single.key, 'content-type');
    });
  });

  group('CloudRequestMapper.toLocalIn', () {
    test('places the request in the given collection and folder, on inherit auth', () {
      final local = CloudRequestMapper.toLocalIn(_cloud(), id: 41, collectionId: 9, folderId: 5);

      expect((local.id, local.collectionId, local.folderId), (41, 9, 5));
      expect(local.auth.type, AuthType.inherit);
      expect(local.queryParams, isEmpty);
    });

    test('a request at the top level has no folder', () {
      expect(CloudRequestMapper.toLocalIn(_cloud(), id: 1, collectionId: 9).folderId, isNull);
    });

    test('keeps headers exactly as written and reads the body type from the text', () {
      final local = CloudRequestMapper.toLocalIn(
        _cloud(headers: [KeyValueItem(key: 'content-type', value: 'application/xml')], body: '<a/>'),
        id: 1,
        collectionId: 9,
      );

      expect(local.headers.single.key, 'content-type');
      expect(local.body.type, BodyType.raw);
      expect(local.body.rawContentType, RawContentType.xml);
    });

    test('toLocal, used by "copy and open", still assumes JSON', () {
      expect(CloudRequestMapper.toLocal(_cloud(body: '<a/>')).body.rawContentType, RawContentType.json);
    });
  });

  group('SendErrorMessage', () {
    test('network failures are told apart by kind', () {
      expect(SendErrorMessage.of(const NetworkException('x', kind: NetworkErrorKind.timeout)), 'Request timed out');
      expect(SendErrorMessage.of(const NetworkException('x', kind: NetworkErrorKind.connectionError)), contains("Couldn't reach the server"));
      expect(SendErrorMessage.of(const NetworkException('x', kind: NetworkErrorKind.badResponse)), 'The server returned an unexpected response');
      expect(SendErrorMessage.of(const NetworkException('x', kind: NetworkErrorKind.cancelled)), 'Request cancelled');
      expect(SendErrorMessage.of(const NetworkException('x')), 'Something went wrong sending this request');
    });

    test('an unsendable URL explains what a URL needs', () {
      expect(SendErrorMessage.of(const InvalidUrlException('Not a valid http(s) URL: ""')), contains('needs a host'));
    });

    test('a URL Uri.parse cannot read reads like a connection problem', () {
      expect(SendErrorMessage.of(const FormatException('bad')), contains("Couldn't reach the server"));
    });

    test('anything else is generic and never leaks internals', () {
      expect(SendErrorMessage.of(StateError('secret internals')), 'Something went wrong sending this request');
    });
  });

  group('copying a team collection', () {
    late InMemoryDb db;
    late CopyCloudCollectionUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = CopyCloudCollectionUseCase(db.collectionRepository, db.requestRepository);
    });

    const folders = [
      CloudFolderEntity(id: 20, collectionId: 3, parentFolderId: 10, name: 'Admin'),
      CloudFolderEntity(id: 10, collectionId: 3, parentFolderId: null, name: 'Users'),
      CloudFolderEntity(id: 30, collectionId: 3, parentFolderId: null, name: 'Orders'),
    ];

    test('creates a local collection with the same nested folders and requests', () async {
      final copied = await useCase(CopyCloudCollectionParams(name: 'Team API', folders: folders, requests: [
        _cloud(id: 1, folderId: 20, name: 'Ban user', method: 'DELETE', url: '{{baseUrl}}/users/1'),
        _cloud(id: 2, folderId: 10, name: 'List users', method: 'GET'),
        _cloud(id: 3, folderId: null, name: 'Ping', method: 'GET'),
        _cloud(id: 4, folderId: 30, name: 'Create order', body: '{"sku":"A1"}'),
      ]));

      expect(db.collections.single.name, 'Team API');
      expect(copied.collectionId, db.collections.single.id);
      expect((copied.folders, copied.requests), (3, 4));
      expect(copied.description, '3 folders, 4 requests');

      final byName = {for (final f in db.folders) f.name: f};
      expect(byName['Admin']!.parentFolderId, byName['Users']!.id);
      expect(byName['Users']!.parentFolderId, isNull);
      expect(byName['Orders']!.parentFolderId, isNull);
      expect(db.folders.every((f) => f.collectionId == copied.collectionId), isTrue);

      final requests = {for (final r in db.requestsOf(copied.collectionId)) r.name: r};
      expect(requests['Ban user']!.folderId, byName['Admin']!.id);
      expect(requests['Ban user']!.method, HttpMethod.delete);
      expect(requests['Ban user']!.url, '{{baseUrl}}/users/1');
      expect(requests['List users']!.folderId, byName['Users']!.id);
      expect(requests['Ping']!.folderId, isNull);
      expect(requests['Create order']!.body.rawText, '{"sku":"A1"}');
      expect(requests['Create order']!.body.rawContentType, RawContentType.json);
      expect(requests['Ping']!.body.type, BodyType.none);
    });

    test('headers come over and cloud auth and query params are dropped', () async {
      await useCase(CopyCloudCollectionParams(name: 'X', folders: const [], requests: [_cloud()]));

      final copy = db.requests.single;
      expect(copy.headers.single.key, 'X-Team');
      expect(copy.headers.single.enabled, isFalse);
      expect(copy.auth.type, AuthType.inherit);
      expect(copy.queryParams, isEmpty);
    });

    test('a request whose folder is not part of the collection lands at the top level', () async {
      await useCase(CopyCloudCollectionParams(name: 'X', folders: const [], requests: [_cloud(folderId: 99)]));

      expect(db.requests.single.folderId, isNull);
    });

    test('a folder whose parent is missing, or that sits in a parent cycle, is flattened to the top level', () async {
      const odd = [
        CloudFolderEntity(id: 1, collectionId: 3, parentFolderId: 99, name: 'Orphan'),
        CloudFolderEntity(id: 2, collectionId: 3, parentFolderId: 3, name: 'A'),
        CloudFolderEntity(id: 3, collectionId: 3, parentFolderId: 2, name: 'B'),
        CloudFolderEntity(id: 4, collectionId: 3, parentFolderId: 1, name: 'Child'),
      ];

      final copied = await useCase(const CopyCloudCollectionParams(name: 'X', folders: odd, requests: []));

      final byName = {for (final f in db.folders) f.name: f};
      expect(copied.folders, 4);
      expect(byName['Orphan']!.parentFolderId, isNull);
      expect(byName['Child']!.parentFolderId, byName['Orphan']!.id);
      expect(byName['A']!.parentFolderId, isNull);
      expect(byName['B']!.parentFolderId, isNull);
    });

    test('an empty collection copies as an empty collection', () async {
      final copied = await useCase(const CopyCloudCollectionParams(name: 'Empty', folders: [], requests: []));

      expect(copied.description, '0 folders, 0 requests');
      expect(db.collections.single.name, 'Empty');
    });

    test('a failure midway removes the half-built collection and keeps existing data', () async {
      final existing = await db.collectionRepository.createCollection('Mine');
      db.failSaveRequestOnCall = 2;

      await expectLater(
        useCase(CopyCloudCollectionParams(name: 'Team API', folders: folders, requests: [_cloud(id: 1, folderId: 10), _cloud(id: 2, folderId: 10)])),
        throwsA(isA<StateError>()),
      );

      expect(db.collections.map((c) => c.id), [existing]);
      expect(db.folders, isEmpty);
      expect(db.requests, isEmpty);
    });
  });

  group('TeamViewModel: send', () {
    late _FakeTeamRepository repository;
    late List<({ApiRequestEntity request, ApiCancelToken? token})> sent;
    late Future<ApiResponseEntity> Function(ApiRequestEntity, {ApiCancelToken? cancelToken}) send;
    late TeamViewModel vm;
    late List<bool> sendingTrail;

    TeamViewModel build() => TeamViewModel(repository, sendRequest: (request, {cancelToken}) => send(request, cancelToken: cancelToken));

    setUp(() {
      repository = _FakeTeamRepository();
      sent = [];
      send = (request, {cancelToken}) async {
        sent.add((request: request, token: cancelToken));
        return _response(200);
      };
      vm = build();
      sendingTrail = [];
      vm.addListener(() => sendingTrail.add(vm.isSendingRequest));
    });

    tearDown(() => vm.dispose());

    test('sends the mapped request and keeps the response', () async {
      await vm.sendRequest(_cloud(body: '{"name":"John"}'));

      expect(sent, hasLength(1));
      expect(sent.single.request.collectionId, 0);
      expect(sent.single.request.auth.type, AuthType.none);
      expect(sent.single.request.body.rawContentType, RawContentType.json);
      expect(sent.single.token, isNotNull);
      expect(vm.sendResponse!.statusCode, 200);
      expect(vm.sendError, isNull);
      expect(vm.isSendingRequest, isFalse);
      expect(vm.hasSendResult, isTrue);
      expect(sendingTrail, [true, false]);
    });

    test('a failed send shows friendly text and drops the response of an earlier send', () async {
      await vm.sendRequest(_cloud());
      expect(vm.sendResponse, isNotNull);
      send = (request, {cancelToken}) async => throw const NetworkException('x', kind: NetworkErrorKind.timeout);

      await vm.sendRequest(_cloud());

      expect(vm.sendResponse, isNull);
      expect(vm.sendError, 'Request timed out');
      expect(vm.hasSendResult, isTrue);
      expect(vm.isSendingRequest, isFalse);
    });

    test('a later successful send clears the error', () async {
      send = (request, {cancelToken}) async => throw const InvalidUrlException('bad');
      await vm.sendRequest(_cloud(url: ''));
      expect(vm.sendError, contains('needs a host'));

      send = (request, {cancelToken}) async => _response(200);
      await vm.sendRequest(_cloud());

      expect(vm.sendError, isNull);
      expect(vm.sendResponse, isNotNull);
    });

    test('cancelling abandons the send without an error and keeps the earlier response', () async {
      await vm.sendRequest(_cloud());
      final earlier = vm.sendResponse;
      final gate = Completer<ApiResponseEntity>();
      send = (request, {cancelToken}) {
        cancelToken!.whenCancelled.then((_) => gate.completeError(const NetworkException('cancelled', kind: NetworkErrorKind.cancelled)));
        return gate.future;
      };

      final running = vm.sendRequest(_cloud());
      expect(vm.isSendingRequest, isTrue);
      vm.cancelSend();
      await running;

      expect(vm.isSendingRequest, isFalse);
      expect(vm.sendError, isNull);
      expect(vm.sendResponse, same(earlier));
    });

    test('a second send while one is running is ignored', () async {
      final gate = Completer<ApiResponseEntity>();
      send = (request, {cancelToken}) {
        sent.add((request: request, token: cancelToken));
        return gate.future;
      };

      final first = vm.sendRequest(_cloud());
      await vm.sendRequest(_cloud());
      gate.complete(_response(200));
      await first;

      expect(sent, hasLength(1));
    });

    test('opening another editor discards the result, and a send still running never shows up on it', () async {
      final gate = Completer<ApiResponseEntity>();
      send = (request, {cancelToken}) => gate.future;

      final running = vm.sendRequest(_cloud(id: 1));
      vm.startRequestEdit(_cloud(id: 2));
      expect(vm.isSendingRequest, isFalse);
      gate.complete(_response(200));
      await running;

      expect(vm.sendResponse, isNull);
      expect(vm.hasSendResult, isFalse);
    });

    test('opening an editor clears the previous request\'s response', () async {
      await vm.sendRequest(_cloud(id: 1));

      vm.startRequestEdit(_cloud(id: 2));

      expect(vm.sendResponse, isNull);
      expect(vm.sendError, isNull);
      expect(vm.hasSendResult, isFalse);
    });

    test('disposing abandons a send in flight', () async {
      final local = build();
      final gate = Completer<ApiResponseEntity>();
      ApiCancelToken? token;
      send = (request, {cancelToken}) {
        token = cancelToken;
        return gate.future;
      };

      unawaited(local.sendRequest(_cloud()));
      local.dispose();

      expect(token!.isCancelled, isTrue);
    });

    test('without a send function the controls stay hidden and sending does nothing', () async {
      final bare = TeamViewModel(repository);
      addTearDown(bare.dispose);

      await bare.sendRequest(_cloud());

      expect(bare.canSendRequests, isFalse);
      expect(bare.canCopyCollection, isFalse);
      expect(bare.hasSendResult, isFalse);
    });
  });

  group('TeamViewModel: sending through the real SendRequestUseCase', () {
    late InMemoryDb db;
    late _RecordingClient client;
    late _RecordingHistory history;
    late TeamViewModel vm;

    setUp(() {
      db = InMemoryDb();
      client = _RecordingClient();
      history = _RecordingHistory();
      // The exact wiring the injector uses: `locator<SendRequestUseCase>().call`.
      final sendRequest = SendRequestUseCase(
        client,
        BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository),
        history,
        db.collectionAuthRepository,
      );
      vm = TeamViewModel(_FakeTeamRepository(), sendRequest: sendRequest.call);
    });

    tearDown(() => vm.dispose());

    test('resolves globals and the active environment, and reads the body type from the text', () async {
      await db.globalVariableRepository.upsert(const GlobalVariableEntity(id: 0, key: 'host', value: 'api.example.com', isSecret: false, enabled: true));
      final environmentId = await db.environmentRepository.create('Dev');
      db.environments[0] = EnvironmentEntity(id: environmentId, name: 'Dev', isActive: true);
      await db.environmentRepository
          .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: environmentId, key: 'team', value: 'blue', isSecret: false, enabled: true));

      await vm.sendRequest(_cloud(
        method: 'POST',
        url: 'https://{{host}}/users',
        headers: [KeyValueItem(key: 'X-Team', value: '{{team}}'), KeyValueItem(key: 'X-Off', value: '1', enabled: false)],
        body: '{"name":"John"}',
      ));

      final spec = client.sent.single;
      expect(spec.method, 'POST');
      expect(spec.url, 'https://api.example.com/users');
      expect(spec.headers, {'X-Team': 'blue', 'Content-Type': 'application/json'});
      expect(String.fromCharCodes(spec.body as List<int>), '{"name":"John"}');
      expect(vm.sendResponse!.statusCode, 200);
      expect(history.recordedUrls, ['https://{{host}}/users']);
    });

    test('collection variables and collection auth of any local collection never apply', () async {
      final other = await db.collectionRepository.createCollection('Other');
      await db.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: other, key: 'host', value: 'wrong.example.com', enabled: true));
      await db.collectionAuthRepository.setAuthJson(other, const RequestAuth(type: AuthType.bearer, bearerToken: 'leak').toJsonString());

      await vm.sendRequest(_cloud(method: 'GET', url: 'https://api.example.com/{{host}}'));

      final spec = client.sent.single;
      expect(spec.url, 'https://api.example.com/{{host}}');
      expect(spec.headers.containsKey('Authorization'), isFalse);
    });

    test('a URL with no host fails with the friendly message before anything is sent', () async {
      await vm.sendRequest(_cloud(url: 'https:///users'));

      expect(client.sent, isEmpty);
      expect(vm.sendError, contains('needs a host'));
    });

    test('a client failure is described, not leaked', () async {
      client.failWith = const NetworkException('dio said something internal', kind: NetworkErrorKind.connectionError);

      await vm.sendRequest(_cloud());

      expect(vm.sendError, contains("Couldn't reach the server"));
      expect(vm.sendError, isNot(contains('internal')));
    });
  });

  group('TeamViewModel: copy to my collections', () {
    late _FakeTeamRepository repository;
    late InMemoryDb db;
    late TeamViewModel vm;

    setUp(() {
      repository = _FakeTeamRepository();
      db = InMemoryDb();
      vm = TeamViewModel(repository, copyCollection: CopyCloudCollectionUseCase(db.collectionRepository, db.requestRepository));
    });

    tearDown(() => vm.dispose());

    Future<void> loadCollection(TeamViewModel target) async {
      target.selectCollection(3);
      repository.members.add(const [CollectionMemberEntity(collectionId: 3, userId: 'u', role: MemberRole.viewer)]);
      repository.folders.add(const [CloudFolderEntity(id: 10, collectionId: 3, parentFolderId: null, name: 'Users')]);
      repository.requests.add([
        _cloud(id: 1, folderId: 10, name: 'List users', method: 'GET'),
        _cloud(id: 2, folderId: null, name: 'Ping', method: 'GET'),
      ]);
      await pumpEventQueue();
    }

    test('copies what is loaded for the selected collection', () async {
      await loadCollection(vm);

      final copied = await vm.copyCollectionToLocal(_collection);

      expect(copied!.description, '1 folder, 2 requests');
      expect(db.collections.single.name, 'Team API');
      expect(db.requestsOf(copied.collectionId).map((r) => r.name), unorderedEquals(['List users', 'Ping']));
      expect(vm.isCopyingCollection, isFalse);
      expect(vm.errorMessage, isNull);
    });

    test('waits for the collection to finish loading', () async {
      vm.selectCollection(3);

      final copied = await vm.copyCollectionToLocal(_collection);

      expect(copied, isNull);
      expect(vm.errorMessage, contains('finished loading'));
      expect(db.collections, isEmpty);
    });

    test('only copies the collection that is open', () async {
      await loadCollection(vm);

      final copied = await vm.copyCollectionToLocal(const CloudCollectionEntity(id: 4, name: 'Other', ownerId: 'o'));

      expect(copied, isNull);
      expect(db.collections, isEmpty);
    });

    test('a failure is reported and leaves nothing behind', () async {
      await loadCollection(vm);
      db.failSaveRequestOnCall = 1;

      final copied = await vm.copyCollectionToLocal(_collection);

      expect(copied, isNull);
      expect(vm.errorMessage, 'Failed to copy collection');
      expect(vm.isCopyingCollection, isFalse);
      expect(db.collections, isEmpty);
    });

    test('a second copy while one is running is ignored', () async {
      final gate = Completer<CopiedCollection>();
      final gated = TeamViewModel(repository, copyCollection: _Gated(gate.future));
      addTearDown(gated.dispose);
      await loadCollection(gated);

      final first = gated.copyCollectionToLocal(_collection);
      final second = await gated.copyCollectionToLocal(_collection);
      gate.complete(const CopiedCollection(collectionId: 1, folders: 0, requests: 0));
      await first;

      expect(second, isNull);
    });
  });
}

final class _RecordingClient implements ApiClient {
  final sent = <ApiRequestSpec>[];
  NetworkException? failWith;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(spec);
    return const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
  }
}

final class _RecordingHistory implements HistoryRepository {
  final recordedUrls = <String>[];

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async =>
      recordedUrls.add(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class _Gated implements UseCase<CopiedCollection, CopyCloudCollectionParams> {
  final Future<CopiedCollection> _result;
  const _Gated(this._result);

  @override
  Future<CopiedCollection> call(CopyCloudCollectionParams params) => _result;
}

/// Just the live streams `selectCollection` subscribes to, and no invites.
final class _FakeTeamRepository implements TeamRepository {
  final members = StreamController<List<CollectionMemberEntity>>.broadcast();
  final folders = StreamController<List<CloudFolderEntity>>.broadcast();
  final requests = StreamController<List<CloudRequestEntity>>.broadcast();

  @override
  Stream<List<CollectionMemberEntity>> watchMembers(int collectionId) => members.stream;

  @override
  Stream<List<CloudFolderEntity>> watchFolders(int collectionId) => folders.stream;

  @override
  Stream<List<CloudRequestEntity>> watchRequests(int collectionId) => requests.stream;

  @override
  Future<List<CollectionInviteEntity>> listCollectionInvites(int collectionId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
