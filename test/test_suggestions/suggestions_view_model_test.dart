import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/test_suggestions/presentation/view_models/suggestions_view_model.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'response_fixtures.dart';

ApiRequestEntity _request(HttpMethod method) => ApiRequestEntity(
      id: 7,
      collectionId: 1,
      folderId: null,
      name: 'List orders',
      method: method,
      url: 'https://shop.test/orders',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(),
    );

List<AssertionEntity> _stored(InMemoryDb db) => ScriptsJsonCodec.decodeAssertions(db.scripts[7]?.assertionsJson ?? '[]');

void main() {
  late InMemoryDb db;
  final first = response(ordersBody());
  final reloaded = <int>[];

  SuggestionsViewModel build({
    ApiRequestEntity? request,
    Future<ApiResponseEntity> Function(ApiRequestEntity)? send,
    Future<bool> Function(ApiRequestEntity)? confirm,
  }) =>
      SuggestionsViewModel(
        requestId: 7,
        response: first,
        scripts: db.scriptsRepository,
        request: () => request,
        send: send,
        confirmSend: confirm,
        afterWrite: (id) async => reloaded.add(id),
      );

  setUp(() {
    db = InMemoryDb();
    reloaded.clear();
  });

  group('what is ticked to start with', () {
    test('the recommended rows, and nothing the request already has', () async {
      db.scripts[7] = RequestScriptsEntity(
        requestId: 7,
        assertionsJson: ScriptsJsonCodec.encodeAssertions([AssertionEntity(type: AssertionType.statusEquals, expected: '200')]),
      );
      final vm = build();
      await vm.load();
      expect(vm.selected, {'content-type', 'schema'}, reason: 'status is already in the Tests tab');
      expect(vm.alreadyThere, {'status'});
      expect(vm.canSelect('status'), isFalse);
      vm.toggle('status');
      expect(vm.isSelected('status'), isFalse, reason: 'a row that is already there cannot be ticked');
    });

    test('Recommended, All and None', () async {
      final vm = build();
      await vm.load();
      expect(vm.selected, {'status', 'content-type', 'schema'});
      vm.selectAll();
      expect(vm.selectedCount, vm.result.suggestions.length);
      vm.selectNone();
      expect(vm.selectedCount, 0);
      vm.selectRecommended();
      expect(vm.selected, {'status', 'content-type', 'schema'});
      vm.toggle('time');
      expect(vm.selectedCount, 4);
      vm.toggle('time');
      expect(vm.selectedCount, 3);
    });
  });

  group('adding to the Tests tab', () {
    test('writes the ticked rows after what is there, keeps the extractors, and tells the open Tests tab', () async {
      final existing = AssertionEntity(type: AssertionType.bodyContains, expected: 'orders');
      db.scripts[7] = RequestScriptsEntity(
        requestId: 7,
        assertionsJson: ScriptsJsonCodec.encodeAssertions([existing]),
        extractorsJson: ScriptsJsonCodec.encodeExtractors([ExtractorEntity(path: 'data.page', variableKey: 'page')]),
      );
      final vm = build();
      await vm.load();
      final added = await vm.addSelected();
      expect(added, 3);
      final stored = _stored(db);
      expect(stored.map((a) => a.type), [AssertionType.bodyContains, AssertionType.statusEquals, AssertionType.headerEquals, AssertionType.jsonSchema]);
      expect(stored.first.expected, 'orders', reason: 'what was there is untouched');
      expect(ScriptsJsonCodec.decodeExtractors(db.scripts[7]!.extractorsJson).single.variableKey, 'page');
      expect(reloaded, [7]);
      expect(vm.lastAdded!.count, 3);
      expect(vm.selected, isEmpty, reason: 'what was added is not ticked any more');
      expect(vm.alreadyThere, {'status', 'content-type', 'schema'});
    });

    test('creates the request\'s tests when it had none', () async {
      final vm = build();
      await vm.load();
      expect(db.scripts[7], isNull);
      await vm.addSelected();
      expect(_stored(db), hasLength(3));
    });

    test('never adds twice: a second press adds nothing, and tests added elsewhere meanwhile are not repeated', () async {
      final vm = build();
      await vm.load();
      await vm.addSelected();
      vm.selectAll();
      expect(vm.selectedCount, vm.result.suggestions.length - 3);
      // The same row added from another place while this one was open.
      db.scripts[7] = db.scripts[7]!.copyWith(
        assertionsJson: ScriptsJsonCodec.encodeAssertions([..._stored(db), AssertionEntity(type: AssertionType.responseTimeBelowMs, expected: '500')]),
      );
      final again = await vm.addSelected();
      expect(again, vm.result.suggestions.length - 4);
      expect(_stored(db).where((a) => a.type == AssertionType.responseTimeBelowMs), hasLength(1));
      expect(_stored(db).length, vm.result.suggestions.length, reason: 'every proposal is there exactly once');
    });

    test('gives each added row an id of its own', () async {
      final vm = build();
      await vm.load();
      await vm.addSelected();
      final ids = _stored(db).map((a) => a.id).toSet();
      expect(ids, hasLength(3));
    });

    test('with nothing ticked it does nothing', () async {
      final vm = build();
      await vm.load();
      vm.selectNone();
      expect(await vm.addSelected(), 0);
      expect(db.scripts[7], isNull);
      expect(reloaded, isEmpty);
    });

    test('one Undo takes out exactly what was added and nothing else, even after other edits', () async {
      final mine = AssertionEntity(type: AssertionType.bodyContains, expected: 'orders');
      db.scripts[7] = RequestScriptsEntity(requestId: 7, assertionsJson: ScriptsJsonCodec.encodeAssertions([mine]));
      final vm = build();
      await vm.load();
      await vm.addSelected();
      // The person adds one of their own afterwards.
      db.scripts[7] = db.scripts[7]!.copyWith(
        assertionsJson: ScriptsJsonCodec.encodeAssertions([..._stored(db), AssertionEntity(type: AssertionType.jsonPathExists, path: 'ok')]),
      );
      reloaded.clear();
      await vm.undo();
      expect(_stored(db).map((a) => a.type), [AssertionType.bodyContains, AssertionType.jsonPathExists]);
      expect(vm.lastAdded, isNull);
      expect(reloaded, [7]);
      expect(vm.alreadyThere, isEmpty, reason: 'the rows can be proposed again');
      await vm.undo();
      expect(_stored(db), hasLength(2), reason: 'a second Undo has nothing to take out');
    });

    test('a failure to save is told, with nothing claimed as added', () async {
      final failing = SuggestionsViewModel(
        requestId: 7,
        response: first,
        scripts: _FailingScripts(db.scriptsRepository),
      );
      await failing.load();
      expect(await failing.addSelected(), 0);
      expect(failing.error, 'The tests could not be saved: Bad state: disk full');
      expect(failing.lastAdded, isNull);
      expect(failing.adding, isFalse);
    });
  });

  group('the stability probe', () {
    test('a read can be sent again straight away, and the rows are made again from the two answers', () async {
      final second = response(ordersBody(queueDepth: 99), ms: 250);
      final sent = <ApiRequestEntity>[];
      final vm = build(request: _request(HttpMethod.get), send: (r) async {
        sent.add(r);
        return second;
      });
      await vm.load();
      expect(vm.probeBlockedReason, isNull);
      expect(vm.result.suggestions.any((s) => s.id == 'equals:queueDepth'), isTrue);
      vm.toggle('equals:currency');
      await vm.sendAgain();
      expect(sent, hasLength(1));
      expect(vm.probed, isTrue);
      expect(vm.result.suggestions.any((s) => s.id == 'equals:queueDepth'), isFalse, reason: 'it changed between the two');
      expect(vm.isSelected('equals:currency'), isTrue, reason: 'a row that is still there keeps its tick');
      expect(vm.stability!.changing, contains('queueDepth'));
      expect(vm.result.volatile.first.label, 'body.queueDepth');
    });

    test('GET, HEAD and OPTIONS are reads; anything else needs the explicit opt-in', () async {
      for (final method in [HttpMethod.get, HttpMethod.head, HttpMethod.options]) {
        final vm = build(request: _request(method), send: (_) async => first);
        expect(vm.methodIsSafe, isTrue, reason: method.label);
        expect(vm.probeBlockedReason, isNull);
      }
      for (final method in [HttpMethod.post, HttpMethod.put, HttpMethod.patch, HttpMethod.delete]) {
        var sends = 0;
        final vm = build(request: _request(method), send: (_) async {
          sends++;
          return first;
        });
        expect(vm.methodIsSafe, isFalse, reason: method.label);
        expect(vm.probeBlockedReason, contains('can change data'));
        await vm.sendAgain();
        expect(sends, 0, reason: '${method.label} is not sent without the opt-in');
        vm.setUnsafeOptIn(true);
        expect(vm.probeBlockedReason, isNull);
        await vm.sendAgain();
        expect(sends, 1);
      }
    });

    test('the production lock is asked first; a "no" sends nothing', () async {
      var sends = 0;
      final asked = <HttpMethod>[];
      final vm = build(
        request: _request(HttpMethod.post),
        send: (_) async {
          sends++;
          return first;
        },
        confirm: (r) async {
          asked.add(r.method);
          return false;
        },
      )..unsafeOptIn = true;
      await vm.load();
      await vm.sendAgain();
      expect(asked, [HttpMethod.post]);
      expect(sends, 0);
      expect(vm.probeProblem, 'Not sent: the request was not confirmed.');
      expect(vm.probed, isFalse);
      expect(vm.probing, isFalse);
    });

    test('a failed second request is told without a secret in it, and the first answer stands', () async {
      final vm = build(request: _request(HttpMethod.get), send: (_) async => throw Exception('connect failed: https://user:hunter2@shop.test/orders?token=abc123'));
      await vm.load();
      final before = vm.result.suggestions.length;
      await vm.sendAgain();
      expect(vm.probeProblem, startsWith('The second request failed:'));
      expect(vm.probeProblem, isNot(contains('hunter2')));
      expect(vm.probeProblem, isNot(contains('abc123')));
      expect(vm.result.suggestions.length, before);
      expect(vm.probed, isFalse);
    });

    test('without a loaded request, or a way to send, it says why it is off', () async {
      expect(build(send: (_) async => first).probeBlockedReason, 'The request is still loading.');
      expect(build(request: _request(HttpMethod.get)).probeBlockedReason, 'This request cannot be sent from here.');
      expect(build(request: _request(HttpMethod.get)).canSendAgain, isFalse);
    });

    test('a second answer with another status class is told and not used', () async {
      final vm = build(request: _request(HttpMethod.get), send: (_) async => response({'error': 'busy'}, status: 503));
      await vm.load();
      await vm.sendAgain();
      expect(vm.result.notes.single, contains('503'));
      expect(vm.stability, isNull);
    });
  });
}

/// Scripts that can be read but not written.
final class _FailingScripts implements RequestScriptsRepository {
  final RequestScriptsRepository _inner;
  _FailingScripts(this._inner);

  @override
  Future<RequestScriptsEntity?> get(int requestId) => _inner.get(requestId);

  @override
  Stream<RequestScriptsEntity?> watch(int requestId) => _inner.watch(requestId);

  @override
  Future<void> save(RequestScriptsEntity scripts) async => throw StateError('disk full');
}
