import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/device_helper/data/network_info.dart';
import 'package:postpilot/features/traffic_recorder/domain/entities/recorded_exchange.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/recording_collection_builder.dart';
import 'package:postpilot/features/traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import 'package:postpilot/features/traffic_recorder/presentation/traffic_recorder_view_model.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'exchange_fixtures.dart';
import 'fake_recorder_engine.dart';

void main() {
  late InMemoryDb db;
  late FakeRecorderEngine engine;
  late TrafficRecorderViewModel vm;
  late List<({String name, Uint8List bytes, String mime})> saved;

  TrafficRecorderViewModel build({int maxExchanges = 1000}) => TrafficRecorderViewModel(
        CreateCollectionFromRecordingUseCase(db.writer, db.environmentRepository, db.exampleRepository, db.scriptsRepository),
        createEngine: () => engine,
        lookupAddresses: () async => const [LocalAddress('Wi-Fi', '192.168.1.23')],
        saveFile: ({required fileName, required bytes, required mimeType}) async {
          saved.add((name: fileName, bytes: bytes, mime: mimeType));
          return '/downloads/$fileName';
        },
        now: () => DateTime.utc(2026, 10, 7, 12),
        maxExchanges: maxExchanges,
      );

  setUp(() {
    db = InMemoryDb();
    engine = FakeRecorderEngine();
    saved = [];
    vm = build();
    addTearDown(vm.dispose);
  });

  Future<void> started({String upstream = 'https://api.example.com'}) async {
    vm.upstreamText = upstream;
    await vm.start();
  }

  Future<void> push(Iterable<int> ids, {String path = '/users'}) async {
    for (final id in ids) {
      engine.push(exchange(id: id, path: '$path/$id'));
    }
    await pumpEventQueue();
  }

  group('starting', () {
    test('an empty or wrong upstream is explained and nothing starts', () async {
      await vm.start();
      expect(vm.error, contains('Enter the address'));
      vm.upstreamText = 'ftp://x';
      await vm.start();
      expect(vm.error, contains('http:// or https://'));
      expect(engine.starts, 0);
      expect(vm.isRunning, isFalse);
    });

    test('a bad port is explained', () async {
      vm
        ..upstreamText = 'https://api.example.com'
        ..portText = '70000';
      await vm.start();
      expect(vm.error, contains('between 1 and 65535'));
      vm.portText = '';
      await vm.start();
      expect(vm.error, contains('between 1 and 65535'));
      expect(engine.starts, 0);
    });

    test('starts on this computer only by default and offers the localhost address first', () async {
      await started(upstream: 'api.example.com/v2/');

      expect(vm.isRunning, isTrue);
      expect(vm.isBusy, isFalse);
      expect(vm.error, isNull);
      expect(engine.config!.upstream.toString(), 'https://api.example.com/v2');
      expect(engine.config!.host, '127.0.0.1');
      expect(engine.config!.rewriteHostHeaders, isTrue);
      expect(engine.config!.keepResponsesReadable, isTrue);
      expect(engine.config!.allowSelfSigned, isFalse);
      expect(vm.port, 8099);
      expect(vm.primaryUrl, 'http://localhost:8099');
      expect(vm.baseUrl, 'https://api.example.com/v2');
      expect(vm.listensForOtherDevices, isFalse);
      expect(vm.connectOptions.last.available, isFalse, reason: 'the Wi-Fi address needs "also reachable from phones"');
    });

    test('"also reachable from phones" listens on every interface and leads with the network address and the adb command', () async {
      vm.allowOtherDevices = true;
      await started();

      expect(engine.config!.host, '0.0.0.0');
      expect(vm.listensForOtherDevices, isTrue);
      expect(vm.primaryUrl, 'http://192.168.1.23:8099');
      final urls = [for (final o in vm.connectOptions) o.url];
      expect(urls, ['http://localhost:8099', 'http://10.0.2.2:8099', 'http://localhost:8099', 'http://192.168.1.23:8099']);
      expect(vm.connectOptions[2].command, 'adb reverse tcp:8099 tcp:8099');
      expect(vm.connectOptions.every((o) => o.available), isTrue);
    });

    test('the switches reach the engine', () async {
      vm
        ..allowSelfSigned = true
        ..rewriteHostHeaders = false
        ..keepResponsesReadable = false
        ..portText = '0';
      await started();

      expect([engine.config!.allowSelfSigned, engine.config!.rewriteHostHeaders, engine.config!.keepResponsesReadable], [true, false, false]);
      expect(vm.port, 49152);
    });

    test('a taken port is shown as the reason and the recorder stays off', () async {
      engine.failWith = 'Port 8099 is already in use or not allowed. Choose another port.';
      await started();

      expect(vm.error, 'Port 8099 is already in use or not allowed. Choose another port.');
      expect(vm.isRunning, isFalse);
      expect(vm.isBusy, isFalse);
      expect(vm.primaryUrl, isNull);
    });

    test('stop ends it and keeps what was recorded', () async {
      await started();
      await push([1, 2]);

      await vm.stop();

      expect(vm.isRunning, isFalse);
      expect(vm.port, isNull);
      expect(vm.recordedCount, 2);
      expect(engine.stops, 1);
    });
  });

  group('the table', () {
    test('lists the newest call first', () async {
      await started();
      await push([1, 2, 3]);

      expect([for (final e in vm.visible) e.id], [3, 2, 1]);
      expect(vm.recordedCount, 3);
    });

    test('the filter matches method, path and status, ignoring case', () async {
      await started();
      engine
        ..push(exchange(id: 1, path: '/users/1'))
        ..push(exchange(id: 2, method: 'POST', path: '/orders', status: 201))
        ..push(exchange(id: 3, path: '/health', status: 404));
      await pumpEventQueue();

      vm.setFilter('ORDERS');
      expect([for (final e in vm.visible) e.id], [2]);
      vm.setFilter('post');
      expect([for (final e in vm.visible) e.id], [2]);
      vm.setFilter('404');
      expect([for (final e in vm.visible) e.id], [3]);
      vm.setFilter('');
      expect(vm.visible, hasLength(3));
    });

    test('pausing keeps forwarding but stops recording, and counts what it did not keep', () async {
      await started();
      await push([1]);

      vm.togglePause();
      await push([2, 3]);
      expect(vm.recordedCount, 1);
      expect(vm.missedWhilePaused, 2);

      vm.togglePause();
      expect(vm.missedWhilePaused, 0);
      await push([4]);
      expect(vm.recordedCount, 2);
    });

    test('clear empties the table, the ticks and the selection', () async {
      await started();
      await push([1, 2]);
      vm
        ..select(1)
        ..toggleChecked(2, true);

      vm.clear();

      expect([vm.recordedCount, vm.selectedId, vm.checkedIds.length], [0, null, 0]);
    });

    test('the memory is bounded: the oldest calls are dropped, and a dropped call cannot stay ticked or selected', () async {
      vm = build(maxExchanges: 3);
      addTearDown(vm.dispose);
      await started();
      await push([1]);
      vm
        ..select(1)
        ..toggleChecked(1, true);

      await push([2, 3, 4, 5]);

      expect([for (final e in vm.visible) e.id], [5, 4, 3]);
      expect(vm.buffer.dropped, 2);
      expect(vm.selectedId, isNull);
      expect(vm.checkedIds, isEmpty);
    });

    test('ticking: one call, all shown calls, and back', () async {
      await started();
      await push([1, 2, 3]);

      vm.toggleChecked(2, true);
      expect(vm.checkedIds, {2});
      expect([for (final e in vm.exportSource) e.id], [2], reason: 'the ticked calls win');
      vm.toggleCheckAllVisible();
      expect(vm.checkedIds, {1, 2, 3});
      vm.toggleCheckAllVisible();
      expect(vm.checkedIds, isEmpty);
      expect([for (final e in vm.exportSource) e.id], [1, 2, 3], reason: 'with no ticks every shown call, oldest first');
      vm.setFilter('/2');
      expect([for (final e in vm.exportSource) e.id], [2]);
    });
  });

  group('secrets', () {
    final secret = exchange(
      id: 1,
      method: 'POST',
      path: '/login?api_key=SECRETKEY123',
      requestHeaders: const [RecordedHeader('authorization', 'Bearer abc123tokenvalue'), RecordedHeader('content-type', 'application/json')],
      requestBody: '{"password":"hunter2"}',
    );

    test('everything shown or copied is masked, and the real values only appear when the session toggle is on', () {
      expect(vm.pathFor(secret), '/login?api_key=••••••');
      expect(vm.headersFor(secret.requestHeaders).first.value, 'Bearer ••••••');
      expect(vm.bodyFor(secret.requestText!), '{"password":"••••••"}');
      expect(vm.curlFor(secret), isNot(contains('hunter2')));
      expect(vm.showRealValues, isFalse);

      vm.setShowRealValues(true);

      expect(vm.pathFor(secret), '/login?api_key=SECRETKEY123');
      expect(vm.headersFor(secret.requestHeaders).first.value, 'Bearer abc123tokenvalue');
      expect(vm.bodyFor(secret.requestText!), '{"password":"hunter2"}');
      expect(vm.curlFor(secret), contains('hunter2'));
    });

    test('the real-values switch is not part of anything that is saved', () async {
      await started();
      engine.push(secret);
      await pumpEventQueue();
      vm.setShowRealValues(true);

      final plan = vm.previewPlan(const RecordingOptions());
      final har = await vm.saveHar();

      expect(har, isNotNull);
      final text = utf8.decode(saved.single.bytes);
      for (final value in ['hunter2', 'abc123tokenvalue', 'SECRETKEY123']) {
        expect(text, isNot(contains(value)), reason: 'HAR holds $value');
      }
      final request = plan.requests.single.request;
      expect(request.url, '{{baseUrl}}/login?api_key={{apiKey}}');
      expect(request.body.rawText, isNot(contains('hunter2')));
    });
  });

  group('resend in PostPilot', () {
    test('builds a request to the real address with credentials as variables', () async {
      await started(upstream: 'https://api.example.com/v2');
      final e = exchange(
        id: 1,
        path: '/users/42?x=1',
        requestHeaders: const [RecordedHeader('host', '10.0.2.2:8099'), RecordedHeader('authorization', 'Bearer abc123tokenvalue')],
      );

      final draft = vm.resendRequestFor(e);

      expect(draft.request.url, 'https://api.example.com/v2/users/42?x=1');
      expect(draft.request.name, 'GET /users/42');
      expect([for (final h in draft.request.headers) '${h.key}: ${h.value}'], ['Authorization: Bearer {{token}}']);
      expect(draft.secrets, {'token'});
    });
  });

  group('collections and HAR', () {
    test('suggests a collection name from the upstream host', () async {
      expect(vm.suggestedCollectionName, 'Recorded traffic');
      await started(upstream: 'https://shop.example.org');
      expect(vm.suggestedCollectionName, 'Recorded from shop.example.org');
    });

    test('creates the collection from the ticked calls only', () async {
      await started();
      await push([1, 2, 3], path: '/items');
      vm.toggleChecked(2, true);

      final result = await vm.createCollection(RecordingOptions(collectionName: vm.suggestedCollectionName));

      expect(result, isNotNull);
      expect(result!.requests, 1);
      expect(db.collections.single.name, 'Recorded from api.example.com');
      expect(db.requests.single.url, '{{baseUrl}}/items/{{itemId}}');
      expect(vm.isBusy, isFalse);
      expect(vm.error, isNull);
    });

    test('a failure is reported and leaves nothing behind', () async {
      await started();
      await push([1], path: '/items');
      db.failSaveRequestOnCall = 1;

      final result = await vm.createCollection(const RecordingOptions());

      expect(result, isNull);
      expect(vm.error, startsWith("Couldn't create the collection"));
      expect(db.collections, isEmpty);
      expect(vm.isBusy, isFalse);
    });

    test('saves a HAR file named after the time, from the ticked or shown calls', () async {
      await started();
      await push([1, 2]);

      final path = await vm.saveHar();

      expect(path, '/downloads/recording-20261007-120000.har');
      expect(saved.single.mime, 'application/json');
      final har = jsonDecode(utf8.decode(saved.single.bytes)) as Map<String, dynamic>;
      expect(har['log']['entries'], hasLength(2));
    });

    test('nothing recorded means no file', () async {
      expect(await vm.saveHar(), isNull);
      expect(saved, isEmpty);
    });
  });
}
