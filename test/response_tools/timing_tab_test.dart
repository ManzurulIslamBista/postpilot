// "Measure connection" probes the host of the request. It used to assume https://
// for a host typed without a scheme while the sender uses http://, so a plain
// local server was probed for a TLS handshake it would never answer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/response_tools/presentation/view_models/response_tools_view_model.dart';
import 'package:postpilot/features/response_tools/presentation/widgets/timing_tab.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'timed out waiting');
}

void main() {
  testWidgets('a host typed without a scheme is measured as http: TCP only, no TLS row, no error', (tester) async {
    final server = (await tester.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0)))!;
    final accepted = <Socket>[];
    server.listen(accepted.add);
    addTearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    final db = InMemoryDb();
    final collection = await db.collectionRepository.createCollection('Local');
    await db.collectionVariableRepository.upsert(
      CollectionVariableEntity(id: 0, collectionId: collection, key: 'host', value: '127.0.0.1:${server.port}', enabled: true),
    );
    final request = await addRequest(db, collection, 'Ping', url: '{{host}}/ping');
    final vm = ResponseToolsViewModel(
      db.requestRepository,
      db.scriptsRepository,
      db.exampleRepository,
      ResponseHistory(),
      ResponseToolsData.from(
        requestId: request,
        requestName: 'Ping',
        response: ApiResponseEntity(
          statusCode: 200,
          statusMessage: 'OK',
          headers: const {},
          bodyBytes: Uint8List.fromList(utf8.encode('{}')),
          duration: const Duration(milliseconds: 12),
        ),
      ),
      prepareRequest: PrepareRequestUseCase(
        BuildVariableResolverUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository),
        db.collectionAuthRepository,
      ),
    );
    await vm.load();
    expect(vm.prepared!.spec.url, 'http://127.0.0.1:${server.port}/ping');

    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: TimingTab(viewModel: vm))));
    await tester.tap(find.text('Measure connection'));
    await tester.pump();

    await _until(tester, () => find.text('TCP connect').evaluate().isNotEmpty || find.textContaining("Couldn't").evaluate().isNotEmpty);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.text('TCP connect'), findsOneWidget);
    expect(find.text('DNS lookup'), findsOneWidget);
    expect(find.text('TLS handshake'), findsNothing, reason: 'plain http has no TLS handshake');
    expect(find.textContaining('127.0.0.1:${server.port}'), findsWidgets);
  });

  testWidgets('when the request cannot be built the tab says so instead of guessing a host', (tester) async {
    final db = InMemoryDb();
    final collection = await db.collectionRepository.createCollection('Local');
    final request = await addRequest(db, collection, 'Ping', url: '{{host}}/ping');
    final vm = ResponseToolsViewModel(
      db.requestRepository,
      db.scriptsRepository,
      db.exampleRepository,
      ResponseHistory(),
      ResponseToolsData.from(
        requestId: request,
        requestName: 'Ping',
        response: ApiResponseEntity(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: Uint8List(0), duration: Duration.zero),
      ),
    );
    await vm.load();
    expect(vm.prepared, isNull);

    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: TimingTab(viewModel: vm))));
    await tester.tap(find.text('Measure connection'));
    await _until(tester, () => find.textContaining("Couldn't build the request").evaluate().isNotEmpty);
    expect(find.text('TCP connect'), findsNothing);
  });
}
