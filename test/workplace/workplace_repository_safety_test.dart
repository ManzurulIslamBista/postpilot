import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_token_store.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

final class _Tokens implements WorkplaceTokenStore {
  @override
  Future<String?> read(String workplaceId) async => null;
  @override
  Future<void> write(String workplaceId, String token) async {}
  @override
  Future<void> delete(String workplaceId) async {}
}

/// A real [FileWorkplaceStorage] that records the order of the writes and can be told to fail them.
final class _SpyStorage implements WorkplaceStorage {
  final FileWorkplaceStorage inner;
  _SpyStorage(this.inner);

  final log = <String>[];
  bool failLocalSecrets = false;
  bool failWorkspace = false;

  @override
  Future<void> writeLocalSecrets(String folderPath, String json) async {
    log.add('secrets');
    if (failLocalSecrets) throw const WorkplaceException('disk full (secrets)');
    await inner.writeLocalSecrets(folderPath, json);
  }

  @override
  Future<void> writeWorkspace(String folderPath, String json) async {
    log.add('workspace');
    if (failWorkspace) throw const WorkplaceException('disk full (workspace)');
    await inner.writeWorkspace(folderPath, json);
  }

  @override
  bool get usesRealFolders => inner.usesRealFolders;
  @override
  bool get canPickFolder => inner.canPickFolder;
  @override
  bool get canRevealFolder => inner.canRevealFolder;
  @override
  String get fileManagerName => inner.fileManagerName;
  @override
  Future<String?> readRegistry() => inner.readRegistry();
  @override
  Future<void> writeRegistry(String json) => inner.writeRegistry(json);
  @override
  Future<String?> backupRegistry(String json) => inner.backupRegistry(json);
  @override
  Future<String?> readWorkspace(String folderPath) => inner.readWorkspace(folderPath);
  @override
  Future<String?> readLocalSecrets(String folderPath) => inner.readLocalSecrets(folderPath);
  @override
  Future<bool> isDirty(String folderPath) => inner.isDirty(folderPath);
  @override
  Future<void> setDirty(String folderPath, bool dirty) => inner.setDirty(folderPath, dirty);
  @override
  Future<String> defaultWorkplacesDirectory() => inner.defaultWorkplacesDirectory();
  @override
  String? validateFolderPath(String folderPath) => inner.validateFolderPath(folderPath);
  @override
  Future<String?> pickFolder({String? initialPath}) => inner.pickFolder(initialPath: initialPath);
  @override
  Future<void> revealFolder(String folderPath) => inner.revealFolder(folderPath);
}

/// GitHub answered by a function; remembers every request.
final class _GitHub implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  final calls = <RequestOptions>[];
  _GitHub(this.handler);

  Iterable<RequestOptions> puts() => calls.where((c) => c.method == 'PUT');

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _file(String text, String sha) => {'content': base64Encode(utf8.encode(text)), 'encoding': 'base64', 'sha': sha};

BackupSnapshot _snapshot({String env = 'Dev', String token = 'tok-1', String collection = 'Pets'}) => BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: env, variables: [
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'token', value: token, isSecret: true, enabled: true),
        ]),
      ],
      collections: [
        BackupCollection(name: collection, variables: const [
          CollectionVariableEntity(id: 0, collectionId: 0, key: 'baseUrl', value: 'https://api.test', enabled: true),
        ]),
      ],
    );

