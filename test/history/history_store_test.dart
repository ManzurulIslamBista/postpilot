// History on a real (in-memory SQLite) database: what is written with each send, that no secret reaches any
// column, search, retention and the way a pruned entry takes its payload along.
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/history/data/repositories/history_repository_impl.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_store.dart';
import 'package:postpilot/features/history/domain/services/history_policy.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

const _mask = '••••••';

final class _Policy implements HistoryPolicy {
  HistoryLimits value = const HistoryLimits();
  Object? failWith;

  @override
  Future<HistoryLimits> limits() async {
    final failure = failWith;
    if (failure != null) throw failure;
    return value;
  }
}

final class _Context implements HistoryContextSource {
  bool fail = false;

  @override
  Future<HistoryContext> of(ApiRequestEntity request) async {
    if (fail) throw StateError('collections are not readable');
    return const HistoryContext(collectionName: 'Shop', environmentName: 'Staging', flaggedSecretKeys: {'customerNo'});
  }
}

ApiRequestEntity _request({
  int id = 7,
  String name = 'Create user',
  HttpMethod method = HttpMethod.post,
  String url = 'https://api.test/users',
  List<KeyValueItem> headers = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(type: AuthType.none),
}) =>
    ApiRequestEntity(
      id: id,
      collectionId: 3,
      folderId: null,
      name: name,
      method: method,
      url: url,
      headers: headers,
      queryParams: const [],
      body: body,
      auth: auth,
    );

HistoryCapture _capture(
  ApiRequestEntity request, {
  String? body,
  List<int>? bytes,
  String contentType = 'application/json',
  String statusMessage = 'OK',
  VariableResolver? resolver,
  String? error,
}) =>
    HistoryCapture(
      request: request,
      responseBytes: bytes ?? (body == null ? const [] : utf8.encode(body)),
      responseContentType: error == null ? contentType : null,
      statusMessage: error == null ? statusMessage : '',
      error: error,
      resolver: resolver,
    );

