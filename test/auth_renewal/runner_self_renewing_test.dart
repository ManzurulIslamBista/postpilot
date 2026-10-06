// A collection run keeps its tokens valid and logs in again on 401 without a click, with the delay and
// iteration options of the runner, and says in its results what it did. The run goes through the real
// runner, send path and database; only the HTTP world and the clock are fakes.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_report.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_selection.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/request_builder_view_model.dart';
import 'auth_harness.dart';

void main() {
  late AuthWorld world;
  late int shop;

  setUp(() async {
    world = await AuthWorld.create(server: FakeAuthServer()..expiresIn = 600);
    shop = await world.collection('Shop');
  });
  tearDown(() => world.close());

  Future<List<CollectionRunResult>> run(CollectionRunOptions options, {RunSelection selection = RunSelection.all}) =>
      world.runner.run(shop, options: options, selection: selection).toList();

  Future<void> fourRequests() async {
    for (final name in ['A', 'B', 'C', 'D']) {
      await world.request(shop, name, '/${name.toLowerCase()}');
    }
  }

  const fetched = 'Fetched a new OAuth 2.0 token (Client Credentials) before sending.';

  group('a token that expires during a run', () {
    test('is renewed right before the request that would have been rejected, and the result says so', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      await fourRequests();

      // Requests go out at minutes 0, 4, 8 and 12; the token lasts 10.
      final results = await run(const CollectionRunOptions(delay: Duration(minutes: 4)));

      expect(results.map((r) => r.response?.statusCode), [200, 200, 200, 200]);
      expect(world.server.tokenCalls, hasLength(2));
      expect(world.server.apiAuthorizations.map((a) => a.replaceFirst(RegExp(r'^Bearer at-'), '')), ['1', '1', '1', '2']);
      expect([for (final r in results) r.authNotes], [
        [fetched],
        <String>[],
        <String>[],
        [fetched],
      ]);
      expect(results.every((r) => r.passed), isTrue);
    });

    test('is renewed across iterations too: the delay between passes counts like any other', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      await fourRequests();

      // Eight sends, six minutes apart: the token (10 minutes) is due at minutes 12, 24 and 36.
      final results = await run(const CollectionRunOptions(iterations: 2, delay: Duration(minutes: 6)));

      expect(results, hasLength(8));
      expect(world.server.tokenCalls, hasLength(4));
      expect([for (final r in results) r.authNotes.isNotEmpty], [true, false, true, false, true, false, true, false]);
      expect(results.map((r) => r.iteration), [1, 1, 1, 1, 2, 2, 2, 2]);
    });

    test('shows in the exported results', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      await world.request(shop, 'A', '/a');
      final results = await run(const CollectionRunOptions());

      final iteration = RunIteration(1, const {})..results.addAll(results);
      final json = jsonDecode(const CollectionRunExporter().toJson([iteration])) as Map<String, dynamic>;

      expect(json['iterations'][0]['results'][0]['authNotes'], [fetched]);
    });

    test('a run in which no token can be had fails each request with the reason, sends none, and keeps going', () async {
      await world.setCollectionAuth(shop, oauthAuth(secret: 'wrong-secret-9'));
      await fourRequests();

      final results = await run(const CollectionRunOptions());

      expect(results, hasLength(4));
      expect(results.every((r) => r.error != null && !r.passed), isTrue);
      expect(results.first.error, allOf(contains('rejected the client credentials'), isNot(contains('wrong-secret-9'))));
      expect(world.server.apiCalls, isEmpty);
    });
  });

  group('a rejected request inside a run', () {
    test('runs the login and is sent again, with no extra click, and the result says so', () async {
      final authFolder = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Auth');
      await world.loginRequest(shop, folderId: authFolder);
      final orders = await world.request(shop, 'Orders', '/orders');
      await world.setCollectionAuth(
        shop,
        const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}').withRelogin(const ReloginConfig(request: 'Auth/Login')),
      );
      await world.repos.globalVariableRepository.upsert(
        const GlobalVariableEntity(id: 0, key: 'token', value: 'stale', isSecret: true, enabled: true),
      );

      final results = await run(const CollectionRunOptions(), selection: RunSelection.requests({orders.id}));

      expect(results.single.response!.statusCode, 200);
      expect(results.single.authNotes.single, startsWith('Re-authenticated via "Auth/Login" and retried'));
      expect(results.single.passed, isTrue);
      expect(world.server.logins, 1);
    });
  });

  group('the production lock and a declined send', () {
    test('a send the person declines asks for no token at all', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      final vm = RequestBuilderViewModel(
        world.repos.requestRepository,
        world.send,
        GenerateCodeSnippetUseCase(world.resolver, world.repos.collectionAuthRepository),
        world.scripts,
      );
      addTearDown(vm.dispose);
      await vm.load(orders.id);
      var asked = 0;
      vm.confirmSend = (request) async {
        asked++;
        return asked > 1;
      };

      await vm.send();
      expect(world.server.tokenCalls, isEmpty, reason: 'the lock\'s question comes before any token request');
      expect(world.server.apiCalls, isEmpty);

      await vm.send();
      expect(world.server.tokenCalls, hasLength(1));
      expect(vm.response!.statusCode, 200);
      expect(vm.response!.authNotes, [fetched]);
    });

    test('the code snippet of a request never fetches a token', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      final vm = RequestBuilderViewModel(
        world.repos.requestRepository,
        world.send,
        GenerateCodeSnippetUseCase(world.resolver, world.repos.collectionAuthRepository),
        world.scripts,
      );
      addTearDown(vm.dispose);
      await vm.load(orders.id);

      final snippet = await vm.generateCodeSnippet(const CurlGenerator());

      expect(snippet, contains('/orders'));
      expect(world.server.tokenCalls, isEmpty, reason: 'a snippet is printed from what is stored; nothing is sent');
      expect(world.server.apiCalls, isEmpty);
    });
  });
}
