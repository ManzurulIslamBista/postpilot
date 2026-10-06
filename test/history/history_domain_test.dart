// The pure parts of History: cURL from a stored request, the body diff, the run budget, filters and search text.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_filter.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/services/history_body_diff.dart';
import 'package:postpilot/features/history/domain/services/history_curl.dart';
import 'package:postpilot/features/history/domain/services/history_run_budget.dart';
import 'package:postpilot/features/history/domain/services/history_search.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';

HistoryEntryEntity _entry(
  int id, {
  String method = 'GET',
  String url = 'https://api.test/x',
  int? status = 200,
  DateTime? sentAt,
  HistoryEntryMeta? meta,
}) =>
    HistoryEntryEntity(id: id, method: method, url: url, statusCode: status, durationMs: 10, sentAt: sentAt ?? DateTime(2026, 10, 6, 12), meta: meta);

void main() {
  group('Copy as cURL, template form', () {
    test('keeps {{variables}} and masked values as written and lays the command out like the code generator', () {
      final snapshot = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.post,
        url: '{{baseUrl}}/users',
        headers: [
          KeyValueItem(key: 'Authorization', value: 'Bearer {{token}}'),
          KeyValueItem(key: 'X-Trace', value: "it's"),
          KeyValueItem(key: 'X-Off', value: 'no', enabled: false),
          KeyValueItem(key: 'X-Empty', value: ''),
        ],
        queryParams: [KeyValueItem(key: 'id', value: '{{id}}')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"a":1}'),
      );

      expect(
        HistoryCurl.template(snapshot),
        "curl --location --request POST '{{baseUrl}}/users?id={{id}}' \\\n"
        "--header 'Authorization: Bearer {{token}}' \\\n"
        "--header 'X-Trace: it'\\''s' \\\n"
        "--header 'X-Empty;' \\\n"
        "--header 'Content-Type: application/json' \\\n"
        "--data-raw '{\"a\":1}'",
      );
    });

    test('writes the auth the request used as a header with the credential masked, and says when it cannot', () {
      final bearer = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.get,
        url: 'https://api.test/a',
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '••••••'),
      );
      final basic = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.get,
        url: 'https://api.test/a',
        auth: const RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: '••••••'),
      );
      final apiKeyInQuery = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.get,
        url: 'https://api.test/a',
        auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'key', apiKeyValue: '{{apiKey}}', apiKeyLocation: ApiKeyLocation.query),
      );

      expect(HistoryCurl.template(bearer), contains("--header 'Authorization: Bearer ••••••'"));
      expect(HistoryCurl.template(basic), contains("--header 'Authorization: Basic ••••••'"));
      expect(HistoryCurl.template(basic), endsWith('\n# Basic Auth credentials are not part of History: add them before running this.'));
      expect(HistoryCurl.template(apiKeyInQuery), startsWith("curl --location --request GET 'https://api.test/a?key={{apiKey}}'"));
    });

    test('a multipart form is --form fields and a urlencoded form one data string', () {
      final multipart = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.post,
        url: 'https://api.test/up',
        body: RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Hi'), KeyValueItem(key: 'x', value: 'y', enabled: false)]),
      );
      final urlEncoded = HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.post,
        url: 'https://api.test/f',
        body: RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [KeyValueItem(key: 'a', value: '1'), KeyValueItem(key: 'b', value: '2')]),
      );

      expect(HistoryCurl.template(multipart), "curl --location --request POST 'https://api.test/up' \\\n--form 'title=Hi'");
      expect(
        HistoryCurl.template(urlEncoded),
        "curl --location --request POST 'https://api.test/f' \\\n"
        "--header 'Content-Type: application/x-www-form-urlencoded' \\\n"
        "--data-raw 'a=1&b=2'",
      );
    });
  });

  group('comparing two response bodies', () {
    test('identical text, and nothing to compare', () {
      expect(HistoryBodyCompare.compare('{"a":1}', '{"a":1}'), isA<BodiesIdentical>());
      expect(HistoryBodyCompare.compare(null, '{"a":1}'), isA<BodiesUnavailable>());
      expect(HistoryBodyCompare.compare('', 'x'), isA<BodiesUnavailable>());
    });

    test('two JSON bodies are compared by structure, whatever their layout', () {
      final diff = HistoryBodyCompare.compare('{"a":1,"b":[1,2]}', '{\n  "c": true,\n  "a": 2,\n  "b": [1, 2, 3]\n}') as JsonBodiesDiff;

      expect(diff.result.changes.map((c) => (c.kind.name, c.path)).toList(), [('changed', 'a'), ('added', 'b[2]'), ('added', 'c')]);
    });

    test('JSON that only differs in layout has no changes; volatile keys can be ignored', () {
      final same = HistoryBodyCompare.compare('{"a":1,"b":2}', '{"b":2,"a":1}') as JsonBodiesDiff;
      expect(same.result.isIdentical, isTrue);

      final stamped = HistoryBodyCompare.compare('{"id":1,"updated_at":"x"}', '{"id":1,"updated_at":"y"}', ignoreKeys: {'updated_at'}) as JsonBodiesDiff;
      expect(stamped.result.isIdentical, isTrue);
    });

    test('other text is compared line by line, with the changed lines in order', () {
      final diff = HistoryBodyCompare.compare('a\nb\nc\nd', 'a\nB\nc\nd\ne') as LineBodiesDiff;

      expect([for (final l in diff.lines) '${l.kind.name}:${l.text}'], ['same:a', 'removed:b', 'added:B', 'same:c', 'same:d', 'added:e']);
      expect((diff.added, diff.removed, diff.cut), (2, 1, false));
    });

    test('a long unchanged stretch is summarised, two lines of context kept around a change', () {
      final before = [for (var i = 1; i <= 21; i++) 'l$i'].join('\n');
      final after = [for (var i = 1; i <= 21; i++) i == 11 ? 'L11' : 'l$i'].join('\n');

      final diff = HistoryBodyCompare.compare(before, after) as LineBodiesDiff;

      expect([for (final l in diff.lines) '${l.kind.name}:${l.text}'], [
        'skipped:8 unchanged lines',
        'same:l9',
        'same:l10',
        'removed:l11',
        'added:L11',
        'same:l12',
        'same:l13',
        'skipped:8 unchanged lines',
      ]);
    });

    test('bodies of more than the limit are compared on their first lines and say so', () {
      final before = [for (var i = 0; i < 2500; i++) 'line $i'].join('\n');
      final after = '$before\nextra';

      // The extra line is past line 2000: no difference in what is compared, but it says that is not all of it.
      final same = HistoryBodyCompare.compare(before, after) as LineBodiesDiff;
      expect((same.added, same.removed, same.cut), (0, 0, true));

      final changed = HistoryBodyCompare.compare(before, after.replaceFirst('line 5\n', 'five\n')) as LineBodiesDiff;
      expect(changed.cut, isTrue);
      expect((changed.added, changed.removed), (1, 1));
    });
  });

  group('the budget of a collection run', () {
    test('keeps a sample of the successes and more of the failures, then stops', () {
      final budget = HistoryRunBudget(limit: 5, okLimit: 2);

      final admitted = [
        budget.admit(statusCode: 200),
        budget.admit(statusCode: 204),
        budget.admit(statusCode: 200), // a third success is over the sample
        budget.admit(statusCode: 500),
        budget.admit(statusCode: null), // no response at all counts as a failure
        budget.admit(statusCode: 404),
        budget.admit(statusCode: 503), // over the limit of 5
      ];

      expect(admitted, [true, true, false, true, true, true, false]);
      expect(budget.recorded, 5);
    });

    test('the defaults are 20 successes and 50 in all', () {
      expect((HistoryRunBudget.defaultOkLimit, HistoryRunBudget.defaultLimit), (20, 50));
    });
  });

  group('the filter', () {
    final now = DateTime(2026, 10, 6, 15);

    test('status class: 2xx 3xx 4xx 5xx, and "no response" for a send that failed', () {
      expect([200, 204, 301, 404, 500, 599, null, 101].map(HistoryStatusClass.of).toList(), [
        HistoryStatusClass.success,
        HistoryStatusClass.success,
        HistoryStatusClass.redirect,
        HistoryStatusClass.clientError,
        HistoryStatusClass.serverError,
        HistoryStatusClass.serverError,
        HistoryStatusClass.failed,
        null,
      ]);
      const filter = HistoryFilter(statusClass: HistoryStatusClass.serverError);
      expect(filter.matchesFacets(_entry(1, status: 500), now), isTrue);
      expect(filter.matchesFacets(_entry(2, status: 404), now), isFalse);
      expect(filter.matchesFacets(_entry(3, status: null), now), isFalse);
      expect(const HistoryFilter(statusClass: HistoryStatusClass.failed).matchesFacets(_entry(3, status: null), now), isTrue);
    });

    test('method, collection and the day range are ANDed', () {
      final fromShop = _entry(1, method: 'POST', meta: const HistoryEntryMeta(collectionId: 3));
      const filter = HistoryFilter(method: 'POST', collectionId: 3, range: HistoryRange.today);

      expect(filter.matchesFacets(fromShop, now), isTrue);
      expect(filter.matchesFacets(_entry(2, method: 'GET', meta: const HistoryEntryMeta(collectionId: 3)), now), isFalse);
      expect(filter.matchesFacets(_entry(3, method: 'POST', meta: const HistoryEntryMeta(collectionId: 4)), now), isFalse);
      expect(filter.matchesFacets(_entry(4, method: 'POST'), now), isFalse, reason: 'an entry with no recorded collection is in none');
      expect(filter.matchesFacets(_entry(5, method: 'POST', meta: const HistoryEntryMeta(collectionId: 3), sentAt: DateTime(2026, 10, 5, 23, 59)), now), isFalse);
    });

    test('"today" starts at local midnight and "last 7 days" reaches six days back', () {
      const today = HistoryFilter(range: HistoryRange.today);
      const week = HistoryFilter(range: HistoryRange.week);

      expect(today.matchesFacets(_entry(1, sentAt: DateTime(2026, 10, 6, 0, 0)), now), isTrue);
      expect(today.matchesFacets(_entry(2, sentAt: DateTime(2026, 10, 5, 23, 59, 59)), now), isFalse);
      expect(week.matchesFacets(_entry(3, sentAt: DateTime(2026, 9, 30, 0, 0)), now), isTrue);
      expect(week.matchesFacets(_entry(4, sentAt: DateTime(2026, 9, 29, 23, 59)), now), isFalse);
      expect(const HistoryFilter().matchesFacets(_entry(5, sentAt: DateTime(2020)), now), isTrue);
    });

    test('copyWith can set a facet back to none', () {
      final filter = const HistoryFilter().copyWith(statusClass: HistoryStatusClass.success, method: 'GET', collectionId: 1);
      expect(filter.hasFacets, isTrue);

      final cleared = filter.copyWith(statusClass: null, method: null, collectionId: null);

      expect((cleared.statusClass, cleared.method, cleared.collectionId, cleared.hasFacets), (null, null, null, false));
      expect(const HistoryFilter(query: '  ').isActive, isFalse);
      expect(const HistoryFilter(query: 'x').isActive, isTrue);
    });
  });

  group('search text', () {
    test('is lower-cased and holds method, url, name, collection, environment, status and an excerpt of each body', () {
      final text = HistorySearch.searchText(
        method: 'POST',
        url: 'https://API.test/Users',
        requestName: 'Create User',
        collectionName: 'Shop',
        environmentName: 'Staging',
        statusCode: 500,
        statusMessage: 'Internal Server Error',
        requestBody: '{"Name":"Ann"}',
        responseBody: '{"Error":"Boom"}',
      );

      expect(text, 'post https://api.test/users create user shop staging 500 internal server error {"name":"ann"} {"error":"boom"}');
    });

    test('the excerpts are bounded', () {
      final text = HistorySearch.searchText(
        method: 'GET',
        url: 'u',
        requestBody: 'q' * 5000,
        responseBody: 'r' * 9000,
      );

      expect('q'.allMatches(text).length, HistorySearch.requestExcerptChars);
      expect('r'.allMatches(text).length, HistorySearch.responseExcerptChars);
    });

    test('a summary matches on its method, URL, status, message, name, collection and environment', () {
      final entry = _entry(
        1,
        method: 'POST',
        url: 'https://api.test/Orders',
        status: 502,
        meta: const HistoryEntryMeta(requestName: 'Place order', collectionName: 'Shop', environmentName: 'Prod', statusMessage: 'Bad Gateway'),
      );

      for (final hit in ['post', 'orders', '502', 'bad gate', 'place', 'shop', 'prod', '']) {
        expect(HistorySearch.matchesSummary(entry, hit), isTrue, reason: hit);
      }
      expect(HistorySearch.matchesSummary(entry, 'refund'), isFalse);
      expect(HistorySearch.normalise('  Mixed Case '), 'mixed case');
    });
  });
}
