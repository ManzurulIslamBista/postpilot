// The CLI (and the MCP server on top of it) builds a request exactly as the app does: same inheritance, same spec.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int shop;
  final requests = <ApiRequestEntity>[];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    requests.clear();
    shop = await repos.collectionRepository.createCollection('Shop');
    await repos.collectionAuthRepository.setAuthJson(
      shop,
      const RequestAuth(type: AuthType.bearer, bearerToken: '{{collectionToken}}').toJsonString(),
    );
    await repos.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: shop, key: 'baseUrl', value: 'https://shop.test', enabled: true),
    );
    final env = await repos.environmentRepository.create('Dev');
    for (final v in [('collectionToken', 'collection-token'), ('region', 'env-region'), ('scope', 'env-scope')]) {
      await repos.environmentRepository
          .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: env, key: v.$1, value: v.$2, isSecret: false, enabled: true));
    }
    await repos.environmentRepository.setActive(env);

    final a = await repos.collectionRepository.createFolder(collectionId: shop, name: 'A');
    final b = await repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: a, name: 'B');
    final c = await repos.collectionRepository.createFolder(collectionId: shop, name: 'C');
    await repos.defaultsRepository.saveCollection(
      shop,
      LevelDefaults(
        headers: [_h('X-Tenant', 'acme'), _h('Accept-Language', 'en'), _h('X-Region', '{{region}}')],
        assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      ),
    );
    await repos.defaultsRepository.saveFolder(
      a,
      LevelDefaults(
        headers: [_h('x-api-version', '2')],
        variables: [
          DefaultVariable(key: 'folderToken', value: 'a-token', isSecret: true),
          DefaultVariable(key: 'pageSize', value: '10'),
          DefaultVariable(key: 'region', value: 'folder-region'),
          DefaultVariable(key: 'folderOnly', value: 'from-a'),
        ],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{folderToken}}'),
        assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')],
      ),
    );
    await repos.defaultsRepository.saveFolder(
      b,
      LevelDefaults(headers: [_h('accept-language', '', enabled: false)], variables: [DefaultVariable(key: 'pageSize', value: '20')]),
    );
    await repos.defaultsRepository.saveFolder(c, const LevelDefaults(auth: RequestAuth(type: AuthType.none)));

    for (final spec in [
      ('Top', null, '{{baseUrl}}/top', <KeyValueItem>[], const RequestAuth(type: AuthType.inherit)),
      ('In A', a, '{{baseUrl}}/a?size={{pageSize}}&only={{folderOnly}}', [_h('X-Own', '1')], const RequestAuth(type: AuthType.inherit)),
      ('In B', b, '{{baseUrl}}/b?size={{pageSize}}', [_h('X-TENANT', 'override')], const RequestAuth(type: AuthType.inherit)),
      ('In C', c, '{{baseUrl}}/c', <KeyValueItem>[], const RequestAuth(type: AuthType.inherit)),
      ('In B no auth', b, '{{baseUrl}}/b2', <KeyValueItem>[], const RequestAuth(type: AuthType.none)),
    ]) {
      final id = await addRequest(repos, shop, spec.$1, folderId: spec.$2, url: spec.$3, headers: spec.$4, auth: spec.$5);
      requests.add((await repos.requestRepository.findById(id))!);
    }
  });
  tearDown(() => db.close());

  Future<WorkspaceRunner> runnerFor(Map<String, CliRequest> sent) async {
    final text = BackupCodec.encode(await repos.backupService.snapshot());
    // Through the same split and merge a workspace file goes through, so a secret folder variable travels as in real use.
    final split = SecretSplitter.split(jsonDecode(text) as Map<String, dynamic>);
    final local = SecretSplitter.encodeLocal(split.secrets);
    return WorkspaceRunner.parse(jsonEncode(split.publicDoc), (request) async {
      sent[Uri.parse(request.url).path] = request;
      return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [123, 125], duration: Duration.zero);
    }, localSecrets: local);
  }

  test('every request gets the same method, URL, headers and body in the app and in the CLI', () async {
    final prepare = PrepareRequestUseCase(
      BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      ),
      repos.collectionAuthRepository,
      defaults: ResolveRequestDefaultsUseCase(repos.defaultsRepository),
    );
    final sent = <String, CliRequest>{};
    final runner = await runnerFor(sent);

    final summary = await runner.run(const RunOptions(environment: 'Dev'));

    expect(summary.outcomes.map((o) => o.error), everyElement(isNull), reason: summary.outcomes.map((o) => o.error).join('\n'));
    expect(sent.length, requests.length);
    for (final request in requests) {
      final app = (await prepare(request)).spec;
      final cli = sent[Uri.parse(app.url).path];
      expect(cli, isNotNull, reason: request.name);
      expect(cli!.method, app.method, reason: request.name);
      expect(cli.url, app.url, reason: request.name);
      expect(cli.headers, app.headers, reason: request.name);
      expect(cli.body, app.bodyBytes, reason: request.name);
    }
  });

  test('and that spec is what the inheritance rules say, worked out by hand', () async {
    final sent = <String, CliRequest>{};
    final runner = await runnerFor(sent);

    await runner.run(const RunOptions(environment: 'Dev'));

    // Top level: the collection's headers and its bearer; the environment gives {{region}} and {{collectionToken}}.
    expect(sent['/top']!.headers, {
      'X-Tenant': 'acme',
      'Accept-Language': 'en',
      'X-Region': 'env-region',
      'Authorization': 'Bearer collection-token',
    });
    // Folder A: its variables, its header and its (secret) bearer; the environment still beats its {{region}}.
    expect(sent['/a']!.url, 'https://shop.test/a?size=10&only=from-a');
    expect(sent['/a']!.headers, {
      'X-Tenant': 'acme',
      'Accept-Language': 'en',
      'X-Region': 'env-region',
      'x-api-version': '2',
      'X-Own': '1',
      'Authorization': 'Bearer a-token',
    });
    // Folder B inside A: the inner pageSize wins, Accept-Language is switched off, the request's X-TENANT replaces X-Tenant,
    // and the bearer is the nearest folder's: B sets none, A's applies.
    expect(sent['/b']!.url, 'https://shop.test/b?size=20');
    expect(sent['/b']!.headers, {
      'X-Region': 'env-region',
      'x-api-version': '2',
      'X-TENANT': 'override',
      'Authorization': 'Bearer a-token',
    });
    // Folder C sets No Auth: no Authorization although the collection has a bearer.
    expect(sent['/c']!.headers.containsKey('Authorization'), isFalse);
    // A request with its own No Auth in a folder with a bearer.
    expect(sent['/b2']!.headers.containsKey('Authorization'), isFalse);
  });

  test('the tests that run, and where each comes from, are the same in the app and in the CLI', () async {
    final scripts = RunRequestScriptsUseCase(
      repos.scriptsRepository,
      BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      ),
      repos.environmentRepository,
      repos.globalVariableRepository,
      const AssertionEvaluator(),
      ResolveRequestDefaultsUseCase(repos.defaultsRepository),
    );
    final inB = requests.firstWhere((r) => r.name == 'In B');
    final app = await scripts(RunRequestScriptsParams(
      requestId: inB.id,
      collectionId: shop,
      response: ApiResponseEntity(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: Uint8List.fromList([123, 125]), duration: Duration.zero),
      folderId: inB.folderId,
    ));
    final runner = await runnerFor({});

    final summary = await runner.run(const RunOptions(environment: 'Dev', folder: 'A/B'));

    final cli = summary.outcomes.where((o) => o.name == 'In B').single.scripts;
    expect(cli.assertions.map((a) => (a.name, a.origin, a.passed)).toList(), app.assertions.map((a) => (a.name, a.origin, a.passed)).toList());
    expect(app.assertions.map((a) => a.origin), ['collection "Shop"', 'folder "A"']);
  });

  test('a workspace file with no defaults runs as before', () async {
    final plain = BackupCodec.encode(
      BackupSnapshot(exportedAt: DateTime.utc(2026), collections: [
        BackupCollection(
          name: 'Plain',
          requests: [
            BackupRequest(
              request: const ApiRequestEntity(
                id: 0,
                collectionId: 0,
                folderId: null,
                name: 'Ping',
                method: HttpMethod.get,
                url: 'https://plain.test/ping',
                headers: [],
                queryParams: [],
                body: RequestBody.empty,
                auth: RequestAuth(),
              ),
            ),
          ],
        ),
      ]),
    );
    final sent = <String, CliRequest>{};
    final runner = WorkspaceRunner.parse(plain, (request) async {
      sent[request.url] = request;
      return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
    });

    final summary = await runner.run(const RunOptions());

    expect(summary.ok, isTrue);
    expect(sent['https://plain.test/ping']!.headers, isEmpty);
  });
}
