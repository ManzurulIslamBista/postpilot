import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Environments implements EnvironmentRepository {
  final EnvironmentEntity? active;
  _Environments(this.active);

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(active);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EnvironmentEntity _env(String name) => EnvironmentEntity(id: 1, name: name, isActive: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ProductionDetector', () {
    test('recognises production by name', () {
      for (final name in ['Production', 'prod', 'Prod (EU)', 'live', 'acme-prod', 'acme_PRD', 'ProdEU']) {
        expect(ProductionDetector.isProduction(name), isTrue, reason: name);
      }
      for (final name in ['Staging', 'Development', 'producer', 'products', 'delivery', 'No Environment']) {
        expect(ProductionDetector.isProduction(name), isFalse, reason: name);
      }
    });

    test('extra words extend it', () {
      expect(ProductionDetector.isProduction('eu-west'), isFalse);
      expect(ProductionDetector.isProduction('eu-west', extraWords: ['EU-West']), isFalse, reason: 'a hyphenated name is split into words, so the extra word must be one of them');
      expect(ProductionDetector.isProduction('customer-a', extraWords: ['customer']), isTrue);
    });

    test('only data-changing methods count', () {
      expect(ProductionDetector.changesData(HttpMethod.get), isFalse);
      expect(ProductionDetector.changesData(HttpMethod.head), isFalse);
      expect(ProductionDetector.changesData(HttpMethod.options), isFalse);
      for (final m in [HttpMethod.post, HttpMethod.put, HttpMethod.patch, HttpMethod.delete]) {
        expect(ProductionDetector.changesData(m), isTrue);
      }
    });
  });

  group('ProductionGuard', () {
    test('warns for a write in production, never for a read or a safe environment', () async {
      final prefs = SafetyPrefs();
      final prod = ProductionGuard(_Environments(_env('Production')), prefs);
      final warning = await prod.checkSend(HttpMethod.delete, 'Delete user');
      expect(warning, isNotNull);
      expect(warning!.environmentName, 'Production');
      expect(warning.description, contains('DELETE'));
      expect(await prod.checkSend(HttpMethod.get, 'List users'), isNull);
      expect(await ProductionGuard(_Environments(_env('Staging')), prefs).checkSend(HttpMethod.post, 'x'), isNull);
      expect(await ProductionGuard(_Environments(null), prefs).checkSend(HttpMethod.post, 'x'), isNull);
    });

    test('can be switched off and silenced for the session', () async {
      final prefs = SafetyPrefs();
      final guard = ProductionGuard(_Environments(_env('Production')), prefs);
      guard.silenceForSession('Production');
      expect(await guard.checkSend(HttpMethod.post, 'x'), isNull);

      final other = SafetyPrefs();
      await other.setConfirmProductionWrites(false);
      expect(await ProductionGuard(_Environments(_env('Production')), other).checkSend(HttpMethod.post, 'x'), isNull);
    });

    test('a run warns once with the number of writes', () async {
      final guard = ProductionGuard(_Environments(_env('prod')), SafetyPrefs());
      final w = await guard.checkRun(3, 'Orders');
      expect(w!.description, contains('3 data-changing requests'));
      expect(await guard.checkRun(0, 'Orders'), isNull);
    });

    test('preferences persist', () async {
      final a = SafetyPrefs();
      await a.setConfirmProductionWrites(false);
      await a.setKeepSecretsLocal(false);
      await a.setExtraWords(['eu', ' ', 'us']);
      final b = SafetyPrefs();
      await b.load();
      expect(b.confirmProductionWrites, isFalse);
      expect(b.keepSecretsLocal, isFalse);
      expect(b.extraWords, ['eu', 'us']);
    });
  });

  group('ProductionGuard: judged by intent', () {
    ApiRequestEntity request(String name, String url, {HttpMethod method = HttpMethod.post, RequestBody body = RequestBody.empty}) => ApiRequestEntity(
          id: 1,
          collectionId: 7,
          folderId: null,
          name: name,
          method: method,
          url: url,
          headers: const [],
          queryParams: const [],
          body: body,
          auth: RequestAuth.none,
        );

    ProductionGuard guard(String env, SafetyPrefs prefs, [Future<String> Function(ApiRequestEntity)? resolve]) =>
        ProductionGuard(_Environments(_env(env)), prefs, resolve);

    test('an Odoo read over POST does not ask; a write asks; unlink asks and says it deletes', () async {
      final g = guard('Production', SafetyPrefs());
      expect(await g.checkRequest(request('List partners', '{{odooUrl}}/json/2/res.partner/search_read')), isNull);
      expect(await g.checkRequest(request('Fields', '{{odooUrl}}/json/2/res.partner/fields_get')), isNull);

      final write = await g.checkRequest(request('Rename partner', '{{odooUrl}}/json/2/res.partner/write'));
      expect(write, isNotNull);
      expect(write!.destructive, isFalse);
      expect(write.description, 'POST "Rename partner" changes data');

      final unlink = await g.checkRequest(request('Delete partner', '{{odooUrl}}/json/2/res.partner/unlink'));
      expect(unlink!.destructive, isTrue);
      expect(unlink.description, 'POST "Delete partner" deletes data');
      expect(unlink.environmentName, 'Production');
    });

    test('a GraphQL query over POST does not ask; a mutation asks; a delete mutation is destructive', () async {
      final g = guard('Production', SafetyPrefs());
      RequestBody gql(String q) => RequestBody(type: BodyType.graphql, graphqlQuery: q);
      expect(await g.checkRequest(request('Orders', 'https://api.test/graphql', body: gql('query { orders { id } }'))), isNull);
      final create = await g.checkRequest(request('Create', 'https://api.test/graphql', body: gql('mutation { createOrder(input: {}) { id } }')));
      expect(create!.destructive, isFalse);
      final delete = await g.checkRequest(request('Delete', 'https://api.test/graphql', body: gql('mutation { deleteOrder(id: 1) { id } }')));
      expect(delete!.destructive, isTrue);

      final raw = RequestBody(type: BodyType.raw, rawText: '{"query": "mutation { removeItem(id: 1) { id } }"}');
      expect((await g.checkRequest(request('Raw', 'https://api.test/graphql', body: raw)))!.destructive, isTrue);
    });

    test('a plain POST, PUT, PATCH still asks and DELETE is destructive', () async {
      final g = guard('prod', SafetyPrefs());
      for (final m in [HttpMethod.post, HttpMethod.put, HttpMethod.patch]) {
        final w = await g.checkRequest(request('x', 'https://api.test/orders', method: m));
        expect(w, isNotNull, reason: m.label);
        expect(w!.destructive, isFalse);
      }
      expect((await g.checkRequest(request('x', 'https://api.test/orders/1', method: HttpMethod.delete)))!.destructive, isTrue);
      expect(await g.checkRequest(request('x', 'https://api.test/orders', method: HttpMethod.get)), isNull);
    });

    test('"don\'t ask again" silences ordinary writes only, never a deletion', () async {
      final prefs = SafetyPrefs();
      final g = guard('Production', prefs);
      final first = await g.checkRequest(request('Create', 'https://api.test/orders'));
      expect(first, isNotNull);
      g.silenceForSession(first!.environmentName);
      expect(await g.checkRequest(request('Create again', 'https://api.test/orders')), isNull);
      expect(await g.checkRequest(request('Update', '{{odooUrl}}/json/2/res.partner/write')), isNull);

      expect(await g.checkRequest(request('Delete', 'https://api.test/orders/1', method: HttpMethod.delete)), isNotNull);
      expect(await g.checkRequest(request('Unlink', '{{odooUrl}}/json/2/res.partner/unlink')), isNotNull);
      expect(await g.checkSend(HttpMethod.delete, 'Delete', url: 'https://api.test/orders/1'), isNotNull);
      expect(await g.checkRun(3, 'Orders', destructiveCount: 1), isNotNull, reason: 'a run that deletes asks even when silenced');
      expect(await g.checkRun(3, 'Orders'), isNull);
    });

    test('silencing is kept in memory for the session: a fresh SafetyPrefs asks again', () async {
      final prefs = SafetyPrefs()..silenceForSession('Production');
      expect(prefs.isSilenced('Production'), isTrue);
      expect(SafetyPrefs().isSilenced('Production'), isFalse);
      prefs.clearSilenced();
      expect(prefs.isSilenced('Production'), isFalse);
    });

    test('a production host is protected under any environment name', () async {
      final prefs = SafetyPrefs();
      await prefs.setProductionHosts(['api.acme.com']);
      final g = guard('Dev', prefs);
      final w = await g.checkRequest(request('Create', 'https://eu.api.acme.com/orders'));
      expect(w, isNotNull);
      expect(w!.environmentName, 'eu.api.acme.com', reason: 'the host is the target, because the environment is not what gave it away');
      expect(w.reason, contains('production hosts'));
      expect(await g.checkRequest(request('List', 'https://eu.api.acme.com/orders', method: HttpMethod.get)), isNull);
      expect(await g.checkRequest(request('Create', 'https://staging.acme.test/orders')), isNull);
      expect(await g.checkRequest(request('Create', 'https://api.acme.com.evil.io/orders')), isNull);
    });

    test('the host is matched after {{variables}} are resolved, so a Dev baseUrl that points at the live server is caught', () async {
      final prefs = SafetyPrefs();
      await prefs.setProductionHosts(['acme.com:8443']);
      final g = guard('Dev', prefs, (r) async => r.url.replaceAll('{{baseUrl}}', 'https://API.ACME.com:8443'));
      expect(await g.checkRequest(request('Create', '{{baseUrl}}/orders')), isNotNull);
      final other = guard('Dev', prefs, (r) async => r.url.replaceAll('{{baseUrl}}', 'https://api.acme.com'));
      expect(await other.checkRequest(request('Create', '{{baseUrl}}/orders')), isNull, reason: 'the port differs');
      final broken = guard('Dev', prefs, (r) async => throw StateError('variable store unavailable'));
      expect(await broken.checkRequest(request('Create', 'https://acme.com:8443/orders')), isNotNull, reason: 'a resolver failure falls back to the URL as written');
    });

    test('a host warning is silenced per host, and the master switch turns hosts off too', () async {
      final prefs = SafetyPrefs();
      await prefs.setProductionHosts(['api.acme.com']);
      final g = guard('Dev', prefs);
      final w = await g.checkRequest(request('Create', 'https://api.acme.com/orders'));
      g.silenceForSession(w!.environmentName);
      expect(await g.checkRequest(request('Create', 'https://api.acme.com/orders')), isNull);
      expect(await g.checkRequest(request('Delete', 'https://api.acme.com/orders/1', method: HttpMethod.delete)), isNotNull);

      await prefs.setConfirmProductionWrites(false);
      expect(await g.checkRequest(request('Delete', 'https://api.acme.com/orders/1', method: HttpMethod.delete)), isNull);
    });

    test('a run is judged request by request: reads are free, writes and deletions are counted', () async {
      final g = guard('Production', SafetyPrefs());
      final requests = [
        request('List', 'https://api.test/orders', method: HttpMethod.get),
        request('Odoo read', '{{odooUrl}}/json/2/res.partner/search_read'),
        request('Create', 'https://api.test/orders'),
        request('Update', 'https://api.test/orders/1', method: HttpMethod.put),
        request('Delete', 'https://api.test/orders/1', method: HttpMethod.delete),
      ];
      final w = await g.checkRunRequests(requests, 'Orders');
      expect(w!.description, 'Running "Orders" sends 3 data-changing requests, 1 of them deletes data');
      expect(w.destructive, isTrue);

      final writesOnly = await g.checkRunRequests(requests.take(4), 'Orders');
      expect(writesOnly!.description, 'Running "Orders" sends 2 data-changing requests');
      expect(writesOnly.destructive, isFalse);
      expect(await g.checkRunRequests(requests.take(2), 'Orders'), isNull, reason: 'only reads');

      g.silenceForSession('Production');
      expect(await g.checkRunRequests(requests.take(4), 'Orders'), isNull);
      expect(await g.checkRunRequests(requests, 'Orders'), isNotNull, reason: 'the deletion is still asked about');
    });

    test('a run only counts the requests that go to a production host under a Dev environment', () async {
      final prefs = SafetyPrefs();
      await prefs.setProductionHosts(['api.acme.com']);
      final g = guard('Dev', prefs);
      final w = await g.checkRunRequests([
        request('Create live', 'https://api.acme.com/orders'),
        request('Create local', 'http://localhost:3000/orders'),
      ], 'Orders');
      expect(w!.description, 'Running "Orders" sends 1 data-changing request');
      expect(w.environmentName, 'api.acme.com');
    });

    test('production hosts persist', () async {
      final a = SafetyPrefs();
      await a.setProductionHosts(['api.acme.com', ' ', ' *.acme.io ']);
      expect(a.productionHosts, ['api.acme.com', '*.acme.io']);
      final b = SafetyPrefs();
      await b.load();
      expect(b.productionHosts, ['api.acme.com', '*.acme.io']);
    });
  });
}
