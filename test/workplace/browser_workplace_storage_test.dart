import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/workplace/data/repositories/workplace_repository_impl.dart';
import 'package:postpilot/features/workplace/data/storage/browser_workplace_storage.dart';
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
