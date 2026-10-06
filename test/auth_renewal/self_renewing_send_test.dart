// The real send path (SendRequestUseCase over a real in-memory database): the OAuth 2.0 token is fetched or
// renewed before the request leaves, written back to whoever owns the auth, shared by requests that start
// together, and a request that cannot get a token is not sent.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/auth_owner.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import '../support/run_harness.dart';
import 'auth_harness.dart';

void main() {
  late AuthWorld world;
  late int shop;

  setUp(() async {
    world = await AuthWorld.create();
    shop = await world.collection('Shop');
  });
  tearDown(() => world.close());

  FakeAuthServer server() => world.server;

  /// Lets the sends get as far as the token endpoint, where [FakeAuthServer.tokenGate] holds them.
  Future<void> untilTokenRequestStarted() async {
    for (var i = 0; i < 200 && server().tokenCalls.isEmpty; i++) {
      await pumpEventQueue();
    }
    expect(server().tokenCalls, isNotEmpty, reason: 'the send never reached the token endpoint');
  }

  group('a request that inherits OAuth 2.0 from its collection', () {
    test('gets a token before it leaves, sends it, and the collection keeps it for the next send', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');

      final first = await world.send(orders);

      expect(server().tokenCalls.single.grant, 'client_credentials');
      expect(server().apiAuthorizations, ['Bearer at-1']);
      expect(first.statusCode, 200);
      expect(first.authNotes, ['Fetched a new OAuth 2.0 token (Client Credentials) before sending.']);
      final stored = await world.storedCollectionAuth(shop);
      expect(stored.oauth2AccessToken, 'at-1');
      expect(stored.oauth2TokenExpiry, world.now.add(const Duration(seconds: 3600)));
      expect(stored.oauth2ClientSecret, 'csecret', reason: 'only the token fields change');

      final second = await world.send(orders);

      expect(server().tokenCalls, hasLength(1), reason: 'the stored token is still good');
      expect(server().apiAuthorizations, ['Bearer at-1', 'Bearer at-1']);
      expect(second.authNotes, isEmpty);
    });

    test('is sent with a renewed token once the old one is within 30 s of its end', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      await world.send(orders);

      world.now = world.now.add(const Duration(seconds: 3600 - 31));
      await world.send(orders);
      expect(server().tokenCalls, hasLength(1));

      world.now = world.now.add(const Duration(seconds: 2));
      final renewed = await world.send(orders);

      expect(server().tokenCalls, hasLength(2));
      expect(server().apiAuthorizations.last, 'Bearer at-2');
      expect(renewed.authNotes, hasLength(1));
      expect((await world.storedCollectionAuth(shop)).oauth2AccessToken, 'at-2');
    });

    test('a token that cannot be had stops the send: nothing goes to the API, and the message says what to fix', () async {
      await world.setCollectionAuth(shop, oauthAuth(secret: 'wrong-secret-9'));
      final orders = await world.request(shop, 'Orders', '/orders');

      await expectLater(
        world.send(orders),
        throwsA(isA<InvalidRequestException>().having(
          (e) => e.message,
          'message',
          allOf(contains('rejected the client credentials'), endsWith('The request was not sent.'), isNot(contains('wrong-secret-9'))),
        )),
      );

      expect(server().apiCalls, isEmpty);
      expect(world.history.calls, isEmpty);
    });

    test('five sends that start together get one token request between them', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      final gate = Completer<void>();
      server().tokenGate = gate.future;

      final all = [for (var i = 0; i < 5; i++) world.send(orders)];
      await untilTokenRequestStarted();
      await pumpEventQueue();
      gate.complete();
      final responses = await Future.wait(all);

      expect(server().tokenCalls, hasLength(1));
      expect(responses.map((r) => r.statusCode).toSet(), {200});
      expect(server().apiAuthorizations.toSet(), {'Bearer at-1'});
    });

    test('a token fetched for a configuration that was edited while it was in flight is not written onto the new one', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      final gate = Completer<void>();
      server().tokenGate = gate.future;

      final sending = world.send(orders);
      await untilTokenRequestStarted();
      await world.setCollectionAuth(shop, oauthAuth().copyWith(oauth2Scope: 'changed-while-fetching'));
      gate.complete();
      await sending;

      final stored = await world.storedCollectionAuth(shop);
      expect(stored.oauth2Scope, 'changed-while-fetching');
      expect(stored.hasOAuth2Token, isFalse);
    });

    test('Auto-renew off sends what is stored, however old, and fetches nothing', () async {
      await world.setCollectionAuth(
        shop,
        oauthAuth(autoRenew: false, token: 'old', expiry: world.now.subtract(const Duration(days: 1))),
      );
      final orders = await world.request(shop, 'Orders', '/orders');

      final response = await world.send(orders);

      expect(server().tokenCalls, isEmpty);
      expect(server().apiAuthorizations, ['Bearer old']);
      expect(response.statusCode, 401);
      expect(response.authNotes, isEmpty);
    });

    test('Authorization Code with no token is not sent blindly: it says to sign in once', () async {
      await world.setCollectionAuth(shop, oauthAuth(grant: OAuth2GrantType.authorizationCodePkce));
      final orders = await world.request(shop, 'Orders', '/orders');

      await expectLater(
        world.send(orders),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('sign in once'))),
      );
      expect(server().apiCalls, isEmpty);
      expect(server().tokenCalls, isEmpty);
    });
  });

  group('whoever owns the auth gets the new token', () {
    test('a request with OAuth 2.0 of its own keeps the token in its own row', () async {
      final own = await world.request(shop, 'Own', '/orders', auth: oauthAuth());

      await world.send(own);

      final stored = (await world.repos.requestRepository.findById(own.id))!;
      expect(stored.auth.oauth2AccessToken, 'at-1');
      expect(server().apiAuthorizations, ['Bearer at-1']);
      expect(server().tokenCalls, hasLength(1));
      await world.send(stored);
      expect(server().tokenCalls, hasLength(1));
    });

    test('a folder that sets OAuth 2.0 keeps it in its defaults, and its requests inherit it', () async {
      final admin = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Admin');
      await world.repos.defaultsRepository.saveFolder(admin, LevelDefaults(auth: oauthAuth()));
      final users = await world.request(shop, 'Users', '/users', folderId: admin);

      final response = await world.send(users);

      expect(response.statusCode, 200);
      expect((await world.repos.defaultsRepository.getFolder(admin)).auth!.oauth2AccessToken, 'at-1');
      expect(await world.repos.collectionAuthRepository.getAuthJson(shop), isNull);
    });

    test('an open request picks up a token renewed for it, so its next edit does not save the old one back', () async {
      final own = await world.request(shop, 'Own', '/orders', auth: oauthAuth());
      final client = FakeRunClient();
      final vm = buildBuilder(world.repos.requestRepository, client);
      addTearDown(vm.dispose);
      await vm.load(own.id);
      expect(vm.request!.auth.hasOAuth2Token, isFalse);

      await world.send(own);
      for (var i = 0; i < 20 && !vm.request!.auth.hasOAuth2Token; i++) {
        await pumpEventQueue();
      }

      expect(vm.request!.auth.oauth2AccessToken, 'at-1');
      vm.updateName('Own (renamed)');
      await pumpEventQueue();
      final stored = (await world.repos.requestRepository.findById(own.id))!;
      expect(stored.name, 'Own (renamed)');
      expect(stored.auth.oauth2AccessToken, 'at-1');
    });
  });

  group('the manager and the Auth tab agree', () {
    test('Renew now for an inherited auth writes the new token where the auth is set', () async {
      await world.setCollectionAuth(shop, oauthAuth(token: 'old', expiry: world.now.add(const Duration(hours: 1))));

      final renewal = await world.manager.ensureFresh(
        await world.storedCollectionAuth(shop),
        owner: AuthOwner.collection(shop, 'Shop'),
        resolver: await world.resolver(shop),
        force: true,
      );

      expect(renewal.kind, TokenRenewalKind.fetched);
      expect((await world.storedCollectionAuth(shop)).oauth2AccessToken, 'at-1');
    });

    test('a network failure on the token endpoint is reported, not sent blindly', () async {
      await world.setCollectionAuth(shop, oauthAuth());
      final orders = await world.request(shop, 'Orders', '/orders');
      server().tokenFailure = const NetworkException(
        'connection refused',
        kind: NetworkErrorKind.connectionError,
        summary: "Couldn't reach auth.test.",
      );

      await expectLater(
        world.send(orders),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('Could not reach the token endpoint at auth.test'))),
      );
      expect(server().apiCalls, isEmpty);
    });
  });

  test('the response of a plain request carries no auth notes', () async {
    await world.setCollectionAuth(shop, const RequestAuth(type: AuthType.none));
    final plain = await world.request(shop, 'Plain', '/orders', auth: const RequestAuth(type: AuthType.none));

    final response = await world.send(plain);

    expect(response.authNotes, isEmpty);
    expect(server().tokenCalls, isEmpty);
  });
}
