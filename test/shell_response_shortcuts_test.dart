// The response pane's side of the shell: what it says before the first send, and the Save-as-example shortcut
// that the shell reaches through ResponseFindController.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/response_viewer.dart';

final class _Examples implements ResponseExampleRepository {
  final saved = <ResponseExampleEntity>[];

  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  Future<int> add(ResponseExampleEntity example) async {
    saved.add(example);
    return saved.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ApiResponseEntity _json() => ApiResponseEntity(
  statusCode: 201,
  statusMessage: 'Created',
  headers: const {'content-type': 'application/json'},
  bodyBytes: Uint8List.fromList('{"id":7}'.codeUnits),
  duration: const Duration(milliseconds: 12),
);

ApiResponseEntity _binary() => ApiResponseEntity(
  statusCode: 200,
  statusMessage: 'OK',
  headers: const {'content-type': 'application/octet-stream'},
  bodyBytes: Uint8List.fromList(const [0, 159, 146, 150, 255, 254]),
  duration: const Duration(milliseconds: 3),
);

void main() {
  late _Examples examples;

  setUp(() async {
    await locator.reset();
    examples = _Examples();
    locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(examples));
  });

  tearDown(() => locator.reset());

  Future<void> pump(
    WidgetTester tester, {
    ApiResponseEntity? response,
    ResponseFindController? controller,
    bool canSaveExamples = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ResponseViewer(response: response, requestId: 1, findController: controller, canSaveExamples: canSaveExamples),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('before the first send', () {
    testWidgets('the summary and the body area both say how to send', (tester) async {
      await pump(tester);

      expect(find.text('No response yet. Press Send or Ctrl+Enter.'), findsOneWidget);
      expect(find.textContaining('Press Send or Ctrl+Enter to see the response'), findsOneWidget);
    });
  });

  group('Save as example from the keyboard', () {
    testWidgets('names the example after the status, saves the body shown, and confirms', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, response: _json(), controller: controller);

      controller.saveExample();
      await tester.pumpAndSettle();
      expect(find.text('Save as example'), findsWidgets, reason: 'the name prompt');
      expect(find.widgetWithText(TextField, '201 Created'), findsOneWidget, reason: 'the suggested name');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(examples.saved, hasLength(1));
      final example = examples.saved.single;
      expect((example.requestId, example.name, example.statusCode), (1, '201 Created', 201));
      expect(example.body, contains('"id"'));
      expect(find.text('Example saved'), findsOneWidget);
    });

    testWidgets('cancelling the prompt saves nothing', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, response: _json(), controller: controller);

      controller.saveExample();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(examples.saved, isEmpty);
    });

    testWidgets('with no response it says to send first, instead of doing nothing', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, controller: controller);

      controller.saveExample();
      await tester.pump();

      expect(find.text('Send the request first: there is no response to save'), findsOneWidget);
      expect(examples.saved, isEmpty);
    });

    testWidgets('a binary body is refused with the same reason as the button gives', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, response: _binary(), controller: controller);

      controller.saveExample();
      await tester.pump();

      expect(find.text("Binary responses can't be saved as examples"), findsOneWidget);
      expect(examples.saved, isEmpty);
    });

    testWidgets('a response of a request without a saved row says so', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, response: _json(), controller: controller, canSaveExamples: false);

      controller.saveExample();
      await tester.pump();

      expect(find.text('This request has no saved row to attach an example to'), findsOneWidget);
      expect(examples.saved, isEmpty);
    });

    testWidgets('once the viewer is gone the shortcut does nothing instead of throwing', (tester) async {
      final controller = ResponseFindController();
      await pump(tester, response: _json(), controller: controller);
      await tester.pumpWidget(const SizedBox());

      expect(controller.saveExample, returnsNormally);
    });
  });
}
