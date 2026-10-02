// Ctrl/Cmd+F opens the response body search: it lands in the search box ready to
// type, from any tab and any body mode, and Esc closes it again.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/response_viewer.dart';

import 'documentation/support/fakes.dart';

final class _NoExamples implements ResponseExampleRepository {
  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Just enough of the request repository for ShellViewModel to open tabs.
final class _OpenableRequests implements RequestRepository {
  @override
  Stream<ApiRequestEntity?> watchById(int id) => Stream.value(requestEntity(id, name: 'Request $id'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ApiResponseEntity _response() => ApiResponseEntity(
  statusCode: 200,
  statusMessage: 'OK',
  headers: const {'content-type': 'application/json'},
  bodyBytes: Uint8List.fromList('{"name":"Ada","job":"Ada again"}'.codeUnits),
  duration: const Duration(milliseconds: 12),
);

void main() {
  late ResponseFindController findController;

  setUp(() async {
    await locator.reset();
    locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(_NoExamples()));
    findController = ResponseFindController();
  });

  tearDown(() => locator.reset());

  Future<void> pumpViewer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ResponseViewer(response: _response(), requestId: 1, findController: findController),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final searchField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search body');

  bool searchHasFocus(WidgetTester tester) {
    return tester.widget<TextField>(searchField).focusNode!.hasFocus;
  }

  testWidgets('find puts the caret in the search box', (tester) async {
    await pumpViewer(tester);
    expect(searchHasFocus(tester), isFalse);

    findController.open();
    await tester.pumpAndSettle();

    expect(searchHasFocus(tester), isTrue);
  });

  testWidgets('what is typed afterwards searches the body and counts the matches', (tester) async {
    await pumpViewer(tester);
    findController.open();
    await tester.pumpAndSettle();

    await tester.enterText(searchField, 'Ada');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('from the Headers tab it switches back to Body first', (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();
    expect(searchField, findsNothing);

    findController.open();
    await tester.pumpAndSettle();

    expect(searchField, findsOneWidget);
    expect(searchHasFocus(tester), isTrue);
  });

  testWidgets('from the Preview mode it returns to Pretty, which has text to search', (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    findController.open();
    await tester.pumpAndSettle();

    expect(searchHasFocus(tester), isTrue);
  });

  testWidgets('opening it again selects the old query, so typing replaces it', (tester) async {
    await pumpViewer(tester);
    findController.open();
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'Ada');
    await tester.pump(const Duration(milliseconds: 400));

    findController.open();
    await tester.pumpAndSettle();

    final selection = tester.widget<TextField>(searchField).controller!.selection;
    expect(selection.start, 0);
    expect(selection.end, 3);
  });

  testWidgets('Esc clears the search and leaves the box', (tester) async {
    await pumpViewer(tester);
    findController.open();
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'Ada');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);
    expect(searchHasFocus(tester), isFalse);
  });

  testWidgets('a viewer without a controller (no shortcut wiring) still works', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ResponseViewer(response: _response(), requestId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(searchField, findsOneWidget);
  });

  test('the shell hands Find to the visible request only, since every open tab keeps its own response', () {
    final shell = ShellViewModel(_OpenableRequests());
    addTearDown(shell.dispose);
    var a = 0;
    var b = 0;
    shell
      ..registerBodySearch(1, () => a++)
      ..registerBodySearch(2, () => b++)
      ..selectRequest(1)
      ..findInResponse();
    expect((a, b), (1, 0));

    shell
      ..selectRequest(2)
      ..findInResponse();
    expect((a, b), (1, 1));
  });

  test('a replaced page keeps its registration when the old page unregisters late', () {
    final shell = ShellViewModel(_OpenableRequests());
    addTearDown(shell.dispose);
    var oldCalls = 0;
    var newCalls = 0;
    void oldPage() => oldCalls++;
    void newPage() => newCalls++;
    shell
      ..registerBodySearch(1, oldPage)
      ..registerBodySearch(1, newPage)
      ..unregisterBodySearch(1, oldPage)
      ..selectRequest(1)
      ..findInResponse();

    expect((oldCalls, newCalls), (0, 1));
  });

  test('the shortcut is Ctrl+F, or Alt+F where the browser owns Ctrl+F', () {
    expect(AppShortcut.findInResponse.key, LogicalKeyboardKey.keyF);
    expect(AppShortcut.findInResponse.keyLabel, anyOf('Ctrl+F', 'Cmd+F', 'Alt+F'));
  });
}
