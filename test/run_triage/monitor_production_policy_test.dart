// The monitor never sends a data-changing request to production: nobody is there to confirm it. What counts as
// "changing data" is judged by what a request does, the same as the production lock everywhere else.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/run_triage/domain/services/monitor_production_policy.dart';

ApiRequestEntity _request(String name, HttpMethod method, String url, {RequestBody body = RequestBody.empty}) => ApiRequestEntity(
      id: name.hashCode,
      collectionId: 1,
      folderId: null,
      name: name,
      method: method,
      url: url,
      headers: const [],
      queryParams: const [],
      body: body,
      auth: const RequestAuth(type: AuthType.none),
    );

({ApiRequestEntity request, String resolvedUrl}) _at(ApiRequestEntity r, [String? url]) => (request: r, resolvedUrl: url ?? r.url);

void main() {
  final get = _request('List', HttpMethod.get, 'https://api.shop.test/orders');
  final head = _request('Ping', HttpMethod.head, 'https://api.shop.test/ping');
  final post = _request('Create', HttpMethod.post, 'https://api.shop.test/orders');
  final put = _request('Replace', HttpMethod.put, 'https://api.shop.test/orders/1');
  final patch = _request('Change', HttpMethod.patch, 'https://api.shop.test/orders/1');
  final delete = _request('Remove', HttpMethod.delete, 'https://api.shop.test/orders/1');
  final odooRead = _request('Partners', HttpMethod.post, 'https://odoo.test/json/2/res.partner/search_read');
  final odooWrite = _request('Create partner', HttpMethod.post, 'https://odoo.test/json/2/res.partner/create');
  final odooUnlink = _request('Delete partner', HttpMethod.post, 'https://odoo.test/json/2/res.partner/unlink');
  final graphqlQuery = _request(
    'Query',
    HttpMethod.post,
    'https://api.shop.test/graphql',
    body: const RequestBody(type: BodyType.graphql, graphqlQuery: '{ orders { id } }'),
  );
  final graphqlMutation = _request(
    'Mutation',
    HttpMethod.post,
    'https://api.shop.test/graphql',
    body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'mutation { createOrder(id: 1) { id } }'),
  );
  final graphqlDelete = _request(
    'Delete via GraphQL',
    HttpMethod.post,
    'https://api.shop.test/graphql',
    body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'mutation { deleteOrder(id: 1) { id } }'),
  );
  final everything = [get, head, post, put, patch, delete, odooRead, odooWrite, odooUnlink, graphqlQuery, graphqlMutation, graphqlDelete];

  List<String> names(Iterable<ApiRequestEntity> list) => [for (final r in list) r.name];

  test('outside production everything is sent', () {
    final plan = MonitorProductionPolicy.plan([for (final r in everything) _at(r)], productionEnvironment: false);
    expect(names(plan.allowed), names(everything));
    expect(plan.skipped, isEmpty);
  });

  test('in a production environment only what reads is sent', () {
    final plan = MonitorProductionPolicy.plan([for (final r in everything) _at(r)], productionEnvironment: true);
    expect(names(plan.allowed), ['List', 'Ping', 'Partners', 'Query']);
    expect(names(plan.skipped.map((s) => s.request)), ['Create', 'Replace', 'Change', 'Remove', 'Create partner', 'Delete partner', 'Mutation', 'Delete via GraphQL']);
  });

  test('a read over POST (Odoo search_read, a GraphQL query) is not a change', () {
    final plan = MonitorProductionPolicy.plan([_at(odooRead), _at(graphqlQuery)], productionEnvironment: true);
    expect(plan.skipped, isEmpty);
  });

  test('the reason says what the request does and why it was left out, and deletions are called deletions', () {
    final plan = MonitorProductionPolicy.plan([_at(post), _at(delete), _at(odooUnlink)], productionEnvironment: true);
    expect(plan.skipped[0].reason, startsWith('Left out by the monitor: it changes data and the environment looks like production.'));
    expect(plan.skipped[1].reason, contains('it deletes data'));
    expect(plan.skipped[2].reason, contains('it deletes data'));
    expect(plan.skipped[0].reason, endsWith('The monitor never sends data-changing requests to production.'));
  });

  test('a production host from Settings > Safety counts under any environment name', () {
    final plan = MonitorProductionPolicy.plan(
      [_at(post, 'https://api.shop.test/orders'), _at(get, 'https://api.shop.test/orders'), _at(post, 'https://staging.shop.test/orders')],
      productionEnvironment: false,
      productionHosts: ['api.shop.test'],
    );
    expect(plan.allowed.map((r) => r.url), ['https://api.shop.test/orders', 'https://api.shop.test/orders']);
    expect(plan.allowed.first.method, HttpMethod.get);
    expect(plan.skipped.single.reason, contains('api.shop.test is one of your production hosts'));
  });

  test('a host pattern covers the subdomains, and a port only that port', () {
    bool skipped(String url, List<String> hosts) =>
        MonitorProductionPolicy.plan([_at(post, url)], productionEnvironment: false, productionHosts: hosts).skipped.isNotEmpty;
    expect(skipped('https://eu.api.shop.test/x', ['shop.test']), isTrue);
    expect(skipped('https://x.other.test/x', ['shop.test']), isFalse);
    expect(skipped('https://shop.test:8443/x', ['shop.test:8443']), isTrue);
    expect(skipped('https://shop.test:9000/x', ['shop.test:8443']), isFalse);
  });

  test('the address is judged after its variables are resolved, not as written', () {
    final plan = MonitorProductionPolicy.plan(
      [_at(_request('Create', HttpMethod.post, '{{baseUrl}}/orders'), 'https://api.shop.test/orders')],
      productionEnvironment: false,
      productionHosts: ['api.shop.test'],
    );
    expect(plan.skipped, hasLength(1));
  });

  test('a request that cannot be proven to be a read counts as a write', () {
    // An unresolved variable where the Odoo method should be: unknown, so a write.
    final unknown = _request('Odoo unknown', HttpMethod.post, 'https://odoo.test/json/2/res.partner/{{method}}');
    final plan = MonitorProductionPolicy.plan([_at(unknown)], productionEnvironment: true);
    expect(plan.skipped, hasLength(1));
  });

  test('nothing to run is an empty plan', () {
    final plan = MonitorProductionPolicy.plan(const [], productionEnvironment: true);
    expect((plan.allowed, plan.skipped), (isEmpty, isEmpty));
  });
}
