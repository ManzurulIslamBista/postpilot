import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/safety/domain/services/graphql_operations.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';

RequestEffect _post(String url, {String? body, String? graphql}) =>
    ProductionDetector.classify(HttpMethod.post, url: url, body: body, graphqlQuery: graphql);

String _gql(String query) => '{"query": ${_jsonString(query)}, "variables": {}}';

String _jsonString(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

void main() {
  group('classify: HTTP verbs', () {
    test('GET, HEAD and OPTIONS read, PUT and PATCH write, DELETE removes', () {
      for (final m in [HttpMethod.get, HttpMethod.head, HttpMethod.options]) {
        expect(ProductionDetector.classify(m, url: 'https://x.test/json/2/res.partner/unlink'), RequestEffect.read, reason: m.label);
      }
      expect(ProductionDetector.classify(HttpMethod.put), RequestEffect.write);
      expect(ProductionDetector.classify(HttpMethod.patch), RequestEffect.write);
      expect(ProductionDetector.classify(HttpMethod.delete), RequestEffect.destructive);
      expect(ProductionDetector.classify(HttpMethod.delete, url: 'https://x.test/json/2/res.partner/search_read'), RequestEffect.destructive);
    });

    test('a plain POST is a write, and only the effect enum says whether data changes', () {
      expect(_post('https://x.test/orders', body: '{"sku": 1}'), RequestEffect.write);
      expect(_post('https://x.test/orders'), RequestEffect.write);
      expect(RequestEffect.read.changesData, isFalse);
      expect(RequestEffect.write.changesData, isTrue);
      expect(RequestEffect.destructive.changesData, isTrue);
    });
  });

  group('classify: Odoo JSON-2', () {
    test('read methods over POST are reads', () {
      for (final method in [
        'search_read',
        'read',
        'search',
        'search_count',
        'fields_get',
        'name_search',
        'name_get',
        'default_get',
        'check_access',
        'check_access_rights',
        'read_group',
        'web_search_read',
        'has_group',
      ]) {
        expect(_post('{{odooUrl}}/json/2/res.partner/$method'), RequestEffect.read, reason: method);
      }
    });

    test('create, write, copy, action_* and unknown methods are writes', () {
      for (final method in ['create', 'write', 'copy', 'action_confirm', 'action_archive', 'message_post', 'my_custom_method']) {
        expect(_post('https://odoo.test/json/2/sale.order/$method'), RequestEffect.write, reason: method);
      }
    });

    test('unlink and delete/remove/purge-style methods are destructive', () {
      expect(_post('https://odoo.test/json/2/res.partner/unlink'), RequestEffect.destructive);
      expect(_post('https://odoo.test/json/2/res.partner/action_unlink_all'), RequestEffect.destructive);
      expect(_post('https://odoo.test/json/2/res.partner/remove_line'), RequestEffect.destructive);
      expect(_post('https://odoo.test/json/2/ir.attachment/purge'), RequestEffect.destructive);
    });

    test('the method name is read as written: case, percent-encoding, query, a prefix path, the web client route', () {
      expect(_post('https://odoo.test/json/2/res.partner/Search_Read?x=1'), RequestEffect.read);
      expect(_post('https://odoo.test/json/2/res.partner/search%5Fread'), RequestEffect.read);
      expect(_post('https://odoo.test/odoo/json/2/res.partner/unlink'), RequestEffect.destructive);
      expect(_post('https://odoo.test/web/dataset/call_kw/res.partner/search_read'), RequestEffect.read);
      expect(_post('https://odoo.test/web/dataset/call_kw/res.partner/write'), RequestEffect.write);
    });

    test('a method not known yet counts as a write, never as a read', () {
      expect(_post('{{odooUrl}}/json/2/res.partner/{{method}}'), RequestEffect.write);
      expect(_post('https://odoo.test/json/2/res.partner/%ZZ'), RequestEffect.write);
    });

    test('the Odoo route wins over the body', () {
      expect(_post('https://odoo.test/json/2/res.partner/search_read', body: '{"query": "mutation { x }"}'), RequestEffect.read);
    });
  });

  group('classify: GraphQL', () {
    test('queries, subscriptions and the anonymous shorthand read', () {
      expect(_post('https://x.test/graphql', body: _gql('query Orders(\$first: Int = 10) { orders(first: \$first) { id } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('{ me { id name } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('subscription OnOrder { orderCreated { id } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('query { __schema { types { name } } }')), RequestEffect.read);
    });

    test('a mutation writes, and one with a delete/remove/drop root field removes', () {
      expect(_post('https://x.test/graphql', body: _gql('mutation { createOrder(input: {sku: "a"}) { id } }')), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: _gql('mutation Del { deleteOrder(id: 1) { id } }')), RequestEffect.destructive);
      expect(_post('https://x.test/graphql', body: _gql('mutation { removeFromCart(id: 1) { id } }')), RequestEffect.destructive);
      expect(_post('https://x.test/graphql', body: _gql('mutation { dropTable(name: "x") }')), RequestEffect.destructive);
      expect(_post('https://x.test/graphql', body: _gql('mutation { updateOrder(id: 1) { id } deleteOrder(id: 2) { id } }')), RequestEffect.destructive);
    });

    test('the real field name counts, not the alias, and only root fields do', () {
      expect(_post('https://x.test/graphql', body: _gql('mutation { deleteMe: createOrder(input: {}) { id } }')), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: _gql('mutation { gone: deleteOrder(id: 1) { id } }')), RequestEffect.destructive);
      expect(_post('https://x.test/graphql', body: _gql('mutation { createOrder(input: {}) { id deletedAt removedBy { id } } }')), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: _gql('mutation { ... on Mutation { deleteOrder(id: 1) { id } } }')), RequestEffect.destructive);
    });

    test('words inside strings and comments do not count', () {
      expect(_post('https://x.test/graphql', body: _gql('query { search(text: "mutation { deleteAll }") { id } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('# mutation { deleteAll }\nquery { me { id } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('query { search(text: """a "quoted" mutation""") { id } }')), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: _gql('mutation { createNote(text: "please delete this") { id } }')), RequestEffect.write);
    });

    test('a document with any mutation writes; directives, fragments and variable definitions are followed', () {
      expect(_post('https://x.test/graphql', body: _gql('query A { me { id } } mutation B { createOrder(input: {}) { id } }')), RequestEffect.write);
      expect(
        _post('https://x.test/graphql', body: _gql('query (\$id: ID!, \$f: [String!] = ["a", "b"]) @live { node(id: \$id) { ...F } } fragment F on Node { id }')),
        RequestEffect.read,
      );
      expect(_post('https://x.test/graphql', body: _gql('mutation (\$id: ID!) @tag(name: "x") { deleteOrder(id: \$id) @skip(if: false) { id } }')), RequestEffect.destructive);
    });

    test('a batch is as bad as its worst entry', () {
      expect(_post('https://x.test/graphql', body: '[${_gql('{ me { id } }')}, ${_gql('{ orders { id } }')}]'), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: '[${_gql('{ me { id } }')}, ${_gql('mutation { createOrder(input: {}) { id } }')}]'), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: '[${_gql('{ me { id } }')}, ${_gql('mutation { deleteOrder(id: 1) { id } }')}]'), RequestEffect.destructive);
    });

    test('the editor query and a raw application/graphql body are read too', () {
      expect(_post('https://x.test/graphql', graphql: 'query { me { id } }'), RequestEffect.read);
      expect(_post('https://x.test/graphql', graphql: 'mutation { deleteOrder(id: 1) { id } }'), RequestEffect.destructive);
      expect(_post('https://x.test/graphql', body: 'query { me { id } }'), RequestEffect.read);
      expect(_post('https://x.test/graphql', body: 'mutation { createOrder(input: {}) { id } }'), RequestEffect.write);
    });

    test('anything that does not parse as GraphQL stays a write', () {
      expect(_post('https://x.test/search', body: '{"query": "shoes"}'), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: _gql('query { me { id }')), RequestEffect.write, reason: 'unbalanced braces');
      expect(_post('https://x.test/graphql', body: _gql('type Query { me: String }')), RequestEffect.write, reason: 'a schema, not an operation');
      expect(_post('https://x.test/graphql', body: _gql('query { me(name: "oops) { id } }')), RequestEffect.write, reason: 'unterminated string');
      expect(_post('https://x.test/graphql', body: '{"variables": {}}'), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: 'a=1&b=2'), RequestEffect.write);
      expect(_post('https://x.test/graphql', body: '[1, 2]'), RequestEffect.write);
    });

    test('GraphqlOperations reads the operation type, name and root fields', () {
      final ops = GraphqlOperations.parse('query Q { a b: c(x: 1) { d } } mutation M { e }')!;
      expect(ops.map((o) => o.type), ['query', 'mutation']);
      expect(ops.map((o) => o.name), ['Q', 'M']);
      expect(ops[0].rootFields, ['a', 'c']);
      expect(ops[1].rootFields, ['e']);
      expect(ops[1].isMutation, isTrue);
      expect(GraphqlOperations.parse(''), isNull);
      expect(GraphqlOperations.parse('fragment F on T { a }'), isNull, reason: 'a fragment alone runs nothing');
    });
  });

  group('isProductionHost', () {
    bool match(String url, List<String> hosts) => ProductionDetector.isProductionHost(url, hosts);

    test('a host entry covers that host and its subdomains, not look-alikes', () {
      expect(match('https://api.acme.com/v1/orders', ['api.acme.com']), isTrue);
      expect(match('https://eu.api.acme.com/v1', ['api.acme.com']), isTrue, reason: 'subdomain');
      expect(match('https://api.acme.com', ['acme.com']), isTrue, reason: 'the registrable domain covers its hosts');
      expect(match('https://acme.com', ['api.acme.com']), isFalse, reason: 'the parent is not covered by a child entry');
      expect(match('https://notacme.com', ['acme.com']), isFalse);
      expect(match('https://acme.com.evil.io/', ['acme.com']), isFalse);
      expect(match('https://evil.io/?next=api.acme.com', ['api.acme.com']), isFalse);
      expect(match('https://api.acme.com@evil.io/', ['api.acme.com']), isFalse, reason: 'the part before @ is user info, the host is evil.io');
      expect(match('https://evil.io@api.acme.com/', ['api.acme.com']), isTrue);
    });

    test('case and a trailing dot do not matter, in the entry or the URL', () {
      expect(match('https://API.Acme.COM/x', ['api.acme.com']), isTrue);
      expect(match('https://api.acme.com/x', ['  API.ACME.COM ']), isTrue);
      expect(match('https://api.acme.com./x', ['api.acme.com']), isTrue);
    });

    test('a port in the entry limits it; the default port of the scheme counts when the URL has none', () {
      expect(match('https://acme.com:8443/x', ['acme.com:8443']), isTrue);
      expect(match('https://acme.com/x', ['acme.com:8443']), isFalse);
      expect(match('https://acme.com:9000/x', ['acme.com:8443']), isFalse);
      expect(match('https://acme.com/x', ['acme.com:443']), isTrue);
      expect(match('http://acme.com/x', ['acme.com:443']), isFalse);
      expect(match('https://acme.com:8443/x', ['acme.com']), isTrue, reason: 'no port in the entry means any port');
    });

    test('wildcard, leading dot, a pasted URL and an IPv6 literal are understood', () {
      expect(match('https://eu.acme.com', ['*.acme.com']), isTrue);
      expect(match('https://eu.acme.com', ['.acme.com']), isTrue);
      expect(match('https://api.acme.com/v2', ['https://api.acme.com/v1/orders']), isTrue);
      expect(match('http://[::1]:3000/x', ['[::1]:3000']), isTrue);
      expect(match('http://[::1]:3001/x', ['[::1]:3000']), isFalse);
      expect(match('http://10.1.2.3/x', ['10.1.2.3']), isTrue);
    });

    test('a URL without a scheme is http, and a host that is not known yet never matches', () {
      expect(match('api.acme.com/x', ['api.acme.com']), isTrue);
      expect(match('{{baseUrl}}/orders', ['api.acme.com']), isFalse);
      expect(match('', ['api.acme.com']), isFalse);
      expect(match('https://api.acme.com', const []), isFalse);
      expect(match('https://api.acme.com', ['', '   ']), isFalse);
    });

    test('hostOf gives the lower-case host without port or user info', () {
      expect(ProductionDetector.hostOf('https://User:Pw@API.Acme.com:8443/x?y=1'), 'api.acme.com');
      expect(ProductionDetector.hostOf('api.acme.com/x'), 'api.acme.com');
      expect(ProductionDetector.hostOf('{{baseUrl}}/x'), isNull);
    });
  });
}