void main() {
  late AppDatabase db;
  late _Policy policy;
  late _Context context;
  late HistoryRepositoryImpl store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    policy = _Policy();
    context = _Context();
    store = HistoryRepositoryImpl(db.historyDao, policy: policy, context: context);
  });
  tearDown(() => db.close());

  Future<void> send(
    ApiRequestEntity request, {
    int? status = 200,
    String? body,
    List<int>? bytes,
    String contentType = 'application/json',
    String? url,
    VariableResolver? resolver,
    String? error,
  }) =>
      store.recordCapture(
        method: request.method.label,
        url: url ?? request.url,
        statusCode: status,
        durationMs: 25,
        capture: _capture(request, body: body, bytes: bytes, contentType: contentType, resolver: resolver, error: error),
      );

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

  /// Every column of every row of both tables, as text.
  Future<String> everythingStored() async {
    final out = StringBuffer();
    for (final table in ['history_entries', 'history_payloads']) {
      for (final row in await db.customSelect('SELECT * FROM $table').get()) {
        for (final value in row.data.values) {
          out.writeln(value is Uint8List ? utf8.decode(value, allowMalformed: true) : '$value');
        }
      }
    }
    return out.toString();
  }

  group('what a send leaves behind', () {
    test('an entry with the request as saved and the response text, found again by detailOf', () async {
      final request = _request(
        url: '{{baseUrl}}/users',
        headers: [KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}'), KeyValueItem(key: 'Accept', value: 'application/json')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"name":"{{name}}"}'),
      );

      await send(request, status: 201, body: '{"id":1}');

      final entries = await store.watchAll().first;
      final entry = entries.single;
      expect((entry.method, entry.url, entry.statusCode, entry.durationMs), ('POST', '{{baseUrl}}/users', 201, 25));
      final meta = entry.meta!;
      expect(meta.requestId, 7);
      expect(meta.requestName, 'Create user');
      expect(meta.collectionId, 3);
      expect(meta.collectionName, 'Shop');
      expect(meta.environmentName, 'Staging');
      expect(meta.responseBytes, 8);
      expect(meta.statusMessage, 'OK');
      expect(meta.hasResponseBody, isTrue);
      expect(meta.responseTruncated, isFalse);
      expect(entry.hasDetails, isTrue);

      final detail = (await store.detailOf(entry.id))!;
      expect(detail.request.url, '{{baseUrl}}/users');
      expect({for (final h in detail.request.headers) h.key: h.value}, {'Authorization': 'Bearer {{token}}', 'Accept': 'application/json'});
      expect(detail.request.body.rawText, '{"name":"{{name}}"}');
      expect(detail.responseText, '{"id":1}');
      expect(detail.responseContentType, 'application/json');
      expect(detail.responseTruncated, isFalse);
      expect((await db.select(db.historyEntries).getSingle()).requestId, 7);
    });

    test('the summary-only record() still works and its entry has no details', () async {
      await store.record(method: 'GET', url: 'https://api.test/old', statusCode: 200, durationMs: 3, responseHeaders: const {'set-cookie': 'a=b'});

      final entry = (await store.watchAll().first).single;

      expect(entry.meta, isNull);
      expect(entry.hasDetails, isFalse);
      expect(await store.detailOf(entry.id), isNull);
      expect((await db.select(db.historyEntries).getSingle()).responseHeadersJson, '{}');
    });

    test('a send that got no response is an entry without a status and with its reason', () async {
      await send(
        _request(url: 'https://api.test/x'),
        status: null,
        error: 'Could not reach https://api.test/x?key=sk_live_ABCDEFGHIJKLMNOP',
      );

      final entry = (await store.watchAll().first).single;

      expect(entry.statusCode, isNull);
      expect(entry.isFailure, isTrue);
      expect(entry.meta!.error, 'Could not reach https://api.test/x?key=$_mask');
      expect(entry.meta!.responseBytes, isNull);
      expect(await everythingStored(), isNot(contains('sk_live_ABCDEFGHIJKLMNOP')));
    });

    test('names around the request are optional: a context that cannot be read does not stop the details', () async {
      context.fail = true;

      await send(_request(), body: '{}');

      final meta = (await store.watchAll().first).single.meta!;
      expect(meta.collectionName, isNull);
      expect(meta.requestName, 'Create user');
    });

    test('limits that cannot be read fall back to the defaults instead of losing the entry', () async {
      policy.failWith = StateError('prefs are gone');

      await send(_request(), body: '{"a":1}');

      expect(await count('history_entries'), 1);
      expect(await count('history_payloads'), 1);
    });
  });

  group('no secret reaches any column', () {
    test('literal credentials, resolved variables and echoed secrets are all gone; templates stay', () async {
      final request = _request(
        url: 'https://alice:hunter2pass@{{host}}/users?api_key=abc123secretvalue',
        headers: [
          KeyValueItem(key: 'Authorization', value: 'Bearer sk_live_AAAAAAAAAAAAAAAA'),
          KeyValueItem(key: 'X-Customer-Ref', value: '{{customerNo}}'),
          KeyValueItem(key: 'X-Echo', value: '{{apiToken}}'),
          // A secret place holding a variable with an innocent name.
          KeyValueItem(key: 'X-Session-Id', value: '{{refCode}}'),
        ],
        body: const RequestBody(type: BodyType.raw, rawText: '{"user":"ann","password":"p4ssw0rd-body","note":"{{host}}"}'),
        auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: 'basicPw-literal-777'),
      );
      const resolver = VariableResolver.layered([
        {
          'host': 'api.test',
          'customerNo': 'CUST-9981-XYZ',
          'apiToken': 'tok_resolved_secret_55',
          'refCode': 'REF-RESOLVED-42',
        },
      ]);
      const response = '{"customer":"CUST-9981-XYZ","seen":"tok_resolved_secret_55","ref":"REF-RESOLVED-42",'
          '"password":"resp-pw-1","note":"ok"}';

      await send(request, url: request.url, body: response, resolver: resolver);

      final stored = await everythingStored();
      for (final secret in [
        'hunter2pass',
        'abc123secretvalue',
        'sk_live_AAAAAAAAAAAAAAAA',
        'CUST-9981-XYZ',
        'tok_resolved_secret_55',
        'REF-RESOLVED-42',
        'basicPw-literal-777',
        'p4ssw0rd-body',
        'resp-pw-1',
      ]) {
        expect(stored, isNot(contains(secret)), reason: secret);
      }
      // The templates are what lets the request be sent again later.
      for (final template in ['{{host}}', '{{customerNo}}', '{{apiToken}}', '{{refCode}}']) {
        expect(stored, contains(template), reason: template);
      }
      final entry = await db.select(db.historyEntries).getSingle();
      expect(entry.url, 'https://alice:$_mask@{{host}}/users?api_key=$_mask');
      final detail = (await store.detailOf(entry.id))!;
      expect(detail.responseText, '{"customer":"$_mask","seen":"$_mask","ref":"$_mask","password":"$_mask","note":"ok"}');
      expect(detail.request.body.rawText, '{"user":"ann","password":"$_mask","note":"{{host}}"}');
      expect(detail.request.auth.basicPassword, _mask);
      expect(detail.request.auth.basicUsername, 'ann');
    });

    test('a collection\'s own credentials, echoed by a server, are hidden too', () async {
      store = HistoryRepositoryImpl(
        db.historyDao,
        policy: policy,
        context: _CollectionAuthContext(),
      );

      await send(_request(), body: '{"auth":"Bearer coll-secret-token-9"}');

      expect(await everythingStored(), isNot(contains('coll-secret-token-9')));
    });

    test('the search text is built from what is masked, so a hidden secret cannot be found', () async {
      final request = _request(body: const RequestBody(type: BodyType.raw, rawText: '{"password":"findme-secret-1"}'));

      await send(request, body: '{"token":"findme-secret-2"}');

      expect(await store.searchStored('findme-secret'), isEmpty);
    });
  });

  group('the response kept', () {
    test('is cut at the limit and flagged, and a secret that straddles the cut is not stored in part', () async {
      policy.value = const HistoryLimits(maxBodyBytes: 1000);
      final body = '{"pad":"${'p' * 970}","password":"${'Z' * 100}"}';

      await send(_request(), body: body);

      final entry = (await store.watchAll().first).single;
      final detail = (await store.detailOf(entry.id))!;
      expect(utf8.encode(detail.responseText!).length, lessThanOrEqualTo(1000));
      expect(detail.responseText, isNot(contains('ZZ')), reason: 'the value is masked before the cut, not cut and then left half there');
      expect(detail.responseTruncated, isTrue);
      expect(entry.meta!.responseTruncated, isTrue);
      expect(entry.meta!.responseBytes, utf8.encode(body).length, reason: 'the size is of what arrived, not of what is kept');
    });

    test('plain text over the limit is kept up to the limit', () async {
      policy.value = const HistoryLimits(maxBodyBytes: 1000);

      await send(_request(), body: 'x' * 5000, contentType: 'text/plain');

      final detail = (await store.detailOf((await store.watchAll().first).single.id))!;
      expect(detail.responseText, 'x' * 1000);
      expect(detail.responseTruncated, isTrue);
    });

    test('a body the client already cut at its size limit is flagged even when it fits', () async {
      await store.recordCapture(
        method: 'GET',
        url: 'https://api.test/big',
        statusCode: 200,
        durationMs: 9,
        capture: HistoryCapture(request: _request(), responseBytes: utf8.encode('{"a":'), responseContentType: 'application/json', responseTruncated: true),
      );

      final detail = (await store.detailOf((await store.watchAll().first).single.id))!;
      expect(detail.responseTruncated, isTrue);
    });

    test('only text is kept: an image or a file is recorded by its size alone', () async {
      await send(_request(url: 'https://api.test/logo'), bytes: [137, 80, 78, 71, 13, 10, 26, 10], contentType: 'image/png');
      await send(_request(url: 'https://api.test/file'), bytes: utf8.encode('looks like text'), contentType: 'application/octet-stream');
      await send(_request(url: 'https://api.test/nul'), bytes: [65, 0, 66], contentType: '');
      await send(_request(url: 'https://api.test/empty'), bytes: const []);

      for (final entry in await store.watchAll().first) {
        final detail = (await store.detailOf(entry.id))!;
        expect(detail.responseText, isNull, reason: entry.url);
        expect(entry.meta!.hasResponseBody, isFalse, reason: entry.url);
      }
      expect((await store.watchAll().first).map((e) => e.meta!.responseBytes), [0, 3, 15, 8]);
    });

    test('the text types are all kept: html, xml, form posts, csv and +json', () async {
      for (final type in ['text/html; charset=utf-8', 'application/xml', 'application/x-www-form-urlencoded', 'text/csv', 'application/vnd.api+json']) {
        await send(_request(url: 'https://api.test/$type'), body: 'a=1', contentType: type);
      }

      for (final entry in await store.watchAll().first) {
        expect((await store.detailOf(entry.id))!.responseText, 'a=1', reason: entry.url);
      }
    });

    test('with "keep bodies" off nothing but the summary is written, and no payload row exists', () async {
      policy.value = const HistoryLimits(keepBodies: false);

      await send(_request(), body: '{"a":1}');

      expect(await count('history_entries'), 1);
      expect(await count('history_payloads'), 0);
      final entry = (await store.watchAll().first).single;
      expect(entry.hasDetails, isFalse);
      expect(entry.url, 'https://api.test/users');
    });
  });

  group('search', () {
    setUp(() async {
      await send(
        _request(id: 1, name: 'List users', method: HttpMethod.get, url: 'https://api.test/users'),
        body: '{"city":"Lisbon"}',
      );
      await send(
        _request(id: 2, name: 'Place order', url: 'https://api.test/orders'),
        status: 500,
        body: 'Payment gateway timeout',
        contentType: 'text/plain',
      );
      await send(
        _request(id: 3, name: 'Sale', method: HttpMethod.get, url: 'https://api.test/50%_off'),
        body: '{}',
      );
    });

    Future<List<String>> urlsFor(String query) async {
      final ids = await store.searchStored(query);
      return [for (final e in await store.watchAll().first) if (ids.contains(e.id)) e.url]..sort();
    }

    test('finds a word inside a response body, a request name, a status and the collection, whatever the case', () async {
      expect(await urlsFor('lisbon'), ['https://api.test/users']);
      expect(await urlsFor('LISBON'), ['https://api.test/users']);
      expect(await urlsFor('gateway'), ['https://api.test/orders']);
      expect(await urlsFor('place order'), ['https://api.test/orders']);
      expect(await urlsFor('500'), ['https://api.test/orders']);
      expect(await urlsFor('staging'), hasLength(3));
      expect(await urlsFor('shop'), hasLength(3));
    });

    test('% and _ in the query are characters, not wildcards', () async {
      expect(await urlsFor('50%_off'), ['https://api.test/50%_off']);
      expect(await urlsFor('50%'), ['https://api.test/50%_off']);
      expect(await urlsFor('us_rs'), isEmpty, reason: '_ must not stand for any character');
      expect(await urlsFor('%'), ['https://api.test/50%_off']);
    });

    test('nothing found, and nothing asked, are empty', () async {
      expect(await store.searchStored('zzzzzz'), isEmpty);
      expect(await store.searchStored('   '), isEmpty);
    });
  });

  group('retention', () {
    test('only the newest entries are kept and every pruned entry takes its payload along', () async {
      policy.value = const HistoryLimits(maxEntries: 5);

      for (var i = 1; i <= 8; i++) {
        await send(_request(url: 'https://api.test/$i'), body: '{"n":$i}');
      }

      final urls = (await store.watchAll().first).map((e) => e.url).toList();
      expect(urls, ['https://api.test/8', 'https://api.test/7', 'https://api.test/6', 'https://api.test/5', 'https://api.test/4']);
      expect(await count('history_entries'), 5);
      expect(await count('history_payloads'), 5);
      final orphans = await db.customSelect('SELECT COUNT(*) AS n FROM history_payloads WHERE history_id NOT IN (SELECT id FROM history_entries)').getSingle();
      expect(orphans.read<int>('n'), 0);
      expect(await everythingStored(), isNot(contains('"n":1')));
    });

    test('lowering the limit takes effect at once through applyRetention', () async {
      for (var i = 1; i <= 6; i++) {
        await send(_request(url: 'https://api.test/$i'), body: '{}');
      }
      expect(await count('history_entries'), 6);

      policy.value = const HistoryLimits(maxEntries: 3);
      await store.applyRetention();

      expect((await store.watchAll().first).map((e) => e.url), ['https://api.test/6', 'https://api.test/5', 'https://api.test/4']);
      expect(await count('history_payloads'), 3);
    });

    test('with a retention in days older entries go too, payload included', () async {
      final oldId = await db.historyDao.record(HistoryEntriesCompanion.insert(
        method: 'GET',
        url: 'https://api.test/ancient',
        sentAt: Value(DateTime.now().subtract(const Duration(days: 10))),
      ));
      await db.historyPayloadsDao.upsert(HistoryPayloadsCompanion.insert(historyId: Value(oldId), requestJson: const Value('{}')));
      await db.historyDao.record(HistoryEntriesCompanion.insert(
        method: 'GET',
        url: 'https://api.test/recent',
        sentAt: Value(DateTime.now().subtract(const Duration(days: 2))),
      ));
      policy.value = const HistoryLimits(retentionDays: 7);

      await send(_request(url: 'https://api.test/new'), body: '{}');

      final urls = (await store.watchAll().first).map((e) => e.url).toSet();
      expect(urls, {'https://api.test/new', 'https://api.test/recent'});
      expect(await count('history_payloads'), 1, reason: 'the old payload went with its entry');
    });

    test('clear empties both tables and recording goes on after', () async {
      await send(_request(), body: '{}');
      await send(_request(), body: '{}');

      await store.clear();

      expect(await count('history_entries'), 0);
      expect(await count('history_payloads'), 0);
      await send(_request(url: 'https://api.test/after'), body: '{}');
      expect((await store.watchAll().first).map((e) => e.url), ['https://api.test/after']);
    });
  });

  group('the list', () {
    test('is newest first and carries what the rows show', () async {
      await send(_request(url: 'https://api.test/1'), status: 200, body: '{"a":1}');
      await store.record(method: 'GET', url: 'https://api.test/legacy', statusCode: 404, durationMs: 1, responseHeaders: const {});
      await send(_request(url: 'https://api.test/3'), status: 500, body: 'oops', contentType: 'text/plain');

      final entries = await store.watchAll().first;

      expect(entries.map((e) => e.url), ['https://api.test/3', 'https://api.test/legacy', 'https://api.test/1']);
      expect(entries.map((e) => e.statusCode), [500, 404, 200]);
      expect(entries.map((e) => e.meta?.responseBytes), [4, null, 7]);
      expect(entries.map((e) => e.hasDetails), [true, false, true]);
      expect(entries.map((e) => e.statusClass), [HistoryStatusClass.serverError, HistoryStatusClass.clientError, HistoryStatusClass.success]);
    });
  });
}

final class _CollectionAuthContext implements HistoryContextSource {
  @override
  Future<HistoryContext> of(ApiRequestEntity request) async =>
      const HistoryContext(collectionName: 'Shop', secretValues: ['Bearer coll-secret-token-9', 'coll-secret-token-9']);
}
