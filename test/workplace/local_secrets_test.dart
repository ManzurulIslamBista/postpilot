import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/file_workplace_storage.dart';
import 'package:postpilot/features/workplace/data/storage/workplace_token_store.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

final class _Tokens implements WorkplaceTokenStore {
  @override
  Future<String?> read(String workplaceId) async => null;
  @override
  Future<void> write(String workplaceId, String token) async {}
  @override
  Future<void> delete(String workplaceId) async {}
}

final class _CapturingGitHub implements HttpClientAdapter {
  final puts = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final key = '${o.method} ${o.uri.path}';
    if (o.method == 'PUT') puts.add(utf8.decode(base64Decode((o.data as Map)['content'] as String)));
    final status = switch (key) {
      'GET /repos/o/r/contents/workspace.json' => 404,
      'PUT /repos/o/r/contents/workspace.json' => 201,
      _ => 200,
    };
    return ResponseBody.fromString(jsonEncode(key == 'GET /repos/o/r' ? {'default_branch': 'main'} : {'message': 'x'}), status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

BackupSnapshot _snapshot({String token = 'tok-123', String password = 'pw-456'}) => BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Dev', variables: [
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'baseUrl', value: 'https://dev.test', isSecret: false, enabled: true),
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'token', value: token, isSecret: true, enabled: true),
        ]),
      ],
      globals: [GlobalVariableEntity(id: 0, key: 'g_secret', value: 'gs-789', isSecret: true, enabled: true)],
      collections: [
        BackupCollection(
          name: 'Pets',
          variables: [CollectionVariableEntity(id: 0, collectionId: 0, key: 'db_password', value: password, enabled: true)],
          requests: [
            BackupRequest(
              request: ApiRequestEntity(
                id: 0,
                collectionId: 0,
                folderId: null,
                name: 'Get pet',
                method: HttpMethod.get,
                url: 'https://api.test/pets',
                headers: const [],
                queryParams: const [],
                body: RequestBody.empty,
                auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'bearer-abc'),
              ),
            ),
          ],
        ),
      ],
    );

void main() {
  group('SecretSplitter', () {
    Map<String, dynamic> doc() => jsonDecode(BackupCodec.encode(_snapshot())) as Map<String, dynamic>;

    test('moves secret variables and auth credentials out, by name', () {
      final split = SecretSplitter.split(doc());
      expect(split.secrets, {
        'env/Dev/token': 'tok-123',
        'global/g_secret': 'gs-789',
        'cvar/Pets/db_password': 'pw-456',
        'rauth/Pets/Get pet/bearerToken': 'bearer-abc',
      });
      final text = jsonEncode(split.publicDoc);
      for (final secret in ['tok-123', 'gs-789', 'pw-456', 'bearer-abc']) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('https://dev.test'), reason: 'ordinary values stay');
    });

    test('merge puts blanks back and never overwrites a value that is set', () {
      final split = SecretSplitter.split(doc());
      final merged = SecretSplitter.merge(split.publicDoc, split.secrets);
      expect(jsonEncode(merged), jsonEncode(doc()));

      final shared = doc();
      ((shared['environments'] as List).first['variables'] as List)[1]['value'] = 'shared-default';
      final result = SecretSplitter.merge(shared, split.secrets);
      expect(((result['environments'] as List).first['variables'] as List)[1]['value'], 'shared-default');
    });

    test('same-named siblings stay apart', () {
      final d = {
        'environments': [
          {'name': 'Dev', 'variables': [{'key': 'k', 'value': 'one', 'secret': true}, {'key': 'k', 'value': 'two', 'secret': true}]},
        ],
      };
      final split = SecretSplitter.split(d);
      expect(split.secrets, {'env/Dev/k': 'one', 'env/Dev/k#2': 'two'});
    });

    test('the local file round-trips and a damaged one means no secrets', () {
      final encoded = SecretSplitter.encodeLocal({'a': 'b'});
      expect(SecretSplitter.decodeLocal(encoded), {'a': 'b'});
      expect(SecretSplitter.decodeLocal('{broken'), isEmpty);
      expect(SecretSplitter.decodeLocal(null), isEmpty);
      expect(SecretSplitter.decodeLocal('{"secrets": 5}'), isEmpty);
    });
  });

  group('WorkplaceRepositoryImpl with secrets kept local', () {
    late Directory tmp;
    late String folder;
    late WorkplaceEntity workplace;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('pp_secrets');
      folder = p.join(tmp.path, 'ws');
      workplace = WorkplaceEntity(id: 'w1', name: 'WS', folderPath: folder, createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
    });
    tearDown(() => tmp.delete(recursive: true));

    WorkplaceRepositoryImpl repo({bool keepLocal = true, Dio? dio}) => WorkplaceRepositoryImpl(
          dio: dio,
          storage: FileWorkplaceStorage(registryDirectory: Directory(p.join(tmp.path, 'reg')), defaultWorkplacesDirectory: tmp.path),
          tokens: _Tokens(),
          keepSecretsLocal: () => keepLocal,
        );

    test('saving writes secrets only to workspace.local.json; loading merges them back', () async {
      final r = repo();
      await r.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: _snapshot()));

      final shared = File(p.join(folder, 'workspace.json')).readAsStringSync();
      final local = File(p.join(folder, 'workspace.local.json')).readAsStringSync();
      for (final secret in ['tok-123', 'gs-789', 'pw-456', 'bearer-abc']) {
        expect(shared, isNot(contains(secret)), reason: 'workspace.json is what Git carries');
        expect(local, contains(secret));
      }

      final loaded = await r.loadWorkplaceContent(workplace);
      final env = loaded.snapshot.environments.single.variables.firstWhere((v) => v.key == 'token');
      expect(env.value, 'tok-123');
      expect(loaded.snapshot.globals.single.value, 'gs-789');
      expect(loaded.snapshot.collections.single.requests.single.request.auth.bearerToken, 'bearer-abc');
    });

    test('with the setting off, secrets stay in workspace.json as before', () async {
      final r = repo(keepLocal: false);
      await r.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: _snapshot()));
      expect(File(p.join(folder, 'workspace.json')).readAsStringSync(), contains('tok-123'));
      expect(File(p.join(folder, 'workspace.local.json')).existsSync(), isFalse);
      expect(r.keepsSecretsLocal, isFalse);
    });

    test('a secret that is removed disappears from the local file too', () async {
      final r = repo();
      await r.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: _snapshot()));
      await r.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: _snapshot(token: '', password: '')));
      final local = File(p.join(folder, 'workspace.local.json')).readAsStringSync();
      expect(local, isNot(contains('tok-123')));
      expect(local, isNot(contains('pw-456')));
    });

    test('pushing to Git sends the shared file, with no secrets in it', () async {
      final github = _CapturingGitHub();
      final dio = Dio()..httpClientAdapter = github;
      final r = repo(dio: dio);
      final connected = workplace.copyWith(gitRepoUrl: 'https://github.com/o/r', gitToken: 'ghp_x');
      await r.saveWorkplaceContent(connected, WorkplaceContent(workplace: connected, snapshot: _snapshot()));
      await r.syncWithGit(connected);
      expect(github.puts, hasLength(1));
      for (final secret in ['tok-123', 'gs-789', 'pw-456', 'bearer-abc']) {
        expect(github.puts.single, isNot(contains(secret)));
      }
      expect(github.puts.single, contains('https://dev.test'));
    });
  });
}
