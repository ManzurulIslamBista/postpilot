// The doors into the features: the shell's top bar and the collections sidebar,
// built by the real PostPilotApp so app.dart's providers are what the widgets
// and dialogs actually read.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/app.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/layout/layout_prefs.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';
import 'package:postpilot/core/usecases/usecase.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/console/presentation/view_models/request_console_log.dart';
import 'package:postpilot/features/console/presentation/widgets/console_dialog.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/all_tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/entity_docs_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/widgets/entity_description_dialog.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_link_repository.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_discover_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_save_token_usecase.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/git_clone_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/view_models/linked_collections_view_model.dart';
import 'package:postpilot/features/git_sync/presentation/widgets/git_clone_dialog.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/history/presentation/view_models/history_view_model.dart';
import 'package:postpilot/features/import_export/domain/entities/backup_export.dart';
import 'package:postpilot/features/import_export/domain/entities/import_summary.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_any_usecase.dart';
import 'package:postpilot/features/import_export/presentation/backup_dialog.dart';
import 'package:postpilot/features/import_export/presentation/import_any_dialog.dart';
import 'package:postpilot/features/import_export/presentation/view_models/backup_view_model.dart';
import 'package:postpilot/features/import_export/presentation/view_models/import_any_view_model.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/settings_dialog.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';

import 'documentation/support/fakes.dart';
import 'git_sync/fakes/fake_credentials_store.dart';
import 'settings/fakes/fake_settings_repositories.dart';
import 'support/fake_workplace_repository.dart';
import 'support/in_memory_import_export_fakes.dart';

/// A use case nobody is waiting for: a dialog that opens it just shows progress.
final class _Pending<Output, Params> implements UseCase<Output, Params> {
  @override
  Future<Output> call(Params params) => Completer<Output>().future;
}

final class _NoHistory implements HistoryRepository {
  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => Stream.value(const []);

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  Future<void> clear() async {}
}

final class _LinkedCollections implements GitLinkRepository {
  final Set<int> ids;
  _LinkedCollections(this.ids);

  @override
  Stream<Set<int>> watchLinkedCollectionIds() => Stream.value(ids);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// Shop (1): folder Users (10) holding List users (100, tagged v2), and Health
/// (101). Blog (2): Posts (200).
void main() {
  late FakeTagRepository tags;
  late FakeDocumentationRepository docs;
  late AppDatabase workplaceDatabase;

  setUp(() async {
    await locator.reset();
    tags = FakeTagRepository()..seed(EntityKind.request, 100, ['v2']);
    docs = FakeDocumentationRepository()
      ..seed(EntityKind.collection, 1, '# Shop docs')
      ..seed(EntityKind.folder, 10, '# Users docs');
    final collections = FakeCollectionRepository(
      collections: const [
        CollectionEntity(id: 1, name: 'Shop'),
        CollectionEntity(id: 2, name: 'Blog'),
      ],
      folders: {
        1: [folderEntity(10, name: 'Users')],
      },
    );
    final requests = FakeRequestRepository({
      1: [requestEntity(100, folderId: 10, name: 'List users'), requestEntity(101, name: 'Health')],
      2: [requestEntity(200, collectionId: 2, name: 'Posts')],
    });
    final environments = InMemoryDb();
    final tagFilter = TagFilterViewModel(tags, collections, requests);
    final shell = ShellViewModel(requests);
    // PostPilotApp provides a WorkplaceViewModel to the whole tree. Never initialised
    // here, so no database query is made and the sidebar header shows "No Workplace".
    workplaceDatabase = AppDatabase.forTesting(NativeDatabase.memory());

    locator
      ..registerSingleton<ShellViewModel>(shell)
      ..registerSingleton<WorkplaceViewModel>(
        WorkplaceViewModel(
          repository: FakeWorkplaceRepository(),
          backupService: environments.backupService,
          database: workplaceDatabase,
          shellViewModel: shell,
        ),
      )
      ..registerSingleton<CollectionsViewModel>(CollectionsViewModel(collections, requests, requestIdFilter: tagFilter))
      ..registerSingleton<EnvironmentsViewModel>(
        EnvironmentsViewModel(environments.environmentRepository, environments.globalVariableRepository),
      )
      ..registerSingleton<HistoryViewModel>(HistoryViewModel(_NoHistory()))
      ..registerSingleton<LinkedCollectionsViewModel>(LinkedCollectionsViewModel(_LinkedCollections({1})))
      ..registerSingleton<SettingsViewModel>(SettingsViewModel(FakeSettingsRepository()))
      ..registerSingleton<TagFilterViewModel>(tagFilter)
      ..registerSingleton<LayoutPrefs>(LayoutPrefs())
      ..registerSingleton<RequestConsoleLog>(RequestConsoleLog())
      ..registerFactory<ImportAnyViewModel>(() => ImportAnyViewModel(_Pending<ImportSummary, ImportAnyParams>()))
      ..registerFactory<BackupViewModel>(
        () => BackupViewModel(_Pending<BackupExport, NoParams>(), _Pending<ImportSummary, String>()),
      )
      ..registerFactory<GitCloneViewModel>(
        () => GitCloneViewModel(
          credentials: FakeCredentialsStore(),
          saveTokenUseCase: _Pending<String, GitTokenParams>(),
          discoverUseCase: _Pending<List<DiscoveredCollection>, GitDiscoverParams>(),
          cloneUseCase: _Pending<GitLink, GitCloneParams>(),
        ),
      )
      ..registerFactoryParam<EntityDocsViewModel, EntityKind, int>((kind, id) => EntityDocsViewModel(docs, kind, id))
      ..registerFactoryParam<TagsViewModel, EntityKind, int>((kind, id) => TagsViewModel(tags, kind, id))
      ..registerFactory<AllTagsViewModel>(() => AllTagsViewModel(tags));
  });

  tearDown(() async {
    locator<WorkplaceViewModel>().dispose();
    await workplaceDatabase.close();
    locator<CollectionsViewModel>().dispose();
    locator<EnvironmentsViewModel>().dispose();
    locator<HistoryViewModel>().dispose();
    locator<LinkedCollectionsViewModel>().dispose();
    locator<SettingsViewModel>().dispose();
    locator<TagFilterViewModel>().dispose();
    locator<LayoutPrefs>().dispose();
    locator<RequestConsoleLog>().dispose();
    await locator.reset();
    await tags.close();
  });

  Future<void> launch(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const PostPilotApp());
    await settle(tester);
  }

