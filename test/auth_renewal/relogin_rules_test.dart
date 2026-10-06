// The rules behind "on 401/403 run the login request, then retry once", apart from any HTTP: which request a
// name picks, who may start a login and when, whose auth a token belongs to.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/auth_owner.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/auth_renewal/domain/services/relogin_coordinator.dart';
import 'package:postpilot/features/auth_renewal/domain/services/relogin_policy.dart';
import 'package:postpilot/features/auth_renewal/domain/services/request_auth_override.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_chain.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_origin.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

ReloginCandidate<String> _c(String folder, String name, {HttpMethod method = HttpMethod.post}) =>
    ReloginCandidate(folderPath: folder, name: name, method: method, value: '$folder/$name');

void main() {
  group('which request a name picks', () {
    final candidates = [_c('Auth', 'Login'), _c('', 'Login'), _c('Admin', 'Login'), _c('Auth', 'Refresh'), _c('', 'Orders', method: HttpMethod.get)];

    String? found(String selector) => switch (ReloginPolicy.find(selector, candidates)) {
          ReloginFound(:final candidate) => candidate.value,
          ReloginAmbiguous(:final count) => 'ambiguous:$count',
          ReloginNotFound() => null,
        };

    test('a full path wins over a bare name, and a path is exact', () {
      expect(found('Auth/Login'), 'Auth/Login');
      expect(found('Admin/Login'), 'Admin/Login');
      expect(found('Login'), '/Login', reason: 'the top-level Login has the path "Login"; the others are not it');
    });

    test('a bare name finds the one request of that name, and refuses two', () {
      expect(found('Refresh'), 'Auth/Refresh');
      expect(found('Orders'), '/Orders');
      final twins = [_c('A', 'Same'), _c('B', 'Same')];
      expect(switch (ReloginPolicy.find('Same', twins)) { ReloginAmbiguous(:final count) => count, _ => -1 }, 2);
      expect(switch (ReloginPolicy.find('A/Same', twins)) { ReloginFound() => 'found', _ => 'no' }, 'found');
    });

    test('a name nobody has is not found, and surrounding spaces do not matter', () {
      expect(found('Nope'), isNull);
      expect(found('  Auth/Refresh '), 'Auth/Refresh');
      expect(ReloginPolicy.find('', candidates), isA<ReloginNotFound<String>>());
    });

    test('only a GET or a POST can be a login', () {
      expect(ReloginPolicy.methodProblem(HttpMethod.post), isNull);
      expect(ReloginPolicy.methodProblem(HttpMethod.get), isNull);
      for (final m in [HttpMethod.delete, HttpMethod.put, HttpMethod.patch]) {
        expect(ReloginPolicy.methodProblem(m), contains(m.label), reason: m.label);
      }
    });
  });

  group('the setting in force', () {
    DefaultsChain chain({ReloginConfig? collection, ReloginConfig? outer, ReloginConfig? inner, bool innerAuth = true}) => DefaultsChain([
          DefaultsScope(
            const DefaultsOrigin.collection('Shop', id: 1),
            LevelDefaults(auth: const RequestAuth(type: AuthType.none).withRelogin(collection)),
          ),
          DefaultsScope(
            const DefaultsOrigin.folder('Outer', id: 2),
            LevelDefaults(auth: outer == null ? null : const RequestAuth(type: AuthType.bearer).withRelogin(outer)),
          ),
          DefaultsScope(
            const DefaultsOrigin.folder('Inner', id: 3),
            LevelDefaults(auth: inner == null || !innerAuth ? null : const RequestAuth(type: AuthType.bearer).withRelogin(inner)),
          ),
        ]);

    const a = ReloginConfig(request: 'A');
    const b = ReloginConfig(request: 'B');
    const c = ReloginConfig(request: 'C');

    test('is the nearest folder\'s, else the collection\'s, else none', () {
      expect(ReloginPolicy.configIn(chain(collection: a, outer: b, inner: c)), c);
      expect(ReloginPolicy.configIn(chain(collection: a, outer: b)), b);
      expect(ReloginPolicy.configIn(chain(collection: a)), a);
      expect(ReloginPolicy.configIn(chain()), isNull);
      expect(ReloginPolicy.configIn(DefaultsChain.empty), isNull);
    });

    test('a config with no statuses does nothing, and so does not shadow the level above', () {
      final silent = const ReloginConfig(request: 'X', statuses: {});
      expect(ReloginPolicy.configIn(chain(collection: a, inner: silent)), a);
    });
  });

  group('who may start a login', () {
    late DateTime now;
    late ReloginCoordinator coordinator;
    var runs = 0;

    setUp(() {
      now = DateTime.utc(2026, 10, 6, 12);
      coordinator = ReloginCoordinator(now: () => now, cooldown: const Duration(seconds: 60));
      runs = 0;
    });

    Future<ReloginLogin> ok() async {
      runs++;
      return const ReloginLogin.ok();
    }

    Future<ReloginLogin> failing() async {
      runs++;
      return const ReloginLogin.failed('it answered HTTP 500');
    }

    test('requests that fail together wait for one login and share its result', () async {
      final gate = Completer<void>();
      Future<ReloginLogin> slow() async {
        runs++;
        await gate.future;
        return const ReloginLogin.ok();
      }

      final all = [for (var i = 0; i < 4; i++) coordinator.run('k', now, slow)];
      gate.complete();
      final results = await Future.wait(all);

      expect(runs, 1);
      expect(results.every((r) => r.ok), isTrue);
      expect(results.where((r) => r.shared), hasLength(3));
    });

    test('a request sent before the last login finished does not log in again; one sent after it does', () async {
      final sentEarly = now;
      now = now.add(const Duration(seconds: 1)); // the login finishes a second after that request went out
      await coordinator.run('k', sentEarly, ok);
      now = now.add(const Duration(seconds: 5));

      final early = await coordinator.run('k', sentEarly, ok);
      expect(runs, 1);
      expect(early.shared, isTrue);

      final late = await coordinator.run('k', now, ok);
      expect(runs, 2);
      expect(late.shared, isFalse);
    });

    test('after a login failed none is started for the cooldown, then one may be', () async {
      final first = await coordinator.run('k', now, failing);
      expect(first.ok, isFalse);

      now = now.add(const Duration(seconds: 30));
      final blocked = await coordinator.run('k', now, ok);
      expect(runs, 1);
      expect(blocked.skipped, isTrue);
      expect(blocked.failure, allOf(contains('it answered HTTP 500'), contains('not tried again for 60 s')));

      now = now.add(const Duration(seconds: 31));
      expect((await coordinator.run('k', now, ok)).ok, isTrue);
      expect(runs, 2);
    });

    test('a login that did not help is not repeated either, and a fixed login can be tried at once', () async {
      await coordinator.run('k', now, ok);
      coordinator.markIneffective('k', 'the request was rejected again');
      now = now.add(const Duration(seconds: 1));

      expect((await coordinator.run('k', now, ok)).skipped, isTrue);
      expect(runs, 1);

      coordinator.reset('k');
      expect((await coordinator.run('k', now, ok)).ok, isTrue);
      expect(runs, 2);
    });

    test('different logins do not hold each other back', () async {
      await coordinator.run('a', now, failing);

      expect((await coordinator.run('b', now, ok)).ok, isTrue);
    });
  });

  group('whose auth a token belongs to', () {
    test('a request with OAuth 2.0 of its own owns it; an inherited one belongs to the level that set it', () {
      AuthOwner of({required bool own, DefaultsOrigin? origin}) => AuthOwner.of(
            ownsAuth: own,
            requestId: 12,
            requestName: 'Orders',
            collectionId: 1,
            collectionName: 'Shop',
            origin: origin,
          );

      expect(of(own: true).kind, AuthOwnerKind.request);
      expect(of(own: true).id, 12);
      final folder = of(own: false, origin: const DefaultsOrigin.folder('Admin', id: 7));
      expect((folder.kind, folder.id, folder.label), (AuthOwnerKind.folder, 7, 'folder "Admin"'));
      final collection = of(own: false, origin: const DefaultsOrigin.collection('Shop', id: 1));
      expect((collection.kind, collection.id), (AuthOwnerKind.collection, 1));
      expect(of(own: false).kind, AuthOwnerKind.collection, reason: 'no defaults known: the collection\'s auth is the only one that can apply');
      expect(of(own: false).id, 1);
    });

    test('owners are told apart by kind and id, and a file\'s owners by their scope', () {
      expect(AuthOwner.folder(1, 'A'), isNot(AuthOwner.collection(1, 'A')));
      expect(AuthOwner.collection(1, 'A'), AuthOwner.collection(1, 'renamed'));
      expect(AuthOwner.named(AuthOwnerKind.collection, 'Shop', 'x'), isNot(AuthOwner.named(AuthOwnerKind.collection, 'Other', 'x')));
    });
  });

  group('putting a renewed auth where the builder reads it', () {
    ApiRequestEntity request(RequestAuth auth) => ApiRequestEntity(
          id: 1,
          collectionId: 1,
          folderId: null,
          name: 'r',
          method: HttpMethod.get,
          url: 'https://x.test',
          headers: const [],
          queryParams: const [],
          body: RequestBody.empty,
          auth: auth,
        );
    const renewed = RequestAuth(type: AuthType.oauth2, oauth2AccessToken: 'new');
    const stale = RequestAuth(type: AuthType.oauth2, oauth2AccessToken: 'old');

    test('a request that inherits takes it as the inherited auth', () {
      final (r, inherited) = RequestAuthOverride.apply(request(const RequestAuth(type: AuthType.inherit)), stale, renewed);

      expect(r.auth.type, AuthType.inherit);
      expect(inherited!.oauth2AccessToken, 'new');
    });

    test('a request with its own takes it into itself and leaves the inherited auth alone', () {
      final (r, inherited) = RequestAuthOverride.apply(request(stale), const RequestAuth(type: AuthType.bearer), renewed);

      expect(r.auth.oauth2AccessToken, 'new');
      expect(inherited!.type, AuthType.bearer);
    });
  });
}
