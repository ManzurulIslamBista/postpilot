// "Save as example" attaches a response to a saved request, so it is offered
// everywhere except where the response belongs to none.
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

final class _NoExamples implements ResponseExampleRepository {
  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ApiResponseEntity _response() => ApiResponseEntity(
  statusCode: 200,
  statusMessage: 'OK',
  headers: const {'content-type': 'application/json'},
  bodyBytes: Uint8List.fromList('{"ok":true}'.codeUnits),
  duration: const Duration(milliseconds: 12),
);

void main() {
  setUp(() async {
    await locator.reset();
    locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(_NoExamples()));
  });

  tearDown(() => locator.reset());

  Future<void> pumpViewer(WidgetTester tester, {bool canSaveExamples = true}) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ResponseViewer(response: _response(), requestId: 1, canSaveExamples: canSaveExamples),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the response viewer offers Save as example by default', (tester) async {
    await pumpViewer(tester);

    expect(find.byTooltip('Save as example'), findsOneWidget);
  });

  testWidgets('and hides it, keeping copy and download, when told examples cannot be saved', (tester) async {
    await pumpViewer(tester, canSaveExamples: false);

    expect(find.byTooltip('Save as example'), findsNothing);
    expect(find.byTooltip('Copy body'), findsOneWidget);
    expect(find.byTooltip('Download body'), findsOneWidget);
  });
}
