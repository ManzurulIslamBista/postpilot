// Where a matrix run keeps its identities (the settings table of this device, one value per workplace, never part of
// the workspace data) and how a column with an identity gets a cookie jar of its own.
import 'package:cookie_jar/cookie_jar.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/network/strict_cookie_jar.dart';
import 'package:postpilot/features/matrix_run/data/cookie_session_isolation.dart';
import 'package:postpilot/features/matrix_run/data/settings_matrix_identity_store.dart';
import 'package:postpilot/features/matrix_run/domain/entities/matrix_identity.dart';

void main() {
  group('SettingsMatrixIdentityStore', () {
    late AppDatabase db;
    String? workplace = 'w1';

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      workplace = 'w1';
    });
    tearDown(() => db.close());

    SettingsMatrixIdentityStore store() => SettingsMatrixIdentityStore(db.settingsDao, () async => workplace);

    const admin = MatrixIdentity(id: 'a', name: 'admin', variables: {'token': 'tok-admin', 'apiKey': ''});
    const user = MatrixIdentity(id: 'u', name: 'user', variables: {'token': 'tok-user'});

    test('identities survive a save and a load, in order', () async {
      expect(await store().load(), isEmpty);
      await store().save([admin, user]);
      expect(await store().load(), [admin, user]);
    });

    test('each workplace has its own, and no workplace has the default key', () async {
      await store().save([admin]);
      workplace = 'w2';
      expect(await store().load(), isEmpty);
      await store().save([user]);
      workplace = null;
      expect(await store().load(), isEmpty);
      await store().save([admin, user]);

      workplace = 'w1';
      expect(await store().load(), [admin]);
      workplace = 'w2';
      expect(await store().load(), [user]);
      expect(await db.settingsDao.get('matrix.identities.w1'), isNotNull);
      expect(await db.settingsDao.get('matrix.identities.default'), isNotNull);
    });

    test('saving none removes the value', () async {
      await store().save([admin]);
      await store().save(const []);
      expect(await db.settingsDao.get('matrix.identities.w1'), isNull);
    });

    test('a damaged value is no identities, not a crash; a damaged item is dropped and the rest kept', () async {
      await db.settingsDao.put('matrix.identities.w1', '{not json');
      expect(await store().load(), isEmpty);
      await db.settingsDao.put('matrix.identities.w1', '"a string"');
      expect(await store().load(), isEmpty);
      await db.settingsDao.put('matrix.identities.w1', '{"v":1,"identities":[7,{"id":"a","name":"admin","variables":{"token":"x"}},{"name":"no id"}]}');
      expect((await store().load()).map((i) => i.name), ['admin']);
    });

    test('identities are device settings, not workspace data: saving one does not touch what workspace.json holds', () async {
      var changes = 0;
      final sub = db.workplaceDataChanges().listen((_) => changes++);
      await store().save([admin, user]);
      await store().load();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(changes, 0, reason: 'a change here would rewrite the workspace file and could carry a token into Git');
      // And clearing the workplace's data (switching workplace) leaves the settings table alone.
      await db.clearWorkplaceData();
      expect(await db.settingsDao.get('matrix.identities.w1'), isNotNull);
    });
  });

  group('CookieSessionIsolation', () {
    final dev = Uri.parse('https://dev.shop.test/api');
    final prod = Uri.parse('https://api.shop.test/api');

    Future<List<String>> names(CookieJar jar, Uri uri) async => [for (final c in await jar.loadForRequest(uri)) '${c.name}=${c.value}'];

    test('the column starts with no cookies, and what it sets does not outlive it', () async {
      final jar = StrictCookieJar();
      await jar.saveFromResponse(dev, [Cookie('session', 'mine')]);
      await jar.saveFromResponse(prod, [Cookie('session', 'prod-mine')]);

      final inside = await CookieSessionIsolation(jar).isolated(() async {
        expect(await names(jar, dev), isEmpty, reason: 'anonymous must not carry my session');
        expect(await names(jar, prod), isEmpty);
        await jar.saveFromResponse(dev, [Cookie('session', 'logged-in-as-user')]);
        return names(jar, dev);
      });

      expect(inside, ['session=logged-in-as-user']);
      expect(await names(jar, dev), ['session=mine']);
      expect(await names(jar, prod), ['session=prod-mine']);
    });

    test('the cookies come back when the column fails, and the failure is not swallowed', () async {
      final jar = StrictCookieJar();
      await jar.saveFromResponse(dev, [Cookie('session', 'mine')]);
      await expectLater(
        CookieSessionIsolation(jar).isolated<void>(() async {
          await jar.saveFromResponse(dev, [Cookie('other', 'x')]);
          throw StateError('the column broke');
        }),
        throwsStateError,
      );
      expect(await names(jar, dev), ['session=mine']);
    });

    test('two columns in a row do not see each other\'s session', () async {
      final jar = StrictCookieJar();
      final isolation = CookieSessionIsolation(jar);
      await isolation.isolated(() => jar.saveFromResponse(dev, [Cookie('session', 'admin')]));
      final second = await isolation.isolated(() => names(jar, dev));
      expect(second, isEmpty);
    });

    test('a jar that is not the app\'s own is left alone and the body still runs', () async {
      final jar = _OtherJar();
      expect(await CookieSessionIsolation(jar).isolated(() async => 42), 42);
    });
  });
}

final class _OtherJar implements CookieJar {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
