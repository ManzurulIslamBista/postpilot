// "On 401/403 run the login request, then retry once": the real send path over a real in-memory database.
// Once per request, never recursive, never when the login itself fails, and always said on the response.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'auth_harness.dart';

void main() {
  late AuthWorld world;
  late int shop;
  late ApiRequestEntity login;
  late ApiRequestEntity orders;

  const bearerToken = RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}');

  setUp(() async {
    world = await AuthWorld.create();
    shop = await world.collection('Shop');
    final authFolder = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Auth');
    login = await world.loginRequest(shop, folderId: authFolder);
    orders = await world.request(shop, 'Orders', '/orders');
    await world.setCollectionAuth(shop, bearerToken.withRelogin(const ReloginConfig(request: 'Auth/Login')));
    await world.repos.globalVariableRepository.upsert(
      const GlobalVariableEntity(id: 0, key: 'token', value: 'stale', isSecret: true, enabled: true),
    );
  });
  tearDown(() => world.close());

  FakeAuthServer server() => world.server;
  List<String> paths() => [for (final c in server().apiCalls) Uri.parse(c.url).path];
  Future<String?> token() async => (await world.repos.globalVariableRepository.getEnabledMap())['token'];

  const retried = 'Re-authenticated via "Auth/Login" and retried (the first answer was HTTP 401).';

  group('a rejected request', () {
    test('runs the login, saves its token, and is sent once more with it; the response says so', () async {
      final response = await world.send(orders);

      expect(paths(), ['/orders', '/login', '/orders']);
      expect(server().apiAuthorizations, ['Bearer stale', '', 'Bearer login-1']);
      expect(response.statusCode, 200);
      expect(response.authNotes, [retried]);
      expect(await token(), 'login-1');
      expect(world.history.calls.map((c) => (c.method, c.status)), [('GET', 401), ('POST', 200), ('GET', 200)]);
    });

    test('is never retried more than once, even when the new token is rejected too', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/orders' ? server().reply(401, {'error': 'nope'}) : null;

      final response = await world.send(orders);

      expect(paths(), ['/orders', '/login', '/orders'], reason: 'one login, one retry, then the answer stands');
      expect(response.statusCode, 401);
      expect(response.authNotes, [retried]);
    });

    test('and the next request that is rejected the same way does not start another login at once', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/orders' ? server().reply(401, {'error': 'nope'}) : null;
      await world.send(orders);
      server().apiCalls.clear();

      final again = await world.send(orders);

      expect(paths(), ['/orders']);
      expect(again.authNotes.single, allOf(startsWith('Re-login via "Auth/Login" skipped:'), contains('rejected again (HTTP 401)')));
    });

    test('is not retried when the login fails: the rejection stands, with the reason', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server().reply(500, {'error': 'down'}) : null;

      final response = await world.send(orders);

      expect(paths(), ['/orders', '/login']);
      expect(response.statusCode, 401);
      expect(response.authNotes, ['Re-login via "Auth/Login" failed (it answered HTTP 500), so the request was not retried.']);
      expect(await token(), 'stale');
    });

    test('is not retried when the login answers 200 but saves no token: it would only repeat the stale one', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server().reply(200, {'nope': 1}) : null;

      final response = await world.send(orders);

      expect(paths(), ['/orders', '/login']);
      expect(response.authNotes.single, allOf(contains('failed (it did not save {{token}}'), endsWith('so the request was not retried.')));
    });

    test('never starts a second login when the login itself is rejected', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server().reply(401, {'error': 'bad password'}) : null;

      final response = await world.send(orders);

      expect(paths().where((p) => p == '/login'), hasLength(1));
      expect(response.statusCode, 401);
      expect(response.authNotes.single, contains('failed (it answered HTTP 401)'));
    });

    test('and sending the login request itself, rejected, does not log in to log in', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server().reply(401, {'error': 'bad password'}) : null;

      final response = await world.send(login);

      expect(paths(), ['/login']);
      expect(response.statusCode, 401);
      expect(response.authNotes, isEmpty);
    });

    test('four requests rejected together share one login and are each retried', () async {
      final all = [for (var i = 0; i < 4; i++) world.send(orders)];

      final responses = await Future.wait(all);

      expect(responses.map((r) => r.statusCode), everyElement(200));
      expect(server().logins, 1);
      expect(paths().where((p) => p == '/orders'), hasLength(8));
      expect(responses.expand((r) => r.authNotes).toSet(), {retried});
    });

    test('403 starts it too; a status that is not in the list does not', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/orders' && !server().validTokens.any((t) => spec.headers['Authorization'] == 'Bearer $t')
          ? server().reply(403, {'error': 'forbidden'})
          : null;
      final forbidden = await world.send(orders);
      expect(forbidden.statusCode, 200);
      expect(forbidden.authNotes.single, startsWith('Re-authenticated via "Auth/Login" and retried (the first answer was HTTP 403)'));

      await world.setCollectionAuth(shop, bearerToken.withRelogin(const ReloginConfig(request: 'Auth/Login', statuses: {401})));
      server()
        ..validTokens.clear()
        ..apiCalls.clear();
      final only401 = await world.send(orders);
      expect(only401.statusCode, 403);
      expect(paths(), ['/orders']);
    });
  });

  group('without a setting, or with a wrong one', () {
    test('a collection with no re-login leaves a 401 alone, silently', () async {
      await world.setCollectionAuth(shop, bearerToken);

      final response = await world.send(orders);

      expect(response.statusCode, 401);
      expect(response.authNotes, isEmpty);
      expect(paths(), ['/orders']);
    });

    test('a login request that does not exist is said, not guessed', () async {
      await world.setCollectionAuth(shop, bearerToken.withRelogin(const ReloginConfig(request: 'Nope')));

      final response = await world.send(orders);

      expect(paths(), ['/orders']);
      expect(response.authNotes.single, allOf(startsWith('Re-login is set to "Nope"'), contains('no request of this collection has that name')));
    });

    test('a name that two requests share is ambiguous', () async {
      await world.request(shop, 'Twin', '/login', method: HttpMethod.post, auth: const RequestAuth(type: AuthType.none));
      await world.request(shop, 'Twin', '/login', method: HttpMethod.post, auth: const RequestAuth(type: AuthType.none));
      await world.setCollectionAuth(shop, bearerToken.withRelogin(const ReloginConfig(request: 'Twin')));

      final response = await world.send(orders);

      expect(paths(), ['/orders']);
      expect(response.authNotes.single, contains('names 2 requests'));
    });

    test('a bare name finds a login in a folder; a DELETE request is refused as a login', () async {
      await world.setCollectionAuth(shop, bearerToken.withRelogin(const ReloginConfig(request: 'Login')));
      expect((await world.send(orders)).authNotes.single, contains('Re-authenticated via "Login" and retried'));

      final purge = await world.request(shop, 'Purge', '/orders', method: HttpMethod.delete);
      await world.setCollectionAuth(shop, bearerToken.withRelogin(ReloginConfig(request: purge.name)));
      server()
        ..validTokens.clear()
        ..apiCalls.clear();
      final refused = await world.send(orders);
      expect(paths(), ['/orders']);
      expect(refused.authNotes.single, allOf(contains('was not run'), contains('DELETE')));
    });
  });

  group('a folder can have its own login', () {
    test('the nearest level that sets one wins: a request in the folder runs the folder\'s login, not the collection\'s', () async {
      final admin = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Admin');
      await world.loginRequest(shop, name: 'AdminLogin', folderId: admin, variable: 'adminToken');
      await world.repos.globalVariableRepository.upsert(
        const GlobalVariableEntity(id: 0, key: 'adminToken', value: 'stale', isSecret: true, enabled: true),
      );
      await world.repos.defaultsRepository.saveFolder(
        admin,
        LevelDefaults(
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{adminToken}}')
              .withRelogin(const ReloginConfig(request: 'Admin/AdminLogin')),
        ),
      );
      final users = await world.request(shop, 'Users', '/users', folderId: admin);

      final response = await world.send(users);

      expect(response.statusCode, 200);
      expect(response.authNotes.single, startsWith('Re-authenticated via "Admin/AdminLogin" and retried'));
      expect((await world.repos.globalVariableRepository.getEnabledMap())['adminToken'], 'login-1');
      expect(await token(), 'stale', reason: 'the collection\'s own login did not run');
    });

    test('a folder with no setting of its own uses the collection\'s', () async {
      final plain = await world.repos.collectionRepository.createFolder(collectionId: shop, name: 'Plain');
      final inside = await world.request(shop, 'Inside', '/orders', folderId: plain);

      final response = await world.send(inside);

      expect(response.authNotes.single, startsWith('Re-authenticated via "Auth/Login"'));
    });
  });

  group('the Test button', () {
    test('runs the login once and says which variables it saved', () async {
      final result = await world.relogin.test(shop, const ReloginConfig(request: 'Auth/Login'), login: (r) => world.send(r, reLogin: false));

      expect(result.ok, isTrue);
      expect(result.message, 'Logged in via "Auth/Login". Saved {{token}}.');
      expect(await token(), 'login-1');
    });

    test('says why it failed, and refuses a request that is no login', () async {
      server().apiOverride = (spec) => Uri.parse(spec.url).path == '/login' ? server().reply(401, {'error': 'bad'}) : null;
      final failed = await world.relogin.test(shop, const ReloginConfig(request: 'Auth/Login'), login: (r) => world.send(r, reLogin: false));
      expect(failed.ok, isFalse);
      expect(failed.message, 'The login failed: it answered HTTP 401.');

      expect((await world.relogin.test(shop, const ReloginConfig(request: 'Nope'), login: (r) => world.send(r, reLogin: false))).message,
          'No request of this collection is called "Nope".');
      await world.request(shop, 'Purge', '/orders', method: HttpMethod.delete);
      final purge = await world.relogin.test(shop, const ReloginConfig(request: 'Purge'), login: (r) => world.send(r, reLogin: false));
      expect(purge.ok, isFalse);
      expect(purge.message, contains('DELETE'));
    });

    test('lists the requests that can be picked, with their folders', () async {
      final candidates = await world.relogin.candidates(shop);

      expect(candidates.map((c) => c.path), unorderedEquals(['Auth/Login', 'Orders']));
      expect(candidates.firstWhere((c) => c.name == 'Login').method, HttpMethod.post);
    });
  });

  test('a send that is cancelled while its login runs throws "cancelled" instead of returning the rejected answer', () async {
    final gate = Completer<void>();
    server().loginGate = gate.future;
    final cancel = ApiCancelToken();

    final sending = world.send(orders, cancelToken: cancel);
    final outcome = sending.then<Object?>((_) => null, onError: (Object e) => e);
    for (var i = 0; i < 200 && !paths().contains('/login'); i++) {
      await pumpEventQueue();
    }
    expect(paths(), contains('/login'));
    cancel.cancel();
    gate.complete();

    expect(await outcome, isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.cancelled));
    expect(paths(), ['/orders', '/login'], reason: 'no retry for a request that was cancelled');
  });
}
