import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/database/daos/history_dao.dart';
import 'package:postpilot/features/history/data/repositories/history_repository_impl.dart';

void main() {
  late AppDatabase db;
  late HistoryRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HistoryRepositoryImpl(db.historyDao);
  });
  tearDown(() => db.close());

  Future<void> record(int n, {Map<String, String> headers = const {}}) => repository.record(
        method: 'GET',
        url: 'https://api.test/$n',
        statusCode: 200,
        durationMs: n,
        responseHeaders: headers,
      );

  test('response headers are accepted but not stored: they hold Set-Cookie and tokens nothing reads back', () async {
    await record(1, headers: {'set-cookie': 'session=abc123', 'x-auth-token': 'tok-secret'});

    final rows = await db.select(db.historyEntries).get();

    expect(rows.single.responseHeadersJson, '{}');
  });

  test('rows an older version wrote with their headers are emptied on the first record', () async {
    await db.historyDao.record(HistoryEntriesCompanion.insert(
      method: 'GET',
      url: 'https://api.test/old',
      responseHeadersJson: const Value('{"set-cookie":"session=abc123"}'),
    ));

    await record(1);

    final rows = await db.select(db.historyEntries).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.responseHeadersJson), everyElement('{}'));
  });

  test('the table is trimmed to the newest rows on every write, the newest kept', () async {
    const extra = 5;
    for (var n = 1; n <= HistoryDao.maxRows + extra; n++) {
      await record(n);
    }

    final rows = await db.select(db.historyEntries).get();

    expect(rows, hasLength(HistoryDao.maxRows));
    final urls = rows.map((r) => r.url).toSet();
    expect(urls, isNot(contains('https://api.test/1')));
    expect(urls, isNot(contains('https://api.test/$extra')));
    expect(urls, contains('https://api.test/${extra + 1}'));
    expect(urls, contains('https://api.test/${HistoryDao.maxRows + extra}'));
  });

  test('the list is newest first and shows 200 entries however many are kept', () async {
    for (var n = 1; n <= 205; n++) {
      await record(n);
    }

    final shown = await repository.watchRecent().first;

    expect(shown, hasLength(200));
    expect(shown.first.url, 'https://api.test/205');
    expect(shown.last.url, 'https://api.test/6');
  });

  test('clear empties it and recording carries on after', () async {
    await record(1);
    await repository.clear();
    await record(2);

    expect((await repository.watchRecent().first).map((e) => e.url), ['https://api.test/2']);
  });
}
