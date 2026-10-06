// One order for the sidebar, the collection runner, the CLI and every export, on a real (in-memory SQLite)
// collection that was arranged by moving things, plus what a run may be narrowed to.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/data/repositories/collection_order_repository_impl.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/import_export/domain/services/collection_tree.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_postman_collection_usecase.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_selection.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/run_harness.dart';
import '../support/shop_seed.dart';

/// What the collection below runs in, worked out by hand: Auth was created after Orders and Health but was moved
/// to the front, so Login runs first; Orders keeps its sub-folder Admin between its two requests.
const _expected = ['Login', 'Health', 'List orders', 'Purge', 'Create order', 'Logout'];

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late CollectionOrderRepositoryImpl order;
  late int c;
  late ({int health, int orders, int list, int admin, int purge, int create, int auth, int login, int logout}) ids;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    order = CollectionOrderRepositoryImpl(db.collectionsDao);
    c = await repos.collectionRepository.createCollection('API');
    String url(String name) => 'https://api.test/$name';
    final health = await addRequest(repos, c, 'Health', url: url('Health'));
    final orders = await repos.collectionRepository.createFolder(collectionId: c, name: 'Orders');
    final list = await addRequest(repos, c, 'List orders', folderId: orders, url: url('List orders'));
    final admin = await repos.collectionRepository.createFolder(collectionId: c, parentFolderId: orders, name: 'Admin');
    final purge = await addRequest(repos, c, 'Purge', folderId: admin, url: url('Purge'));
    final create = await addRequest(repos, c, 'Create order', folderId: orders, url: url('Create order'));
    final auth = await repos.collectionRepository.createFolder(collectionId: c, name: 'Auth');
    final login = await addRequest(repos, c, 'Login', folderId: auth, url: url('Login'));
    final logout = await addRequest(repos, c, 'Logout', url: url('Logout'));
    ids = (health: health, orders: orders, list: list, admin: admin, purge: purge, create: create, auth: auth, login: login, logout: logout);
    // Created last, so it sits last; the user drags it to the front.
    await order.moveFolder(auth, collectionId: c, before: OrderRef.request(health));
  });

  tearDown(() => db.close());

  Future<List<String>> run(CollectionRunnerService runner, {RunSelection selection = RunSelection.all}) async {
    final results = await runner.run(c, selection: selection).toList();
    return [for (final r in results) r.request.name];
  }

  /// The sidebar's tree, read the way its widgets read it.
  Future<List<String>> sidebarOrder() async {
    final vm = CollectionsViewModel(repos.collectionRepository, repos.requestRepository, orderRepository: order);
    addTearDown(vm.dispose);
    vm.toggleExpand(c);
    for (var i = 0; i < 20 && (vm.foldersByCollection[c] == null || vm.requestsByCollection[c] == null); i++) {
      await pumpEventQueue();
    }
    final names = <String>[];
    void walk(int? parent) {
      for (final item in vm.childrenOf(c, parent)) {
        if (item.folder != null) {
          walk(item.folder!.id);
        } else {
          names.add(item.request!.name);
        }
      }
    }

    walk(null);
    return names;
  }

  CollectionRunnerService runnerWith(FakeRunClient client) =>
      buildRunner(repos.requestRepository, repos.collectionRepository, client);

  group('one order everywhere', () {
    test('the app runner sends in the order the sidebar shows, a request in a later folder included', () async {
      final client = FakeRunClient();

      final names = await run(runnerWith(client));

      expect(names, _expected);
      expect(client.sentNames, _expected, reason: 'and the URLs really left in that order');
      expect(await sidebarOrder(), _expected);
    });

    test('every iteration takes the same way through the collection', () async {
      final client = FakeRunClient();
      final runner = runnerWith(client);

      final results = await runner.run(c, options: const CollectionRunOptions(iterations: 3)).toList();

      expect([for (final r in results) r.request.name], [..._expected, ..._expected, ..._expected]);
      expect([for (final r in results) r.iteration], [for (var i = 1; i <= 3; i++) ...List.filled(6, i)]);
    });

    test('the CLI runs a workspace file in the same order, and lists it that way', () async {
      final snapshot = await repos.backupService.snapshot();
      final sent = <String>[];
      Future<CliResponse> send(CliRequest request) async {
        sent.add(Uri.parse(request.url).pathSegments.last);
        return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
      }

      final live = WorkspaceRunner(snapshot, send);
      final fromFile = WorkspaceRunner.parse(BackupCodec.encode(snapshot), send);

      for (final runner in [live, fromFile]) {
        sent.clear();
        expect(runner.listRequests().map((r) => r.name), _expected);
        final summary = await runner.run(const RunOptions());
        expect(summary.outcomes.map((o) => o.name), _expected);
        expect(sent, _expected);
      }
    });

    test('--folder and --request pick from that order, they never change it', () async {
      final snapshot = await repos.backupService.snapshot();
      final runner = WorkspaceRunner(snapshot, (request) async {
        return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
      });

      final folder = await runner.run(const RunOptions(folder: 'Orders'));
      final sub = await runner.run(const RunOptions(folder: 'Orders/Admin'));
      // given as Logout, Login: still Login first
      final requests = await runner.run(const RunOptions(requests: ['Logout', 'Auth/Login']));
      final both = await runner.run(const RunOptions(folder: 'Orders', requests: ['Orders/Admin/Purge', 'Health']));

      expect(folder.outcomes.map((o) => o.name), ['List orders', 'Purge', 'Create order']);
      expect(sub.outcomes.map((o) => o.name), ['Purge']);
      expect(requests.outcomes.map((o) => o.name), ['Login', 'Logout']);
      expect(both.outcomes.map((o) => o.name), ['Purge'], reason: 'a request has to match both');
      expect(runner.unmatchedRequestSelectors(const RunOptions(requests: ['Logout', 'Nope', 'Orders/Purge'])), ['Nope', 'Orders/Purge']);
      expect(runner.unmatchedRequestSelectors(const RunOptions(folder: 'Auth', requests: ['Health'])), ['Health']);
    });

    test('the CLI refuses a --request that matches nothing before anything is sent', () async {
      final snapshot = await repos.backupService.snapshot();
      var sends = 0;
      final runner = WorkspaceRunner(snapshot, (request) async {
        sends++;
        return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
      });

      expect(runner.unmatchedRequestSelectors(const RunOptions(requests: ['Typo'])), ['Typo']);
      expect(sends, 0);
    });

    test('the Postman export lists folders and requests in that order, interleaved as arranged', () async {
      final text = await ExportPostmanCollectionUseCase(
        repos.collectionRepository,
        repos.requestRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
      )(c);

      final tree = (jsonDecode(text) as Map<String, dynamic>)['item'] as List<dynamic>;
      // top level: Auth, Health, Orders, Logout; a folder item has an 'item' list of its own
      expect([for (final i in tree) (i as Map)['name']], ['Auth', 'Health', 'Orders', 'Logout']);
      final names = <String>[];
      void walk(List<dynamic> items) {
        for (final item in items.cast<Map<String, dynamic>>()) {
          if (item['item'] is List) {
            walk(item['item'] as List<dynamic>);
          } else {
            names.add(item['name'] as String);
          }
        }
      }

      walk(tree);
      expect(names, _expected);
      final orders = tree.cast<Map<String, dynamic>>().firstWhere((i) => i['name'] == 'Orders')['item'] as List<dynamic>;
      expect([for (final i in orders) (i as Map)['name']], ['List orders', 'Admin', 'Create order'], reason: 'a sub-folder sits between requests');
    });

    test('the loader behind OpenAPI, cURL and the Dart API layer, and the docs, follow it too', () async {
      final loaded = await repos.loader.load(c);

      expect(CollectionTree.ordered(loaded.folders, loaded.requests).map((p) => p.request.name), _expected);
      expect(loaded.requests.map((r) => r.name), _expected);
      expect(loaded.folders.map((f) => f.name), ['Auth', 'Orders', 'Admin']);

      final docs = await BuildApiDocsUseCase(
        repos.collectionRepository,
        repos.requestRepository,
        repos.exampleRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
        repos.documentationRepository,
        repos.tagRepository,
      )(c);
      expect(docs.folders.map((f) => f.name), ['Auth', 'Orders']);
      expect(docs.requests.map((r) => r.name), ['Health', 'Logout']);
      final orders = docs.folders.last;
      expect(orders.requests.map((r) => r.name), ['List orders', 'Create order']);
      expect(orders.folders.single.requests.map((r) => r.name), ['Purge']);
    });

    test('a backup and a restore bring the same arrangement back', () async {
      final backup = (await repos.backupService.export()).text;

      final otherDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(otherDb.close);
      final copy = DriftRepos(otherDb);
      await copy.backupService.restore(backup);
      final restored = (await copy.backupService.snapshot()).collections.single;
      final back = await copy.backupService.export();

      expect(restored.requests.map((r) => r.request.name), _expected);
      // The restored file is identical to the first one: same positions, same nesting.
      expect(normalizedBackup(back.text), normalizedBackup(backup));
    });
  });

  group('what a run is narrowed to', () {
    test('a folder runs its requests and those of the folders under it, in order', () async {
      final runner = runnerWith(FakeRunClient());

      expect(await run(runner, selection: RunSelection.folder(ids.orders)), ['List orders', 'Purge', 'Create order']);
      expect(await run(runner, selection: RunSelection.folder(ids.admin)), ['Purge']);
      expect(await run(runner, selection: RunSelection.folder(ids.auth)), ['Login']);
    });

    test('a hand-picked set runs in the collection order, whatever order it was picked in', () async {
      final runner = runnerWith(FakeRunClient());

      final picked = RunSelection.requests([ids.logout, ids.purge, ids.login]);

      expect(await run(runner, selection: picked), ['Login', 'Purge', 'Logout']);
    });

    test('ids that no longer exist are ignored', () async {
      final runner = runnerWith(FakeRunClient());

      expect(await run(runner, selection: RunSelection.requests([ids.health, 99999])), ['Health']);
    });

    test('an empty selection runs nothing and sends nothing, an unknown folder likewise', () async {
      final client = FakeRunClient();
      final runner = runnerWith(client);

      expect(await run(runner, selection: RunSelection.requests(const [])), isEmpty);
      expect(await run(runner, selection: const RunSelection.folder(424242)), isEmpty);
      expect(client.sent, isEmpty);
    });

    test('the production lock is shown exactly the requests that will be sent', () async {
      final runner = runnerWith(FakeRunClient());

      final folder = await runner.fullRequestsIn(c, selection: RunSelection.folder(ids.orders));
      final picked = await runner.fullRequestsIn(c, selection: RunSelection.requests([ids.logout, ids.health]));
      final all = await runner.fullRequestsIn(c);

      expect(folder.map((r) => r.name), ['List orders', 'Purge', 'Create order']);
      expect(picked.map((r) => r.name), ['Health', 'Logout']);
      expect(all.map((r) => r.name), _expected);
    });

    test('selections compare by content', () {
      expect(RunSelection.requests([1, 2]), RunSelection.requests([2, 1]));
      expect(RunSelection.requests([1, 2]), isNot(RunSelection.requests([1])));
      expect(const RunSelection.folder(3), const RunSelection.folder(3));
      expect(RunSelection.all, RunSelection.all);
      expect(const RunSelection.folder(3), isNot(RunSelection.all));
    });
  });

  group('while a run is in progress', () {
    test('a request deleted or moved to another collection is skipped; moving one within the collection changes nothing',
        () async {
      final other = await repos.collectionRepository.createCollection('Other');
      final client = FakeRunClient();
      client.beforeAnswer = (url) async {
        if (!url.endsWith('/Login')) return;
        await repos.requestRepository.deleteRequest(ids.purge);
        await order.moveRequest(ids.create, collectionId: other);
        await order.moveRequest(ids.logout, collectionId: c, before: OrderRef.request(ids.health));
      };

      final names = await run(runnerWith(client));

      expect(names, ['Login', 'Health', 'List orders', 'Logout'], reason: 'Logout kept its place in the run');
      expect(client.sentNames, names, reason: 'nothing was sent for the two that were gone');
    });
  });

  group('the runner view model', () {
    late CollectionRunnerViewModel vm;

    setUp(() {
      vm = CollectionRunnerViewModel(runnerWith(FakeRunClient()));
    });

    tearDown(() => vm.dispose());

    Future<void> untilIdle() async {
      while (vm.isRunning) {
        await pumpEventQueue();
      }
    }

    test('lists the collection as a tree in run order, with the place each ticked request will run in', () async {
      await vm.load(c);

      String describe(RunTreeRow row) => switch (row) {
        RunFolderRow() => '${'  ' * row.depth}[${row.folder.name}] ${row.selectedCount}/${row.requestCount}',
        RunRequestRow() => '${'  ' * row.depth}${row.request.name} #${row.runNumber}',
      };

      expect(vm.treeRows.map(describe), [
        '[Auth] 1/1',
        '  Login #1',
        'Health #2',
        '[Orders] 3/3',
        '  List orders #3',
        '  [Admin] 1/1',
        '    Purge #4',
        '  Create order #5',
        'Logout #6',
      ]);
      expect(vm.selectedCount, 6);
      expect(vm.allSelected, isTrue);
    });

    test('opened for a folder, only that folder is ticked', () async {
      await vm.load(c, folderId: ids.orders);

      expect(vm.requests.map((r) => r.name), ['List orders', 'Purge', 'Create order']);
      expect(vm.folderSelection(ids.orders), isTrue);
      expect(vm.folderSelection(ids.admin), isTrue);
      expect(vm.folderSelection(ids.auth), isFalse);
      expect(vm.isSelected(ids.health), isFalse);
      expect(vm.allSelected, isFalse);
      expect(vm.plannedRequestCount, 3);
    });

    test('a folder is ticked, unticked or partly ticked from what is in it; ticking it again ticks the rest', () async {
      await vm.load(c);

      vm.toggleRequest(ids.create);
      expect(vm.folderSelection(ids.orders), isNull, reason: 'two of three');
      expect(vm.folderSelection(ids.admin), isTrue);
      expect((vm.treeRows.whereType<RunFolderRow>().firstWhere((r) => r.folder.id == ids.orders)).checked, isNull);

      vm.toggleFolderSelection(ids.orders);
      expect(vm.folderSelection(ids.orders), isTrue);
      vm.toggleFolderSelection(ids.orders);
      expect(vm.folderSelection(ids.orders), isFalse);
      expect(vm.requests.map((r) => r.name), ['Login', 'Health', 'Logout']);
    });

    test('nothing ticked: no run, and a message that says why', () async {
      await vm.load(c);

      vm.selectNone();

      expect(vm.canRun, isFalse);
      expect(vm.selectionError, contains('Tick at least one'));
      expect(vm.plannedRequestCount, 0);
      vm.start(c);
      expect(vm.hasStarted, isFalse, reason: 'start does nothing without a selection');
      vm.selectAll();
      expect(vm.canRun, isTrue);
      expect(vm.selectionError, isNull);
    });

    test('a collapsed folder hides what is in it but keeps it ticked', () async {
      await vm.load(c);

      vm.toggleFolderExpanded(ids.orders);

      final rows = vm.treeRows;
      expect(rows.whereType<RunRequestRow>().map((r) => r.request.name), ['Login', 'Health', 'Logout']);
      expect(vm.selectedCount, 6);
    });

    test('Run sends the ticked requests only, in order, and the results come back numbered by it', () async {
      final client = FakeRunClient();
      vm.dispose();
      vm = CollectionRunnerViewModel(runnerWith(client));
      await vm.load(c);
      vm.toggleRequest(ids.health);
      vm.toggleRequest(ids.purge);

      vm.start(c);
      await untilIdle();

      expect(vm.results.map((r) => r.request.name), ['Login', 'List orders', 'Create order', 'Logout']);
      expect(client.sentNames, ['Login', 'List orders', 'Create order', 'Logout']);
      expect((await vm.fullRequests(c)).map((r) => r.name), ['Login', 'List orders', 'Create order', 'Logout']);
    });

    test('a request added after the dialog opened does not join the run', () async {
      final client = FakeRunClient();
      vm.dispose();
      vm = CollectionRunnerViewModel(runnerWith(client));
      await vm.load(c);
      await addRequest(repos, c, 'Late arrival', url: 'https://api.test/Late');

      vm.start(c);
      await untilIdle();

      expect(client.sentNames, _expected);
    });
  });

  test('a collection whose rows all share an index (a workspace from before ordering) runs in creation order, folders first',
      () async {
    final legacy = await repos.collectionRepository.createCollection('Legacy');
    await db.customStatement('UPDATE requests SET order_index = 0');
    await db.customStatement('UPDATE folders SET order_index = 0');
    final f = await repos.collectionRepository.createFolder(collectionId: legacy, name: 'Folder');
    await db.customStatement('UPDATE folders SET order_index = 0');
    final r1 = await addRequest(repos, legacy, 'Root first', url: 'https://api.test/RootFirst');
    final inFolder = await addRequest(repos, legacy, 'In folder', folderId: f, url: 'https://api.test/InFolder');
    final r2 = await addRequest(repos, legacy, 'Root second', url: 'https://api.test/RootSecond');
    await db.customStatement('UPDATE requests SET order_index = 0');
    expect([r1, inFolder, r2], everyElement(isPositive));
    final client = FakeRunClient();

    final results = await runnerWith(client).run(legacy).toList();

    // folders first, then the root requests by id: the order the sidebar has always shown such a collection in
    expect(results.map((r) => r.request.name), ['In folder', 'Root first', 'Root second']);
  });
}
