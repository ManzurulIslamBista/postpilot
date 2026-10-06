// The small parts the page walk is made of: writing at a JSON path, reading and writing the page parameter of a
// request, the Link header, and waiting.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_clock.dart';
import 'package:postpilot/features/request_flow/domain/services/json_path_editor.dart';
import 'package:postpilot/features/request_flow/domain/services/page_requests.dart';
import 'package:postpilot/features/request_flow/domain/services/pagination_engine.dart';
import 'flow_support.dart';

void main() {
  group('JsonPathEditor.set', () {
    test('replaces a value at a key, a nested key and a list index', () {
      final doc = <String, Object?>{
        'a': 1,
        'b': <String, Object?>{'c': <Object?>[10, 20, 30]},
      };

      JsonPathEditor.set(doc, 'a', 2);
      JsonPathEditor.set(doc, 'b.c[1]', 99);
      JsonPathEditor.set(doc, r'$.b.d', 'new');

      expect(doc, {
        'a': 2,
        'b': {'c': [10, 99, 30], 'd': 'new'},
      });
    });

    test('an empty path or `\$` is the whole document: the value replaces it', () {
      expect(JsonPathEditor.set(<Object?>[1], '', [2, 3]), [2, 3]);
      expect(JsonPathEditor.set({'x': 1}, r'$', [4]), [4]);
    });

    test('creates the objects on the way, and appends at the end of a list', () {
      final doc = <String, Object?>{
        'list': [1, 2],
      };

      JsonPathEditor.set(doc, 'params.kwargs.offset', 5);
      JsonPathEditor.set(doc, 'list[2]', 3);

      expect(doc['params'], {'kwargs': {'offset': 5}});
      expect(doc['list'], [1, 2, 3]);
    });

    test('says which path failed: an index past the end, or a step through a scalar', () {
      expect(() => JsonPathEditor.set({'list': [1]}, 'list[5]', 0), throwsA(isA<FormatException>()));
      expect(() => JsonPathEditor.set({'list': [1]}, 'list[3].x', 0), throwsA(isA<FormatException>()));
      expect(() => JsonPathEditor.set({'a': 'text'}, 'a.b', 0), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"a.b"'))));
    });

    test('writes where the resolver reads, whatever the path is spelled like', () {
      for (final path in ['a.b', r'$.a.b', "a['b']", 'a["b"]']) {
        final doc = <String, Object?>{'a': {'b': 0}};

        JsonPathEditor.set(doc, path, 7);

        expect(JsonPathEditor.read(doc, path), 7, reason: path);
      }
    });
  });

  group('PageRequests', () {
    final resolver = VariableResolver(const {'size': '25'});

    test('reads a query parameter from a row (resolved), else from the URL itself', () {
      final request = flowRequest(
        url: 'https://api.test/items?page=4&other=x',
        queryParams: [KeyValueItem(key: 'limit', value: '{{size}}'), KeyValueItem(key: 'off', value: '9', enabled: false)],
      );

      expect(PageRequests.read(request, 'limit', PageParamLocation.query, resolver), '25');
      expect(PageRequests.read(request, 'page', PageParamLocation.query, resolver), '4');
      expect(PageRequests.read(request, 'off', PageParamLocation.query, resolver), isNull, reason: 'a disabled row is not sent');
      expect(PageRequests.read(request, 'missing', PageParamLocation.query, resolver), isNull);
    });

    test('writes a query parameter as a row, replacing a row of that name, and a row beats the URL\'s own', () {
      final request = flowRequest(url: 'https://api.test/items?page=1', queryParams: [KeyValueItem(key: 'page', value: '1', enabled: false)]);

      final next = PageRequests.write(request, 'page', PageParamLocation.query, 2, resolver);

      expect(next.queryParams.map((p) => (p.key, p.value, p.enabled)), [('page', '2', true)]);
      expect(request.queryParams.single.value, '1', reason: 'the saved request itself is never changed');
    });

    test('reads and writes a body value by path, in a raw JSON body and in the variables of a GraphQL one', () {
      final raw = flowRequest(body: jsonBody({'params': {'offset': 0}}));
      final graphql = flowRequest(
        body: const RequestBody(type: BodyType.graphql, graphqlQuery: 'query', graphqlVariables: '{"first": 10, "after": null}'),
      );

      final rawNext = PageRequests.write(raw, 'params.offset', PageParamLocation.body, 40, resolver);
      final graphqlNext = PageRequests.write(graphql, 'after', PageParamLocation.body, 'abc', resolver);

      expect(jsonDecode(rawNext.body.rawText), {'params': {'offset': 40}});
      expect(PageRequests.read(rawNext, 'params.offset', PageParamLocation.body, resolver), '40');
      expect(jsonDecode(graphqlNext.body.graphqlVariables), {'first': 10, 'after': 'abc'});
      expect(graphqlNext.body.graphqlQuery, 'query');
    });

    test('a body that only becomes JSON once its variables are filled in is written from the filled-in text', () {
      final request = flowRequest(body: const RequestBody(type: BodyType.raw, rawText: '{"limit": {{size}}, "offset": 0}'));

      final next = PageRequests.write(request, 'offset', PageParamLocation.body, 25, resolver);

      expect(jsonDecode(next.body.rawText), {'limit': 25, 'offset': 25});
    });

    test('a body that is not JSON cannot take a page parameter, and says so', () {
      final form = flowRequest(body: const RequestBody(type: BodyType.urlEncoded));
      final text = flowRequest(body: const RequestBody(type: BodyType.raw, rawText: 'plain text'));

      for (final request in [form, text]) {
        expect(
          () => PageRequests.write(request, 'offset', PageParamLocation.body, 1, resolver),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not JSON'))),
        );
        expect(PageRequests.read(request, 'offset', PageParamLocation.body, resolver), isNull);
      }
    });

    test('a next URL replaces the URL and the rows it sets itself; the other rows stay', () {
      final request = flowRequest(queryParams: [KeyValueItem(key: 'page', value: '1'), KeyValueItem(key: 'api_key', value: 'k')]);

      final next = PageRequests.withUrl(request, Uri.parse('https://api.test/items?page=2&q=x'));

      expect(next.url, 'https://api.test/items?page=2&q=x');
      expect(next.queryParams.map((p) => p.key), ['api_key']);
    });

    test('the same origin is the same scheme, host (any case) and port, with the default port written or not', () {
      bool same(String a, String b) => PageRequests.sameOrigin(Uri.parse(a), Uri.parse(b));

      expect(same('https://api.test/a', 'https://API.test/b?x=1'), isTrue);
      expect(same('https://api.test/a', 'https://api.test:443/b'), isTrue);
      expect(same('https://api.test/a', 'http://api.test/a'), isFalse);
      expect(same('https://api.test/a', 'https://api.test:8443/a'), isFalse);
      expect(same('https://api.test/a', 'https://api.test.evil.example/a'), isFalse);
      expect(same('https://api.test/a', 'https://evil.example/api.test'), isFalse);
    });

    test('a value with {{ in it is recognised, so it is never written into a request', () {
      expect(PageRequests.looksLikeVariable('{{token}}'), isTrue);
      expect(PageRequests.looksLikeVariable('https://x/?a={{b}}'), isTrue);
      expect(PageRequests.looksLikeVariable('abc{def}'), isFalse);
    });
  });

  group('LinkHeader.next', () {
    test('finds the next link wherever it is, in any case, with or without quotes', () {
      expect(LinkHeader.next('<https://x/2>; rel="next"'), 'https://x/2');
      expect(LinkHeader.next('<https://x/1>; rel="prev", <https://x/3>; rel="next"'), 'https://x/3');
      expect(LinkHeader.next('<https://x/3>; REL=next'), 'https://x/3');
      expect(LinkHeader.next('<https://x/3>; rel="NEXT last"'), 'https://x/3');
      expect(LinkHeader.next('<https://x/3>;title="a, b";rel=next'), 'https://x/3');
    });

    test('is null when there is none', () {
      expect(LinkHeader.next(null), isNull);
      expect(LinkHeader.next(''), isNull);
      expect(LinkHeader.next('<https://x/1>; rel="prev"'), isNull);
      expect(LinkHeader.next('<https://x/9>; rel="nextpage"'), isNull);
      expect(LinkHeader.next('not a link header'), isNull);
    });
  });

  group('SystemFlowClock.sleep', () {
    const clock = SystemFlowClock();

    test('returns at once for a wait of nothing, or when it was cancelled before it began', () async {
      await clock.sleep(Duration.zero);
      await clock.sleep(const Duration(seconds: -5));
      final token = ApiCancelToken()..cancel();

      await clock.sleep(const Duration(minutes: 10), cancel: token);
    });

    test('waits about as long as asked', () async {
      final clockTime = Stopwatch()..start();

      await clock.sleep(const Duration(milliseconds: 60));

      expect(clockTime.elapsedMilliseconds, greaterThanOrEqualTo(50));
    });

    test('ends early, and leaves no timer behind, when Stop is pressed during the wait', () async {
      final token = ApiCancelToken();
      final stopwatch = Stopwatch()..start();

      final waiting = clock.sleep(const Duration(minutes: 10), cancel: token);
      Future<void>.delayed(const Duration(milliseconds: 20), token.cancel);
      await waiting;

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
