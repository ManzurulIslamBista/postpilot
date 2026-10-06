// Which collections the monitor watches is remembered in the settings table, per device.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/run_triage/data/settings_monitor_config_store.dart';
import 'package:postpilot/features/run_triage/domain/entities/monitor_config.dart';

void main() {
  late AppDatabase db;
  late SettingsMonitorConfigStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = SettingsMonitorConfigStore(db.settingsDao);
  });
  tearDown(() => db.close());

  test('nothing saved means no monitors', () async {
    expect(await store.load(), isEmpty);
  });

  test('the choices survive a save and a load, per collection', () async {
    const configs = {
      3: MonitorConfig(enabled: true, everyMinutes: 5),
      9: MonitorConfig(enabled: true, everyMinutes: 1440, environment: 'Staging'),
    };
    await store.save(configs);
    expect(await store.load(), configs);
  });

  test('saving replaces what was there, and an empty save forgets everything', () async {
    await store.save({1: const MonitorConfig(enabled: true)});
    await store.save({2: const MonitorConfig(enabled: true, everyMinutes: 7)});
    expect((await store.load()).keys, [2]);
    await store.save(const {});
    expect(await store.load(), isEmpty);
  });

  test('it is one row in the settings table, under its own key', () async {
    await store.save({1: const MonitorConfig(enabled: true)});
    expect(await db.settingsDao.get('monitor.configs'), isNotNull);
    expect(await db.settingsDao.get('app_settings'), isNull, reason: 'the app settings are untouched');
  });

  test('a damaged value is no monitors, not a crash', () async {
    for (final broken in ['not json', '[1,2]', '{"1": 5}', '{"x": {"enabled": true}}', '']) {
      await db.settingsDao.put('monitor.configs', broken);
      expect(await store.load(), isEmpty, reason: broken);
    }
  });

  test('an entry with bad fields takes defaults, the others are kept', () async {
    await db.settingsDao.put('monitor.configs', '{"1": {"enabled": true, "every": "soon"}, "2": {"enabled": true, "every": 20}}');
    final loaded = await store.load();
    expect(loaded[1], const MonitorConfig(enabled: true));
    expect(loaded[2], const MonitorConfig(enabled: true, everyMinutes: 20));
  });
}
