// What a brand-new install does with the first things anyone presses: New request, a history entry, the empty
// screens, and the tour's buttons. The placement logic runs against a real in-memory database; the widget flows
// use in-memory fakes, which complete without a real event loop and so work inside the widget tester.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/collections/presentation/widgets/collections_sidebar.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/history/presentation/view_models/history_view_model.dart';
import 'package:postpilot/features/history/presentation/widgets/history_dialog.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/shell/presentation/new_request_action.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/shell/presentation/widgets/empty_workspace.dart';
import 'package:postpilot/features/templates/domain/usecases/add_starter_template_usecase.dart';
import 'package:postpilot/features/tour/presentation/tour_dialog.dart';

import 'support/drift_repos.dart';
import 'support/in_memory_import_export_fakes.dart';

final class _OneEntryHistory implements HistoryRepository {
  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => Stream.value([
    HistoryEntryEntity(id: 1, method: 'POST', url: 'https://api.test/users', statusCode: 201, durationMs: 40, sentAt: DateTime(2026, 1, 2, 3, 4, 5)),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// The in-memory requests, plus the one stream the shell opens a tab with.
final class _Requests implements RequestRepository {
  final RequestRepository inner;
  _Requests(this.inner);

  @override
  Stream<ApiRequestEntity?> watchById(int id) => Stream.fromFuture(inner.findById(id));

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) =>
      inner.createRequest(collectionId: collectionId, folderId: folderId, name: name);

  @override
  Future<void> saveRequest(ApiRequestEntity request) => inner.saveRequest(request);

  @override
  Future<ApiRequestEntity?> findById(int id) => inner.findById(id);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => inner.watchByCollection(collectionId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// The in-memory environments, which cannot activate one; this records which was activated.
final class _Environments implements EnvironmentRepository {
  final EnvironmentRepository inner;
  int? activated;
  _Environments(this.inner);

  @override
  Future<int> create(String name) => inner.create(name);

  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) => inner.upsertVariable(variable);

  @override
  Future<void> setActive(int id) async => activated = id;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('New request, against a real database', () {
    late AppDatabase db;
    late DriftRepos repos;
    late CollectionsViewModel collections;
    late ShellViewModel shell;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = DriftRepos(db);
      collections = CollectionsViewModel(repos.collectionRepository, repos.requestRepository);
      shell = ShellViewModel(repos.requestRepository);
    });

    tearDown(() async {
      collections.dispose();
      shell.dispose();
      await db.close();
    });

    Future<List<String>> names() async => (await db.collectionsDao.watchAllCollections().first).map((c) => c.name).toList();

    test('on a fresh install creates "My collection" and the request in it', () async {
      final placed = await createNewRequest(collections, shell);

      expect(placed.createdCollection, isTrue);
      expect(await names(), ['My collection']);
      final request = await repos.requestRepository.findById(placed.requestId);
      expect(request!.collectionId, placed.collectionId);
      expect(request.name, 'New Request');
    });

    test('the second time it reuses that collection instead of making another', () async {
      final first = await createNewRequest(collections, shell);
      final second = await createNewRequest(collections, shell);

      expect(second.createdCollection, isFalse);
      expect(second.collectionId, first.collectionId);
      expect(second.requestId, isNot(first.requestId));
      expect(await names(), ['My collection']);
    });

    test('with collections but no tab open it uses the first collection and creates nothing else', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      await repos.collectionRepository.createCollection('Blog');

      final placed = await createNewRequest(collections, shell);

      expect((placed.collectionId, placed.createdCollection), (shop, false));
      expect(await names(), ['Shop', 'Blog']);
    });

    test('with a tab open it goes beside it: same collection, same folder', () async {
      await repos.collectionRepository.createCollection('Shop');
      final blog = await repos.collectionRepository.createCollection('Blog');
      final posts = await repos.collectionRepository.createFolder(collectionId: blog, name: 'Posts');
      final open = await repos.requestRepository.createRequest(collectionId: blog, folderId: posts, name: 'List posts');
      shell.selectRequest(open);

      final placed = await createNewRequest(collections, shell);

      final request = await repos.requestRepository.findById(placed.requestId);
      expect((request!.collectionId, request.folderId, placed.createdCollection), (blog, posts, false));
    });

    test('two quick presses share one default collection', () async {
      final both = await Future.wait([createNewRequest(collections, shell), createNewRequest(collections, shell)]);

      expect(await names(), ['My collection']);
      expect(both[0].collectionId, both[1].collectionId);
      expect(both[0].requestId, isNot(both[1].requestId));
    });

    test('ensureCollection says whether it made the collection', () async {
      final first = await collections.ensureCollection();
      final again = await collections.ensureCollection();

      expect((first.created, again.created), (true, false));
      expect(again.id, first.id);
    });
  });

