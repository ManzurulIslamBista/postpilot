import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';

import 'documentation/support/fakes.dart';

/// Every request exists and never changes, so a tab opens and stays open.
final class _Requests implements RequestRepository {
  @override
  Stream<ApiRequestEntity?> watchById(int id) => Stream.value(requestEntity(id, name: 'Request $id'));

  @override
  Future<ApiRequestEntity?> findById(int id) async => requestEntity(id, name: 'Request $id');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late ShellViewModel shell;
  late int notifications;

  setUp(() {
    shell = ShellViewModel(_Requests());
    notifications = 0;
    shell.addListener(() => notifications++);
  });

  tearDown(() => shell.dispose());

  group('next and previous tab', () {
    setUp(() async {
      for (final id in [10, 20, 30]) {
        shell.selectRequest(id);
      }
      shell.selectRequest(20);
      // The tabs' names arrive on streams and notify; those are not what the tests count.
      await pumpEventQueue();
      notifications = 0;
    });

    test('next moves one tab to the right and wraps from the last to the first', () {
      shell.selectNextTab();
      expect(shell.selectedRequestId, 30);
      shell.selectNextTab();
      expect(shell.selectedRequestId, 10);
      expect(notifications, 2);
    });

    test('previous moves one tab to the left and wraps from the first to the last', () {
      shell.selectPreviousTab();
      expect(shell.selectedRequestId, 10);
      shell.selectPreviousTab();
      expect(shell.selectedRequestId, 30);
    });

    test('next then previous comes back, and the tab order is untouched', () {
      shell.selectNextTab();
      shell.selectPreviousTab();
      expect(shell.selectedRequestId, 20);
      expect(shell.openRequestIds, [10, 20, 30]);
    });

    test('pinned tabs count in the order they are shown in', () {
      shell.togglePin(30); // pinned tabs sit first: 30, 10, 20
      shell.selectRequest(30);
      shell.selectNextTab();
      expect(shell.selectedRequestId, 10);
      shell.selectNextTab();
      expect(shell.selectedRequestId, 20);
    });
  });

  group('with fewer than two tabs', () {
    test('there is nothing to switch to and nobody is notified', () async {
      shell.selectNextTab();
      shell.selectPreviousTab();
      expect(shell.selectedRequestId, isNull);

      shell.selectRequest(5);
      await pumpEventQueue();
      notifications = 0;
      shell.selectNextTab();
      shell.selectPreviousTab();

      expect(shell.selectedRequestId, 5);
      expect(notifications, 0);
    });
  });

  group('per-tab actions', () {
    test('an action runs on the selected tab only', () {
      shell
        ..selectRequest(1)
        ..selectRequest(2);
      final ran = <String>[];
      shell
        ..registerTabAction(1, TabAction.focusUrl, () => ran.add('one'))
        ..registerTabAction(2, TabAction.focusUrl, () => ran.add('two'));

      expect(shell.runTabAction(TabAction.focusUrl), isTrue);
      shell.selectRequest(1);
      shell.focusUrl();

      expect(ran, ['two', 'one']);
    });

    test('different actions of one tab are kept apart', () {
      shell.selectRequest(1);
      final ran = <String>[];
      shell
        ..registerTabAction(1, TabAction.focusUrl, () => ran.add('focus'))
        ..registerTabAction(1, TabAction.saveResponseExample, () => ran.add('save'));

      shell.saveResponseExample();
      shell.focusUrl();

      expect(ran, ['save', 'focus']);
    });

    test('with no tab, or a tab that offers none, nothing runs and false says so', () {
      expect(shell.runTabAction(TabAction.focusUrl), isFalse);
      shell.selectRequest(1);
      expect(shell.runTabAction(TabAction.saveResponseExample), isFalse);
    });

    test('unregistering removes only the callback it is given, so a page replaced under one id keeps its action', () {
      shell.selectRequest(1);
      var oldRuns = 0;
      var newRuns = 0;
      void oldAction() => oldRuns++;
      void newAction() => newRuns++;
      shell.registerTabAction(1, TabAction.focusUrl, oldAction);
      shell.registerTabAction(1, TabAction.focusUrl, newAction); // the new page registers before the old one is disposed
      shell.unregisterTabAction(1, TabAction.focusUrl, oldAction);

      shell.focusUrl();
      expect((oldRuns, newRuns), (0, 1));

      shell.unregisterTabAction(1, TabAction.focusUrl, newAction);
      expect(shell.runTabAction(TabAction.focusUrl), isFalse);
    });
  });
}
