import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/entity_docs_view_model.dart';

import 'support/fakes.dart';

void main() {
  const debounce = Duration(milliseconds: 500);

  // The tests that watch the clock run in the widget tester's fake time; the
  // view model is disposed in each of them so no timer is left running.
  group('loading', () {
    testWidgets('shows what is stored, and empty when nothing is', (tester) async {
      final repo = FakeDocumentationRepository()..seed(EntityKind.folder, 3, '# Stored');
      final stored = EntityDocsViewModel(repo, EntityKind.folder, 3);
      final empty = EntityDocsViewModel(repo, EntityKind.folder, 4);
      expect(stored.isLoading, isTrue);

      await tester.pump();

      expect(stored.isLoading, isFalse);
      expect(stored.markdown, '# Stored');
      expect(empty.isLoading, isFalse);
      expect(empty.markdown, '');
      stored.dispose();
      empty.dispose();
    });

    testWidgets('text typed before the load finished is not overwritten by it', (tester) async {
      final repo = FakeDocumentationRepository()..seed(EntityKind.request, 1, 'stored');
      final vm = EntityDocsViewModel(repo, EntityKind.request, 1);
      vm.update('typed');

      await tester.pump();

      expect(vm.markdown, 'typed');
      await tester.pump(debounce);
      expect(repo.stored(EntityKind.request, 1), 'typed');
      vm.dispose();
    });
  });

  group('auto-save', () {
    testWidgets('saves once, 500 ms after the last keystroke', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('a');
      await tester.pump(const Duration(milliseconds: 300));
      vm.update('ab');
      await tester.pump(const Duration(milliseconds: 300));
      vm.update('abc');
      await tester.pump(const Duration(milliseconds: 499));
      expect(repo.writes, isEmpty, reason: 'still inside the quiet period of the last edit');

      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.writes, [(EntityKind.request, 7, 'abc')]);

      await tester.pump(const Duration(seconds: 5));
      expect(repo.writes, hasLength(1));
      vm.dispose();
    });

    testWidgets('a second burst is saved separately', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('one');
      await tester.pump(debounce);
      vm.update('two');
      await tester.pump(debounce);

      expect(repo.writes.map((w) => w.$3), ['one', 'two']);
      vm.dispose();
    });

    testWidgets('the debounce can be shortened', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7, debounce: const Duration(milliseconds: 50));
      await tester.pump();

      vm.update('quick');
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.writes, hasLength(1));
      vm.dispose();
    });

    testWidgets('does not save text that never changed', (tester) async {
      final repo = FakeDocumentationRepository()..seed(EntityKind.request, 7, 'same');
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('same');
      await tester.pump(debounce * 2);
      await vm.flush();

      expect(repo.writes, isEmpty);
      vm.dispose();
    });

    testWidgets('clearing the text saves an empty document, which removes it', (tester) async {
      final repo = FakeDocumentationRepository()..seed(EntityKind.request, 7, 'old');
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('');
      await tester.pump(debounce);

      expect(repo.writes, [(EntityKind.request, 7, '')]);
      expect(repo.stored(EntityKind.request, 7), isNull);
      vm.dispose();
    });

    testWidgets('each entity saves under its own kind and id', (tester) async {
      final repo = FakeDocumentationRepository();
      final folder = EntityDocsViewModel(repo, EntityKind.folder, 1);
      final collection = EntityDocsViewModel(repo, EntityKind.collection, 1);
      await tester.pump();

      folder.update('folder text');
      collection.update('collection text');
      await tester.pump(debounce);

      expect(repo.stored(EntityKind.folder, 1), 'folder text');
      expect(repo.stored(EntityKind.collection, 1), 'collection text');
      folder.dispose();
      collection.dispose();
    });
  });

  group('flush', () {
    testWidgets('flush() saves at once and cancels the wait', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('now');
      await vm.flush();
      expect(repo.writes, hasLength(1));

      await tester.pump(debounce * 2);
      expect(repo.writes, hasLength(1));
      vm.dispose();
    });

    testWidgets('disposing saves what is still waiting, straight away', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('last words');
      vm.dispose();

      expect(repo.writes, [(EntityKind.request, 7, 'last words')]);
      await tester.pump(debounce * 2);
      expect(repo.writes, hasLength(1), reason: 'the timer must not save it a second time');
    });

    testWidgets('disposing with nothing waiting writes nothing', (tester) async {
      final repo = FakeDocumentationRepository();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('saved');
      await tester.pump(debounce);
      vm.dispose();

      expect(repo.writes, hasLength(1));
    });

    testWidgets('disposing before the load finished still saves the typed text', (tester) async {
      final repo = FakeDocumentationRepository()..seed(EntityKind.request, 7, 'stored');
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      vm.update('typed early');
      vm.dispose();
      await tester.pump();

      expect(repo.stored(EntityKind.request, 7), 'typed early');
    });
  });

  group('failures', () {
    testWidgets('a failed save is reported and retried on the next flush', (tester) async {
      final repo = FakeDocumentationRepository()..failWith = 'disk full';
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('x');
      await vm.flush();
      expect(vm.saveError, contains('disk full'));
      expect(repo.stored(EntityKind.request, 7), isNull);

      repo.failWith = null;
      await vm.flush();
      expect(vm.saveError, isNull);
      expect(repo.stored(EntityKind.request, 7), 'x');
      vm.dispose();
    });

    testWidgets('a failure in the background timer does not escape as an error', (tester) async {
      final repo = FakeDocumentationRepository()..failWith = 'disk full';
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('x');
      await tester.pump(debounce);

      expect(vm.saveError, isNotNull);
      expect(tester.takeException(), isNull);
      repo.failWith = null;
      vm.dispose();
      await tester.pump();
      expect(repo.stored(EntityKind.request, 7), 'x');
    });

    testWidgets('a save that finishes after dispose does not notify', (tester) async {
      final repo = FakeDocumentationRepository()..holdWrites = Completer<void>();
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();

      vm.update('x');
      final saving = vm.flush();
      vm.dispose();
      repo.failWith = 'late failure';
      repo.holdWrites!.complete();
      await saving;
      expect(repo.writes, hasLength(1));
    });

    testWidgets('notifies when the save error appears and when it clears', (tester) async {
      final repo = FakeDocumentationRepository()..failWith = 'nope';
      final vm = EntityDocsViewModel(repo, EntityKind.request, 7);
      await tester.pump();
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.update('x');
      await vm.flush();
      expect(notifications, 1);
      await vm.flush();
      expect(notifications, 1, reason: 'the same error again is not news');

      repo.failWith = null;
      await vm.flush();
      expect(notifications, 2);
      vm.dispose();
    });
  });
}
