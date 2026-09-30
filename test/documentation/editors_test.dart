import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/documentation/presentation/widgets/markdown_editor.dart';
import 'package:postpilot/features/documentation/presentation/widgets/tag_filter_bar.dart';
import 'package:postpilot/features/documentation/presentation/widgets/tags_editor.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';

const _markdownField = ValueKey('markdown-editor-field');
const _tagsField = ValueKey('tags-editor-field');

void main() {
  group('MarkdownEditor', () {
    testWidgets('starts with the given text and reports each edit', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(themedApp(SingleChildScrollView(
        child: MarkdownEditor(initialValue: '# Hi', onChanged: changes.add),
      )));

      expect(find.text('# Hi'), findsOneWidget);
      await tester.enterText(find.byKey(_markdownField), '# Hello\n\n**bold**');

      expect(changes, ['# Hello\n\n**bold**']);
    });

    testWidgets('previews the rendered markdown and comes back to the same text', (tester) async {
      await tester.pumpWidget(themedApp(SingleChildScrollView(
        child: MarkdownEditor(initialValue: '', onChanged: (_) {}),
      )));
      await tester.enterText(find.byKey(_markdownField), '# Hello\n\nSome **bold** text');

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(find.byKey(_markdownField), findsNothing);
      expect(find.text('Hello', findRichText: true), findsOneWidget);
      expect(find.text('Some bold text', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pump();

      expect(find.byKey(_markdownField), findsOneWidget);
      expect(find.text('# Hello\n\nSome **bold** text'), findsOneWidget);
    });

    testWidgets('says so when there is nothing to preview', (tester) async {
      await tester.pumpWidget(themedApp(SingleChildScrollView(
        child: MarkdownEditor(initialValue: '  \n ', onChanged: (_) {}),
      )));

      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(find.text('Nothing to preview yet.'), findsOneWidget);
    });

    testWidgets('the edit box grows with its text instead of scrolling inside', (tester) async {
      await tester.pumpWidget(themedApp(SingleChildScrollView(
        child: MarkdownEditor(initialValue: List.generate(60, (i) => 'line $i').join('\n'), onChanged: (_) {}),
      )));

      expect(tester.getSize(find.byKey(_markdownField)).height, greaterThan(600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a hint while empty', (tester) async {
      await tester.pumpWidget(themedApp(SingleChildScrollView(
        child: MarkdownEditor(initialValue: '', onChanged: (_) {}, hintText: 'Describe it'),
      )));

      expect(find.text('Describe it'), findsOneWidget);
    });
  });

  group('TagsEditor', () {
    late List<String> added;
    late List<String> removed;

    setUp(() {
      added = [];
      removed = [];
    });

    Future<void> pump(
      WidgetTester tester, {
      List<String> tags = const [],
      List<String> suggestions = const [],
    }) =>
        tester.pumpWidget(themedApp(SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TagsEditor(tags: tags, suggestions: suggestions, onAdd: added.add, onRemove: removed.add),
        )));

    testWidgets('Enter adds the typed tag, clears the box and keeps the focus', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), '  v2 ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(added, ['v2']);
      expect(find.text('  v2 '), findsNothing);
      expect(tester.widget<TextField>(find.byKey(_tagsField)).controller!.text, isEmpty);
      expect(tester.widget<TextField>(find.byKey(_tagsField)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('Enter on an empty box adds nothing', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(added, isEmpty);
    });

    testWidgets('a comma adds everything before it and keeps what comes after', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), 'a, b ,c');

      expect(added, ['a', 'b']);
      expect(tester.widget<TextField>(find.byKey(_tagsField)).controller!.text, 'c');
    });

    testWidgets('a trailing comma leaves the box empty', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), 'v3,');

      expect(added, ['v3']);
      expect(tester.widget<TextField>(find.byKey(_tagsField)).controller!.text, isEmpty);
    });

    testWidgets('commas with nothing between them add nothing', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), ', ,,');

      expect(added, isEmpty);
    });

    testWidgets('leaving the box adds what was typed', (tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(_tagsField), 'blurred');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(added, ['blurred']);
      expect(tester.widget<TextField>(find.byKey(_tagsField)).controller!.text, isEmpty);
    });

    testWidgets('shows a chip per tag and removes one with its x', (tester) async {
      await pump(tester, tags: ['alpha', 'beta']);

      expect(find.byType(InputChip), findsNWidgets(2));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('tag-alpha')), matching: find.byIcon(Icons.close)));
      await tester.pump();

      expect(removed, ['alpha']);
    });

    testWidgets('offers tags in use elsewhere, minus the ones already on the entity', (tester) async {
      await pump(tester, tags: ['Alpha'], suggestions: ['alpha', 'gamma', 'delta']);

      expect(find.byType(ActionChip), findsNWidgets(2));
      expect(find.byKey(const ValueKey('suggestion-gamma')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-delta')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-alpha')), findsNothing);
    });

    testWidgets('narrows the suggestions to what is being typed, ignoring case', (tester) async {
      await pump(tester, suggestions: ['alpha', 'gamma', 'delta']);

      await tester.enterText(find.byKey(_tagsField), 'DEL');
      await tester.pump();

      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-delta')), findsOneWidget);
    });

    testWidgets('tapping a suggestion adds it', (tester) async {
      await pump(tester, suggestions: ['gamma']);

      await tester.tap(find.byKey(const ValueKey('suggestion-gamma')));
      await tester.pump();

      expect(added, ['gamma']);
    });

    testWidgets('lists at most twelve suggestions and none when there are none', (tester) async {
      await pump(tester, suggestions: List.generate(20, (i) => 'tag$i'));
      expect(find.byType(ActionChip), findsNWidgets(12));

      await pump(tester);
      expect(find.text('Suggestions'), findsNothing);
    });

    testWidgets('removing the widget while text is typed is safe', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(_tagsField), 'half typed');

      await tester.pumpWidget(themedApp(const SizedBox()));

      expect(tester.takeException(), isNull);
    });
  });

  group('TagFilterBar', () {
    late FakeTagRepository tags;
    late TagFilterViewModel filter;

    setUp(() => tags = FakeTagRepository());

    tearDown(() => tags.close());

    // The view model listens to streams, so it is made inside the test, in the
    // tester's fake-async zone, where pump() can deliver their events.
    Future<void> pump(WidgetTester tester) async {
      filter = TagFilterViewModel(
        tags,
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Shop')]),
        FakeRequestRepository({
          1: [requestEntity(1), requestEntity(2)],
        }),
      );
      addTearDown(filter.dispose);
      await tester.pumpWidget(themedApp(
        ChangeNotifierProvider<TagFilterViewModel>.value(
          value: filter,
          child: const Column(children: [TagFilterBar(), Text('below')]),
        ),
      ));
      await tester.pump();
    }

    testWidgets('is not there while no tag exists', (tester) async {
      await pump(tester);

      expect(find.byType(FilterChip), findsNothing);
      expect(tester.getSize(find.byType(TagFilterBar)).height, 0);
    });

    testWidgets('shows All and every tag, with All selected', (tester) async {
      tags
        ..seed(EntityKind.request, 1, ['v2'])
        ..seed(EntityKind.folder, 5, ['v3', 'beta']);
      await tags.setTags(EntityKind.request, 2, ['v2']);
      await pump(tester);

      expect(find.byType(FilterChip), findsNWidgets(4));
      expect(find.text('All'), findsOneWidget);
      for (final label in ['beta', 'v2', 'v3']) {
        expect(find.text(label), findsOneWidget);
      }
      FilterChip chip(String label) => tester.widget<FilterChip>(find.byKey(ValueKey('tag-filter-$label')));
      expect(chip('All').selected, isTrue);
      expect(chip('v2').selected, isFalse);
    });

    testWidgets('tapping tags selects them, any number, and All clears them', (tester) async {
      await tags.setTags(EntityKind.request, 1, ['v2']);
      await tags.setTags(EntityKind.request, 2, ['v3']);
      await pump(tester);
      FilterChip chip(String label) => tester.widget<FilterChip>(find.byKey(ValueKey('tag-filter-$label')));

      await tester.tap(find.text('v2'));
      await tester.pump();
      expect(filter.selectedTags, {'v2'});
      expect(chip('v2').selected, isTrue);
      expect(chip('All').selected, isFalse);

      await tester.tap(find.text('v3'));
      await tester.pump();
      expect(filter.selectedTags, {'v2', 'v3'});
      expect(chip('v3').selected, isTrue);

      await tester.tap(find.text('v2'));
      await tester.pump();
      expect(filter.selectedTags, {'v3'});

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(filter.isFiltering, isFalse);
      expect(chip('All').selected, isTrue);
      expect(chip('v3').selected, isFalse);
    });

    testWidgets('the filter narrows the requests that match', (tester) async {
      await tags.setTags(EntityKind.request, 1, ['v2']);
      await pump(tester);

      await tester.tap(find.text('v2'));
      await tester.pump();

      expect(filter.matchingRequestIds, {1});
    });

    testWidgets('many tags scroll sideways without overflowing', (tester) async {
      await tags.setTags(EntityKind.request, 1, [for (var t = 0; t < 40; t++) 'tag-${t.toString().padLeft(2, '0')}']);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tag-filter-tag-39')), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(-5000, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('tag-filter-tag-39')), findsOneWidget);
    });

    testWidgets('a tag that disappears takes its chip and its selection with it', (tester) async {
      await tags.setTags(EntityKind.request, 1, ['v2']);
      await tags.setTags(EntityKind.request, 2, ['v3']);
      await pump(tester);
      await tester.tap(find.text('v3'));
      await tester.pump();

      await tags.setTags(EntityKind.request, 2, []);
      await tester.pump();

      expect(find.text('v3'), findsNothing);
      expect(filter.isFiltering, isFalse);
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('tag-filter-All'))).selected, isTrue);
    });
  });
}