void main() {
  late Directory tmp;
  late String folder;
  late _SpyStorage storage;
  late WorkplaceEntity workplace;

  File file(String name) => File(p.join(folder, name));
  String workspaceText() => file('workspace.json').readAsStringSync();
  LocalSecrets localFile() => SecretSplitter.decodeLocalFile(file('workspace.local.json').readAsStringSync());

  WorkplaceRepositoryImpl repo({Dio? dio, bool keepLocal = true}) =>
      WorkplaceRepositoryImpl(dio: dio, storage: storage, tokens: _Tokens(), keepSecretsLocal: () => keepLocal);

  Dio dioFor(_GitHub github) => Dio()..httpClientAdapter = github;

  Future<void> save(WorkplaceRepositoryImpl r, BackupSnapshot snapshot) =>
      r.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: snapshot));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pp_w1a_repo');
    folder = p.join(tmp.path, 'ws');
    storage = _SpyStorage(FileWorkplaceStorage(registryDirectory: Directory(p.join(tmp.path, 'reg')), defaultWorkplacesDirectory: tmp.path));
    workplace = WorkplaceEntity(
      id: 'w1',
      name: 'WS',
      folderPath: folder,
      gitRepoUrl: 'o/r',
      gitToken: 'ghp_x',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('local secrets: what a pull may not lose', () {
    test('a pull keeps the secrets the repository copy has no place for, and a later pull brings them back', () async {
      final r = repo();
      await save(r, _snapshot(env: 'Dev', token: 'tok-1'));
      expect(localFile().secrets, {'env/Dev/token': 'tok-1'});

      var remoteName = 'Development';
      final github = _GitHub((o) {
        if (o.uri.path == '/repos/o/r/contents/workspace.json') {
          // The teammate's file: the environment has another name and no secret value.
          final theirs = WorkplaceContent(workplace: workplace, snapshot: _snapshot(env: remoteName, token: ''));
          return _json(200, _file(theirs.toJsonString(), 'sha-$remoteName'));
        }
        return _json(500, {'message': 'unexpected ${o.method} ${o.uri}'});
      });
      final pulling = repo(dio: dioFor(github));

      final first = await pulling.pullFromGit(workplace);
      expect(first.snapshot.environments.single.name, 'Development');
      expect(first.snapshot.environments.single.variables.single.value, '', reason: 'nothing of that name to put here');
      expect(localFile().secrets, isEmpty);
      expect(localFile().unmatched, {'env/Dev/token': 'tok-1'}, reason: 'the secret is kept, not dropped');
      expect(workspaceText(), isNot(contains('tok-1')));

      remoteName = 'Dev';
      final second = await pulling.pullFromGit(workplace);
      expect(second.snapshot.environments.single.name, 'Dev');
      expect(second.snapshot.environments.single.variables.single.value, 'tok-1');
      expect(localFile().secrets, {'env/Dev/token': 'tok-1'});
      expect(localFile().unmatched, isEmpty);
    });

    test('a workspace.json changed from outside does not make the next save drop the secrets', () async {
      final r = repo();
      await save(r, _snapshot(env: 'Dev', token: 'tok-1'));
      // A git pull in the folder: the file now names the environment differently.
      final renamed = jsonDecode(workspaceText()) as Map<String, dynamic>;
      ((renamed['environments'] as List).first as Map)['name'] = 'Development';
      file('workspace.json').writeAsStringSync(jsonEncode(renamed));

      final loaded = await r.loadWorkplaceContent(workplace);
      expect(loaded.snapshot.environments.single.variables.single.value, '');
      expect(localFile().unmatched, {'env/Dev/token': 'tok-1'});

      // What the app does next: it saves the database, which holds the loaded content.
      await r.saveWorkplaceContent(workplace, loaded);
      expect(localFile().unmatched, {'env/Dev/token': 'tok-1'});
      expect(localFile().secrets, isEmpty);
    });

    test('an ordinary save still forgets a secret that was removed', () async {
      final r = repo();
      await save(r, _snapshot(token: 'tok-1'));
      await save(r, _snapshot(token: ''));
      expect(localFile().secrets, isEmpty);
      expect(localFile().unmatched, isEmpty);
      expect(file('workspace.local.json').readAsStringSync(), isNot(contains('tok-1')));
    });
  });

  group('writing the secrets file and the workspace', () {
    test('the secrets are written first, so a crash between the two never leaves blanks without them', () async {
      final r = repo();
      storage.log.clear();
      await save(r, _snapshot());
      expect(storage.log, ['secrets', 'workspace']);
    });

    test('a failed secrets write is reported, and workspace.json is left as it was', () async {
      final r = repo();
      await save(r, _snapshot(token: 'tok-1', collection: 'Before'));
      final before = workspaceText();
      storage.failLocalSecrets = true;

      await expectLater(
        save(r, _snapshot(token: 'tok-2', collection: 'After')),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('disk full (secrets)'))),
      );

      expect(workspaceText(), before);
      expect(localFile().secrets, {'env/Dev/token': 'tok-1'});
    });

    test('a failed workspace write is reported too', () async {
      final r = repo();
      storage.failWorkspace = true;
      await expectLater(save(r, _snapshot()), throwsA(isA<WorkplaceException>()));
    });

    test('nothing to keep local: no secrets file and no .gitignore are created', () async {
      final r = repo();
      await save(r, BackupSnapshot(exportedAt: DateTime.utc(2026), collections: const [BackupCollection(name: 'Plain')]));
      expect(file('workspace.local.json').existsSync(), isFalse);
      expect(file('.gitignore').existsSync(), isFalse);
    });

    test('the setting off writes everything to workspace.json and touches no other file', () async {
      final r = repo(keepLocal: false);
      await save(r, _snapshot(token: 'tok-1'));
      expect(workspaceText(), contains('tok-1'));
      expect(file('workspace.local.json').existsSync(), isFalse);
      expect(file('.gitignore').existsSync(), isFalse);
    });
  });

  group('.gitignore of the workplace folder', () {
    List<String> lines() => file('.gitignore').readAsLinesSync();

    test('is created with the secrets file and its temp file, once', () async {
      final r = repo();
      await save(r, _snapshot());
      await save(r, _snapshot(token: 'tok-2'));
      await save(r, _snapshot(token: 'tok-3'));

      expect(lines().where((l) => l == 'workspace.local.json'), hasLength(1));
      expect(lines().where((l) => l == 'workspace.local.json.tmp'), hasLength(1));
    });

    test('keeps every line the user has, and adds to the end', () async {
      Directory(folder).createSync(recursive: true);
      file('.gitignore').writeAsStringSync('build/\n# mine\n*.log');

      await save(repo(), _snapshot());

      expect(lines().take(3), ['build/', '# mine', '*.log']);
      expect(lines(), containsAll(['workspace.local.json', 'workspace.local.json.tmp']));
    });

    test('does not touch a .gitignore that already lists both, in any spelling', () async {
      Directory(folder).createSync(recursive: true);
      const mine = '/workspace.local.json\r\nworkspace.local.json.tmp\r\n';
      file('.gitignore').writeAsStringSync(mine);

      await save(repo(), _snapshot());

      expect(file('.gitignore').readAsStringSync(), mine);
    });

    test('follows the line endings the file already has', () async {
      Directory(folder).createSync(recursive: true);
      file('.gitignore').writeAsBytesSync(utf8.encode('build/\r\nout/\r\n'));

      await save(repo(), _snapshot());

      final text = file('.gitignore').readAsStringSync();
      expect(text, startsWith('build/\r\nout/\r\n'));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'no bare line feed was added');
    });
  });

  group('a workplace list that cannot be read', () {
    late File registry;
    List<File> backups() => Directory(p.join(tmp.path, 'reg')).listSync().whereType<File>().where((f) => f.path.endsWith('.bak')).toList();

    setUp(() {
      registry = File(p.join(tmp.path, 'reg', 'workplaces_registry.json'))..createSync(recursive: true);
    });

    test('is kept as it is, copied to a timestamped .bak, and reported, not replaced by a default workplace', () async {
      const damaged = '{"activeId": "w1", "workplaces": [{"id": "w1", "name": "Mine", "folderPath": ';
      registry.writeAsStringSync(damaged);
      final r = repo();

      await expectLater(
        r.getWorkplaces(),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', allOf(contains('could not be read'), contains('workplaces_registry.json'), contains('.bak')))),
      );
      await expectLater(r.createWorkplace(name: 'New', folderPath: p.join(tmp.path, 'new')), throwsA(isA<WorkplaceException>()));

      expect(registry.readAsStringSync(), damaged, reason: 'nothing overwrote it');
      expect(backups(), hasLength(1), reason: 'one copy per run, however often it is read');
      expect(backups().single.readAsStringSync(), damaged);
      expect(p.basename(backups().single.path), matches(RegExp(r'^workplaces_registry\.json\.\d{8}T\d{6}(-\d+)?\.bak$')));
      expect(Directory(p.join(tmp.path, 'new')).existsSync(), isFalse);
    });

    test('valid JSON of the wrong shape is damaged too', () async {
      registry.writeAsStringSync('{"workplaces": 5}');
      await expectLater(repo().getWorkplaces(), throwsA(isA<WorkplaceException>()));
      expect(registry.readAsStringSync(), '{"workplaces": 5}');
    });

    test('an empty file counts as a first start', () async {
      registry.writeAsStringSync('  \n');
      final workplaces = await repo().getWorkplaces();
      expect(workplaces.single.name, 'My Workplace');
      expect(backups(), isEmpty);
    });

    test('a readable registry is still read, and nothing is copied', () async {
      final r = repo();
      final created = await r.createWorkplace(name: 'Mine', folderPath: p.join(tmp.path, 'mine'));
      final reloaded = await repo().getWorkplaces();
      expect(reloaded.map((w) => w.id), contains(created.id));
      expect(backups(), isEmpty);
    });
  });

  group('pushing from a workplace that never synced', () {
    late String localText;

    setUp(() async {
      // A folder that already is a workspace, connected to a repository (no network until a push).
      Directory(folder).createSync(recursive: true);
      localText = WorkplaceContent(workplace: workplace, snapshot: _snapshot(collection: 'Mine')).toJsonString();
      file('workspace.json').writeAsStringSync(localText);
    });

    _GitHub remote(String text, {String sha = 'sha-remote'}) => _GitHub((o) {
          final path = o.uri.path;
          if (path.startsWith('/repos/o/r/branches/')) return _json(200, {});
          if (path == '/repos/o/r/contents/workspace.json') {
            return o.method == 'GET' ? _json(200, _file(text, sha)) : _json(200, {'content': {'sha': 'sha-new'}});
          }
          return _json(500, {'message': 'unexpected ${o.method} $path'});
        });

    Future<WorkplaceEntity> connect(WorkplaceRepositoryImpl r) =>
        r.createWorkplace(name: 'Mine', folderPath: folder, gitRepoUrl: 'o/r', gitBranch: 'main', gitToken: 'ghp_x');

    test('is refused when the repository holds a different workspace.json, and nothing is overwritten', () async {
      final theirs = WorkplaceContent(workplace: workplace, snapshot: _snapshot(collection: 'Theirs')).toJsonString();
      final github = remote(theirs);
      final r = repo(dio: dioFor(github));
      final connected = await connect(r);
      expect(connected.lastSyncedSha, isNull);

      final preview = await r.previewPush(connected);
      expect(preview.remoteExists, isTrue);
      expect(preview.remoteChanged, isTrue);
      expect(preview.neverSynced, isTrue);

      await expectLater(
        r.syncWithGit(connected),
        throwsA(isA<RemoteChangedException>().having((e) => e.message, 'message', contains('never synced'))),
      );
      expect(github.puts(), isEmpty);
    });

    test('goes through when the person chooses to overwrite, using the repository sha', () async {
      final github = remote(WorkplaceContent(workplace: workplace, snapshot: _snapshot(collection: 'Theirs')).toJsonString());
      final r = repo(dio: dioFor(github));
      final connected = await connect(r);

      await r.syncWithGit(connected, overwrite: true);

      expect((github.puts().single.data as Map)['sha'], 'sha-remote');
      expect((await r.getWorkplaces()).firstWhere((w) => w.id == connected.id).lastSyncedSha, 'sha-new');
    });

    test('goes through without asking when the repository says the same as this workplace', () async {
      final github = remote(localText);
      final r = repo(dio: dioFor(github));
      final connected = await connect(r);

      final preview = await r.previewPush(connected);
      expect(preview.remoteChanged, isFalse);
      expect(preview.neverSynced, isFalse);

      await r.syncWithGit(connected);
      expect(github.puts(), hasLength(1));
    });

    test('a repository without the file is not a conflict', () async {
      final github = _GitHub((o) {
        final path = o.uri.path;
        if (path.startsWith('/repos/o/r/branches/')) return _json(200, {});
        if (path == '/repos/o/r/contents/workspace.json') {
          return o.method == 'GET' ? _json(404, {'message': 'Not Found'}) : _json(201, {'content': {'sha': 'sha-first'}});
        }
        return _json(500, {'message': 'unexpected'});
      });
      final r = repo(dio: dioFor(github));
      final connected = await connect(r);

      await r.syncWithGit(connected);
      expect(github.puts(), hasLength(1));
      expect((github.puts().single.data as Map).containsKey('sha'), isFalse);
    });

    test('a push that races another one is refused whether or not the workplace ever synced', () async {
      var reads = 0;
      final github = _GitHub((o) {
        final path = o.uri.path;
        if (path.startsWith('/repos/o/r/branches/')) return _json(200, {});
        if (path == '/repos/o/r/contents/workspace.json') {
          if (o.method == 'GET') return _json(200, _file(localText, 'sha-${reads++ == 0 ? 'a' : 'b'}'));
          return _json(409, {'message': 'sha does not match'});
        }
        return _json(500, {'message': 'unexpected'});
      });
      final r = repo(dio: dioFor(github));
      final connected = await connect(r);

      await expectLater(r.syncWithGit(connected), throwsA(isA<RemoteChangedException>()));
    });
  });

  group('reading the repository file', () {
    late String remoteText;
    final tooLarge = {
      'message': 'This API returns blobs up to 1 MB in size. The requested blob is too large to fetch via the API, '
          'but you can use the Git Data API to request blobs up to 100 MB in size.',
      'errors': [
        {'resource': 'Blob', 'field': 'data', 'code': 'too_large'},
      ],
    };

    setUp(() {
      remoteText = WorkplaceContent(workplace: workplace, snapshot: _snapshot(collection: 'Big one')).toJsonString();
    });

    _GitHub github({required ResponseBody Function(RequestOptions o) contents, String sha = 'bigsha'}) => _GitHub((o) {
          final path = o.uri.path;
          if (path.startsWith('/repos/o/r/branches/')) return _json(200, {});
          if (path == '/repos/o/r/contents/workspace.json' && o.method == 'GET') return contents(o);
          if (path == '/repos/o/r/contents') {
            return _json(200, [
              {'name': 'README.md', 'type': 'file', 'sha': 'readme'},
              {'name': 'workspace.json', 'type': 'file', 'sha': sha},
            ]);
          }
          if (path == '/repos/o/r/git/blobs/$sha') return _json(200, {'content': base64Encode(utf8.encode(remoteText)), 'encoding': 'base64'});
          if (path == '/repos/o/r/contents/workspace.json' && o.method == 'PUT') return _json(200, {'content': {'sha': 'sha-new'}});
          return _json(500, {'message': 'unexpected ${o.method} $path'});
        });

    test('a file over 1 MB that GitHub refuses (403 "too large") is read through the blob API', () async {
      final fake = github(contents: (o) => _json(403, tooLarge));
      final pulled = await repo(dio: dioFor(fake)).pullFromGit(workplace);

      expect(pulled.snapshot.collections.single.name, 'Big one');
      expect(fake.calls.map((c) => c.uri.path), containsAllInOrder(['/repos/o/r/contents/workspace.json', '/repos/o/r/contents', '/repos/o/r/git/blobs/bigsha']));
    });

    test('an answer without the content (encoding "none") is read through the blob API too', () async {
      final fake = github(contents: (o) => _json(200, {'content': '', 'encoding': 'none', 'sha': 'bigsha', 'size': 2000000}));
      final pulled = await repo(dio: dioFor(fake)).pullFromGit(workplace);

      expect(pulled.snapshot.collections.single.name, 'Big one');
      expect(fake.calls.where((c) => c.uri.path == '/repos/o/r/contents'), isEmpty, reason: 'the sha was in the answer');
    });

    test('the preview and a push work on such a file as well', () async {
      final fake = github(contents: (o) => _json(403, tooLarge));
      final r = repo(dio: dioFor(fake));
      Directory(folder).createSync(recursive: true);
      file('workspace.json').writeAsStringSync(WorkplaceContent(workplace: workplace, snapshot: _snapshot(collection: 'Mine')).toJsonString());
      final synced = workplace.copyWith(lastSyncedSha: 'bigsha');

      final preview = await r.previewPush(synced);
      expect(preview.remoteExists, isTrue);
      expect(preview.remoteChanged, isFalse);

      await r.syncWithGit(synced);
      expect((fake.puts().single.data as Map)['sha'], 'bigsha');
    });

    test('a real permission problem says what GitHub said, not that the token lacks a scope', () async {
      final fake = github(contents: (o) => _json(403, {'message': 'Resource not accessible by personal access token'}));
      await expectLater(
        repo(dio: dioFor(fake)).pullFromGit(workplace),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', allOf(contains('Access Denied'), contains('Resource not accessible by personal access token'), contains('SSO')))),
      );
    });

    test('a rate limit is called a rate limit', () async {
      final fake = github(contents: (o) => _json(403, {'message': 'API rate limit exceeded for user ID 1.'}));
      await expectLater(
        repo(dio: dioFor(fake)).pullFromGit(workplace),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', allOf(contains('rate limit'), isNot(contains('Access Denied'))))),
      );
    });

    test('a file that is not there is still "nothing to pull", not an error about size', () async {
      final fake = github(contents: (o) => _json(404, {'message': 'Not Found'}));
      await expectLater(
        repo(dio: dioFor(fake)).pullFromGit(workplace),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('No remote'))),
      );
    });
  });
}
