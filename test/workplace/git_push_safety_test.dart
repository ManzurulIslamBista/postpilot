import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_token_store.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:postpilot/features/workplace/domain/services/workspace_diff.dart';

String _ws(List<Map<String, dynamic>> requests, {List<Map<String, dynamic>> envs = const [], List<Map<String, dynamic>> globals = const []}) => jsonEncode({
      'format': 'postpilot-backup',
      'version': 2,
      'collections': [
        {
          'name': 'Pets',
          'folders': [
            {'id': 1, 'parentId': null, 'name': 'Admin'},
          ],
          'variables': <Object>[],
          'requests': requests,
        },
      ],
      'environments': envs,
      'globals': globals,
    });

Map<String, dynamic> _req(String name, {String url = 'https://x.test', int? folderId, String method = 'get'}) =>
    {'name': name, 'method': method, 'url': url, 'folderId': folderId, 'headers': <Object>[]};

Map<String, dynamic> _var(String key, String value, {bool secret = false}) => {'key': key, 'value': value, 'secret': secret, 'enabled': true};

final class _Tokens implements WorkplaceTokenStore {
  @override
  Future<String?> read(String id) async => null;
  @override
  Future<void> write(String id, String token) async {}
  @override
  Future<void> delete(String id) async {}
}

/// A GitHub that remembers one file: `GET contents` returns it, `PUT` replaces it only when the sha matches.
final class _Github implements HttpClientAdapter {
  String? text;
  int version = 0;
  int puts = 0;

  String get sha => 'sha$version';

