import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/response_body/body_decoder.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/response_examples_view_model.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/response_viewer.dart';

Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);

String? _decode(List<int> bytes, {bool truncated = false, String mimeType = 'text/csv'}) =>
    decodeResponseBody(_bytes(bytes), mimeType: mimeType, truncated: truncated);

void main() {
  group('a body cut off by the size limit', () {
    test('loses a multi-byte character cut in half, not the readability of the whole body', () {
      final threeByte = utf8.encode('a,ব'); // ব is 3 bytes
      final twoByte = utf8.encode('Zoë'); // ë is 2 bytes
      final fourByte = utf8.encode('ok 😀'); // 4 bytes

      expect(_decode(threeByte.sublist(0, threeByte.length - 1), truncated: true), 'a,');
      expect(_decode(threeByte.sublist(0, threeByte.length - 2), truncated: true), 'a,');
      expect(_decode(twoByte.sublist(0, twoByte.length - 1), truncated: true), 'Zo');
      expect(_decode(fourByte.sublist(0, fourByte.length - 3), truncated: true), 'ok ');
    });

    test('keeps every non-ASCII character it does have, instead of decoding it as windows-1252', () {
      final full = utf8.encode('নাম,শহর\nZoë,ঢাকা');
      final cut = full.sublist(0, full.length - 1);

      final text = _decode(cut, truncated: true)!;

      expect(text, startsWith('নাম,শহর\nZoë,'));
      expect(text, isNot(contains('Ã')), reason: 'no mojibake');
    });

    test('a body that ends on a whole character is decoded whole', () {
      expect(_decode(utf8.encode('a,ব'), truncated: true), 'a,ব');
      expect(_decode(utf8.encode('plain ascii'), truncated: true), 'plain ascii');
    });

    test('the same bytes without the flag still fall back to windows-1252, as before', () {
      final threeByte = utf8.encode('a,ব');

      expect(_decode(threeByte.sublist(0, threeByte.length - 1)), contains('à'));
    });

    test('a real windows-1252 body is still read as windows-1252', () {
      // "café è" — 0xE8 at the end looks like the start of a UTF-8 sequence.
      final body = [0x63, 0x61, 0x66, 0xE9, 0x20, 0xE8];

      expect(_decode(body, truncated: true), 'café è');
    });

    test('an explicit UTF-8 charset and JSON bodies are cut cleanly too', () {
      final json = utf8.encode('{"n":"ব');
      final cut = json.sublist(0, json.length - 1);

      expect(_decode(cut, truncated: true, mimeType: 'application/json'), '{"n":"');
      expect(
        decodeResponseBody(_bytes(cut), mimeType: 'text/plain', charset: 'utf-8', truncated: true),
        '{"n":"',
      );
    });
  });

  group('an example saved from a truncated response', () {
    late _RecordingExamples repository;

    setUp(() => repository = _RecordingExamples());

    ApiResponseEntity response({required bool truncated}) => ApiResponseEntity(
          statusCode: 200,
          statusMessage: 'OK',
          headers: const {'content-type': 'text/plain'},
          bodyBytes: _bytes(utf8.encode('hello')),
          duration: Duration.zero,
          truncated: truncated,
        );

    test('remembers that it is only the first part', () async {
      final viewModel = ResponseExamplesViewModel(repository)..watch(1);
      addTearDown(viewModel.dispose);

      await viewModel.saveExample(name: 'cut', response: response(truncated: true), body: 'hello');
      await viewModel.saveExample(name: 'whole', response: response(truncated: false), body: 'hello');

      expect(repository.added[0].truncated, isTrue);
      expect(repository.added[0].headers['content-type'], 'text/plain');
      expect(repository.added[1].truncated, isFalse);
      expect(repository.added[1].headers, isNot(contains(ResponseExampleEntity.truncatedHeader)));
    });

    test('is recognised whatever the case of the marker header', () {
      final example = ResponseExampleEntity(
        id: 1,
        requestId: 1,
        name: 'x',
        statusCode: 200,
        headers: const {'X-PostPilot-Truncated': 'true'},
        body: '',
        savedAt: DateTime(2026),
      );

      expect(example.truncated, isTrue);
    });
  });

  group('the response viewer', () {
    late _RecordingExamples repository;

    setUp(() {
      repository = _RecordingExamples();
      locator.registerFactory<ResponseExamplesViewModel>(() => ResponseExamplesViewModel(repository));
    });
    tearDown(locator.reset);

    ApiResponseEntity response({required bool truncated}) => ApiResponseEntity(
          statusCode: 200,
          statusMessage: 'OK',
          headers: const {'content-type': 'text/plain'},
          bodyBytes: _bytes(utf8.encode('hello')),
          duration: Duration.zero,
          truncated: truncated,
        );

    Future<void> pump(WidgetTester tester, ApiResponseEntity response) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ResponseViewer(response: response, requestId: 1)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before saving a partial body as an example, and saves it marked when confirmed', (tester) async {
      await pump(tester, response(truncated: true));

      await tester.tap(find.byTooltip('Save as example'));
      await tester.pumpAndSettle();
      expect(find.text('Save a partial body?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.added, isEmpty);

      await tester.tap(find.byTooltip('Save as example'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.added.single.truncated, isTrue);
    });

    testWidgets('does not ask when the body arrived whole', (tester) async {
      await pump(tester, response(truncated: false));

      await tester.tap(find.byTooltip('Save as example'));
      await tester.pumpAndSettle();

      expect(find.text('Save a partial body?'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget, reason: 'straight to naming it');
    });

    testWidgets('asks before downloading a partial body', (tester) async {
      await pump(tester, response(truncated: true));

      await tester.tap(find.byTooltip('Download body'));
      await tester.pumpAndSettle();

      expect(find.text('Incomplete body'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Incomplete body'), findsNothing);
    });

    testWidgets('says so when a saved example holds only the first part of a response', (tester) async {
      repository.stored = [
        ResponseExampleEntity(
          id: 7,
          requestId: 1,
          name: 'big one',
          statusCode: 200,
          headers: const {'content-type': 'text/plain', ResponseExampleEntity.truncatedHeader: 'true'},
          body: 'first part',
          savedAt: DateTime(2026),
        ),
      ];
      await pump(tester, response(truncated: false));

      await tester.tap(find.text('Examples (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('big one'));
      await tester.pumpAndSettle();

      expect(find.textContaining('This example holds only the first part'), findsOneWidget);
    });
  });
}

final class _RecordingExamples implements ResponseExampleRepository {
  final List<ResponseExampleEntity> added = [];
  List<ResponseExampleEntity> stored = const [];

  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) => Stream.value(stored);

  @override
  Future<int> add(ResponseExampleEntity example) async {
    added.add(example);
    return added.length;
  }

  @override
  Future<void> delete(int id) async {}
}