  Finder menuOf(String tileTitle) =>
      find.descendant(of: find.widgetWithText(ListTile, tileTitle), matching: find.byType(PopupMenuButton<String>));

  group('top bar', () {
    for (final width in [640.0, 1000.0]) {
      testWidgets('fits a ${width.toInt()} px window without scrolling', (tester) async {
        await launch(tester, width: width);

        for (final tooltip in ['More', 'History', 'Settings', 'Manage environments']) {
          expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
        }
        expect(find.text('No Environment'), findsOneWidget);
        final bar = find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
        final scrollable = tester.state<ScrollableState>(find.descendant(of: bar, matching: find.byType(Scrollable)));
        expect(scrollable.position.maxScrollExtent, 0);
      });
    }

    testWidgets('More holds Console, Cookies and Keyboard shortcuts, and Console opens', (tester) async {
      await launch(tester);
      expect(find.byTooltip('Console'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      expect(find.text('Console'), findsOneWidget);
      expect(find.text('Cookies'), findsOneWidget);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);

      await tester.tap(find.text('Console'));
      await settle(tester);
      expect(find.byType(ConsoleDialog), findsOneWidget);
    });

    testWidgets('More opens the keyboard shortcuts', (tester) async {
      await launch(tester);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Keyboard shortcuts'));
      await settle(tester);

      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
    });

    testWidgets('Settings opens the dialog, whose Data section reaches backup and the shortcuts', (tester) async {
      await launch(tester);

      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      expect(find.byType(SettingsDialog), findsOneWidget);
      await tester.tap(find.text('Data'));
      await settle(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Keyboard shortcuts'));
      await settle(tester);
      expect(find.byType(SettingsDialog), findsNothing);
      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await settle(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      await tester.tap(find.text('Data'));
      await settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Backup & restore…'));
      await settle(tester);
      expect(find.byType(SettingsDialog), findsNothing);
      expect(find.byType(BackupDialog), findsOneWidget);
    });
  });

  group('sidebar header', () {
    testWidgets('has one Import, Clone from Git and New collection', (tester) async {
      await launch(tester);

      expect(find.byTooltip('Import…'), findsOneWidget);
      expect(find.byTooltip('Clone from Git'), findsOneWidget);
      expect(find.byTooltip('New collection'), findsOneWidget);
      expect(find.byTooltip('Import Postman collection'), findsNothing);
      expect(find.byTooltip('Import OpenAPI/Swagger'), findsNothing);
    });

    testWidgets('Import opens the any-format import dialog', (tester) async {
      await launch(tester);

      await tester.tap(find.byTooltip('Import…'));
      await settle(tester);

      expect(find.byType(ImportAnyDialog), findsOneWidget);
    });

    testWidgets('a cloned collection is opened and announced', (tester) async {
      await launch(tester);

      await tester.tap(find.byTooltip('Clone from Git'));
      await settle(tester);
      expect(find.byType(GitCloneDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(GitCloneDialog))).pop(2);
      await settle(tester);

      expect(locator<CollectionsViewModel>().isExpanded(2), isTrue);
      expect(find.text('Collection cloned'), findsOneWidget);
      expect(find.text('Posts'), findsOneWidget);
    });

    testWidgets('cancelling the clone changes nothing', (tester) async {
      await launch(tester);

      await tester.tap(find.byTooltip('Clone from Git'));
      await settle(tester);
      Navigator.of(tester.element(find.byType(GitCloneDialog))).pop();
      await settle(tester);

      expect(find.text('Collection cloned'), findsNothing);
      expect(locator<CollectionsViewModel>().expandedCollectionIds, isEmpty);
    });

    testWidgets('fits the drawer of a narrow window', (tester) async {
      await launch(tester, width: 400);

      await tester.tap(find.byTooltip('Collections'));
      await settle(tester);

      expect(find.byTooltip('Clone from Git'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
    });
  });

  group('collection and folder menus', () {
    testWidgets('a collection offers its documentation, sync and export actions', (tester) async {
      await launch(tester);

      await tester.tap(menuOf('Shop'));
      await settle(tester);

      for (final label in [
        'Add request',
        'Add folder',
        'Import cURL',
        'Run collection',
        'Variables',
        'Collection auth',
        'Description & tags…',
        'Documentation…',
        'Git sync…',
        'Export as Postman JSON',
        'Export as OpenAPI',
        'Export cURL script',
        'Rename',
        'Duplicate',
        'Delete',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Description & tags opens the collection\'s own description', (tester) async {
      await launch(tester);

      await tester.tap(menuOf('Shop'));
      await settle(tester);
      await tester.tap(find.text('Description & tags…'));
      await settle(tester);

      expect(find.byType(EntityDescriptionDialog), findsOneWidget);
      expect(find.text('# Shop docs'), findsOneWidget);
    });

    testWidgets('Import cURL opens the import dialog', (tester) async {
      await launch(tester);

      await tester.tap(menuOf('Shop'));
      await settle(tester);
      await tester.tap(find.text('Import cURL'));
      await settle(tester);

      expect(find.byType(ImportAnyDialog), findsOneWidget);
    });

    testWidgets('a folder offers Description & tags too, and opens its own', (tester) async {
      await launch(tester);
      await tester.tap(find.text('Shop'));
      await settle(tester);

      await tester.tap(menuOf('Users'));
      await settle(tester);
      await tester.tap(find.text('Description & tags…'));
      await settle(tester);

      expect(find.byType(EntityDescriptionDialog), findsOneWidget);
      expect(find.text('# Users docs'), findsOneWidget);
    });

    testWidgets('a Git-linked collection carries the badge and the others do not', (tester) async {
      await launch(tester);

      Finder badgeIn(String name) =>
          find.descendant(of: find.widgetWithText(ListTile, name), matching: find.byIcon(Icons.merge_type));
      expect(badgeIn('Shop'), findsOneWidget);
      expect(badgeIn('Blog'), findsNothing);
    });
  });

  group('filtering', () {
    testWidgets('a tag chip narrows the sidebar to what carries it, and All brings the rest back', (tester) async {
      await launch(tester);
      expect(find.byKey(const ValueKey('tag-filter-v2')), findsOneWidget);
      expect(find.text('Blog'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-filter-v2')));
      await settle(tester);

      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Blog'), findsNothing);
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('List users'), findsOneWidget);
      expect(find.text('Health'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tag-filter-All')));
      await settle(tester);

      expect(find.text('Blog'), findsOneWidget);
    });

    testWidgets('a search nothing satisfies says so', (tester) async {
      await launch(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await settle(tester);

      expect(find.text('Nothing matches'), findsOneWidget);
      expect(find.text('Shop'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await settle(tester);

      expect(find.text('Nothing matches'), findsNothing);
      expect(find.text('Shop'), findsOneWidget);
    });
  });
}

/// A frame plus enough time for route and menu animations, without waiting on
/// the progress indicators some dialogs keep spinning.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
