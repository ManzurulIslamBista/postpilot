import 'dart:convert';
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

const _notice = 'Response larger than the limit was cut off — raise the limit in Settings';

final class _NoExamples implements ResponseExampleRepository {
  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(const []);

  @override
  Future<int> add(ResponseExampleEntity example) async => 1;

  @override
  Future<void> delete(int id) async {}
}

Widget _viewer(ApiResponseEntity response) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SizedBox(height: 500, child: ResponseViewer(response: response, requestId: 1))),
    );

ApiResponseEntity _response({required bool truncated}) => ApiResponseEntity(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {'content-type': 'text/plain'},
      bodyBytes: Uint8List.fromList(utf8.encode('hello')),
      duration: Duration.zero,
      truncated: truncated,
    );

void main() {
  setUp(() => locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(_NoExamples())));
  tearDown(locator.reset);

  testWidgets('a response cut off at the size limit says so and points at Settings', (tester) async {
    await tester.pumpWidget(_viewer(_response(truncated: true)));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsOneWidget);
    expect(find.text('hello'), findsWidgets, reason: 'the part that arrived is still shown');
  });

  testWidgets('a response that arrived whole shows no such notice', (tester) async {
    await tester.pumpWidget(_viewer(_response(truncated: false)));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsNothing);
    expect(find.text('hello'), findsWidgets);
  });

  testWidgets('the notice goes away when the next response is whole', (tester) async {
    await tester.pumpWidget(_viewer(_response(truncated: true)));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsOneWidget);

    await tester.pumpWidget(_viewer(_response(truncated: false)));
    await tester.pumpAndSettle();

    expect(find.text(_notice), findsNothing);
  });
}
