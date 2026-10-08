import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/data/repositories/collection_auth_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_variable_repository_impl.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/git_sync/data/repositories/entity_uid_registry.dart';
import 'package:postpilot/features/git_sync/data/repositories/local_collection_store_impl.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_exceptions.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/repo_layout.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/git_sync/domain/services/three_way_merger.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_repository_impl.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

const _alreadyCloned = 'This collection is already cloned on this device.';

const _dumpedTables = [
  'collections',
  'folders',
  'requests',
  'collection_variables',
  'collection_auth',
  'request_scripts',
  'request_setting_entries',
  'entity_uids',
  'entity_docs',
  'entity_tags',
];

/// One installation of the app: its own database, uid registry and store.
final class Device {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final uids = EntityUidRegistry(db.entityUidsDao);
  late final store = LocalCollectionStoreImpl(db, uids);
  late final _collections = CollectionRepositoryImpl(db.collectionsDao);
  late final _requests = RequestRepositoryImpl(db.requestsDao);
  late final _variables = CollectionVariableRepositoryImpl(db.collectionVariablesDao);
  late final _auth = CollectionAuthRepositoryImpl(db.collectionAuthDao);

  Future<void> close() => db.close();

  Future<SyncSnapshot> read(int collectionId, {bool secrets = true}) =>
      store.readSnapshot(collectionId, includeSecrets: secrets);

  /// Every row of the tables sync touches, to prove a failed apply changed nothing.
  Future<Map<String, List<Map<String, Object?>>>> dump() async => {
        for (final table in _dumpedTables)
          table: [for (final row in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get()) row.data],
      };

  Future<int> addCollection(String name) => _collections.createCollection(name);

  Future<int> addFolder(int collectionId, String name, {int? parent, int order = 0}) async {
    final id = await _collections.createFolder(collectionId: collectionId, parentFolderId: parent, name: name);
    if (order != 0) {
      await (db.update(db.folders)..where((t) => t.id.equals(id))).write(FoldersCompanion(orderIndex: Value(order)));
    }
    return id;
  }

  Future<int> addRequest(
    int collectionId,
    String name, {
    int? folder,
    int order = 0,
    HttpMethod method = HttpMethod.get,
    String url = '',
    List<KeyValueItem> headers = const [],
    List<KeyValueItem> queryParams = const [],
    RequestBody body = const RequestBody(),
    RequestAuth auth = const RequestAuth(),
  }) async {
    final id = await _requests.createRequest(collectionId: collectionId, folderId: folder, name: name);
    await _requests.saveRequest(ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: folder,
      name: name,
      method: method,
      url: url,
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: auth,
    ));
    if (order != 0) await db.requestsDao.updateRequest(id, RequestsCompanion(orderIndex: Value(order)));
    return id;
  }

  Future<void> addVariable(int collectionId, String key, String value, {bool enabled = true}) => _variables.upsert(
        CollectionVariableEntity(id: 0, collectionId: collectionId, key: key, value: value, enabled: enabled),
      );

  Future<void> setCollectionAuth(int collectionId, RequestAuth auth) =>
      _auth.setAuthJson(collectionId, auth.toJsonString());

  Future<int> requestId(String uid) async => (await uids.localIdFor(SyncKind.request, uid))!;

  /// A collection that uses every body type, auth type and http method, with
  /// nested folders, an empty folder, explicit orders, variables (two of them
  /// secret), collection auth, tests, settings, descriptions and tags.
  Future<Rich> buildRich() async {
    final c = await addCollection('Payments API');
    final v1 = await addFolder(c, 'v1', order: 2);
    final users = await addFolder(c, 'users', parent: v1, order: 1);
    final admin = await addFolder(c, 'admin', parent: users);
    final empty = await addFolder(c, 'empty', order: 1);
    final docs = await addFolder(c, 'Docs');

    final ids = <String, int>{};
    Future<void> add(
      String name, {
      int? folder,
      int order = 0,
      HttpMethod method = HttpMethod.get,
      String url = '',
      List<KeyValueItem> headers = const [],
      List<KeyValueItem> queryParams = const [],
      RequestBody body = const RequestBody(),
      RequestAuth auth = const RequestAuth(),
    }) async {
      ids[name] = await addRequest(
        c,
        name,
        folder: folder,
        order: order,
        method: method,
        url: url,
        headers: headers,
        queryParams: queryParams,
        body: body,
        auth: auth,
      );
    }

    await add('Bare');
    await add('Health', order: 3, url: 'https://api.test/health');
    await add(
      'List users',
      folder: users,
      order: 2,
      url: 'https://api.test/users?page={{page}}',
      headers: [
        KeyValueItem(key: 'Accept', value: 'application/json'),
        KeyValueItem(key: 'X-Debug', value: '1', enabled: false),
      ],
      queryParams: [KeyValueItem(key: 'page', value: '1'), KeyValueItem(key: 'limit', value: '50', enabled: false)],
      auth: authFor(AuthType.bearer),
    );
    await add(
      'Create user',
      folder: users,
      method: HttpMethod.post,
      url: 'https://api.test/users',
      headers: [KeyValueItem(key: 'Content-Type', value: 'application/json')],
      body: const RequestBody(type: BodyType.raw, rawText: '{"name":"Ada"}'),
      auth: authFor(AuthType.basic),
    );
    await add(
      'Login',
      folder: v1,
      method: HttpMethod.post,
      url: 'https://api.test/login',
      body: RequestBody(
        type: BodyType.urlEncoded,
        urlEncodedFields: [
          KeyValueItem(key: 'user', value: 'ada'),
          KeyValueItem(key: 'pass', value: 's3cret', enabled: false),
        ],
      ),
      auth: authFor(AuthType.digest),
    );
    await add(
      'Upload avatar',
      folder: admin,
      method: HttpMethod.put,
      url: 'https://api.test/avatar',
      body: RequestBody(
        type: BodyType.formData,
        formFields: [
          KeyValueItem(key: 'name', value: 'Ada'),
          KeyValueItem(key: 'file', value: '@me.png', enabled: false),
        ],
      ),
      auth: authFor(AuthType.apiKey),
    );
    // Files travel as references only: a form-data file row, and a binary body (its file is a nameless file row).
    await add(
      'Upload photo',
      folder: admin,
      method: HttpMethod.post,
      url: 'https://api.test/photo',
      body: RequestBody(
        type: BodyType.formData,
        formFields: [
          KeyValueItem(
            key: 'photo',
            value: '{{uploadDir}}/me.png',
            kind: FormFieldKind.file,
            fileName: 'portrait.png',
            contentType: 'image/png',
          ),
        ],
      ),
    );
    await add(
      'Upload backup',
      folder: docs,
      method: HttpMethod.put,
      url: 'https://api.test/backup',
      body: const RequestBody(type: BodyType.binary).withBinaryFile(
        KeyValueItem(key: '', value: '{{backupDir}}/backup.tar', kind: FormFieldKind.file, contentType: 'application/x-tar'),
      ),
    );
    await add(
      'GraphQL',
      folder: v1,
      method: HttpMethod.post,
      url: 'https://api.test/graphql',
      body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'query { me { id } }', graphqlVariables: '{"a":1}'),
      auth: authFor(AuthType.awsSignatureV4),
    );
    await add(
      'Ünïcode "quoted" \u{1F680}',
      url: 'https://api.test/search?q=café &x=%20',
      headers: [KeyValueItem(key: 'X-Emoji', value: '\u{1F680} "hi"')],
      body: const RequestBody(
        type: BodyType.raw,
        rawContentType: RawContentType.text,
        rawText: 'line1\nline2\t\\ "q" \u{1F680} </script>',
      ),
    );
    for (final type in RawContentType.values) {
      await add(
        'Raw ${type.name}',
        folder: docs,
        body: RequestBody(type: BodyType.raw, rawContentType: type, rawText: 'body of ${type.name}'),
        auth: type == RawContentType.json ? authFor(AuthType.jwtBearer) : const RequestAuth(),
      );
    }
    for (final method in HttpMethod.values) {
      await add('Method ${method.name}', folder: docs, method: method, url: 'https://api.test/${method.name}');
    }
    for (final type in AuthType.values) {
      await add('Auth ${type.name}', folder: admin, auth: authFor(type));
    }
    for (final grant in OAuth2GrantType.values) {
      await add('OAuth ${grant.name}', folder: admin, auth: authFor(AuthType.oauth2).copyWith(oauth2GrantType: grant));
    }

    await addVariable(c, 'zeta', 'z');
    await addVariable(c, 'baseUrl', 'https://api.test');
    await addVariable(c, 'apiToken', 'tok-123');
    await addVariable(c, 'dup', 'first');
    await addVariable(c, 'dup', 'second', enabled: false);
    await addVariable(c, 'region', 'eu', enabled: false);
    await addVariable(c, 'dbPassword', 'pw-456');
    await setCollectionAuth(c, authFor(AuthType.bearer).copyWith(bearerToken: 'collection-secret'));

    await db.entityDocsDao.setMarkdown('collection', c, '# Payments\nInternal API');
    await db.entityTagsDao.setTags('collection', c, ['internal', 'Beta', 'api']);
    await db.entityDocsDao.setMarkdown('folder', users, 'All about users');
    await db.entityTagsDao.setTags('folder', admin, ['staff']);
    await db.entityDocsDao.setMarkdown('request', ids['Create user']!, 'Creates a user.\n\n- returns 201');
    await db.entityTagsDao.setTags('request', ids['List users']!, ['read', 'Users']);
    await db.requestScriptsDao.upsert(RequestScriptsCompanion.insert(
      requestId: Value(ids['List users']!),
      assertionsJson: Value(jsonEncode([
        {'type': 'statusIn2xx', 'path': '', 'expected': ''},
        {'type': 'jsonPathEquals', 'path': r'$.ok', 'expected': 'true'},
      ])),
      extractorsJson: Value(jsonEncode([
        {'source': 'jsonPath', 'path': r'$.token', 'scope': 'environment', 'key': 'token'},
      ])),
    ));
    await db.requestSettingsDao.put(ids['Health']!, jsonEncode({'followRedirects': false, 'timeoutMs': 5000}));

    return Rich(c, {'v1': v1, 'users': users, 'admin': admin, 'empty': empty, 'Docs': docs}, ids);
  }
}

