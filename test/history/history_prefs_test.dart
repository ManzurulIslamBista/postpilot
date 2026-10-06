// Settings > History: the values, their limits and that they survive a restart.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/history/domain/services/history_policy.dart';
import 'package:postpilot/features/settings/data/history_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the defaults: bodies kept, 1000 entries, no age limit, 256 KB per body', () async {
    final limits = await HistoryPrefs().limits();

    expect(limits.keepBodies, isTrue);
    expect(limits.maxEntries, 1000);
    expect(limits.retentionDays, isNull);
    expect(limits.maxBodyBytes, 256 * 1024);
  });

  test('what is set is what the next send uses, and it is still there after a restart', () async {
    final prefs = HistoryPrefs();
    await prefs.setKeepBodies(false);
    await prefs.setMaxEntries(250);
    await prefs.setRetentionDays(30);
    await prefs.setMaxBodyKb(64);

    final limits = await prefs.limits();
    expect((limits.keepBodies, limits.maxEntries, limits.retentionDays, limits.maxBodyBytes), (false, 250, 30, 64 * 1024));

    final afterRestart = await HistoryPrefs().limits();
    expect(afterRestart, limits);
  });

  test('values outside the range are brought into it, and 0 days means no age limit', () async {
    final prefs = HistoryPrefs();

    await prefs.setMaxEntries(1);
    expect(prefs.maxEntries, HistoryLimits.minMaxEntries);
    await prefs.setMaxEntries(1000000);
    expect(prefs.maxEntries, HistoryLimits.maxMaxEntries);
    await prefs.setMaxBodyKb(0);
    expect(prefs.maxBodyKb, HistoryLimits.minMaxBodyBytes ~/ 1024);
    await prefs.setMaxBodyKb(1 << 30);
    expect(prefs.maxBodyKb, HistoryLimits.maxMaxBodyBytes ~/ 1024);
    await prefs.setRetentionDays(-5);
    expect(prefs.retentionDays, 0);
    expect((await prefs.limits()).retentionDays, isNull);
    await prefs.setRetentionDays(100000);
    expect(prefs.retentionDays, HistoryPrefs.maxRetentionDays);
  });

  test('stored values that are out of range are clamped when read', () async {
    SharedPreferences.setMockInitialValues({'history.maxEntries': 3, 'history.retentionDays': -2, 'history.maxBodyKb': 99999999});

    final limits = await HistoryPrefs().limits();

    expect(limits.maxEntries, HistoryLimits.minMaxEntries);
    expect(limits.retentionDays, isNull);
    expect(limits.maxBodyBytes, HistoryLimits.maxMaxBodyBytes);
  });

  test('a listener hears about a change', () async {
    final prefs = HistoryPrefs();
    var heard = 0;
    prefs.addListener(() => heard++);
    await prefs.load();
    final afterLoad = heard;

    await prefs.setKeepBodies(false);

    expect(heard, greaterThan(afterLoad));
    expect(prefs.keepBodies, isFalse);
  });
}
