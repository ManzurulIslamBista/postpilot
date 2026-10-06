import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../support/drift_repos.dart';

ApiResponseEntity _response(String body) => ApiResponseEntity(
      statusCode: 200,
      statusMessage: '',
      headers: const {},
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: const Duration(milliseconds: 5),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late DriftRepos repos;
  late int collectionId;
  late int requestId;
  late int environmentId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    collectionId = await repos.collectionRepository.createCollection('Auth');
    requestId = (await repos.requestRepository.createRequest(collectionId: collectionId, name: 'Login'));
    environmentId = await repos.environmentRepository.create('Dev');
    await repos.environmentRepository.setActive(environmentId);
  });

  tearDown(() => database.close());

  Future<void> extract(List<ExtractorEntity> extractors, String body) async {
    await repos.scriptsRepository.save(
      RequestScriptsEntity(requestId: requestId, extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors)),
    );
    await RunRequestScriptsUseCase(
      repos.scriptsRepository,
      BuildVariableResolverUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository),
      repos.environmentRepository,
      repos.globalVariableRepository,
    )(RunRequestScriptsParams(requestId: requestId, collectionId: collectionId, response: _response(body)));
  }

  Future<Map<String, bool>> environmentSecrets() async => {
        for (final v in await repos.environmentRepository.watchVariables(environmentId).first) v.key: v.isSecret,
      };

  Future<Map<String, bool>> globalSecrets() async => {
        for (final v in await repos.globalVariableRepository.watchAll().first) v.key: v.isSecret,
      };

  test('an extracted token is a secret variable from the start, so Git never gets its value', () async {
    await extract([
      ExtractorEntity(path: 'data.access_token', variableKey: 'access_token'),
      ExtractorEntity(path: 'data.user.id', variableKey: 'userId'),
      ExtractorEntity(path: 'data.api_key', variableKey: 'apiKey'),
    ], '{"data": {"access_token": "at-1", "user": {"id": 7}, "api_key": "ak-1"}}');

    expect(await environmentSecrets(), {'access_token': true, 'userId': false, 'apiKey': true});
    expect((await repos.environmentRepository.getActiveVariables())['access_token'], 'at-1');
  });

  test('the same for a global variable', () async {
    await extract([
      ExtractorEntity(path: 'refresh_token', scope: ExtractorScope.global, variableKey: 'refresh_token'),
      ExtractorEntity(path: 'region', scope: ExtractorScope.global, variableKey: 'region'),
    ], '{"refresh_token": "rt-1", "region": "eu"}');

    expect(await globalSecrets(), {'refresh_token': true, 'region': false});
  });

  test('a variable the user already has keeps its own flag, either way', () async {
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: environmentId, key: 'access_token', value: 'old', isSecret: false, enabled: true),
    );
    await repos.environmentRepository.upsertVariable(
      EnvironmentVariableEntity(id: 0, environmentId: environmentId, key: 'plainName', value: 'old', isSecret: true, enabled: true),
    );
    await repos.globalVariableRepository.upsert(GlobalVariableEntity(id: 0, key: 'token', value: 'old', isSecret: false, enabled: true));

    await extract([
      ExtractorEntity(path: 'a', variableKey: 'access_token'),
      ExtractorEntity(path: 'b', variableKey: 'plainName'),
      ExtractorEntity(path: 'c', scope: ExtractorScope.global, variableKey: 'token'),
    ], '{"a": "new-a", "b": "new-b", "c": "new-c"}');

    expect(await environmentSecrets(), {'access_token': false, 'plainName': true}, reason: "the user's choice is respected");
    expect(await globalSecrets(), {'token': false});
    expect((await repos.environmentRepository.getActiveVariables())['access_token'], 'new-a');
  });
}
