import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/settings/data/repositories/request_settings_repository_impl.dart';
import 'package:postpilot/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';

const _custom = AppSettings(
  themeMode: AppThemeMode.dark,
  requestTimeoutSeconds: 5,
  verifySsl: false,
  proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.local', port: 3128),
);

/// A database stream may repeat a value when an unrelated write touches its table.
List<T> _withoutRepeats<T>(List<T> events) => [
      for (var i = 0; i < events.length; i++)
        if (i == 0 || events[i] != events[i - 1]) events[i],
    ];

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('SettingsRepositoryImpl', () {
    late SettingsRepositoryImpl repository;

    setUp(() => repository = SettingsRepositoryImpl(db.settingsDao));

    test('holds the defaults until load has run', () {
      expect(repository.current, const AppSettings());
    });

    test('load reads the stored settings, and current is then synchronous', () async {
      await db.settingsDao.put(SettingsRepositoryImpl.storageKey, _custom.encode());

      await repository.load();

      expect(repository.current, _custom);
    });

    test('load with nothing stored keeps the defaults', () async {
      await repository.load();

      expect(repository.current, const AppSettings());
    });

    test('load survives corrupt, blank and non-object stored text', () async {
      for (final stored in ['{oops', '', '   ', '[1,2]', '"text"', '17']) {
        await db.settingsDao.put(SettingsRepositoryImpl.storageKey, stored);

        await repository.load();

        expect(repository.current, const AppSettings(), reason: stored);
      }
    });

    test('load keeps what is readable of a partly damaged document', () async {
      await db.settingsDao.put(
        SettingsRepositoryImpl.storageKey,
        '{"verifySsl": false, "requestTimeoutSeconds": "soon", "proxy": {"mode": "custom", "host": "p"}}',
      );

      await repository.load();

      expect(repository.current.verifySsl, isFalse);
      expect(repository.current.requestTimeoutSeconds, 30);
      expect(repository.current.proxy.mode, ProxyMode.custom);
      expect(repository.current.proxy.host, 'p');
    });

    test('save makes the settings current at once and stores one JSON value under app_settings', () async {
      final saving = repository.save(_custom);

      expect(repository.current, _custom, reason: 'the next send must already see it');
      await saving;

      expect(AppSettings.decode(await db.settingsDao.get('app_settings')), _custom);
      expect(await db.select(db.settingEntries).get(), hasLength(1));
    });

    test('saving again replaces the stored value rather than adding a row', () async {
      await repository.save(_custom);
      await repository.save(const AppSettings(followRedirects: false));

      expect(await db.select(db.settingEntries).get(), hasLength(1));
      expect(AppSettings.decode(await db.settingsDao.get('app_settings')), const AppSettings(followRedirects: false));
    });

    test('a new repository over the same database loads what the first saved', () async {
      await repository.save(_custom);

      final restarted = SettingsRepositoryImpl(db.settingsDao);
      await restarted.load();

      expect(restarted.current, _custom);
    });

    test('reset goes back to the defaults and forgets what was stored', () async {
      await repository.save(_custom);

      await repository.reset();

      expect(repository.current, const AppSettings());
      expect(await db.settingsDao.get('app_settings'), isNull);
    });

    test('watch starts with the current settings and then reports every change', () async {
      await repository.save(_custom);
      final seen = <AppSettings>[];
      final subscription = repository.watch().listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repository.save(const AppSettings(sendNoCacheHeader: true));
      await repository.reset();
      await pumpEventQueue();

      expect(seen, [_custom, const AppSettings(sendNoCacheHeader: true), const AppSettings()]);
    });

    test('load announces what it read to those already watching', () async {
      await db.settingsDao.put(SettingsRepositoryImpl.storageKey, _custom.encode());
      final seen = <AppSettings>[];
      final subscription = repository.watch().listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repository.load();
      await pumpEventQueue();

      expect(seen, [const AppSettings(), _custom]);
    });

    test('a watcher that cancelled hears nothing more', () async {
      final seen = <AppSettings>[];
      final subscription = repository.watch().listen(seen.add);
      await pumpEventQueue();
      await subscription.cancel();

      await repository.save(_custom);
      await pumpEventQueue();

      expect(seen, [const AppSettings()]);
    });

    test('several watchers each get every change', () async {
      final first = <AppSettings>[];
      final second = <AppSettings>[];
      final subscriptions = [repository.watch().listen(first.add), repository.watch().listen(second.add)];
      addTearDown(() => Future.wait(subscriptions.map((s) => s.cancel())));
      await pumpEventQueue();

      await repository.save(_custom);
      await pumpEventQueue();

      expect(first, [const AppSettings(), _custom]);
      expect(second, first);
    });
  });

  group('RequestSettingsRepositoryImpl', () {
    late RequestSettingsRepositoryImpl repository;
    late int requestId;

    setUp(() async {
      repository = RequestSettingsRepositoryImpl(db.requestSettingsDao);
      final collectionId = await db.collectionsDao.createCollection('c');
      requestId = await db.requestsDao.createRequest(RequestsCompanion.insert(collectionId: collectionId, name: 'r'));
    });

    test('a request with nothing stored has no overrides', () async {
      expect(await repository.get(requestId), RequestSettings.none);
      expect(await repository.get(9999), RequestSettings.none);
    });

    test('save and get round trip', () async {
      const settings = RequestSettings(followRedirects: false, timeoutSeconds: 0, sendNoCacheHeader: true);

      await repository.save(requestId, settings);

      expect(await repository.get(requestId), settings);
    });

    test('saving again replaces the overrides', () async {
      await repository.save(requestId, const RequestSettings(verifySsl: false));
      await repository.save(requestId, const RequestSettings(timeoutSeconds: 9));

      expect(await repository.get(requestId), const RequestSettings(timeoutSeconds: 9));
    });

    test('overrides that are all "use global" are not stored at all', () async {
      await repository.save(requestId, const RequestSettings(verifySsl: false));

      await repository.save(requestId, RequestSettings.none);

      expect(await db.requestSettingsDao.get(requestId), isNull);
      expect(await repository.get(requestId), RequestSettings.none);
    });

    test('each request keeps its own overrides', () async {
      final collectionId = await db.collectionsDao.createCollection('other');
      final other = await db.requestsDao.createRequest(RequestsCompanion.insert(collectionId: collectionId, name: 'o'));

      await repository.save(requestId, const RequestSettings(verifySsl: false));
      await repository.save(other, const RequestSettings(followRedirects: false));

      expect(await repository.get(requestId), const RequestSettings(verifySsl: false));
      expect(await repository.get(other), const RequestSettings(followRedirects: false));
    });

    test('unreadable stored text reads as no overrides', () async {
      for (final stored in ['{oops', '', '[]', '"x"']) {
        await db.requestSettingsDao.put(requestId, stored);

        expect(await repository.get(requestId), RequestSettings.none, reason: stored);
      }
    });

    test('delete forgets the overrides', () async {
      await repository.save(requestId, const RequestSettings(verifySsl: false));

      await repository.delete(requestId);

      expect(await repository.get(requestId), RequestSettings.none);
    });

    test('deleting the request deletes its overrides too', () async {
      await repository.save(requestId, const RequestSettings(verifySsl: false));

      await db.requestsDao.deleteRequest(requestId);

      expect(await db.requestSettingsDao.get(requestId), isNull);
    });

    test('watch starts with the stored overrides and follows each change', () async {
      await repository.save(requestId, const RequestSettings(verifySsl: false));
      final seen = <RequestSettings>[];
      final subscription = repository.watch(requestId).listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repository.save(requestId, const RequestSettings(timeoutSeconds: 3));
      await pumpEventQueue();
      await repository.delete(requestId);
      await pumpEventQueue();

      expect(_withoutRepeats(seen), [
        const RequestSettings(verifySsl: false),
        const RequestSettings(timeoutSeconds: 3),
        RequestSettings.none,
      ]);
    });
  });
}