  group('with in-memory fakes in the widget tester', () {
    late InMemoryDb memory;
    late CollectionsViewModel collections;
    late ShellViewModel shell;

    setUp(() async {
      await locator.reset();
      memory = InMemoryDb();
      final requests = _Requests(memory.requestRepository);
      locator.registerSingleton<RequestRepository>(requests);
      collections = CollectionsViewModel(memory.collectionRepository, requests);
      shell = ShellViewModel(requests);
    });

    tearDown(() async {
      collections.dispose();
      shell.dispose();
      await locator.reset();
    });

    List<String> names() => [for (final c in memory.collections) c.name];

    Widget host({required Widget Function(BuildContext) opener, HistoryViewModel? history, EnvironmentsViewModel? environments}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
          ChangeNotifierProvider<ShellViewModel>.value(value: shell),
          if (history != null) ChangeNotifierProvider<HistoryViewModel>.value(value: history),
          if (environments != null) ChangeNotifierProvider<EnvironmentsViewModel>.value(value: environments),
        ],
        child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: Builder(builder: opener))),
      );
    }

    group('History', () {
      Future<void> openHistory(WidgetTester tester, HistoryViewModel history) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            history: history,
            opener: (context) => TextButton(onPressed: () => HistoryDialog.show(context), child: const Text('open')),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // A tap on a row shows the entry; "Open as new request" is what makes a request of it.
        await tester.tap(find.text('https://api.test/users'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open as new request'));
        await tester.pumpAndSettle();
      }

      testWidgets('opening an entry on a fresh install makes "My collection" instead of refusing', (tester) async {
        final history = HistoryViewModel(_OneEntryHistory());
        addTearDown(history.dispose);

        await openHistory(tester, history);

        expect(names(), ['My collection']);
        final request = memory.requests.single;
        expect((request.method, request.url, request.name), (HttpMethod.post, 'https://api.test/users', 'POST https://api.test/users'));
        expect(shell.selectedRequestId, request.id);
        expect(find.byType(HistoryDialog), findsNothing, reason: 'the dialog closes once the request is open');
        expect(find.text('Create a collection first'), findsNothing);
      });

      testWidgets('with a collection already there it asks which one instead of picking the first, and creates no second one', (tester) async {
        final shop = await memory.collectionRepository.createCollection('Shop');
        await memory.collectionRepository.createCollection('Blog');
        // The in-memory repository answers once, so the sidebar's model is made after the collections exist.
        collections.dispose();
        collections = CollectionsViewModel(memory.collectionRepository, locator<RequestRepository>());
        final history = HistoryViewModel(_OneEntryHistory());
        addTearDown(history.dispose);

        await openHistory(tester, history);

        // The entry kept no collection, and there are two to choose from: nothing is chosen silently.
        expect(find.text('Open in which collection?'), findsOneWidget);
        expect(memory.requests, isEmpty);
        await tester.tap(find.text('Shop'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open here'));
        await tester.pumpAndSettle();

        expect(names(), ['Shop', 'Blog']);
        expect(memory.requests.single.collectionId, shop);
        expect(shell.selectedRequestId, memory.requests.single.id);
      });
    });

    group('empty screens', () {
      Future<void> pumpEmptyWorkspace(WidgetTester tester, {VoidCallback? onCommandPalette, VoidCallback? onTemplates}) async {
        tester.view.physicalSize = const Size(1000, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: EmptyWorkspace(onNewRequest: () {}, onImport: () {}, onTemplates: onTemplates, onCommandPalette: onCommandPalette),
            ),
          ),
        );
      }

      testWidgets('the empty workspace offers the command palette and the starter templates, and says how to open them', (tester) async {
        var palette = 0;
        var templates = 0;
        await pumpEmptyWorkspace(tester, onCommandPalette: () => palette++, onTemplates: () => templates++);

        expect(find.textContaining('starter template'), findsOneWidget);
        expect(find.text('Open command palette (Ctrl+Shift+P)'), findsOneWidget);
        // The key list in the footer carries the palette too.
        expect(find.text('Command palette: tools, requests, environments'), findsOneWidget);

        await tester.tap(find.text('Open command palette (Ctrl+Shift+P)'));
        await tester.tap(find.text('Templates'));
        expect((palette, templates), (1, 1));
      });

      testWidgets('without the callbacks the buttons are left out', (tester) async {
        await pumpEmptyWorkspace(tester);
        expect(find.textContaining('Open command palette'), findsNothing);
        expect(find.text('Templates'), findsNothing);
      });

      testWidgets('the sidebar of a fresh install has a real button, and an import', (tester) async {
        var created = 0;
        var imported = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SizedBox(width: 260, height: 400, child: NoCollectionsPrompt(onCreate: () => created++, onImport: () => imported++)),
            ),
          ),
        );

        expect(find.text('No collections yet'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'New collection'));
        await tester.tap(find.widgetWithText(TextButton, 'or import one'));

        expect((created, imported), (1, 1));
        expect(tester.takeException(), isNull);
      });
    });

    group('the tour', () {
      Future<void> openTour(WidgetTester tester, {VoidCallback? onOpenPalette}) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            opener: (context) => TextButton(onPressed: () => TourDialog.show(context, onOpenPalette: onOpenPalette), child: const Text('open')),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      Future<void> next(WidgetTester tester, int times) async {
        for (var i = 0; i < times; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }

      testWidgets('the Tests tab is described as holding extractors', (tester) async {
        await openTour(tester);

        await next(tester, 1);

        expect(find.textContaining('The Tests tab also holds extractors'), findsOneWidget);
      });

      testWidgets('"Add the sample collection" adds the REST starter, opens a request of it and closes the tour', (tester) async {
        final environments = _Environments(memory.environmentRepository);
        locator.registerSingleton<AddStarterTemplateUseCase>(AddStarterTemplateUseCase(memory.writer, environments));
        await openTour(tester);

        await tester.ensureVisible(find.text('Add the sample collection'));
        await tester.tap(find.text('Add the sample collection'));
        await tester.pumpAndSettle();

        expect(names(), ['REST basics']);
        expect(memory.requests, hasLength(10));
        expect(memory.environments.single.name, 'JSONPlaceholder');
        expect(environments.activated, memory.environments.single.id, reason: "the template's environment becomes the active one");
        expect(memory.requests.map((r) => r.id), contains(shell.selectedRequestId));
        expect(find.text('Quick tour'), findsNothing, reason: 'the tour closes behind the action');
        expect(find.textContaining('Added "REST basics" with 10 requests'), findsOneWidget);
      });

      testWidgets('a failing sample leaves the tour open with the reason, and the button usable again', (tester) async {
        // No AddStarterTemplateUseCase registered: the locator throws, which the tour must report, not swallow.
        await openTour(tester);

        await tester.ensureVisible(find.text('Add the sample collection'));
        await tester.tap(find.text('Add the sample collection'));
        await tester.pumpAndSettle();

        expect(find.textContaining("Couldn't add the sample collection"), findsOneWidget);
        expect(find.text('Quick tour'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Add the sample collection')).onPressed, isNotNull);
      });

      testWidgets('without the app\'s callback the same button opens a palette of tools, requests and environments', (tester) async {
        locator.registerSingleton<CollectionLoader>(memory.loader);
        final environments = EnvironmentsViewModel(memory.environmentRepository, memory.globalVariableRepository);
        addTearDown(environments.dispose);
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            environments: environments,
            opener: (context) => TextButton(onPressed: () => TourDialog.show(context), child: const Text('open')),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await next(tester, 4);
        await tester.ensureVisible(find.text('Open the command palette'));
        await tester.tap(find.text('Open the command palette'));
        await tester.pumpAndSettle();

        expect(find.text('Quick tour'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Starter templates'), findsOneWidget, reason: 'the palette lists the tools');
      });

      testWidgets('"Open the command palette" closes the tour and hands over to the app\'s own palette', (tester) async {
        var opened = 0;
        await openTour(tester, onOpenPalette: () => opened++);

        await next(tester, 4);
        await tester.ensureVisible(find.text('Open the command palette'));
        await tester.tap(find.text('Open the command palette'));
        await tester.pumpAndSettle();

        expect(opened, 1);
        expect(find.text('Quick tour'), findsNothing);
      });
    });
  });
}
