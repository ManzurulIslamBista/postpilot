import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_token_store.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';

/// A token store that remembers what was written, so a test can see where tokens did and did not go.
final class _MemoryTokens implements WorkplaceTokenStore {
  final values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String workplaceId) async => values[workplaceId];

  @override
  Future<void> write(String workplaceId, String token) async {
    writes++;
    values[workplaceId] = token;
  }

  @override
  Future<void> delete(String workplaceId) async => values.remove(workplaceId);
}

/// Answers GitHub's REST API from a function, so Git flows run without a network.
final class _FakeGitHub implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final calls = <RequestOptions>[];
  _FakeGitHub(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// GitHub as it answers a brand-new empty repository o/r: the repository exists, its branches exist,
/// workspace.json does not yet, and the first push is accepted.
ResponseBody _happyHandler(RequestOptions o) {
  final key = '${o.method} ${o.uri.path}';
  if (key == 'GET /repos/o/r') return _json(200, {'default_branch': 'main'});
  if (key == 'GET /repos/o/r/contents/workspace.json') return _json(404, {'message': 'Not Found'});
  if (key.startsWith('GET /repos/o/r/branches/')) return _json(200, {});
  if (key == 'PUT /repos/o/r/contents/workspace.json') return _json(201, {});
  return _json(500, {'message': 'unexpected $key'});
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

WorkplaceEntity _entity(String folder, {String name = 'Test'}) => WorkplaceEntity(
  id: 'test-id',
  name: name,
  folderPath: folder,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

String _workspaceJson(String folder, String collectionName) => WorkplaceContent(
  workplace: _entity(folder),
  snapshot: BackupSnapshot(
    exportedAt: DateTime.utc(2026, 1, 1),
    collections: [BackupCollection(name: collectionName)],
  ),
).toJsonString();

/// A workplace connected to o/r whose first pull finds nothing, so it starts from an empty workspace pushed as the first commit.
Future<WorkplaceEntity> _createGitWorkplace(
  WorkplaceRepositoryImpl repository,
  Directory tempDir, {
  required String token,
  String folder = 'git',
  String repo = 'o/r',
  String branch = 'main',
}) =>
    repository.createWorkplace(
      name: 'Git $folder',
      folderPath: p.join(tempDir.path, folder),
      gitRepoUrl: repo,
      gitBranch: branch,
      gitToken: token,
    );

void main() {
  late Directory tempDir;
  late FileWorkplaceStorage storage;
  late String workplacesRoot;

  late _MemoryTokens tokens;

  WorkplaceRepositoryImpl newRepository({Dio? dio}) => WorkplaceRepositoryImpl(storage: storage, dio: dio, tokens: tokens);

  setUp(() {
    // Every path the repository uses is inside this directory: the test never
    // reads or writes the real application-support or Documents folders.
    tokens = _MemoryTokens();
    tempDir = Directory.systemTemp.createTempSync('postpilot_workplace_test_');
    workplacesRoot = p.join(tempDir.path, 'workplaces');
    storage = FileWorkplaceStorage(
      registryDirectory: Directory(p.join(tempDir.path, 'registry')),
      defaultWorkplacesDirectory: workplacesRoot,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('WorkplaceEntity & WorkplaceContent', () {
    test('serializes and deserializes workplace with classic token', () {
      final workplace = WorkplaceEntity(
        id: 'test-id',
        name: 'My Workspace',
        folderPath: tempDir.path,
        gitRepoUrl: 'https://github.com/owner/repo.git',
        gitBranch: 'main',
        gitToken: 'ghp_classicToken12345',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final json = workplace.toJson();
      expect(json['name'], 'My Workspace');
      expect(json['gitToken'], 'ghp_classicToken12345');
      expect(workplace.isGitConnected, isTrue);

      final restored = WorkplaceEntity.fromJson(json);
      expect(restored.id, workplace.id);
      expect(restored.name, workplace.name);
      expect(restored.gitToken, workplace.gitToken);
      expect(restored.gitBranch, workplace.gitBranch);
    });

    test('WorkplaceContent produces single JSON file format', () {
      final workplace = _entity(tempDir.path, name: 'My Workspace');
      final jsonStr = WorkplaceContent.empty(workplace).toJsonString();

      expect(jsonStr, contains('"format": "postpilot-backup"'));
      expect(jsonStr, contains('"workplace"'));
      expect(jsonStr, contains('"collections"'));
      expect(jsonStr, contains('"environments"'));

      final decoded = WorkplaceContent.fromJsonString(jsonStr, fallbackWorkplace: workplace);
      expect(decoded.workplace.name, workplace.name);
    });

    test('the git token is never written to workspace.json', () {
      final workplace = _entity(tempDir.path).copyWith(gitRepoUrl: 'owner/repo', gitToken: 'ghp_secret');
      expect(WorkplaceContent.empty(workplace).toJsonString(), isNot(contains('ghp_secret')));
    });
  });

  group('WorkplaceRepository local files', () {
    test('creates workplace and creates single workspace.json file on disk', () async {
      final repository = newRepository();
      final folder = p.join(tempDir.path, 'project_alpha');
      final workplace = await repository.createWorkplace(name: 'Project Alpha', folderPath: folder);

      expect(workplace.name, 'Project Alpha');
      expect(Directory(folder).existsSync(), isTrue);
      expect(File(p.join(folder, 'workspace.json')).existsSync(), isTrue);

      final loaded = await repository.loadWorkplaceContent(workplace);
      expect(loaded.workplace.name, 'Project Alpha');
      expect(loaded.snapshot.collections, isEmpty);
    });

    test('first launch creates the default workplace inside the injected directories only', () async {
      final workplaces = await newRepository().getWorkplaces();

      expect(workplaces, hasLength(1));
      expect(workplaces.single.name, 'My Workplace');
      expect(p.isWithin(workplacesRoot, workplaces.single.folderPath), isTrue);
      expect(File(p.join(tempDir.path, 'registry', 'workplaces_registry.json')).existsSync(), isTrue);
    });

    test('opens a folder that already holds a workspace.json without touching it', () async {
      final folder = p.join(tempDir.path, 'existing');
      Directory(folder).createSync();
      final file = File(p.join(folder, 'workspace.json'));
      final original = _workspaceJson(folder, 'Already Here');
      file.writeAsStringSync(original);

      final repository = newRepository();
      final workplace = await repository.createWorkplace(name: 'Opened', folderPath: folder);

      expect(file.readAsStringSync(), original);
      final content = await repository.loadWorkplaceContent(workplace);
      expect(content.snapshot.collections.single.name, 'Already Here');
    });

    test('a workspace.json that is not a PostPilot workspace is reported and left alone', () async {
      final folder = p.join(tempDir.path, 'broken');
      Directory(folder).createSync();
      final file = File(p.join(folder, 'workspace.json'))..writeAsStringSync('{ this is not json');

      final repository = newRepository();
      await expectLater(
        repository.createWorkplace(name: 'Broken', folderPath: folder),
        throwsA(
          isA<WorkplaceException>().having((e) => e.message, 'message', contains('not a valid PostPilot workspace')),
        ),
      );

      expect(file.readAsStringSync(), '{ this is not json');
      expect((await repository.getWorkplaces()).map((w) => w.name), isNot(contains('Broken')));
    });

    test('refuses a folder another workplace already uses, however it is written', () async {
      final repository = newRepository();
      final folder = p.join(tempDir.path, 'shared');
      await repository.createWorkplace(name: 'First', folderPath: folder);

      for (final again in [folder, '$folder${Platform.pathSeparator}', folder.toUpperCase()]) {
        await expectLater(
          repository.createWorkplace(name: 'Second', folderPath: again),
          throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('"First"'))),
        );
      }
    });

    test('validates name and folder before touching the disk', () async {
      final repository = newRepository();

      await expectLater(
        repository.createWorkplace(name: '   ', folderPath: p.join(tempDir.path, 'x')),
        throwsA(isA<WorkplaceException>()),
      );
      await expectLater(
        repository.createWorkplace(name: 'Relative', folderPath: 'just/a/relative/path'),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('full folder path'))),
      );
      await expectLater(
        repository.createWorkplace(name: 'No token', folderPath: p.join(tempDir.path, 'y'), gitRepoUrl: 'owner/repo'),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('token'))),
      );
      expect(Directory(p.join(tempDir.path, 'x')).existsSync(), isFalse);
      expect(Directory(p.join(tempDir.path, 'y')).existsSync(), isFalse);
    });

    test('the registry remembers the active workplace across repository instances', () async {
      final first = newRepository();
      final a = await first.createWorkplace(name: 'A', folderPath: p.join(tempDir.path, 'a'));
      final b = await first.createWorkplace(name: 'B', folderPath: p.join(tempDir.path, 'b'));

      expect((await newRepository().getActiveWorkplace())?.id, b.id);
      await first.setActiveWorkplace(a.id);
      expect((await newRepository().getActiveWorkplace())?.id, a.id);
    });

    test('deleting a workplace keeps its files and activates another one', () async {
      final repository = newRepository();
      final folder = p.join(tempDir.path, 'doomed');
      final doomed = await repository.createWorkplace(name: 'Doomed', folderPath: folder);

      await repository.deleteWorkplace(doomed.id);

      expect(File(p.join(folder, 'workspace.json')).existsSync(), isTrue);
      expect((await repository.getWorkplaces()).map((w) => w.id), isNot(contains(doomed.id)));
      expect((await repository.getActiveWorkplace())?.id, isNot(doomed.id));
    });

    test('saving replaces workspace.json completely and leaves no temp file behind', () async {
      final repository = newRepository();
      final folder = p.join(tempDir.path, 'save');
      final workplace = await repository.createWorkplace(name: 'Save', folderPath: folder);
      final content = WorkplaceContent(
        workplace: workplace,
        snapshot: BackupSnapshot(
          exportedAt: DateTime.utc(2026, 1, 1),
          collections: const [BackupCollection(name: 'Saved')],
        ),
      );

      await repository.saveWorkplaceContent(workplace, content);

      expect(File(p.join(folder, 'workspace.json.tmp')).existsSync(), isFalse);
      expect((await repository.loadWorkplaceContent(workplace)).snapshot.collections.single.name, 'Saved');
    });

    test('suggested folders keep letters of any script and drop symbols', () async {
      final repository = newRepository();

      expect(p.basename(await repository.getDefaultWorkplacesDirectory(workplaceName: 'Team: A/B?')), 'Team_AB');
      expect(p.basename(await repository.getDefaultWorkplacesDirectory(workplaceName: 'আমার কাজ')), 'আমার_কাজ');
      expect(p.basename(await repository.getDefaultWorkplacesDirectory(workplaceName: '???')), 'New_Workplace');
      expect(await repository.getDefaultWorkplacesDirectory(), workplacesRoot);
    });

    test('syncWithGit and pullFromGit refuse a workplace without a repository', () async {
      final workplace = _entity(tempDir.path);
      final repository = newRepository();

      for (final action in [() => repository.syncWithGit(workplace), () => repository.pullFromGit(workplace)]) {
        await expectLater(
          action(),
          throwsA(
            isA<WorkplaceException>().having(
              (e) => e.message,
              'message',
              contains('not connected to a Git repository'),
            ),
          ),
        );
      }
    });
  });

  group('WorkplaceRepository Git', () {
    Dio dioFor(_FakeGitHub github) => Dio()..httpClientAdapter = github;

    test('a rejected token stops creation: nothing is registered or written', () async {
      final github = _FakeGitHub((o) => _json(401, {'message': 'Bad credentials'}));
      final repository = newRepository(dio: dioFor(github));
      final folder = p.join(tempDir.path, 'git_bad');

      await expectLater(
        repository.createWorkplace(
          name: 'Git',
          folderPath: folder,
          gitRepoUrl: 'https://github.com/o/r',
          gitToken: 'bad',
        ),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('Authentication failed'))),
      );

      expect(File(p.join(folder, 'workspace.json')).existsSync(), isFalse);
      expect((await repository.getWorkplaces()).map((w) => w.name), isNot(contains('Git')));
    });

    test('starts from the copy in the repository when it has one', () async {
      final remote = _workspaceJson('irrelevant', 'From Remote');
      final github = _FakeGitHub((o) {
        switch ('${o.method} ${o.uri.path}') {
          case 'GET /repos/o/r':
            return _json(200, {'default_branch': 'main'});
          case 'GET /repos/o/r/contents/workspace.json':
            return _json(200, {'encoding': 'base64', 'content': base64Encode(utf8.encode(remote)), 'sha': 'abc'});
        }
        return _json(500, {'message': 'unexpected ${o.method} ${o.uri}'});
      });
      final repository = newRepository(dio: dioFor(github));

      final workplace = await repository.createWorkplace(
        name: 'Git',
        folderPath: p.join(tempDir.path, 'git_ok'),
        gitRepoUrl: 'https://github.com/o/r.git',
        gitToken: 'ghp_x',
      );

      expect((await repository.loadWorkplaceContent(workplace)).snapshot.collections.single.name, 'From Remote');
      expect(workplace.lastSyncedAt, isNotNull);
      expect(github.calls.every((c) => c.headers['Authorization'] == 'token ghp_x'), isTrue);
    });

    test('pushes an empty workspace as the first commit when the repository has none', () async {
      Map<String, dynamic>? pushed;
      final github = _FakeGitHub((o) {
        switch ('${o.method} ${o.uri.path}') {
          case 'GET /repos/o/r':
            return _json(200, {'default_branch': 'main'});
          case 'GET /repos/o/r/contents/workspace.json':
            return _json(404, {'message': 'Not Found'});
          case 'GET /repos/o/r/branches/dev':
            return _json(200, {});
          case 'PUT /repos/o/r/contents/workspace.json':
            pushed = Map<String, dynamic>.from(o.data as Map);
            return _json(201, {});
        }
        return _json(500, {'message': 'unexpected ${o.method} ${o.uri}'});
      });
      final repository = newRepository(dio: dioFor(github));

      final workplace = await repository.createWorkplace(
        name: 'Git',
        folderPath: p.join(tempDir.path, 'git_new'),
        gitRepoUrl: 'o/r',
        gitBranch: 'dev',
        gitToken: 'ghp_x',
      );

      expect(pushed, isNotNull);
      expect(pushed!['branch'], 'dev');
      expect(pushed!.containsKey('sha'), isFalse);
      expect(BackupCodec.decode(utf8.decode(base64Decode(pushed!['content'] as String))).collections, isEmpty);
      expect(workplace.lastSyncedAt, isNotNull);
    });

    test('a push the token is not allowed to make is reported instead of silently skipped', () async {
      final github = _FakeGitHub((o) {
        switch ('${o.method} ${o.uri.path}') {
          case 'GET /repos/o/r':
            return _json(200, {'default_branch': 'main'});
          case 'GET /repos/o/r/contents/workspace.json':
            return _json(404, {'message': 'Not Found'});
          case 'GET /repos/o/r/branches/main':
            return _json(200, {});
          case 'PUT /repos/o/r/contents/workspace.json':
            return _json(403, {'message': 'Resource not accessible by personal access token'});
        }
        return _json(500, {'message': 'unexpected'});
      });
      final repository = newRepository(dio: dioFor(github));

      await expectLater(
        repository.createWorkplace(
          name: 'Git',
          folderPath: p.join(tempDir.path, 'git_ro'),
          gitRepoUrl: 'o/r',
          gitToken: 'ghp_x',
        ),
        throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('Access Denied'))),
      );
      expect((await repository.getWorkplaces()).map((w) => w.name), isNot(contains('Git')));
    });

    test('the GitHub token lives in the token store, never in the registry file, and still comes back after a restart', () async {
      final github = _FakeGitHub(_happyHandler);
      final repository = newRepository(dio: dioFor(github));
      final registryFile = File(p.join(tempDir.path, 'registry', 'workplaces_registry.json'));
      final created = await _createGitWorkplace(repository, tempDir, token: 'ghp_very_secret');

      expect(registryFile.readAsStringSync(), isNot(contains('ghp_very_secret')));
      expect(tokens.values[created.id], 'ghp_very_secret');
      expect((await newRepository().getActiveWorkplace())?.gitToken, 'ghp_very_secret', reason: 'a new run reads it back');
    });

    test('a registry written by an older version, with the token inside it, is migrated to the token store', () async {
      final repository = newRepository();
      final created = await repository.createWorkplace(name: 'Old', folderPath: p.join(tempDir.path, 'old'));
      final registryFile = File(p.join(tempDir.path, 'registry', 'workplaces_registry.json'));
      final registry = jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
      for (final w in registry['workplaces'] as List) {
        if ((w as Map)['id'] == created.id) {
          w['gitRepoUrl'] = 'o/r';
          w['gitToken'] = 'ghp_from_old_version';
        }
      }
      registryFile.writeAsStringSync(jsonEncode(registry));

      final reloaded = (await newRepository().getWorkplaces()).firstWhere((w) => w.id == created.id);

      expect(reloaded.gitToken, 'ghp_from_old_version', reason: 'nothing is lost');
      expect(tokens.values[created.id], 'ghp_from_old_version');
      expect(registryFile.readAsStringSync(), isNot(contains('ghp_from_old_version')), reason: 'the file was rewritten without it');
    });

    test('deleting a workplace, or disconnecting it from Git, removes its token', () async {
      final github = _FakeGitHub(_happyHandler);
      final repository = newRepository(dio: dioFor(github));
      final first = await _createGitWorkplace(repository, tempDir, token: 'ghp_one', folder: 'one', repo: 'o/r');
      final second = await _createGitWorkplace(repository, tempDir, token: 'ghp_two', folder: 'two', repo: 'o/r', branch: 'other');
      expect(tokens.values.keys, containsAll([first.id, second.id]));

      await repository.updateWorkplace(first.copyWith(gitRepoUrl: null, gitToken: null));
      await repository.deleteWorkplace(second.id);

      expect(tokens.values, isEmpty);
    });

    test('saving the registry again does not rewrite a token that has not changed', () async {
      final github = _FakeGitHub(_happyHandler);
      final repository = newRepository(dio: dioFor(github));
      final created = await _createGitWorkplace(repository, tempDir, token: 'ghp_once');
      final writes = tokens.writes;

      for (var i = 0; i < 5; i++) {
        await repository.saveWorkplaceContent(created, WorkplaceContent.empty(created));
      }

      expect(tokens.writes, writes);
    });

    test('a repository and branch belong to one workplace: another spelling of the same repo is refused', () async {
      final remote = _workspaceJson('x', 'Remote');
      final github = _FakeGitHub((o) {
        if (o.uri.path == '/repos/o/r') return _json(200, {'default_branch': 'main'});
        return _json(200, {'encoding': 'base64', 'content': base64Encode(utf8.encode(remote)), 'sha': 'abc'});
      });
      final repository = newRepository(dio: dioFor(github));
      await repository.createWorkplace(
        name: 'First',
        folderPath: p.join(tempDir.path, 'one'),
        gitRepoUrl: 'https://github.com/o/r',
        gitToken: 't',
      );

      for (final spelling in ['O/R', 'https://github.com/o/r.git', 'git@github.com:o/r.git']) {
        await expectLater(
          repository.createWorkplace(
            name: 'Second',
            folderPath: p.join(tempDir.path, 'two'),
            gitRepoUrl: spelling,
            gitToken: 't',
          ),
          throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('"First" already uses o/r'))),
          reason: spelling,
        );
      }
      // Another branch is a different file in the repository, so it is allowed.
      final other = await repository.createWorkplace(
        name: 'Second',
        folderPath: p.join(tempDir.path, 'two'),
        gitRepoUrl: 'o/r',
        gitBranch: 'team-b',
        gitToken: 't',
      );
      expect(other.gitBranch, 'team-b');
    });

    test(
      'connecting an existing workplace to a taken repository is refused, but already shared ones can still save',
      () async {
        final repository = newRepository(dio: dioFor(_FakeGitHub((o) => _json(404, {'message': 'Not Found'}))));
        final a = await repository.createWorkplace(name: 'A', folderPath: p.join(tempDir.path, 'a'));
        final b = await repository.createWorkplace(name: 'B', folderPath: p.join(tempDir.path, 'b'));
        // An older registry (written before the rule existed) with both on one repository.
        final registryFile = File(p.join(tempDir.path, 'registry', 'workplaces_registry.json'));
        final registry = jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
        for (final w in registry['workplaces'] as List) {
          (w as Map<String, dynamic>)['gitRepoUrl'] = 'o/shared';
          w['gitBranch'] = 'main';
        }
        registryFile.writeAsStringSync(jsonEncode(registry));

        await repository.saveWorkplaceContent(a.copyWith(gitRepoUrl: 'o/shared'), WorkplaceContent.empty(a));
        await repository.updateWorkplace(b.copyWith(gitRepoUrl: 'o/shared', gitBranch: 'main', name: 'B renamed'));
        await repository.updateWorkplace(
          b.copyWith(gitRepoUrl: 'o/shared', gitBranch: 'other'),
        ); // a different file: free

        final c = await repository.createWorkplace(name: 'C', folderPath: p.join(tempDir.path, 'c'));
        await expectLater(
          repository.updateWorkplace(c.copyWith(gitRepoUrl: 'o/shared', gitBranch: 'main')),
          throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('already uses o/shared'))),
        );
      },
    );

    test('syncWithGit updates the existing remote file using its sha', () async {
      Map<String, dynamic>? pushed;
      final github = _FakeGitHub((o) {
        switch ('${o.method} ${o.uri.path}') {
          case 'GET /repos/o/r/branches/main':
            return _json(200, {});
          case 'GET /repos/o/r/contents/workspace.json':
            return _json(200, {'sha': 'old-sha'});
          case 'PUT /repos/o/r/contents/workspace.json':
            pushed = Map<String, dynamic>.from(o.data as Map);
            return _json(200, {});
        }
        return _json(500, {'message': 'unexpected'});
      });
      final repository = newRepository(dio: dioFor(github));
      final folder = p.join(tempDir.path, 'git_sync');
      Directory(folder).createSync();
      File(p.join(folder, 'workspace.json')).writeAsStringSync(_workspaceJson(folder, 'Local'));
      final workplace = _entity(folder).copyWith(gitRepoUrl: 'o/r', gitToken: 'ghp_x');

      await repository.syncWithGit(workplace, commitMessage: 'my message');

      expect(pushed!['sha'], 'old-sha');
      expect(pushed!['message'], 'my message');
      expect(
        BackupCodec.decode(utf8.decode(base64Decode(pushed!['content'] as String))).collections.single.name,
        'Local',
      );
    });

    test('pullFromGit replaces the local file with the remote one', () async {
      final remote = _workspaceJson('x', 'Newer Remote');
      final github = _FakeGitHub(
        (o) => _json(200, {'encoding': 'base64', 'content': base64Encode(utf8.encode(remote))}),
      );
      final repository = newRepository(dio: dioFor(github));
      final folder = p.join(tempDir.path, 'git_pull');
      Directory(folder).createSync();
      File(p.join(folder, 'workspace.json')).writeAsStringSync(_workspaceJson(folder, 'Stale Local'));
      final workplace = _entity(folder).copyWith(gitRepoUrl: 'o/r', gitToken: 'ghp_x');

      final pulled = await repository.pullFromGit(workplace);

      expect(pulled.snapshot.collections.single.name, 'Newer Remote');
      expect(File(p.join(folder, 'workspace.json')).readAsStringSync(), contains('Newer Remote'));
    });
  });
}
