// Flow and pagination settings through every place a request's settings are kept or sent along: the database row,
// a backup file, the workspace file (and its secret splitter), and a Git document.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/git_sync/data/mappers/request_doc_mapper.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'flow_support.dart';

RequestSettings _settings() => RequestSettings(
      verifySsl: false,
      flow: FlowSettings(
        retry: const RetryPolicy(enabled: true, maxRetries: 4, backoff: BackoffKind.fixed, delayMs: 300, statuses: ['5xx', '409']),
        poll: PollPolicy(
          enabled: true,
          until: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done')],
          intervalMs: 500,
          maxAttempts: 9,
        ),
        runIf: RunIfPolicy(enabled: true, conditions: [
          RunCondition(kind: RunConditionKind.environmentIs, name: 'Staging'),
          RunCondition(kind: RunConditionKind.variableEquals, name: 'region', value: 'eu'),
        ]),
        alwaysRun: true,
        repeatUnsafe: true,
      ),
      pagination: const PaginationSettings(
        enabled: true,
        kind: PaginationKind.cursor,
        itemsPath: 'data.items',
        nextPath: 'meta.next',
        param: 'cursor',
        maxPages: 12,
        delayMs: 100,
      ),
    );

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int collectionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    collectionId = await repos.collectionRepository.createCollection('Jobs');
  });

  tearDown(() => db.close());

  group('the database row', () {
    test('saves and reads flow and pagination with the other settings, in the same row, without a schema change', () async {
      final id = await addRequest(repos, collectionId, 'Start job');

      await repos.requestSettingsRepository.save(id, _settings());

      expect(await repos.requestSettingsRepository.get(id), _settings());
      final stored = jsonDecode((await db.requestSettingsDao.get(id))!) as Map<String, dynamic>;
      expect(stored.keys, containsAll(['verifySsl', 'flow', 'pagination']));
    });

    test('a request with only flow settings still has a row, and one with none has none', () async {
      final id = await addRequest(repos, collectionId, 'A');
      final other = await addRequest(repos, collectionId, 'B');

      await repos.requestSettingsRepository.save(id, RequestSettings(flow: _settings().flow));
      await repos.requestSettingsRepository.save(other, RequestSettings.none);

      expect(await db.requestSettingsDao.get(id), isNotNull);
      expect(await db.requestSettingsDao.get(other), isNull);
    });

    test('copying a request copies its flow settings along', () async {
      final id = await addRequest(repos, collectionId, 'Original');
      await repos.requestSettingsRepository.save(id, _settings());

      final copy = await db.requestsDao.duplicateRequest(id);

      expect(await repos.requestSettingsRepository.get(copy), _settings());
    });

    test('deleting the request removes the row with its flow settings', () async {
      final id = await addRequest(repos, collectionId, 'Gone');
      await repos.requestSettingsRepository.save(id, _settings());

      await db.requestsDao.deleteRequest(id);

      expect(await db.requestSettingsDao.get(id), isNull);
    });
  });

  group('a backup file', () {
    test('writes the settings under `settings` and reads them back, as data and as text', () async {
      final id = await addRequest(repos, collectionId, 'Start job', method: HttpMethod.post);
      await repos.requestSettingsRepository.save(id, _settings());

      final text = (await repos.backupService.export()).text;
      final restored = BackupCodec.decode(text).collections.single.requests.single.settings;

      expect(restored, _settings());
      final request = ((jsonDecode(text) as Map)['collections'] as List).cast<Map>().single['requests'] as List;
      final settings = (request.single as Map)['settings'] as Map;
      expect((settings['flow'] as Map)['alwaysRun'], true);
      expect((settings['pagination'] as Map)['kind'], 'cursor');
    });

    test('a restore into another database puts every setting on the new request row', () async {
      final id = await addRequest(repos, collectionId, 'Start job');
      await repos.requestSettingsRepository.save(id, _settings());
      final backup = (await repos.backupService.export()).text;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = DriftRepos(other);
      // Different ids than in the source, so an un-remapped id would show.
      for (var i = 0; i < 4; i++) {
        await target.collectionRepository.createCollection('Noise $i');
      }

      await target.backupService.restore(backup);

      final jobs = (await target.collectionRepository.watchCollections().first).singleWhere((c) => c.name == 'Jobs');
      final request = (await target.requestRepository.watchByCollection(jobs.id).first).single;
      expect(await target.requestSettingsRepository.get(request.id), _settings());
    });

    test('a file written before flow settings existed still restores, with none', () async {
      final id = await addRequest(repos, collectionId, 'Plain');
      await repos.requestSettingsRepository.save(id, const RequestSettings(timeoutSeconds: 9));
      final text = (await repos.backupService.export()).text;

      final restored = BackupCodec.decode(text).collections.single.requests.single.settings!;

      expect(restored.timeoutSeconds, 9);
      expect(restored.flow, FlowSettings.none);
      expect(restored.pagination, PaginationSettings.none);
    });

    test('a request that has only a flow is carried, and one without settings gets no settings key', () async {
      final a = await addRequest(repos, collectionId, 'With');
      await addRequest(repos, collectionId, 'Without');
      await repos.requestSettingsRepository.save(a, RequestSettings(flow: _settings().flow));

      final requests = BackupCodec.decode((await repos.backupService.export()).text).collections.single.requests;

      expect(requests.singleWhere((r) => r.request.name == 'With').settings, RequestSettings(flow: _settings().flow));
      expect(requests.singleWhere((r) => r.request.name == 'Without').settings, isNull);
    });
  });

  group('the workspace file and its secret splitter', () {
    Map<String, dynamic> workspaceWith(RequestSettings settings) {
      final snapshot = BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [
          BackupCollection(
            name: 'Jobs',
            variables: const [],
            folders: const [],
            requests: [BackupRequest(request: flowRequest(), settings: settings)],
          ),
        ],
      );
      return jsonDecode(BackupCodec.encode(snapshot)) as Map<String, dynamic>;
    }

    Map<String, dynamic> flowOf(Map<String, dynamic> doc) =>
        (((doc['collections'] as List).first as Map)['requests'] as List).cast<Map>().first['settings']['flow'] as Map<String, dynamic>;

    final withSecrets = RequestSettings(
      flow: FlowSettings(
        poll: PollPolicy(enabled: true, until: [
          AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.access_token', expected: 'tok-1'),
          AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done'),
        ]),
        runIf: RunIfPolicy(enabled: true, conditions: [
          RunCondition(kind: RunConditionKind.variableEquals, name: 'api_key', value: 'k-12345'),
          RunCondition(kind: RunConditionKind.variableEquals, name: 'region', value: 'eu'),
        ]),
      ),
      pagination: const PaginationSettings(enabled: true, kind: PaginationKind.page, param: 'page', itemsPath: 'rows'),
    );

    test('the settings reach the workspace document and read back from it', () {
      final doc = workspaceWith(withSecrets);

      final back = BackupCodec.decode(jsonEncode(doc)).collections.single.requests.single.settings;

      expect(back, withSecrets);
    });

    test('what a poll condition or a run-if expects of a credential is split off, the rest stays shared', () {
      final split = SecretSplitter.split(workspaceWith(withSecrets));

      final flow = flowOf(split.publicDoc);
      final until = ((flow['poll'] as Map)['until'] as List).cast<Map>();
      expect(until[0]['expected'], '', reason: 'data.access_token is a credential');
      expect(until[1]['expected'], 'done');
      final all = ((flow['runIf'] as Map)['all'] as List).cast<Map>();
      expect(all[0]['value'], '', reason: 'api_key is a credential');
      expect(all[1]['value'], 'eu');
      expect(split.secrets.entries.where((e) => e.key.startsWith('rflow/')).map((e) => e.value), ['tok-1']);
      expect(split.secrets.entries.where((e) => e.key.startsWith('rrunif/')).map((e) => e.value), ['k-12345']);
      expect(jsonEncode(split.publicDoc), isNot(contains('tok-1')));
      expect(jsonEncode(split.publicDoc), isNot(contains('k-12345')));
    });

    test('merging the local secrets back gives the settings as they were', () {
      final original = workspaceWith(withSecrets);
      final split = SecretSplitter.split(original);

      final merged = SecretSplitter.merge(split.publicDoc, split.secrets);

      expect(BackupCodec.decode(jsonEncode(merged)).collections.single.requests.single.settings, withSecrets);
    });

    test('settings that hold nothing secret are not touched, and pagination is never a secret', () {
      final doc = workspaceWith(RequestSettings(flow: _settings().flow, pagination: _settings().pagination));

      final split = SecretSplitter.split(doc);

      expect(split.secrets, isEmpty);
      expect(jsonEncode(split.publicDoc), jsonEncode(doc));
    });

    test('a request whose settings key holds something unexpected does not break the split', () {
      final doc = workspaceWith(withSecrets);
      ((doc['collections'] as List).first['requests'] as List).first['settings']['flow'] = 'garbage';

      expect(() => SecretSplitter.split(doc), returnsNormally);
    });
  });

  group('a Git document', () {
    SyncDoc doc(Map<String, Object?> settings) => RequestDocMapper.canonical(SyncDoc(
          uid: 'r1',
          kind: SyncKind.request,
          parentUid: 'c1',
          name: 'Start job',
          data: {
            'method': 'get',
            'url': 'https://api.test/jobs',
            'headers': <Object?>[],
            'queryParams': <Object?>[],
            'body': {
              'type': 'none',
              'rawContentType': 'json',
              'rawText': '',
              'formFields': <Object?>[],
              'urlEncodedFields': <Object?>[],
              'graphqlQuery': '',
              'graphqlVariables': '{}',
            },
            'auth': {'type': 'inherit'},
            'settings': settings,
          },
        ));

    final plain = _settings().toJson();
    final secretive = RequestSettings(
      flow: FlowSettings(
        poll: PollPolicy(enabled: true, until: [
          AssertionEntity(type: AssertionType.headerEquals, path: 'Authorization', expected: 'Bearer abc'),
          AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done'),
        ]),
        runIf: RunIfPolicy(enabled: true, conditions: [
          RunCondition(kind: RunConditionKind.variableEquals, name: 'api_key', value: 'k-12345'),
        ]),
      ),
    ).toJson();

    test('carries flow and pagination in the doc exactly as the row holds them', () {
      final synced = doc(plain);

      expect(synced.data['settings'], plain);
      // What a pull writes back into the row reads as the same settings.
      expect(RequestSettings.decode(jsonEncode(synced.data['settings'])), _settings());
    });

    test('the doc is the same whoever wrote it: a second canonical pass changes nothing', () {
      final once = doc(plain);

      expect(RequestDocMapper.canonical(once), once);
    });

    test('a request without settings has no settings key in its doc', () {
      expect(doc(const {}).data.containsKey('settings'), isFalse);
    });

    test('without credentials in the doc, a poll condition and a run-if lose what they expect of one', () {
      final stripped = SecretFields.stripDoc(doc(secretive));

      final flow = (stripped.data['settings'] as Map)['flow'] as Map;
      final until = ((flow['poll'] as Map)['until'] as List).cast<Map>();
      expect(until[0]['expected'], '');
      expect(until[1]['expected'], 'done');
      expect((((flow['runIf'] as Map)['all'] as List).single as Map)['value'], '');
      expect(jsonEncode(stripped.data), isNot(contains('Bearer abc')));
      expect(jsonEncode(stripped.data), isNot(contains('k-12345')));
    });

    test('a pull of the stripped doc keeps the local credentials the remote file does not have', () {
      final full = doc(secretive);
      final stripped = SecretFields.stripDoc(full);

      final applied = RequestDocMapper.canonical(stripped, local: full);

      expect(applied, full);
    });

    test('a pull that changes a non-secret value of the flow takes it, and still keeps the local credentials', () {
      final full = doc(secretive);
      final remote = SecretFields.stripDoc(doc({
        ...secretive,
        'flow': {
          ...(secretive['flow']! as Map<String, dynamic>),
          'alwaysRun': true,
        },
      }));

      final applied = RequestDocMapper.canonical(remote, local: full);

      final flow = (applied.data['settings'] as Map)['flow'] as Map;
      expect(flow['alwaysRun'], true);
      expect((((flow['runIf'] as Map)['all'] as List).single as Map)['value'], 'k-12345');
      expect((((flow['poll'] as Map)['until'] as List).first as Map)['expected'], 'Bearer abc');
    });

    test('stripping is idempotent and leaves settings without credentials as they were', () {
      final harmless = doc(plain);

      // The settings are untouched (the rest of the doc loses its empty credential fields until it is read back).
      expect(SecretFields.stripDoc(harmless).data['settings'], harmless.data['settings']);
      expect(RequestDocMapper.canonical(SecretFields.stripDoc(harmless)), harmless);
      final once = SecretFields.stripDoc(doc(secretive));
      expect(SecretFields.stripDoc(once), once);
    });
  });
}
