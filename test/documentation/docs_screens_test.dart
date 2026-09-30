import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/documentation/presentation/view_models/all_tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/collection_docs_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/entity_docs_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/widgets/collection_docs_dialog.dart';
import 'package:postpilot/features/documentation/presentation/widgets/entity_description_dialog.dart';
import 'package:postpilot/features/documentation/presentation/widgets/request_docs_tab.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';

const _markdownField = ValueKey('markdown-editor-field');
const _tagsField = ValueKey('tags-editor-field');
const _debounce = Duration(milliseconds: 500);

/// A collection-auth store that answers only once [gate] has completed.
class _GatedAuthRepository extends FakeCollectionAuthRepository {
  final Future<void>? gate;
  const _GatedAuthRepository(this.gate);

  @override
  Future<String?> getAuthJson(int collectionId) async {
    await gate;
    return null;
  }
}

void main() {
  late FakeDocumentationRepository docs;
  late FakeTagRepository tags;

  setUp(() {
    docs = FakeDocumentationRepository();
    tags = FakeTagRepository();
    locator
      ..registerFactoryParam<EntityDocsViewModel, EntityKind, int>((kind, id) => EntityDocsViewModel(docs, kind, id))
      ..registerFactoryParam<TagsViewModel, EntityKind, int>((kind, id) => TagsViewModel(tags, kind, id))
      ..registerFactory<AllTagsViewModel>(() => AllTagsViewModel(tags));
  });

  tearDown(() async {
    await locator.reset();
    await tags.close();
  });

  Widget scrollable(Widget child) => themedApp(SingleChildScrollView(padding: const EdgeInsets.all(12), child: child));

  Future<void> submitTag(WidgetTester tester, String tag) async {
    await tester.enterText(find.byKey(_tagsField), tag);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  group('RequestDocsTab', () {
    testWidgets('loads the description and the tags of the request', (tester) async {
      docs.seed(EntityKind.request, 7, '# Stored docs');
      tags.seed(EntityKind.request, 7, ['v2', 'auth']);
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('# Stored docs'), findsOneWidget);
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('auth'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
    });

    testWidgets('shows the empty state for a request with no docs or tags', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 1)));
      await tester.pump();

      expect(find.byKey(_markdownField), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves the description 500 ms after typing stops', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await tester.enterText(find.byKey(_markdownField), 'New description');
      await tester.pump(const Duration(milliseconds: 499));
      expect(docs.writes, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(docs.writes, [(EntityKind.request, 7, 'New description')]);
      expect(docs.stored(EntityKind.request, 7), 'New description');
    });

    testWidgets('saves what is pending as soon as the tab goes away', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();
      await tester.enterText(find.byKey(_markdownField), 'unsaved words');
      expect(docs.writes, isEmpty);

      await tester.pumpWidget(themedApp(const SizedBox()));
      await tester.pump();

      expect(docs.stored(EntityKind.request, 7), 'unsaved words');
    });

    testWidgets('saves what is pending when the app goes to the background or is closed', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();
      await tester.enterText(find.byKey(_markdownField), 'about to leave');
      expect(docs.writes, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(docs.stored(EntityKind.request, 7), 'about to leave');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(_debounce * 2);
      expect(docs.writes, hasLength(1));
    });

    testWidgets('showing another request saves the first and starts fresh', (tester) async {
      docs.seed(EntityKind.request, 2, 'two');
      tags.seed(EntityKind.request, 2, ['only-two']);
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 1)));
      await tester.pump();
      await tester.enterText(find.byKey(_markdownField), 'one edited');

      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 2)));
      await tester.pump();

      expect(docs.stored(EntityKind.request, 1), 'one edited');
      expect(find.text('two'), findsOneWidget);
      expect(find.text('one edited'), findsNothing);
      expect(find.text('only-two'), findsOneWidget);
    });

    testWidgets('a tag typed in is added, shown and stored', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await submitTag(tester, '  v2 ');

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
      expect(tags.tagsFor(EntityKind.request, 7), ['v2']);
    });

    testWidgets('a duplicate tag is not added twice', (tester) async {
      tags.seed(EntityKind.request, 7, ['v2']);
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await submitTag(tester, 'V2');

      expect(find.byType(InputChip), findsOneWidget);
      expect(tags.writes, isEmpty);
    });

    testWidgets('a tag is removed with its x', (tester) async {
      tags.seed(EntityKind.request, 7, ['v2', 'v3']);
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('tag-v2')), matching: find.byIcon(Icons.close)));
      await tester.pump();

      expect(find.text('v2'), findsNothing);
      expect(tags.tagsFor(EntityKind.request, 7), ['v3']);
    });

    testWidgets('offers the tags used elsewhere and adds one on tap', (tester) async {
      tags
        ..seed(EntityKind.folder, 1, ['from-folder'])
        ..seed(EntityKind.request, 99, ['from-other-request']);
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      expect(find.byKey(const ValueKey('suggestion-from-folder')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-from-other-request')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('suggestion-from-folder')));
      await tester.pump();

      expect(tags.tagsFor(EntityKind.request, 7), ['from-folder']);
      expect(find.byKey(const ValueKey('suggestion-from-folder')), findsNothing);
    });

    testWidgets('typing in the description is not disturbed by tag changes', (tester) async {
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();
      await tester.enterText(find.byKey(_markdownField), 'draft text');

      await submitTag(tester, 'v2');

      expect(find.text('draft text'), findsOneWidget);
    });

    testWidgets('tells the user when the description could not be saved', (tester) async {
      docs.failWith = 'disk full';
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await tester.enterText(find.byKey(_markdownField), 'x');
      await tester.pump(_debounce);
      await tester.pump();

      expect(find.textContaining('Could not save the description'), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
    });

    testWidgets('tells the user when the tags could not be saved and puts the chips back', (tester) async {
      tags.failWith = 'disk full';
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await submitTag(tester, 'v2');
      await tester.pump();

      expect(find.textContaining('Could not save the tags'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('previewing shows the rendered description', (tester) async {
      docs.seed(EntityKind.request, 7, '# Heading\n\n- a\n- b');
      await tester.pumpWidget(scrollable(const RequestDocsTab(requestId: 7)));
      await tester.pump();

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(find.text('Heading', findRichText: true), findsOneWidget);
      expect(find.text('a', findRichText: true), findsOneWidget);
    });
  });

  group('EntityDescriptionDialog', () {
    Future<void> open(WidgetTester tester, {EntityKind kind = EntityKind.folder, int id = 5, String title = 'Users'}) async {
      await tester.pumpWidget(themedApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => EntityDescriptionDialog.show(context, kind, id, title),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('names what is being edited', (tester) async {
      useLargeWindow(tester);
      await open(tester, title: 'Admin folder');

      expect(find.text('Description & tags'), findsOneWidget);
      expect(find.text('Admin folder'), findsOneWidget);
      expect(find.byKey(_markdownField), findsOneWidget);
      expect(find.byKey(_tagsField), findsOneWidget);
    });

    testWidgets('shows the stored description and tags of a folder', (tester) async {
      useLargeWindow(tester);
      docs.seed(EntityKind.folder, 5, 'Folder docs');
      tags.seed(EntityKind.folder, 5, ['v3']);
      tags.seed(EntityKind.request, 5, ['not-this-one']);
      await open(tester);
      await tester.pump();

      expect(find.text('Folder docs'), findsOneWidget);
      expect(find.text('v3'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('closing it with the x saves what was typed', (tester) async {
      useLargeWindow(tester);
      await open(tester);
      await tester.pump();

      await tester.enterText(find.byKey(_markdownField), 'typed just now');
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(EntityDescriptionDialog), findsNothing);
      expect(docs.stored(EntityKind.folder, 5), 'typed just now');
    });

    testWidgets('dismissing it by tapping outside saves too', (tester) async {
      useLargeWindow(tester);
      await open(tester);
      await tester.pump();

      await tester.enterText(find.byKey(_markdownField), 'typed just now');
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(EntityDescriptionDialog), findsNothing);
      expect(docs.stored(EntityKind.folder, 5), 'typed just now');
    });

    testWidgets('edits a collection under its own kind', (tester) async {
      useLargeWindow(tester);
      await open(tester, kind: EntityKind.collection, id: 3, title: 'Shop');
      await tester.pump();

      await tester.enterText(find.byKey(_markdownField), 'about the shop');
      await submitTag(tester, 'public');
      await tester.pump(_debounce);

      expect(docs.stored(EntityKind.collection, 3), 'about the shop');
      expect(tags.tagsFor(EntityKind.collection, 3), ['public']);
      expect(docs.stored(EntityKind.folder, 3), isNull);
    });

    testWidgets('fits a small window without overflowing', (tester) async {
      tester.view.physicalSize = const Size(420, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tags.seed(EntityKind.folder, 5, List.generate(12, (i) => 'tag-number-$i'));
      await open(tester, title: 'A very long folder name ' * 8);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(EntityDescriptionDialog), findsOneWidget);
    });
  });

  group('CollectionDocsDialog', () {
    late List<({String fileName, String text, String mimeType})> saved;
    String? clipboard;

    setUp(() {
      saved = [];
      clipboard = null;
    });

    /// [gate], when given, holds the documentation back until it completes.
    void registerDocs(
      WidgetTester tester, {
      int requests = 1,
      String? savedPath = r'C:\Downloads\Shop docs.md',
      Future<void>? gate,
    }) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final useCase = BuildApiDocsUseCase(
        FakeCollectionRepository(
          collections: const [CollectionEntity(id: 1, name: 'Shop')],
          folders: {
            1: [folderEntity(10, name: 'Users')],
          },
        ),
        FakeRequestRepository({
          1: [
            for (var i = 0; i < requests; i++)
              requestEntity(100 + i, folderId: i == 0 ? 10 : null, name: i == 0 ? 'List users' : 'Request $i', url: '/r$i', method: HttpMethod.get),
          ],
        }),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        _GatedAuthRepository(gate),
        docs..seed(EntityKind.collection, 1, 'Everything about the **shop**.'),
        tags,
      );
      locator.registerFactory<CollectionDocsViewModel>(
        () => CollectionDocsViewModel(
          useCase,
          saveFile: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
            saved.add((fileName: fileName, text: utf8.decode(bytes), mimeType: mimeType));
            return savedPath;
          },
        ),
      );
    }

    Future<void> open(WidgetTester tester, {int collectionId = 1}) async {
      useLargeWindow(tester);
      await tester.pumpWidget(themedApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => CollectionDocsDialog.show(context, collectionId: collectionId, collectionName: 'Shop'),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    OutlinedButton button(WidgetTester tester, String label) =>
        tester.widget<OutlinedButton>(find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)));

    testWidgets('shows a progress indicator, then the rendered documentation', (tester) async {
      final gate = Completer<void>();
      registerDocs(tester, gate: gate.future);
      await open(tester);

      expect(find.text('Documentation · Shop'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Users', findRichText: true), findsNothing);

      gate.complete();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Shop', findRichText: true), findsOneWidget);
      expect(find.text('Everything about the shop.', findRichText: true), findsOneWidget);
      expect(find.text('Users', findRichText: true), findsOneWidget);
      expect(find.text('List users', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the three buttons wait for the documentation', (tester) async {
      final gate = Completer<void>();
      registerDocs(tester, gate: gate.future);
      await open(tester);

      expect(button(tester, 'Copy Markdown').onPressed, isNull);
      expect(button(tester, 'Download .md').onPressed, isNull);
      expect(button(tester, 'Download .html').onPressed, isNull);

      gate.complete();
      await tester.pump();

      expect(button(tester, 'Copy Markdown').onPressed, isNotNull);
      expect(button(tester, 'Download .md').onPressed, isNotNull);
      expect(button(tester, 'Download .html').onPressed, isNotNull);
    });

    testWidgets('Copy Markdown puts the markdown on the clipboard and says so', (tester) async {
      registerDocs(tester);
      await open(tester);
      await tester.pump();

      await tester.tap(find.text('Copy Markdown'));
      await tester.pump();

      expect(clipboard, startsWith('# Shop\n'));
      expect(clipboard, contains('## Users'));
      expect(clipboard, contains('### List users'));
      expect(find.text('Markdown copied to the clipboard'), findsOneWidget);
    });

    testWidgets('Download .md saves the markdown and shows where it went', (tester) async {
      registerDocs(tester);
      await open(tester);
      await tester.pump();

      await tester.tap(find.text('Download .md'));
      await tester.pump();

      expect(saved.single.fileName, 'Shop docs.md');
      expect(saved.single.text, startsWith('# Shop\n'));
      expect(find.text(r'Saved to C:\Downloads\Shop docs.md'), findsOneWidget);
    });

    testWidgets('Download .html saves a self-contained page', (tester) async {
      registerDocs(tester, savedPath: null);
      await open(tester);
      await tester.pump();

      await tester.tap(find.text('Download .html'));
      await tester.pump();

      expect(saved.single.fileName, 'Shop docs.html');
      expect(saved.single.text, startsWith('<!doctype html>'));
      expect(saved.single.text, contains('<h1>Shop</h1>'));
      expect(find.text('Download started'), findsOneWidget);
    });

    testWidgets('an unknown collection shows the reason and keeps the buttons off', (tester) async {
      registerDocs(tester);
      await open(tester, collectionId: 42);
      await tester.pump();

      expect(find.text('Collection not found.'), findsOneWidget);
      expect(button(tester, 'Copy Markdown').onPressed, isNull);
      expect(button(tester, 'Download .md').onPressed, isNull);
    });

    testWidgets('a big collection is previewed without building all of it at once', (tester) async {
      registerDocs(tester, requests: 300);
      await open(tester);
      await tester.pump();

      expect(find.text('Request 299', findRichText: true), findsNothing);
      expect(find.byType(RichText).evaluate().length, lessThan(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the x closes it', (tester) async {
      registerDocs(tester);
      await open(tester);
      await tester.pump();

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CollectionDocsDialog), findsNothing);
    });
  });
}