final class Rich {
  final int collection;
  final Map<String, int> folders;
  final Map<String, int> requests;
  const Rich(this.collection, this.folders, this.requests);
}

RequestAuth authFor(AuthType type) => switch (type) {
      AuthType.none => const RequestAuth(type: AuthType.none),
      AuthType.inherit => const RequestAuth(),
      AuthType.apiKey => const RequestAuth(
          type: AuthType.apiKey,
          apiKeyName: 'X-Api-Key',
          apiKeyValue: 'key-123',
          apiKeyLocation: ApiKeyLocation.query,
        ),
      AuthType.bearer => const RequestAuth(type: AuthType.bearer, bearerToken: 'bearer-abc'),
      AuthType.basic => const RequestAuth(type: AuthType.basic, basicUsername: 'ada', basicPassword: 'basic-pw'),
      AuthType.digest => const RequestAuth(type: AuthType.digest, basicUsername: 'ada', basicPassword: 'digest-pw'),
      AuthType.awsSignatureV4 => const RequestAuth(
          type: AuthType.awsSignatureV4,
          awsAccessKey: 'AKIA123',
          awsSecretKey: 'aws-secret',
          awsRegion: 'eu-west-1',
          awsService: 's3',
          awsSessionToken: 'aws-session',
        ),
      AuthType.jwtBearer => const RequestAuth(
          type: AuthType.jwtBearer,
          jwtSecret: 'jwt-secret',
          jwtAlgorithm: JwtAlgorithm.hs512,
          jwtPayload: '{"sub":"1"}',
          jwtHeaderPrefix: 'JWT',
        ),
      AuthType.hmac => const RequestAuth(
          type: AuthType.hmac,
          hmacPreset: HmacPreset.generic,
          hmacSecret: 'hmac-secret',
          hmacAlgorithm: HmacAlgorithm.sha512,
          hmacEncoding: HmacEncoding.base64,
          hmacPayloadTemplate: 'v0:{timestamp}:{body}',
          hmacHeaderName: 'X-Signature',
          hmacHeaderTemplate: 'v0={signature}',
          hmacTimestampHeader: 'X-Timestamp',
        ),
      AuthType.oauth2 => RequestAuth(
          type: AuthType.oauth2,
          oauth2GrantType: OAuth2GrantType.password,
          oauth2AccessTokenUrl: 'https://auth.test/token',
          oauth2ClientId: 'client-id',
          oauth2ClientSecret: 'oauth-client-secret',
          oauth2ClientAuthentication: OAuth2ClientAuthentication.body,
          oauth2Scope: 'read write',
          oauth2Username: 'ada',
          oauth2Password: 'oauth-pw',
          oauth2AccessToken: 'oauth-access',
          oauth2RefreshToken: 'oauth-refresh',
          oauth2TokenExpiry: DateTime.utc(2030, 1, 2, 3, 4, 5),
        ),
    };

Map<String, String> texts(SyncSnapshot snapshot) => {
      for (final e in snapshot.docs.entries) e.key: e.value.canonicalText,
    };

SyncDoc docNamed(SyncSnapshot snapshot, String name, [SyncKind kind = SyncKind.request]) =>
    snapshot.docs.values.singleWhere((doc) => doc.kind == kind && doc.name == name);

Map<String, Object?> authOf(SyncDoc doc) => Map<String, Object?>.from(doc.data['auth'] as Map);

/// [doc] with fields replaced or removed.
SyncDoc edit(
  SyncDoc doc, {
  String? name,
  String? parent,
  int? order,
  Map<String, Object?> set = const {},
  Iterable<String> remove = const [],
}) =>
    SyncDoc(
      uid: doc.uid,
      kind: doc.kind,
      parentUid: parent ?? doc.parentUid,
      name: name ?? doc.name,
      order: order ?? doc.order,
      data: {...doc.data, ...set}..removeWhere((key, _) => remove.contains(key)),
    );

/// [snapshot] with docs added or replaced and the uids in [drop] removed.
SyncSnapshot snapshotWith(
  SyncSnapshot snapshot, {
  Iterable<SyncDoc> put = const [],
  Iterable<String> drop = const [],
}) =>
    SyncSnapshot({
      for (final doc in snapshot.docs.values)
        if (!drop.contains(doc.uid)) doc.uid: doc,
      for (final doc in put) doc.uid: doc,
    });

SyncSnapshot snapshotOf(Iterable<SyncDoc> docs) => SyncSnapshot({for (final doc in docs) doc.uid: doc});

SyncDoc collectionDoc(String uid, String name, {Map<String, Object?> data = const {}}) =>
    SyncDoc(uid: uid, kind: SyncKind.collection, parentUid: null, name: name, data: data);

