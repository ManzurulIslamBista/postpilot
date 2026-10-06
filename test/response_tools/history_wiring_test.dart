// The real container over an in-memory database: closing or deleting a request
// tab must take the responses kept for "Compare" with it.
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';

ApiResponseEntity _response(int bytes) =>
    ApiResponseEntity(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: Uint8List(bytes), duration: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late int collection;

  setUp(() async {
    await locator.reset();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    setupDependencies(database: database);
    collection = await locator<CollectionRepository>().createCollection('Shop');
  });
  tearDown(() async {
    locator<ShellViewModel>().dispose();
    await locator.reset();
    await database.close();
  });

  Future<int> openTab(String name) async {
    final id = await locator<RequestRepository>().createRequest(collectionId: collection, name: name);
    locator<ShellViewModel>().selectRequest(id);
    await pumpEventQueue(times: 40);
    return id;
  }

  test('closing a tab forgets its responses and keeps the others', () async {
    final shell = locator<ShellViewModel>();
    final history = locator<ResponseHistory>();
    final a = await openTab('A');
    final b = await openTab('B');
    history
      ..record(a, _response(10))
      ..record(b, _response(20));

    shell.closeRequest(a);

    expect(history.of(a), isEmpty);
    expect(history.of(b), hasLength(1));
    expect(history.totalBytes, 20);
  });

  test('"close all" and "close others" empty the history the same way', () async {
    final shell = locator<ShellViewModel>();
    final history = locator<ResponseHistory>();
    final a = await openTab('A');
    final b = await openTab('B');
    final c = await openTab('C');
    for (final id in [a, b, c]) {
      history.record(id, _response(5));
    }

    shell.closeOthers(b);
    expect(history.of(a), isEmpty);
    expect(history.of(b), hasLength(1));
    expect(history.of(c), isEmpty);

    shell.closeAll();
    expect(history.totalBytes, 0);
  });

  test('deleting a request that is open forgets its responses', () async {
    final history = locator<ResponseHistory>();
    final a = await openTab('A');
    history.record(a, _response(10));

    await locator<RequestRepository>().deleteRequest(a);
    await pumpEventQueue(times: 60);

    expect(history.of(a), isEmpty);
    expect(history.totalBytes, 0);
  });
}
