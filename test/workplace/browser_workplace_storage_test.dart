import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/browser_workplace_storage.dart';
import 'package:postpilot/features/workplace/domain/entities/storage_usage.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The web build's storage. It only uses shared_preferences (which is
/// localStorage in a browser), so it runs here with the plugin's in-memory fake.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reports no file-system abilities', () {
    final storage = BrowserWorkplaceStorage();

    expect(storage.usesRealFolders, isFalse);
    expect(storage.canPickFolder, isFalse);
    expect(storage.canRevealFolder, isFalse);
  });

  test('round-trips the registry and each workplace file under its own key', () async {
    final storage = BrowserWorkplaceStorage();

    expect(await storage.readRegistry(), isNull);
    await storage.writeRegistry('{"workplaces":[]}');
    await storage.writeWorkspace('Team/A', 'first');
    await storage.writeWorkspace('Team/B', 'second');

    expect(await storage.readRegistry(), '{"workplaces":[]}');
    expect(await storage.readWorkspace('Team/A'), 'first');
    expect(await storage.readWorkspace('Team/B'), 'second');
    expect(await storage.readWorkspace('Team/C'), isNull);
  });

  test('treats folder names case-insensitively, like the desktop file systems', () async {
    final storage = BrowserWorkplaceStorage();

    await storage.writeWorkspace('Team/A', 'content');

    expect(await storage.readWorkspace('team/a'), 'content');
  });

  test('refuses a workspace too large for browser storage instead of dropping it', () async {
    final storage = BrowserWorkplaceStorage();

    await expectLater(
      storage.writeWorkspace('big', 'x' * (5 * 1024 * 1024)),
      throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('too large'))),
    );
    expect(await storage.readWorkspace('big'), isNull);
  });

  test('counts what the browser stores: every quote of a JSON file takes two characters', () async {
    final storage = BrowserWorkplaceStorage();
    // 3 million quotes are 3 MB as text but 6 MB once stored.
    await expectLater(
      storage.writeWorkspace('quotes', '"' * (3 * 1000 * 1000)),
      throwsA(isA<WorkplaceException>().having((e) => e.message, 'message', contains('too large'))),
    );
    await storage.writeWorkspace('quotes', '"' * 1000);
    expect((await storage.workspaceUsage('quotes'))!.usedBytes, 2002);
  });

  group('how full the storage is', () {
    test('a workspace file is measured against the 4 MB cap, and nothing is reported for one that is not there', () async {
      final storage = BrowserWorkplaceStorage();

      expect(await storage.workspaceUsage('none'), isNull);
      await storage.writeWorkspace('mine', 'x' * 1000);

      final usage = (await storage.workspaceUsage('MINE'))!;
      expect(usage.usedBytes, 1002, reason: 'the browser stores the JSON-encoded text, with its two quotes');
      expect(usage.limitBytes, 4 * 1024 * 1024);
      expect(usage.isNearLimit, isFalse);
    });

    test('3 MB and more is close to the cap, and the label reads like the sentence the sidebar shows', () async {
      final storage = BrowserWorkplaceStorage();
      // Stored with its two quotes, so this is exactly 3 MB.
      await storage.writeWorkspace('mine', 'x' * (3 * 1024 * 1024 - 2));

      final usage = (await storage.workspaceUsage('mine'))!;
      expect(usage.isNearLimit, isTrue);
      expect(usage.label, '3 MB of 4 MB');
    });

    test('the label shows one decimal below 10 MB and a whole number from there', () {
      // 3565158 bytes = 3.4 MB (3565158 / 1048576 = 3.4000...), the example in the task description.
      expect(const StorageUsage(usedBytes: 3565158, limitBytes: 4 * 1024 * 1024).label, '3.4 MB of 4 MB');
      expect(const StorageUsage(usedBytes: 12 * 1024 * 1024, limitBytes: 16 * 1024 * 1024).label, '12 MB of 16 MB');
    });

    test('the warning starts at three quarters of the cap, not before', () {
      const limit = 4 * 1024 * 1024;
      expect(const StorageUsage(usedBytes: limit * 3 ~/ 4 - 1, limitBytes: limit).isNearLimit, isFalse);
      expect(const StorageUsage(usedBytes: limit * 3 ~/ 4, limitBytes: limit).isNearLimit, isTrue);
    });

    test('the repository reports it for the browser storage', () async {
      final repository = WorkplaceRepositoryImpl(storage: BrowserWorkplaceStorage());
      final workplace = await repository.createWorkplace(name: 'Big', folderPath: 'PostPilot/Big');

      final usage = await repository.storageUsage(workplace);
      expect(usage, isNotNull);
      expect(usage!.limitBytes, BrowserWorkplaceStorage.maxWorkspaceBytes);
    });
  });

  test('only needs a non-blank name where desktop needs a real path', () {
    final storage = BrowserWorkplaceStorage();

    expect(storage.validateFolderPath('  '), isNotNull);
    expect(storage.validateFolderPath('PostPilot/Workplaces/Mine'), isNull);
  });

  test('a full workplace lifecycle works on top of it (what the web build does)', () async {
    final repository = WorkplaceRepositoryImpl(storage: BrowserWorkplaceStorage());

    final first = (await repository.getWorkplaces()).single;
    final created = await repository.createWorkplace(name: 'Shop', folderPath: 'PostPilot/Workplaces/Shop');

    expect((await repository.getActiveWorkplace())?.id, created.id);
    expect((await repository.loadWorkplaceContent(created)).workplace.name, 'Shop');
    expect((await repository.getWorkplaces()).map((w) => w.id), [first.id, created.id]);
    await expectLater(
      repository.createWorkplace(name: 'Again', folderPath: 'postpilot/workplaces/shop'),
      throwsA(isA<WorkplaceException>()),
    );
  });
}