  void remoteEdit(String newText) {
    text = newText;
    version++;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final path = o.uri.path;
    ResponseBody json(int status, Object body) =>
        ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    if (path == '/repos/o/r') return json(200, {'default_branch': 'main'});
    if (path.startsWith('/repos/o/r/branches/')) return json(200, {});
    if (path == '/repos/o/r/contents/workspace.json') {
      if (o.method == 'GET') {
        if (text == null) return json(404, {'message': 'Not Found'});
        return json(200, {'content': base64Encode(utf8.encode(text!)), 'encoding': 'base64', 'sha': sha});
      }
      if (o.method == 'PUT') {
        final data = o.data as Map;
        if (text != null && data['sha'] != sha) return json(409, {'message': 'sha does not match'});
        puts++;
        text = utf8.decode(base64Decode(data['content'] as String));
        version++;
        return json(200, {'content': {'sha': sha}});
      }
    }
    return json(500, {'message': 'unexpected ${o.method} $path'});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('WorkspaceDiff', () {
    test('finds added, removed and changed requests, by folder path and name', () {
      final before = _ws([_req('List'), _req('Create'), _req('Delete me')]);
      final after = _ws([_req('List'), _req('Create', url: 'https://changed.test'), _req('Brand new'), _req('Nested', folderId: 1)]);
      final c = WorkspaceDiff.compare(before, after).changes;
      expect(c.where((x) => x.kind == WorkspaceChangeKind.added && x.scope == 'Request').map((x) => x.label), unorderedEquals(['Brand new', 'Admin/Nested']));
      expect(c.where((x) => x.kind == WorkspaceChangeKind.removed && x.scope == 'Request').map((x) => x.label), ['Delete me']);
      expect(c.where((x) => x.kind == WorkspaceChangeKind.changed && x.scope == 'Request').map((x) => x.label), ['Create']);
    });

    test('reordering and database ids are not changes', () {
      final a = _ws([_req('A'), _req('B', folderId: 1)]);
      final b = _ws([_req('B', folderId: 1), _req('A')]);
      expect(WorkspaceDiff.compare(a, b).isEmpty, isTrue);
    });

    test('environments, variables and globals', () {
      final before = _ws([], envs: [
        {'name': 'Dev', 'variables': [_var('url', 'a'), _var('gone', 'x')]},
        {'name': 'Old', 'variables': <Object>[]},
      ], globals: [_var('g', '1')]);
      final after = _ws([], envs: [
        {'name': 'Dev', 'variables': [_var('url', 'b'), _var('new', 'y')]},
        {'name': 'Staging', 'variables': <Object>[]},
      ], globals: [_var('g', '2')]);
      final c = WorkspaceDiff.compare(before, after).changes;
      expect(c.where((x) => x.scope == 'Variable').map((x) => '${x.kind.name}:${x.label}@${x.container}'), unorderedEquals(['changed:url@Dev', 'added:new@Dev', 'removed:gone@Dev']));
      expect(c.where((x) => x.scope == 'Environment').map((x) => '${x.kind.name}:${x.label}'), unorderedEquals(['added:Staging', 'removed:Old']));
      expect(c.where((x) => x.scope == 'Global').single.kind, WorkspaceChangeKind.changed);
    });

    test('a missing or damaged side counts as empty', () {
      expect(WorkspaceDiff.compare(null, _ws([_req('A')])).changes.map((x) => '${x.kind.name}:${x.scope}'), containsAll(['added:Request']));
      expect(WorkspaceDiff.compare('not json', null).isEmpty, isTrue);
    });

    test('commit messages say what happened', () {
      final summary = WorkspaceDiff.compare(_ws([_req('A'), _req('B')]), _ws([_req('A', url: 'https://c.test'), _req('C'), _req('D')]));
      final message = summary.commitMessage();
      expect(message.split('\n').first, 'Add 2 requests, change 1 request, remove 1 request in Pets');
      expect(message, contains('- '));
      expect(WorkspaceDiff.compare('{}', '{}').commitMessage(), 'Update workspace from PostPilot');
      final env = WorkspaceDiff.compare(_ws([], envs: [{'name': 'Dev', 'variables': <Object>[]}]), _ws([], envs: [{'name': 'Dev', 'variables': [_var('k', 'v')]}]));
      expect(env.commitMessage(), 'Update the Dev environment');
    });
  });

  group('Pushing with a repository that may have changed', () {
    late Directory tmp;
    late _Github github;
    late WorkplaceRepositoryImpl repo;
    late WorkplaceEntity workplace;

    /// A real workspace file holding one request per name in the collection "Pets".
    String real(List<String> names, {String url = 'https://x.test'}) => WorkplaceContent(
          workplace: workplace,
          snapshot: BackupSnapshot(
            exportedAt: DateTime.utc(2026),
            collections: [
              BackupCollection(
                name: 'Pets',
                requests: [
                  for (final n in names)
                    BackupRequest(
                      request: ApiRequestEntity(
                        id: 0,
                        collectionId: 0,
                        folderId: null,
                        name: n,
                        method: HttpMethod.get,
                        url: url,
                        headers: const [],
                        queryParams: const [],
                        body: RequestBody.empty,
                        auth: const RequestAuth(type: AuthType.none),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ).toJsonString();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('pp_push');
      github = _Github();
      repo = WorkplaceRepositoryImpl(
        dio: Dio()..httpClientAdapter = github,
        storage: FileWorkplaceStorage(registryDirectory: Directory(p.join(tmp.path, 'reg')), defaultWorkplacesDirectory: tmp.path),
        tokens: _Tokens(),
      );
      // Created against an empty repository: the first commit is pushed and its sha remembered.
      workplace = await repo.createWorkplace(name: 'W', folderPath: p.join(tmp.path, 'ws'), gitRepoUrl: 'o/r', gitBranch: 'main', gitToken: 'ghp_x');
    });
    tearDown(() => tmp.delete(recursive: true));

    void localEdit(String text) => File(p.join(workplace.folderPath, 'workspace.json')).writeAsStringSync(text);

    test('creating the workplace records the sha it started from; a push moves it forward', () async {
      expect(workplace.lastSyncedSha, github.sha);
      localEdit(real(['A', 'B']));
      await repo.syncWithGit(workplace, commitMessage: 'add B');
      expect((await repo.getWorkplaces()).firstWhere((w) => w.id == workplace.id).lastSyncedSha, github.sha);
      expect(github.puts, 2, reason: 'the initial commit and this push');
    });

    test('a push is refused when the repository changed since the last sync, and nothing is overwritten', () async {
      localEdit(real(['A', 'Mine']));
      github.remoteEdit(real(['A', 'Theirs']));
      final before = github.text;
      await expectLater(repo.syncWithGit(workplace), throwsA(isA<RemoteChangedException>()));
      expect(github.text, before, reason: "the other person's work is untouched");
    });

    test('overwrite goes through, and the sha follows', () async {
      localEdit(real(['Mine']));
      github.remoteEdit(real(['Theirs']));
      await repo.syncWithGit(workplace, overwrite: true);
      expect(github.text, contains('Mine'));
      expect((await repo.getWorkplaces()).firstWhere((w) => w.id == workplace.id).lastSyncedSha, github.sha);
    });

    test("pulling first resolves it: the sha moves to the repository's, then a push works", () async {
      github.remoteEdit(real(['A', 'Theirs']));
      await repo.pullFromGit(workplace);
      // The token lives in the keychain, which this test replaces with nothing: put it back as the app would.
      final synced = (await repo.getWorkplaces()).firstWhere((w) => w.id == workplace.id).copyWith(gitToken: 'ghp_x');
      expect(synced.lastSyncedSha, github.sha);
      localEdit(real(['A', 'Theirs', 'Mine']));
      await repo.syncWithGit(synced);
      expect(github.text, contains('Mine'));
      expect(github.text, contains('Theirs'));
    });

    test('the preview names the changes, writes the message, and flags a changed repository', () async {
      localEdit(real(['B']));
      var preview = await repo.previewPush(workplace);
      expect(preview.remoteExists, isTrue);
      expect(preview.remoteChanged, isFalse);
      expect(preview.changes.changes.map((c) => '${c.kind.name}:${c.label}'), containsAll(['added:B']));
      expect(preview.suggestedMessage, startsWith('Add 1 collection and 1 request'));

      github.remoteEdit(real(['Theirs']));
      preview = await repo.previewPush(workplace);
      expect(preview.remoteChanged, isTrue);
    });

    test('the sync bookkeeping stays out of the shared file', () async {
      localEdit(real(['A']));
      await repo.syncWithGit(workplace, overwrite: true);
      expect(github.text, isNot(contains('"lastSyncedSha": "')));
      expect(github.text, isNot(contains('"lastSyncedAt": "')));
    });
  });
}