SyncDoc folderDoc(String uid, String name, String parent, {int order = 0, Map<String, Object?> data = const {}}) =>
    SyncDoc(uid: uid, kind: SyncKind.folder, parentUid: parent, name: name, order: order, data: data);

SyncDoc requestDoc(String uid, String name, String parent, {int order = 0, Map<String, Object?> data = const {}}) =>
    SyncDoc(
      uid: uid,
      kind: SyncKind.request,
      parentUid: parent,
      name: name,
      order: order,
      data: {'method': 'get', 'url': '', ...data},
    );

Matcher gitSyncError(Object message) => throwsA(isA<GitSyncException>().having((e) => e.message, 'message', message));

void main() {
  // Two devices are two databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Device a;

  setUp(() => a = Device());
  tearDown(() => a.close());

  Device newDevice() {
    final device = Device();
    addTearDown(device.close);
    return device;
  }

  group('readSnapshot', () {
    test('docs follow the on-disk schema', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final root = snapshot.root!;

      expect(root.kind, SyncKind.collection);
      expect(root.parentUid, isNull);
      expect(root.name, 'Payments API');
      expect(root.order, 0);
      expect(root.data.keys, unorderedEquals(['description', 'tags', 'variables', 'auth']));
      expect(root.data['description'], '# Payments\nInternal API');
      expect(root.data['tags'], ['api', 'Beta', 'internal']);
      expect(root.data['variables'], [
        {'key': 'apiToken', 'value': 'tok-123', 'enabled': true},
        {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
        {'key': 'dbPassword', 'value': 'pw-456', 'enabled': true},
        {'key': 'dup', 'value': 'first', 'enabled': true},
        {'key': 'dup', 'value': 'second', 'enabled': false},
        {'key': 'region', 'value': 'eu', 'enabled': false},
        {'key': 'zeta', 'value': 'z', 'enabled': true},
      ]);
      expect(authOf(root)['type'], 'bearer');
      expect(authOf(root)['bearerToken'], 'collection-secret');

      final v1 = docNamed(snapshot, 'v1', SyncKind.folder);
      final users = docNamed(snapshot, 'users', SyncKind.folder);
      final admin = docNamed(snapshot, 'admin', SyncKind.folder);
      expect(v1.parentUid, root.uid);
      expect(v1.order, 2);
      expect(v1.data, isEmpty);
      expect(users.parentUid, v1.uid);
      expect(users.order, 1);
      expect(users.data, {'description': 'All about users'});
      expect(admin.parentUid, users.uid);
      expect(admin.data, {'tags': ['staff']});
      expect(docNamed(snapshot, 'empty', SyncKind.folder).parentUid, root.uid);

      final bare = docNamed(snapshot, 'Bare');
      expect(bare.parentUid, root.uid);
      expect(bare.data.keys, unorderedEquals(['method', 'url', 'headers', 'queryParams', 'body', 'auth']));
      expect(bare.data['method'], 'get');
      expect(bare.data['headers'], isEmpty);
      expect(bare.data['body'], {
        'type': 'none',
        'rawContentType': 'json',
        'rawText': '',
        'formFields': <Object?>[],
        'urlEncodedFields': <Object?>[],
        'graphqlQuery': '',
        'graphqlVariables': '{}',
      });
      expect(authOf(bare)['type'], 'inherit');

      final list = docNamed(snapshot, 'List users');
      expect(list.parentUid, users.uid);
      expect(list.order, 2);
      expect(list.data['headers'], [
        {'key': 'Accept', 'value': 'application/json', 'enabled': true},
        {'key': 'X-Debug', 'value': '1', 'enabled': false},
      ]);
      expect(list.data['queryParams'], [
        {'key': 'page', 'value': '1', 'enabled': true},
        {'key': 'limit', 'value': '50', 'enabled': false},
      ]);
      expect(list.data['tests'], {
        'assertions': [
          {'type': 'statusIn2xx', 'path': '', 'expected': ''},
          {'type': 'jsonPathEquals', 'path': r'$.ok', 'expected': 'true'},
        ],
        'extractors': [
          {'source': 'jsonPath', 'path': r'$.token', 'scope': 'environment', 'key': 'token'},
        ],
      });
      expect(list.data['tags'], ['read', 'Users']);
      expect(list.data.containsKey('settings'), isFalse);
      expect(list.data.containsKey('description'), isFalse);

      expect(docNamed(snapshot, 'Health').data['settings'], {'followRedirects': false, 'timeoutMs': 5000});
      expect(docNamed(snapshot, 'Health').order, 3);
      expect(docNamed(snapshot, 'Create user').data['description'], 'Creates a user.\n\n- returns 201');
      expect(docNamed(snapshot, 'Login').data['body'], containsPair('type', 'urlEncoded'));

      final bodyTypes = {
        for (final doc in snapshot.docs.values)
          if (doc.kind == SyncKind.request) (doc.data['body'] as Map)['type'],
      };
      final authTypes = {
        for (final doc in snapshot.docs.values)
          if (doc.kind == SyncKind.request) authOf(doc)['type'],
      };
      expect(bodyTypes, BodyType.values.map((t) => t.name).toSet());
      expect(authTypes, AuthType.values.map((t) => t.name).toSet());
    });

    test('uids are assigned once and stay the same across calls', () async {
      final rich = await a.buildRich();
      final first = await a.read(rich.collection);
      final second = await a.read(rich.collection, secrets: false);

      expect(second.docs.keys.toSet(), first.docs.keys.toSet());
      expect(second.root!.uid, first.root!.uid);
      for (final doc in first.docs.values) {
        expect(doc.uid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
        expect(await a.uids.localIdFor(doc.kind, doc.uid), isNotNull);
      }

      final lateId = await a.addRequest(rich.collection, 'Late');
      final third = await a.read(rich.collection);
      final lateUid = await a.uids.uidFor(SyncKind.request, lateId);
      expect(third.docs.keys.toSet().difference(first.docs.keys.toSet()), {lateUid});
      expect({...texts(third)}..remove(lateUid), texts(first));
    });

    test('a collection nobody added anything to is just its collection doc', () async {
      final id = await a.addCollection('Empty');
      final snapshot = await a.read(id);
      expect(snapshot.docs.length, 1);
      expect(snapshot.root!.name, 'Empty');
      expect(snapshot.root!.data, isEmpty);
    });

    test('an unknown collection is reported, not treated as empty', () async {
      await expectLater(a.read(999), gitSyncError(contains('no longer exists')));
    });

    test('a collection auth of "no auth" counts as none set', () async {
      final id = await a.addCollection('c');
      await a.setCollectionAuth(id, const RequestAuth(type: AuthType.none));
      expect((await a.read(id)).root!.data.containsKey('auth'), isFalse);
      await a.db.collectionAuthDao.upsert(id, '{}');
      expect((await a.read(id)).root!.data.containsKey('auth'), isFalse);
      await a.setCollectionAuth(id, authFor(AuthType.bearer));
      expect(authOf((await a.read(id)).root!)['type'], 'bearer');
    });

    test('a stored tests or settings column that no longer parses counts as empty', () async {
      final id = await a.addCollection('c');
      final request = await a.addRequest(id, 'r');
      await a.db.requestScriptsDao.upsert(
        RequestScriptsCompanion.insert(requestId: Value(request), assertionsJson: const Value('not json')),
      );
      await a.db.requestSettingsDao.put(request, '[1, 2]');

      final doc = docNamed(await a.read(id), 'r');

      expect(doc.data.containsKey('tests'), isFalse);
      expect(doc.data.containsKey('settings'), isFalse);
    });

    test('a folder cycle in the database is read without looping and deleted without looping', () async {
      final id = await a.addCollection('c');
      final first = await a.addFolder(id, 'first');
      final second = await a.addFolder(id, 'second', parent: first);
      await (a.db.update(a.db.folders)..where((t) => t.id.equals(first)))
          .write(FoldersCompanion(parentFolderId: Value(second)));
      final snapshot = await a.read(id);
      expect(snapshot.docs.length, 3);

      final outcome = await a.store.applySnapshot(snapshotOf([snapshot.root!]), collectionId: id);

      expect(outcome.deleted, 2);
      expect(await a.db.select(a.db.folders).get(), isEmpty);
    });
  });

  group('secrets on read', () {
    test('includeSecrets false strips credentials from auth maps and masks secret-looking variables', () async {
      final rich = await a.buildRich();
      final full = await a.read(rich.collection);
      final stripped = await a.read(rich.collection, secrets: false);

      expect(texts(stripped), texts(SecretFields.stripSnapshot(full)));
      for (final doc in stripped.docs.values) {
        final auth = doc.data['auth'];
        if (auth is Map) expect(auth.keys.toSet().intersection(SecretFields.authKeys), isEmpty, reason: doc.name);
      }
      expect(authOf(docNamed(stripped, 'Auth bearer')), containsPair('type', 'bearer'));
      expect(authOf(docNamed(stripped, 'Auth basic')), containsPair('basicUsername', 'ada'));
      expect(authOf(docNamed(stripped, 'Auth oauth2')), containsPair('oauth2ClientId', 'client-id'));
      expect(authOf(docNamed(full, 'Auth oauth2')), containsPair('oauth2AccessToken', 'oauth-access'));
      expect(authOf(docNamed(full, 'Auth oauth2')), containsPair('oauth2TokenExpiry', '2030-01-02T03:04:05.000Z'));
      expect(authOf(stripped.root!), isNot(contains('bearerToken')));

      expect(stripped.root!.data['variables'], [
        {'key': 'apiToken', 'value': '', 'enabled': true},
        {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
        {'key': 'dbPassword', 'value': '', 'enabled': true},
        {'key': 'dup', 'value': 'first', 'enabled': true},
        {'key': 'dup', 'value': 'second', 'enabled': false},
        {'key': 'region', 'value': 'eu', 'enabled': false},
        {'key': 'zeta', 'value': 'z', 'enabled': true},
      ]);
    });
  });

  group('round trip', () {
    test('a collection cloned onto another device reads back as equal docs with the same uids', () async {
      final rich = await a.buildRich();
      final first = await a.read(rich.collection);

      final b = newDevice();
      final noise = await b.addCollection('unrelated');
      await b.addFolder(noise, 'noise');
      await b.addRequest(noise, 'noise request');
      final outcome = await b.store.applySnapshot(first);

      expect(outcome.collectionId, isNot(noise));
      expect(outcome.added, first.docs.length);
      expect(outcome.updated, 0);
      expect(outcome.deleted, 0);
      expect(outcome.changedRequestIds, isEmpty);
      final second = await b.read(outcome.collectionId);
      expect(texts(second), texts(first));
      expect(second.root!.uid, first.root!.uid);
      for (final doc in first.docs.values) {
        expect(await b.uids.localIdFor(doc.kind, doc.uid), isNotNull, reason: doc.name);
      }
      expect(await b.uids.localIdFor(SyncKind.collection, first.root!.uid), outcome.collectionId);

      // the clone is independent of what it was cloned from
      Future<Map<String, int>> orders(Device d, int id) async {
        final folders = await (d.db.select(d.db.folders)..where((t) => t.collectionId.equals(id))).get();
        final requests = await (d.db.select(d.db.requests)..where((t) => t.collectionId.equals(id))).get();
        return {
          for (final f in folders) 'f:${f.name}': f.orderIndex,
          for (final r in requests) 'r:${r.name}': r.orderIndex,
        };
      }
      expect(await orders(b, outcome.collectionId), await orders(a, rich.collection));
      expect((await orders(b, outcome.collectionId))['f:v1'], 2);
      expect((await orders(b, outcome.collectionId))['r:Health'], 3);
    });

    test('docs survive being written to repository files and read back, so a clone from files matches', () async {
      final rich = await a.buildRich();
      final first = await a.read(rich.collection);
      final files = RepoLayout.toFiles(first, basePath: 'apis/payments');
      expect(files.keys, contains('apis/payments/collection.json'));

      final parsed = RepoLayout.fromFiles(files, basePath: 'apis/payments');
      expect(parsed.skippedPaths, isEmpty);
      expect(texts(parsed.snapshot), texts(first));

      final b = newDevice();
      final outcome = await b.store.applySnapshot(parsed.snapshot);
      expect(texts(await b.read(outcome.collectionId)), texts(first));
    });

    test('a collection deleted here and cloned again gets new local ids under the same uids', () async {
      final rich = await a.buildRich();
      final first = await a.read(rich.collection);
      final oldRequestIds = {for (final id in rich.requests.values) id};
      await a.db.collectionsDao.deleteCollection(rich.collection);

      final outcome = await a.store.applySnapshot(first);

      expect(outcome.collectionId, isNot(rich.collection));
      final second = await a.read(outcome.collectionId);
      expect(texts(second), texts(first));
      final newRequestIds = {
        for (final doc in second.docs.values)
          if (doc.kind == SyncKind.request) await a.requestId(doc.uid),
      };
      expect(newRequestIds.length, oldRequestIds.length);
      expect(newRequestIds.intersection(oldRequestIds), isEmpty);
    });

    test('applying what was just read changes nothing and touches no row', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final stamp = DateTime(2001, 2, 3, 4, 5, 6);
      await a.db.update(a.db.requests).write(RequestsCompanion(updatedAt: Value(stamp)));
      final before = await a.dump();

      final outcome = await a.store.applySnapshot(snapshot, collectionId: rich.collection);

      expect(outcome.collectionId, rich.collection);
      expect([outcome.added, outcome.updated, outcome.deleted], [0, 0, 0]);
      expect(outcome.changedRequestIds, isEmpty);
      expect(outcome.deletedRequestIds, isEmpty);
      expect(await a.dump(), before);
    });

    test('docs that are not in canonical form apply as their canonical form and then count as unchanged', () async {
      final loose = snapshotOf([
        collectionDoc('root', 'Loose', data: {
          'description': '',
          'tags': ['  b ', 'B', 'a', ''],
          'variables': [
            {'key': 'z', 'value': '1'},
            {'key': 'a', 'value': '2', 'enabled': false},
          ],
          'auth': {'type': 'none'},
        }),
        folderDoc('f', 'Folder', 'root', data: {'tags': [], 'description': ''}),
        requestDoc('r', 'Request', 'f', data: {
          'method': 'POST',
          'body': {'type': 'raw', 'rawText': 'x'},
          'headers': [
            {'key': 'k', 'value': 'v'},
          ],
          'tests': {'assertions': [], 'extractors': []},
          'settings': {},
        }),
      ]);
      final outcome = await a.store.applySnapshot(loose);
      final canonical = await a.read(outcome.collectionId);

      expect(canonical.root!.data, {
        'tags': ['a', 'b'],
        'variables': [
          {'key': 'a', 'value': '2', 'enabled': false},
          {'key': 'z', 'value': '1', 'enabled': true},
        ],
      });
      expect(docNamed(canonical, 'Folder', SyncKind.folder).data, isEmpty);
      final request = docNamed(canonical, 'Request');
      expect(request.data['method'], 'post');
      expect(request.data['headers'], [
        {'key': 'k', 'value': 'v', 'enabled': true},
      ]);
      expect((request.data['body'] as Map)['type'], 'raw');
      expect((request.data['body'] as Map)['rawContentType'], 'json');
      expect(authOf(request)['type'], 'inherit');
      expect(request.data.keys, unorderedEquals(['method', 'url', 'headers', 'queryParams', 'body', 'auth']));

      final again = await a.store.applySnapshot(loose, collectionId: outcome.collectionId);
      expect([again.added, again.updated, again.deleted], [0, 0, 0]);
    });

    test('null where a doc may leave a field out counts as leaving it out', () async {
      final nulls = snapshotOf([
        collectionDoc('root', 'Nulls', data: {'description': null, 'tags': null, 'variables': null, 'auth': null}),
        folderDoc('f', 'Folder', 'root', data: {'description': null, 'tags': null}),
        requestDoc('r', 'Request', 'f', data: {
          'headers': null,
          'queryParams': null,
          'body': null,
          'auth': null,
          'tests': null,
          'settings': null,
          'description': null,
          'tags': null,
        }),
      ]);

      final outcome = await a.store.applySnapshot(nulls);

      final read = await a.read(outcome.collectionId);
      expect(read.root!.data, isEmpty);
      expect(docNamed(read, 'Folder', SyncKind.folder).data, isEmpty);
      final request = docNamed(read, 'Request');
      expect(request.data.keys, unorderedEquals(['method', 'url', 'headers', 'queryParams', 'body', 'auth']));
      expect(authOf(request)['type'], 'inherit');
      expect((await a.store.applySnapshot(nulls, collectionId: outcome.collectionId)).updated, 0);
    });
  });

  group('applySnapshot on an existing collection', () {
    test('updates what changed, reports it, and leaves other rows untouched', () async {
      final rich = await a.buildRich();
      final before = await a.read(rich.collection);
      final stamp = DateTime(2001, 2, 3, 4, 5, 6);
      await a.db.update(a.db.requests).write(RequestsCompanion(updatedAt: Value(stamp)));

      final root = before.root!;
      final list = docNamed(before, 'List users');
      final health = docNamed(before, 'Health');
      final bare = docNamed(before, 'Bare');
      final v1 = docNamed(before, 'v1', SyncKind.folder);
      final users = docNamed(before, 'users', SyncKind.folder);
      final freshFolder = folderDoc('uid-fresh-folder', 'fresh', root.uid);
      final freshRequest = requestDoc('uid-fresh-request', 'Fresh request', freshFolder.uid, data: {
        'method': 'post',
        'headers': <Object?>[],
        'queryParams': <Object?>[],
        'body': {
          'type': 'raw',
          'rawContentType': 'json',
          'rawText': '{}',
          'formFields': <Object?>[],
          'urlEncodedFields': <Object?>[],
          'graphqlQuery': '',
          'graphqlVariables': '{}',
        },
        'auth': const RequestAuth().toJson(),
        'tests': {
          'assertions': [
            {'type': 'statusIn2xx', 'path': '', 'expected': ''},
          ],
          'extractors': <Object?>[],
        },
      });
      final target = snapshotWith(before, put: [
        edit(root, name: 'Payments API v2', set: {
          'description': 'New description',
          'tags': ['prod'],
          'variables': [
            {'key': 'apiToken', 'value': 'tok-999', 'enabled': true},
            {'key': 'baseUrl', 'value': 'https://api.test/v2', 'enabled': true},
            {'key': 'newVar', 'value': 'n', 'enabled': true},
          ],
        }, remove: ['auth']),
        edit(list, set: {
          'url': 'https://api.test/v2/users',
          'headers': [
            ...(list.data['headers'] as List),
            {'key': 'X-New', 'value': 'yes', 'enabled': true},
          ],
          'auth': {...authOf(list), 'bearerToken': 'new-token'},
          'description': 'Lists users',
          'tags': ['Users'],
        }),
        edit(health, name: 'Health check', parent: v1.uid, set: {
          'settings': {'followRedirects': true},
        }),
        edit(bare, set: {
          'tests': {
            'assertions': [
              {'type': 'statusIn2xx', 'path': '', 'expected': ''},
            ],
            'extractors': <Object?>[],
          },
        }),
        edit(users, name: 'people', order: 5),
        freshFolder,
        freshRequest,
      ]);

      final outcome = await a.store.applySnapshot(target, collectionId: rich.collection);

      expect(outcome.collectionId, rich.collection);
      expect(outcome.added, 2);
      expect(outcome.updated, 5);
      expect(outcome.deleted, 0);
      expect(
        outcome.changedRequestIds,
        unorderedEquals([rich.requests['List users'], rich.requests['Health'], rich.requests['Bare']]),
      );
      expect(texts(await a.read(rich.collection)), texts(target));

      final rows = {for (final r in await a.db.select(a.db.requests).get()) r.name: r};
      for (final entry in rows.entries) {
        final touched = {'List users', 'Health check', 'Bare', 'Fresh request'}.contains(entry.key);
        expect(entry.value.updatedAt.isAfter(stamp), touched, reason: entry.key);
      }
      expect(rows['Health check']!.folderId, rich.folders['v1']);
      expect(jsonDecode((await a.db.requestSettingsDao.get(rich.requests['Health']!))!), {'followRedirects': true});
      final bareScripts = await a.db.requestScriptsDao.findByRequest(rich.requests['Bare']!);
      expect(bareScripts!.assertionsJson, contains('statusIn2xx'));
      expect((await a.db.collectionsDao.watchAllCollections().first).map((c) => c.name), contains('Payments API v2'));
      final people = (await a.db.select(a.db.folders).get()).singleWhere((f) => f.name == 'people');
      expect(people.orderIndex, 5);
      expect(await a.db.collectionAuthDao.findByCollection(rich.collection), isNull);
      expect(await a.db.entityTagsDao.tagsOf('collection', rich.collection), ['prod']);
      expect(await a.db.entityDocsDao.markdownOf('request', rich.requests['List users']!), 'Lists users');
      final names = (await a.db.select(a.db.folders).get()).map((f) => f.name);
      expect(names, containsAll(['people', 'fresh']));
      expect(names, isNot(contains('users')));
    });

    test('removing tests, settings, description and tags from a doc removes their rows', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final list = docNamed(snapshot, 'List users');
      final create = docNamed(snapshot, 'Create user');
      final health = docNamed(snapshot, 'Health');
      final users = docNamed(snapshot, 'users', SyncKind.folder);
      final admin = docNamed(snapshot, 'admin', SyncKind.folder);
      final target = snapshotWith(snapshot, put: [
        edit(list, remove: ['tests', 'tags']),
        edit(create, remove: ['description']),
        edit(health, remove: ['settings']),
        edit(users, remove: ['description']),
        edit(admin, remove: ['tags']),
        edit(snapshot.root!, remove: ['description', 'tags', 'variables']),
      ]);

      await a.store.applySnapshot(target, collectionId: rich.collection);

      expect(await a.db.select(a.db.requestScripts).get(), isEmpty);
      expect(await a.db.select(a.db.requestSettingEntries).get(), isEmpty);
      expect(await a.db.select(a.db.entityDocs).get(), isEmpty);
      expect(await a.db.select(a.db.entityTags).get(), isEmpty);
      expect(await a.db.select(a.db.collectionVariables).get(), isEmpty);
      expect(texts(await a.read(rich.collection)), texts(target));
    });

    test('creates siblings with equal order by name, so a clone lists them the same way everywhere', () async {
      final snapshot = snapshotOf([
        collectionDoc('root', 'C'),
        folderDoc('fb', 'b', 'root'),
        folderDoc('fa', 'a', 'root'),
        requestDoc('rc', 'c', 'root'),
        requestDoc('rb', 'b', 'root'),
        requestDoc('ra', 'a', 'root', order: 1),
      ]);

      final outcome = await a.store.applySnapshot(snapshot);

      final cloneId = outcome.collectionId;
      final folders = await (a.db.select(a.db.folders)..where((t) => t.collectionId.equals(cloneId))).get();
      expect(([...folders]..sort((x, y) => x.id.compareTo(y.id))).map((f) => f.name), ['a', 'b']);
      final requests = await (a.db.select(a.db.requests)..where((t) => t.collectionId.equals(cloneId))).get();
      expect(([...requests]..sort((x, y) => x.id.compareTo(y.id))).map((r) => r.name), ['b', 'c', 'a']);
    });

    test('a request deleted here but present in the target comes back under its uid', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final uid = docNamed(snapshot, 'Health').uid;
      final oldId = rich.requests['Health']!;
      await a.db.requestsDao.deleteRequest(oldId);

      final outcome = await a.store.applySnapshot(snapshot, collectionId: rich.collection);

      expect(outcome.added, 1);
      expect(outcome.updated, 0);
      final newId = await a.uids.localIdFor(SyncKind.request, uid);
      expect(newId, isNotNull);
      expect(newId, isNot(oldId));
      expect(texts(await a.read(rich.collection)), texts(snapshot));
    });

    test('a target whose collection doc has another uid is still that collection', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final foreign = ThreeWayMerger.alignRoot(snapshot, 'foreign-root');
      expect(foreign.root!.uid, 'foreign-root');

      final outcome = await a.store.applySnapshot(foreign, collectionId: rich.collection);

      expect([outcome.added, outcome.updated, outcome.deleted], [0, 0, 0]);
      expect((await a.read(rich.collection)).root!.uid, snapshot.root!.uid);
    });
  });

  group('deletions', () {
    late int collection;
    late Map<String, int> ids;
    late SyncSnapshot snapshot;

    setUp(() async {
      collection = await a.addCollection('Tree');
      final f1 = await a.addFolder(collection, 'f1');
      final f1a = await a.addFolder(collection, 'f1a', parent: f1);
      final f1b = await a.addFolder(collection, 'f1b', parent: f1);
      final f2 = await a.addFolder(collection, 'f2');
      ids = {
        'f1': f1,
        'f1a': f1a,
        'f1b': f1b,
        'f2': f2,
        'r1': await a.addRequest(collection, 'r1', folder: f1),
        'r1keep': await a.addRequest(collection, 'r1keep', folder: f1),
        'r1a': await a.addRequest(collection, 'r1a', folder: f1a),
        'r1b': await a.addRequest(collection, 'r1b', folder: f1b),
        'r2': await a.addRequest(collection, 'r2'),
        'r3': await a.addRequest(collection, 'r3'),
      };
      await a.db.entityTagsDao.setTags('request', ids['r1']!, ['gone']);
      await a.db.entityDocsDao.setMarkdown('folder', f1, 'gone too');
      await a.db.requestScriptsDao.upsert(RequestScriptsCompanion.insert(requestId: Value(ids['r1a']!)));
      snapshot = await a.read(collection);
    });

    test('removes absent requests and folders, deepest first, and keeps what moved out of a deleted folder', () async {
      final root = snapshot.root!;
      final target = snapshotWith(
        snapshot,
        drop: [
          for (final name in ['f1', 'f1a']) docNamed(snapshot, name, SyncKind.folder).uid,
          for (final name in ['r1', 'r1a', 'r3']) docNamed(snapshot, name).uid,
        ],
        put: [
          edit(docNamed(snapshot, 'f1b', SyncKind.folder), parent: root.uid),
          edit(docNamed(snapshot, 'r1keep'), parent: root.uid),
        ],
      );

      final outcome = await a.store.applySnapshot(target, collectionId: collection);

      expect(outcome.added, 0);
      expect(outcome.updated, 2);
      expect(outcome.deleted, 5);
      expect(outcome.deletedRequestIds, unorderedEquals([ids['r1'], ids['r1a'], ids['r3']]));
      expect(outcome.changedRequestIds, [ids['r1keep']]);

      final folders = {for (final f in await a.db.select(a.db.folders).get()) f.name: f};
      expect(folders.keys, unorderedEquals(['f1b', 'f2']));
      expect(folders['f1b']!.parentFolderId, isNull);
      final requests = {for (final r in await a.db.select(a.db.requests).get()) r.name: r};
      expect(requests.keys, unorderedEquals(['r1b', 'r1keep', 'r2']));
      expect(requests['r1keep']!.folderId, isNull);
      expect(requests['r1b']!.folderId, ids['f1b']);
      expect(texts(await a.read(collection)), texts(target));

      // what hung off the deleted entities is gone with them
      expect(await a.db.select(a.db.requestScripts).get(), isEmpty);
      expect(await a.db.select(a.db.entityTags).get(), isEmpty);
      expect(await a.db.select(a.db.entityDocs).get(), isEmpty);
      expect((await a.uids.uidsFor(SyncKind.request)).keys, unorderedEquals([ids['r1keep'], ids['r1b'], ids['r2']]));
      expect((await a.uids.uidsFor(SyncKind.folder)).keys, unorderedEquals([ids['f1b'], ids['f2']]));
    });

    test('deleting a folder with everything in it takes the whole subtree', () async {
      final target = snapshotWith(snapshot, drop: [
        for (final name in ['f1', 'f1a', 'f1b']) docNamed(snapshot, name, SyncKind.folder).uid,
        for (final name in ['r1', 'r1keep', 'r1a', 'r1b']) docNamed(snapshot, name).uid,
      ]);

      final outcome = await a.store.applySnapshot(target, collectionId: collection);

      expect(outcome.deleted, 7);
      expect(outcome.updated, 0);
      expect((await a.db.select(a.db.folders).get()).map((f) => f.name), ['f2']);
      expect((await a.db.select(a.db.requests).get()).map((r) => r.name), unorderedEquals(['r2', 'r3']));
    });

    test('entities that never got a uid are deleted too when the target lacks them', () async {
      final lateFolder = await a.addFolder(collection, 'late folder');
      final lateRequest = await a.addRequest(collection, 'late request', folder: lateFolder);
      expect(await a.uids.uidsFor(SyncKind.request), isNot(contains(lateRequest)));

      final outcome = await a.store.applySnapshot(snapshot, collectionId: collection);

      expect(outcome.deleted, 2);
      expect(outcome.deletedRequestIds, [lateRequest]);
      expect(await a.db.requestsDao.findById(lateRequest), isNull);
      expect((await a.db.select(a.db.folders).get()).map((f) => f.name), isNot(contains('late folder')));
      expect(texts(await a.read(collection)), texts(snapshot));
    });
  });

  group('scale and isolation', () {
    test('deleting more requests than fit in one statement removes them all, with what hangs off them', () async {
      final collection = await a.addCollection('Big');
      var parent = await a.addFolder(collection, 'level 0');
      for (var depth = 1; depth < 8; depth++) {
        parent = await a.addFolder(collection, 'level $depth', parent: parent);
      }
      await a.db.batch((batch) => batch.insertAll(a.db.requests, [
            for (var i = 0; i < 850; i++)
              RequestsCompanion.insert(
                collectionId: collection,
                folderId: Value(i.isEven ? parent : null),
                name: 'request $i',
              ),
          ]));
      for (final request in (await a.db.select(a.db.requests).get()).take(30)) {
        await a.db.entityTagsDao.setTags('request', request.id, ['tag ${request.name}']);
      }
      final snapshot = await a.read(collection);
      final target = snapshotOf([snapshot.root!, docNamed(snapshot, 'request 7')]);

      final outcome = await a.store.applySnapshot(target, collectionId: collection);

      expect(outcome.deleted, 849 + 8);
      expect(outcome.deletedRequestIds.length, 849);
      expect((await a.db.select(a.db.requests).get()).map((r) => r.name), ['request 7']);
      expect(await a.db.select(a.db.folders).get(), isEmpty);
      expect((await a.db.select(a.db.entityTags).get()).map((t) => t.tag), ['tag request 7']);
      expect((await a.uids.uidsFor(SyncKind.request)).length, 1);
      expect(await a.uids.uidsFor(SyncKind.folder), isEmpty);
    });

    test('a sync only ever sees and changes its own collection', () async {
      final rich = await a.buildRich();
      final other = await a.addCollection('Other');
      final otherFolder = await a.addFolder(other, 'other folder');
      final otherRequest =
          await a.addRequest(other, 'other request', folder: otherFolder, auth: authFor(AuthType.bearer));
      await a.db.entityDocsDao.setMarkdown('request', otherRequest, 'other notes');
      await a.db.entityTagsDao.setTags('folder', otherFolder, ['other-tag']);
      await a.addVariable(other, 'otherVar', 'x');
      final otherBefore = await a.read(other);
      expect(otherBefore.docs.length, 3);

      final snapshot = await a.read(rich.collection);
      expect(snapshot.docs.values.map((d) => d.name), isNot(contains('other request')));
      final target = snapshotWith(
        snapshot,
        drop: [docNamed(snapshot, 'v1', SyncKind.folder).uid, docNamed(snapshot, 'Health').uid],
        put: [edit(snapshot.root!, set: {'description': 'only mine'})],
      );
      await a.store.applySnapshot(target, collectionId: rich.collection);

      expect(texts(await a.read(other)), texts(otherBefore));
      expect(await a.db.entityDocsDao.markdownOf('request', otherRequest), 'other notes');
      expect(await a.db.entityTagsDao.tagsOf('folder', otherFolder), ['other-tag']);
    });
  });

  group('folders whose parents are broken', () {
    test('are attached to the collection instead of being dropped or looping', () async {
      final target = snapshotOf([
        collectionDoc('root', 'Broken'),
        folderDoc('f-orphan', 'orphan', 'nowhere'),
        folderDoc('f-a', 'a', 'f-b'),
        folderDoc('f-b', 'b', 'f-a'),
        folderDoc('f-self', 'self', 'f-self'),
        requestDoc('r-x', 'x', 'root'),
        requestDoc('r-under-request', 'under request', 'r-x'),
        requestDoc('r-in-orphan', 'in orphan', 'f-orphan'),
        requestDoc('r-lost', 'lost', 'gone'),
      ]);

      final outcome = await a.store.applySnapshot(target);

      expect(outcome.added, 9);
      final read = await a.read(outcome.collectionId);
      String parentOf(String name, [SyncKind kind = SyncKind.request]) => docNamed(read, name, kind).parentUid!;
      expect(parentOf('orphan', SyncKind.folder), 'root');
      expect(parentOf('self', SyncKind.folder), 'root');
      expect(parentOf('under request'), 'root');
      expect(parentOf('lost'), 'root');
      expect(parentOf('in orphan'), 'f-orphan');
      final cycle = {parentOf('a', SyncKind.folder), parentOf('b', SyncKind.folder)};
      expect(cycle, {'root', docNamed(read, 'a', SyncKind.folder).uid});
    });
  });

  group('secrets on apply', () {
    test('a snapshot without credentials never erases the ones stored here', () async {
      final rich = await a.buildRich();
      final full = await a.read(rich.collection);
      final stripped = await a.read(rich.collection, secrets: false);

      final unchanged = await a.store.applySnapshot(stripped, collectionId: rich.collection);
      expect([unchanged.added, unchanged.updated, unchanged.deleted], [0, 0, 0]);
      expect(texts(await a.read(rich.collection)), texts(full));

      final bearer = docNamed(stripped, 'Auth bearer');
      final edited = snapshotWith(stripped, put: [
        edit(bearer, set: {'url': 'https://api.test/edited'}),
        edit(stripped.root!, set: {
          'variables': [
            {'key': 'apiToken', 'value': '', 'enabled': true},
            {'key': 'baseUrl', 'value': 'https://edited.test', 'enabled': true},
            {'key': 'dbPassword', 'value': '', 'enabled': true},
            {'key': 'dup', 'value': 'first', 'enabled': true},
            {'key': 'dup', 'value': 'second', 'enabled': false},
            {'key': 'region', 'value': 'eu', 'enabled': false},
            {'key': 'zeta', 'value': 'z', 'enabled': true},
          ],
        }),
      ]);
      final outcome = await a.store.applySnapshot(edited, collectionId: rich.collection);

      expect(outcome.updated, 2);
      final after = await a.read(rich.collection);
      expect(docNamed(after, 'Auth bearer').data['url'], 'https://api.test/edited');
      expect(authOf(docNamed(after, 'Auth bearer'))['bearerToken'], 'bearer-abc');
      expect(authOf(docNamed(after, 'Auth oauth2'))['oauth2AccessToken'], 'oauth-access');
      expect(authOf(docNamed(after, 'Auth oauth2'))['oauth2TokenExpiry'], '2030-01-02T03:04:05.000Z');
      expect(authOf(after.root!)['bearerToken'], 'collection-secret');
      final variables = {
        for (final v in after.root!.data['variables'] as List) '${v['key']}/${v['enabled']}': v['value'],
      };
      expect(variables['apiToken/true'], 'tok-123');
      expect(variables['dbPassword/true'], 'pw-456');
      expect(variables['baseUrl/true'], 'https://edited.test');
    });

    test('a clone made from a snapshot without credentials starts with none', () async {
      final rich = await a.buildRich();
      final stripped = await a.read(rich.collection, secrets: false);

      final b = newDevice();
      final outcome = await b.store.applySnapshot(stripped);

      expect(texts(await b.read(outcome.collectionId, secrets: false)), texts(stripped));
      final full = await b.read(outcome.collectionId);
      expect(authOf(docNamed(full, 'Auth bearer'))['bearerToken'], '');
      expect(authOf(docNamed(full, 'Auth oauth2'))['oauth2AccessToken'], '');
      expect(authOf(docNamed(full, 'Auth oauth2'))['oauth2TokenExpiry'], isNull);
      expect(authOf(full.root!)['bearerToken'], '');
      final variables = {for (final v in full.root!.data['variables'] as List) v['key']: v['value']};
      expect(variables['apiToken'], '');
      expect(variables['baseUrl'], 'https://api.test');
      expect(texts(SecretFields.stripSnapshot(full)), texts(stripped));
    });

    test('credentials in the target replace local ones, empty ones do not', () async {
      final rich = await a.buildRich();
      final full = await a.read(rich.collection);
      final b = newDevice();
      final clone = await b.store.applySnapshot(SecretFields.stripSnapshot(full));

      await b.store.applySnapshot(full, collectionId: clone.collectionId);
      expect(texts(await b.read(clone.collectionId)), texts(full));

      final bearer = docNamed(full, 'Auth bearer');
      final blanked = edit(bearer, set: {'auth': {...authOf(bearer), 'bearerToken': ''}});
      final blankedTarget = snapshotWith(full, put: [blanked]);
      final unchanged = await b.store.applySnapshot(blankedTarget, collectionId: clone.collectionId);
      expect(unchanged.updated, 0);
      expect(authOf(docNamed(await b.read(clone.collectionId), 'Auth bearer'))['bearerToken'], 'bearer-abc');

      final rotated = edit(bearer, set: {'auth': {...authOf(bearer), 'bearerToken': 'rotated'}});
      final changed = await b.store.applySnapshot(snapshotWith(full, put: [rotated]), collectionId: clone.collectionId);
      expect(changed.updated, 1);
      expect(authOf(docNamed(await b.read(clone.collectionId), 'Auth bearer'))['bearerToken'], 'rotated');
    });

    test('variables with a secret-looking key keep the local value per occurrence of the key', () async {
      final id = await a.addCollection('vars');
      await a.addVariable(id, 'token', 'local-1');
      await a.addVariable(id, 'token', 'local-2', enabled: false);
      await a.addVariable(id, 'host', 'h');
      await a.addVariable(id, 'note', 'n');
      final stripped = await a.read(id, secrets: false);
      List variablesOf(SyncSnapshot s) => s.root!.data['variables'] as List;
      expect([for (final v in variablesOf(stripped)) v['value']], ['h', 'n', '', '']);

      final same = await a.store.applySnapshot(stripped, collectionId: id);
      expect(same.updated, 0);
      expect([for (final v in variablesOf(await a.read(id))) v['value']], ['h', 'n', 'local-1', 'local-2']);

      final mixed = snapshotWith(stripped, put: [
        edit(stripped.root!, set: {
          'variables': [
            {'key': 'host', 'value': '', 'enabled': true},
            {'key': 'note', 'value': 'changed', 'enabled': true},
            {'key': 'token', 'value': 'new-1', 'enabled': true},
            {'key': 'token', 'value': '', 'enabled': false},
          ],
        }),
      ]);
      final outcome = await a.store.applySnapshot(mixed, collectionId: id);
      expect(outcome.updated, 1);
      expect([for (final v in variablesOf(await a.read(id))) '${v['key']}=${v['value']}'], [
        'host=',
        'note=changed',
        'token=new-1',
        'token=local-2',
      ]);
    });

    test('a doc without auth clears the collection auth, one without its secret keeps the stored one', () async {
      final id = await a.addCollection('auth');
      await a.setCollectionAuth(id, authFor(AuthType.bearer));
      final full = await a.read(id);
      final stripped = await a.read(id, secrets: false);

      final kept = await a.store.applySnapshot(stripped, collectionId: id);
      expect(kept.updated, 0);
      expect(authOf((await a.read(id)).root!)['bearerToken'], 'bearer-abc');

      final withoutAuth = snapshotWith(full, put: [edit(full.root!, remove: ['auth'])]);
      final cleared = await a.store.applySnapshot(withoutAuth, collectionId: id);
      expect(cleared.updated, 1);
      expect(await a.db.collectionAuthDao.findByCollection(id), isNull);

      final set = await a.store.applySnapshot(full, collectionId: id);
      expect(set.updated, 1);
      expect((await a.db.collectionAuthDao.findByCollection(id))!.authJson, contains('bearer-abc'));
    });
  });

  group('failures leave the database as it was', () {
    test('cloning what is already cloned here throws and writes nothing', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final before = await a.dump();

      await expectLater(a.store.applySnapshot(snapshot), gitSyncError(_alreadyCloned));
      expect(await a.dump(), before);

      final overlap = snapshotOf([
        collectionDoc('another-root', 'Another'),
        requestDoc(docNamed(snapshot, 'Health').uid, 'Health elsewhere', 'another-root'),
      ]);
      await expectLater(a.store.applySnapshot(overlap), gitSyncError(_alreadyCloned));
      expect(await a.dump(), before);

      final other = await a.addCollection('Other');
      final afterOther = await a.dump();
      await expectLater(a.store.applySnapshot(snapshot, collectionId: other), gitSyncError(_alreadyCloned));
      expect(await a.dump(), afterOther);
    });

    test('a uid reused for another kind of entity is refused', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final health = docNamed(snapshot, 'Health');
      final clash = snapshotWith(snapshot, put: [folderDoc(health.uid, 'was a request', snapshot.root!.uid)]);
      final before = await a.dump();

      await expectLater(a.store.applySnapshot(clash, collectionId: rich.collection), gitSyncError(_alreadyCloned));
      expect(await a.dump(), before);
    });

    test('one malformed doc rolls back everything applied before it', () async {
      final rich = await a.buildRich();
      final snapshot = await a.read(rich.collection);
      final requests = [
        for (final doc in snapshot.docs.values)
          if (doc.kind == SyncKind.request) doc,
      ]..sort((x, y) => x.order != y.order ? x.order.compareTo(y.order) : x.name.compareTo(y.name));
      final first = requests.first;
      final last = requests.last;
      expect(first.uid, isNot(last.uid));
      final target = snapshotWith(snapshot, put: [
        edit(snapshot.root!, name: 'Renamed', set: {'description': 'changed'}),
        folderDoc('brand-new-folder', 'brand new', snapshot.root!.uid),
        edit(first, set: {'url': 'https://changed.test'}),
        edit(last, set: {'headers': 'not a list'}),
      ]);
      final before = await a.dump();

      await expectLater(
        a.store.applySnapshot(target, collectionId: rich.collection),
        gitSyncError(allOf(contains('request'), contains('"${last.name}"'), contains('unexpected format'))),
      );

      expect(await a.dump(), before);
      expect(await a.uids.localIdFor(SyncKind.folder, 'brand-new-folder'), isNull);
      expect(texts(await a.read(rich.collection)), texts(snapshot));
    });

    test('a malformed doc in a clone leaves no collection behind', () async {
      final target = snapshotOf([
        collectionDoc('root', 'Never created'),
        folderDoc('f', 'folder', 'root'),
        requestDoc('r-ok', 'a fine one', 'f'),
        requestDoc('r-bad', 'z broken', 'f', data: {'body': 'not a map'}),
      ]);
      final before = await a.dump();

      await expectLater(a.store.applySnapshot(target), gitSyncError(contains('unexpected format')));

      expect(await a.dump(), before);
      expect(await a.db.select(a.db.collections).get(), isEmpty);
    });

    test('a malformed collection doc is refused before any entity is written', () async {
      final target = snapshotOf([
        collectionDoc('root', 'Bad root', data: {'variables': 'nope'}),
        folderDoc('f', 'folder', 'root'),
      ]);

      await expectLater(a.store.applySnapshot(target), gitSyncError(contains('unexpected format')));

      expect(await a.dump(), {for (final table in _dumpedTables) table: <Map<String, Object?>>[]});
    });

    test('a snapshot without exactly one collection doc is refused', () async {
      await expectLater(a.store.applySnapshot(SyncSnapshot.empty), gitSyncError(contains('exactly one collection')));
      await expectLater(
        a.store.applySnapshot(snapshotOf([collectionDoc('r1', 'one'), collectionDoc('r2', 'two')])),
        gitSyncError(contains('exactly one collection')),
      );
      expect(await a.db.select(a.db.collections).get(), isEmpty);
    });

    test('applying to a collection that does not exist is refused', () async {
      await expectLater(
        a.store.applySnapshot(snapshotOf([collectionDoc('root', 'x')]), collectionId: 42),
        gitSyncError(contains('no longer exists')),
      );
    });
  });
}
