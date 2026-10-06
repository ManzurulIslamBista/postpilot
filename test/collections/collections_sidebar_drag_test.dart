// Moving and reordering from the sidebar: press-and-hold drag with its drop indicators, the menu and the
// "Move to…" list as the keyboard way, undo, and what must not happen (a folder into itself, losing the open tab).
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/collections/presentation/widgets/collections_sidebar.dart';
import 'package:postpilot/features/collections/presentation/widgets/sidebar_drag_drop.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/workplace/presentation/view_models/workplace_view_model.dart';
import 'package:provider/provider.dart';
import '../documentation/support/fakes.dart';
import '../support/fake_workplace_repository.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/in_memory_tree.dart';

const _shop = 1;
const _blog = 2;
const _alpha = 1;
const _bravo = 4;
const _folder = 10;

void main() {
  late InMemoryTree tree;
  late CollectionsViewModel vm;
  late ShellViewModel shell;
  late WorkplaceViewModel workplace;
  late FakeTagRepository tags;
  late TagFilterViewModel tagFilter;
  late AppDatabase database;

  setUp(() {
    tree = InMemoryTree(const [CollectionEntity(id: _shop, name: 'Shop'), CollectionEntity(id: _blog, name: 'Blog')]);
    // Shop: Alpha, [Folder](Xray, Yankee), Bravo        Blog: Post
    tree.addRequest(_shop, 'Alpha', id: _alpha);
    tree.addFolder(_shop, 'Folder', id: _folder);
    tree.addRequest(_shop, 'Xray', folder: _folder, id: 2);
    tree.addRequest(_shop, 'Yankee', folder: _folder, id: 3);
    tree.addRequest(_shop, 'Bravo', id: _bravo);
    tree.addRequest(_blog, 'Post', id: 20);
    tags = FakeTagRepository();
    tagFilter = TagFilterViewModel(tags, tree, tree);
    vm = CollectionsViewModel(tree, tree, requestIdFilter: tagFilter, orderRepository: tree);
    shell = ShellViewModel(tree);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    workplace = WorkplaceViewModel(
      repository: FakeWorkplaceRepository(),
      backupService: InMemoryDb().backupService,
      database: database,
      shellViewModel: shell,
    );
  });

  tearDown(() async {
    vm.dispose();
    tagFilter.dispose();
    shell.dispose();
    workplace.dispose();
    await database.close();
    await tags.close();
    await tree.close();
  });

  Future<void> launch(WidgetTester tester, {Size size = const Size(1200, 900), bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShellViewModel>.value(value: shell),
          ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
          ChangeNotifierProvider<CollectionsViewModel>.value(value: vm),
          ChangeNotifierProvider<TagFilterViewModel>.value(value: tagFilter),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: CollectionsSidebar()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Opens a collection (its content loads from the streams).
  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(SidebarDndRow)).first;
  Rect rect(WidgetTester tester, String name) => tester.getRect(rowOf(name));

  /// Press and hold on [name] until it lifts.
  Future<TestGesture> lift(WidgetTester tester, String name, {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
    final gesture = await tester.startGesture(rect(tester, name).center, kind: kind);
    await tester.pump(SidebarDndRow.holdToDrag + const Duration(milliseconds: 50));
    return gesture;
  }

  /// Moves the held item to [fraction] of the way down [name]'s row.
  Future<void> hover(WidgetTester tester, TestGesture gesture, String name, double fraction) async {
    final r = rect(tester, name);
    await gesture.moveTo(Offset(r.center.dx, r.top + r.height * fraction));
    await tester.pump();
  }

  Future<void> drop(WidgetTester tester, TestGesture gesture) async {
    await gesture.up();
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String name) => tester.getTopLeft(find.text(name)).dy;

  const indicators = [ValueKey('drop-before'), ValueKey('drop-into'), ValueKey('drop-after')];
  Finder indicator(ValueKey<String> key) => find.byKey(key);

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('holding a request and dropping it in front of another reorders them, and Undo puts it back ($label)',
          (tester) async {
        await launch(tester, size: size, dark: dark);
        await open(tester, 'Shop');
        expect(tree.outline(_shop), ['Alpha', '[Folder]', '  Xray', '  Yankee', 'Bravo']);

        final gesture = await lift(tester, 'Bravo');
        await hover(tester, gesture, 'Alpha', 0.2);
        expect(indicator(indicators[0]), findsOneWidget, reason: 'a line in front of Alpha');
        expect(indicator(indicators[1]), findsNothing);
        await drop(tester, gesture);

        expect(tree.outline(_shop), ['Bravo', 'Alpha', '[Folder]', '  Xray', '  Yankee']);
        expect(top(tester, 'Bravo'), lessThan(top(tester, 'Alpha')));
        expect(find.text('Moved "Bravo".'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(tree.outline(_shop), ['Alpha', '[Folder]', '  Xray', '  Yankee', 'Bravo']);
        expect(top(tester, 'Alpha'), lessThan(top(tester, 'Bravo')));
        expect(find.text('Move undone.'), findsOneWidget);
      });
    }
  }

  testWidgets('the lower half of a row means behind it', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Alpha');
    await hover(tester, gesture, 'Bravo', 0.8);
    expect(indicator(indicators[2]), findsOneWidget);
    await drop(tester, gesture);

    expect(tree.outline(_shop), ['[Folder]', '  Xray', '  Yankee', 'Bravo', 'Alpha']);
  });

  testWidgets('the middle of a folder means into it: highlighted, then appended after its content', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Alpha');
    await hover(tester, gesture, 'Folder', 0.5);
    expect(indicator(indicators[1]), findsOneWidget);
    expect(indicator(indicators[0]), findsNothing);
    await drop(tester, gesture);

    expect(tree.outline(_shop), ['[Folder]', '  Xray', '  Yankee', '  Alpha', 'Bravo']);
    expect(find.text('Moved "Alpha" to "Folder".'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget, reason: 'the folder stays open so the request stays in view');
  });

  testWidgets('the edges of a folder row are in front of it and behind it; behind an open folder is its top', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    var gesture = await lift(tester, 'Bravo');
    await hover(tester, gesture, 'Folder', 0.1);
    expect(indicator(indicators[0]), findsOneWidget);
    await drop(tester, gesture);
    expect(tree.outline(_shop), ['Alpha', 'Bravo', '[Folder]', '  Xray', '  Yankee']);

    gesture = await lift(tester, 'Alpha');
    await hover(tester, gesture, 'Folder', 0.9);
    expect(indicator(indicators[2]), findsOneWidget);
    await drop(tester, gesture);
    expect(tree.outline(_shop), ['Bravo', '[Folder]', '  Alpha', '  Xray', '  Yankee']);
  });

  testWidgets('out of a folder to the top level, in front of a root request', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Yankee');
    await hover(tester, gesture, 'Bravo', 0.2);
    await drop(tester, gesture);

    expect(tree.outline(_shop), ['Alpha', '[Folder]', '  Xray', 'Yankee', 'Bravo']);
  });

  testWidgets('a closed folder opens by itself when something rests on it', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');
    await tester.tap(find.text('Folder'));
    await tester.pump();
    expect(find.text('Xray'), findsNothing, reason: 'closed');

    final gesture = await lift(tester, 'Bravo');
    await hover(tester, gesture, 'Folder', 0.5);
    expect(find.text('Xray'), findsNothing, reason: 'not yet');
    await tester.pump(SidebarDndRow.hoverToOpen + const Duration(milliseconds: 100));

    expect(find.text('Xray'), findsOneWidget);
    expect(find.text('Yankee'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a closed collection opens when something rests on it, and a drop on it goes to its top level',
      (tester) async {
    await launch(tester);
    await open(tester, 'Shop');
    expect(find.text('Post'), findsNothing);

    final gesture = await lift(tester, 'Alpha');
    await hover(tester, gesture, 'Blog', 0.5);
    expect(indicator(indicators[1]), findsOneWidget);
    await tester.pump(SidebarDndRow.hoverToOpen + const Duration(milliseconds: 100));
    expect(find.text('Post'), findsOneWidget);
    await drop(tester, gesture);

    expect(tree.locationOf(_alpha).collectionId, _blog);
    expect(tree.outline(_blog), ['Post', 'Alpha']);
    expect(find.textContaining('now comes from "Blog"'), findsOneWidget, reason: 'it says what the move changes');
  });

  testWidgets('a folder cannot be dropped on itself or on anything inside it: nothing lights up, nothing moves',
      (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Folder');
    for (final over in const ['Folder', 'Xray', 'Yankee']) {
      await hover(tester, gesture, over, 0.5);
      for (final key in indicators) {
        expect(indicator(key), findsNothing, reason: 'over $over');
      }
    }
    await hover(tester, gesture, 'Xray', 0.1);
    await drop(tester, gesture);

    expect(tree.moveCalls, isEmpty);
    expect(tree.outline(_shop), ['Alpha', '[Folder]', '  Xray', '  Yankee', 'Bravo']);
  });

  testWidgets('a folder can still be dropped beside its siblings', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Folder');
    await hover(tester, gesture, 'Alpha', 0.2);
    expect(indicator(indicators[0]), findsOneWidget);
    await drop(tester, gesture);

    expect(tree.outline(_shop), ['[Folder]', '  Xray', '  Yankee', 'Alpha', 'Bravo']);
  });

  testWidgets('a drop outside any row moves nothing', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Alpha');
    await gesture.moveTo(const Offset(1100, 850));
    await tester.pump();
    await drop(tester, gesture);

    expect(tree.moveCalls, isEmpty);
  });

  testWidgets('a quick tap still opens the request, only a hold lifts it', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    await tester.tap(find.text('Alpha'));
    await tester.pump();

    expect(shell.selectedRequestId, _alpha);
    expect(tree.moveCalls, isEmpty);
  });

  testWidgets('a mouse picks a row up by pressing and holding too', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');

    final gesture = await lift(tester, 'Bravo', kind: PointerDeviceKind.mouse);
    await hover(tester, gesture, 'Alpha', 0.2);
    await drop(tester, gesture);

    expect(tree.outline(_shop), ['Bravo', 'Alpha', '[Folder]', '  Xray', '  Yankee']);
  });

  testWidgets('the open request keeps its tab and stays selected when it is moved', (tester) async {
    await launch(tester);
    await open(tester, 'Shop');
    await tester.tap(find.text('Bravo'));
    await tester.pump();
    expect(shell.openRequestIds, [_bravo]);

    final gesture = await lift(tester, 'Bravo');
    await hover(tester, gesture, 'Folder', 0.5);
    await drop(tester, gesture);

    expect(tree.locationOf(_bravo).folderId, _folder);
    expect(shell.selectedRequestId, _bravo);
    expect(shell.openRequestIds, [_bravo]);
  });

  testWidgets('while searching or filtering nothing can be lifted, since the rows shown are not the whole level',
      (tester) async {
    await launch(tester);
    await open(tester, 'Shop');
    await tester.enterText(find.byType(TextField).first, 'a');
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Alpha')));
    await tester.pump(SidebarDndRow.holdToDrag + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tree.moveCalls, isEmpty);
  });

  group('menus, the way that does not need a pointer to drag', () {
    Future<void> choose(WidgetTester tester, String row, String entry) async {
      await tester.tap(find.descendant(of: rowOf(row), matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
    }

    testWidgets('Move up and Move down swap a request with its neighbour', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      await choose(tester, 'Bravo', 'Move up');
      expect(tree.outline(_shop), ['Alpha', 'Bravo', '[Folder]', '  Xray', '  Yankee']);

      await choose(tester, 'Alpha', 'Move down');
      expect(tree.outline(_shop), ['Bravo', 'Alpha', '[Folder]', '  Xray', '  Yankee']);
    });

    testWidgets('the first has no Move up, the last no Move down', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      await tester.tap(find.descendant(of: rowOf('Alpha'), matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, 'Move up')).enabled, isFalse);
      expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, 'Move down')).enabled, isTrue);
    });

    testWidgets('folders move up and down too', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      await choose(tester, 'Folder', 'Move up');

      expect(tree.outline(_shop), ['[Folder]', '  Xray', '  Yankee', 'Alpha', 'Bravo']);
    });

    testWidgets('Move to… lists every collection and folder; the choice gets the item at its end', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      await choose(tester, 'Alpha', 'Move to…');
      expect(find.text('Move "Alpha" to…'), findsOneWidget);
      for (final place in const ['Shop', 'Folder', 'Blog']) {
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(place)), findsOneWidget, reason: place);
      }
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Folder')));
      await tester.pumpAndSettle();

      expect(tree.outline(_shop), ['[Folder]', '  Xray', '  Yankee', '  Alpha', 'Bravo']);
      expect(find.text('Moved "Alpha" to "Folder".'), findsOneWidget);
    });

    testWidgets('Move to… another collection says what changes, and offers Undo', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      await choose(tester, 'Bravo', 'Move to…');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Blog')));
      await tester.pumpAndSettle();

      expect(tree.locationOf(_bravo).collectionId, _blog);
      expect(find.textContaining('variables, auth'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tree.locationOf(_bravo).collectionId, _shop);
    });

    testWidgets('Move to… will not offer a folder its own inside', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');
      tree.addFolder(_shop, 'Inner', parent: _folder);
      await tester.pump();

      await choose(tester, 'Folder', 'Move to…');

      final own = find.widgetWithText(ListTile, 'Folder');
      expect(tester.widget<ListTile>(own.last).enabled, isFalse);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Inner').last).enabled, isFalse);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Shop').last).enabled, isTrue);
      expect(find.text("A folder can't go inside itself"), findsNWidgets(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tree.moveCalls, isEmpty);
    });

    testWidgets('a refused move says why instead of failing quietly', (tester) async {
      await launch(tester);
      await open(tester, 'Shop');

      final outcome = await vm.moveFolder(_folder, collectionId: _shop, parentFolderId: _folder);

      expect(outcome.error, contains('itself'));
      expect(outcome.moved, isFalse);
    });
  });

  testWidgets('without an order repository the rows cannot be lifted and have no move entries', (tester) async {
    final readOnly = CollectionsViewModel(tree, tree);
    addTearDown(readOnly.dispose);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShellViewModel>.value(value: shell),
          ChangeNotifierProvider<WorkplaceViewModel>.value(value: workplace),
          ChangeNotifierProvider<CollectionsViewModel>.value(value: readOnly),
          ChangeNotifierProvider<TagFilterViewModel>.value(value: tagFilter),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: CollectionsSidebar())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Shop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LongPressDraggable<SidebarDragItem>), findsNothing);
    await tester.tap(find.descendant(of: find.ancestor(of: find.text('Bravo'), matching: find.byType(InkWell)).first, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });
}
