// Find and replace over a whole workspace, with no database: units built by hand and searched. The counts and texts
// below were worked out by reading the fixtures, not by calling the code under test.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_plan.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_scope.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/request_unit.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/workspace_finder.dart';

import 'refactor_fixtures.dart';

void main() {
  group('scopes', () {
    final snapshot = acmeWorkspace();

    test('every scope finds exactly its own occurrence', () {
      for (final scope in RefactorScope.values) {
        final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta', scopes: {scope});
        expect(plan.editCount, 1, reason: scope.name);
        expect(plan.changes.single.scope, scope, reason: scope.name);
      }
    });

    test('all scopes together find all twelve', () {
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta').editCount, 12);
    });

    test('an empty scope set finds nothing', () {
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta', scopes: {}).isEmpty, isTrue);
    });

    test('the changes come in the order of the workspace and say where they are', () {
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta');
      expect([for (final c in plan.changes) c.scope], [
        RefactorScope.defaults, // the collection's default header
        RefactorScope.names,
        RefactorScope.urls,
        RefactorScope.queryParams,
        RefactorScope.headers,
        RefactorScope.bodies,
        RefactorScope.auth,
        RefactorScope.scripts,
        RefactorScope.docs,
        RefactorScope.tags,
        RefactorScope.examples,
        RefactorScope.variables,
      ]);
      expect(plan.changes[1].trail, ['Shop', 'Acme list']);
      expect(plan.changes[1].label, 'Request name');
      expect(plan.changes.last.trail, ['Environments', 'Dev']);
    });
  });

  group('what an edit says', () {
    test('the old text, the new text and the words around it', () {
      final plan = WorkspaceFinder.plan(acmeWorkspace(), const FindOptions(query: 'acme'), 'Zeta', scopes: {RefactorScope.urls});
      final edit = plan.edits.single;
      // https://acme.test/orders: "acme" is at 8..12.
      expect([edit.start, edit.end], [8, 12]);
      expect(edit.before, 'acme');
      expect(edit.after, 'Zeta');
      expect(edit.lead, 'https://');
      expect(edit.tail, '.test/orders');
      expect(edit.id, 'request:100|url@8');
    });

    test('long text is cut around the match and line breaks become arrows', () {
      final text = '${'a' * 40}\nfind${'b' * 40}';
      final snapshot = WorkspaceSnapshot([req(1, 'R', body: RequestBody(type: BodyType.raw, rawText: text))]);
      final edit = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'find'), 'FOUND').edits.single;
      // 26 characters of context each side: the last 25 a's and the break, then the match, then the first 26 b's.
      expect(edit.lead, '…${'a' * 25}↵');
      expect(edit.tail, '${'b' * 26}…');
    });

    test('replacing a text with itself offers nothing', () {
      final plan = WorkspaceFinder.plan(acmeWorkspace(), const FindOptions(query: 'acme', caseSensitive: true), 'acme');
      expect(plan.isEmpty, isTrue);
    });

    test('every occurrence in one text is its own edit with its own id', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', url: 'a/b/a/b')]);
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'a'), 'X', scopes: {RefactorScope.urls});
      expect([for (final e in plan.edits) e.id], ['request:1|url@0', 'request:1|url@4']);
      expect(plan.changes.single.length, 7);
    });
  });

  group('options', () {
    test('a regular expression with groups gives each edit its own replacement', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', url: 'https://api.shop.test/v1/users/42/orders/7')]);
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: r'/(\w+)/(\d+)', regex: true), r'/$1/{$2}');
      expect([for (final e in plan.edits) e.after], ['/users/{42}', '/orders/{7}']);
    });

    test('an expression that does not compile is an error on the plan, not an exception', () {
      final plan = WorkspaceFinder.plan(acmeWorkspace(), const FindOptions(query: '(', regex: true), 'x');
      expect(plan.error, startsWith('Not a valid regular expression'));
      expect(plan.isEmpty, isTrue);
    });

    test('whole word and case apply to every field', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', url: 'user_id id Id', headers: [row('Id', 'id')])]);
      final loose = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'id'), 'x');
      final word = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'id', wholeWord: true, caseSensitive: true), 'x');
      // url: user_id, id, Id; header key Id; header value id.
      expect(loose.editCount, 5);
      // whole word + exact case: only the "id" of the URL and the header value.
      expect(word.editCount, 2);
    });
  });

  group('escaped JSON and unicode in bodies', () {
    // The body as stored: \" for a quote inside a string, a real é and 日本.
    const bs = r'\';
    final body = '{"msg":"say $bs"acme$bs" café 日本","n":1}';

    test('a quote written as backslash-quote is part of the text', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', body: RequestBody(type: BodyType.raw, rawText: body))]);
      final plan = WorkspaceFinder.plan(snapshot, FindOptions(query: '$bs"acme$bs"'), '$bs"zeta$bs"');
      final edit = plan.edits.single;
      expect(edit.before, '$bs"acme$bs"');
      // {0 "1 msg2-4 "5 :6 "7 say8-10 space11, then the backslash at 12.
      expect(edit.start, 12);
      expect(TextSplice.apply(body, [edit]), '{"msg":"say $bs"zeta$bs" café 日本","n":1}');
    });

    test('a non-latin word is replaced whole', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', body: RequestBody(type: BodyType.raw, rawText: body))]);
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: '日本'), '中国');
      expect(TextSplice.apply(body, plan.edits), '{"msg":"say $bs"acme$bs" café 中国","n":1}');
    });
  });

  group('secrets', () {
    final snapshot = WorkspaceSnapshot([
      envVar(1, 'Prod', 'apiKey', 'sk_live_acme_123', secret: true),
      envVar(2, 'Prod', 'host', 'acme.example'),
      globalVar(3, 'token', 'acme-global-secret', secret: true),
      req(10, 'Pay', auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'acme-literal-token')),
      req(11, 'Pay with variable', auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{acmeToken}}')),
      folder(
        20,
        'Billing',
        defaults: LevelDefaults(variables: [DefaultVariable(key: 'k', value: 'acme-folder-secret', isSecret: true)]),
      ),
    ]);

    test('secret values are not searched unless asked, and are only counted', () {
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta');
      // Not secret: the host value and the {{acmeToken}} reference. Secret and skipped: the key, the global, the
      // literal bearer token and the folder variable.
      expect([for (final c in plan.changes) '${c.unitKey}|${c.path}'], ['environmentVariable:2|value', 'request:11|auth.bearerToken']);
      expect(plan.secretSkipped, 4);
    });

    test('with include secret values they are found, but the plan never carries their text for the screen', () {
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'Zeta', includeSecret: true);
      expect(plan.secretSkipped, 0);
      final secretChanges = plan.changes.where((c) => c.secret).toList();
      expect(secretChanges, hasLength(4));
      for (final change in secretChanges) {
        for (final edit in change.edits) {
          expect(edit.lead, '');
          expect(edit.tail, '');
          expect(edit.shownBefore, '••••••');
          expect(edit.shownAfter, '••••••');
        }
      }
      // The real text is still in the edit, for the applier.
      expect(plan.changes.firstWhere((c) => c.unitKey == 'environmentVariable:1').edits.single.after, 'Zeta');
    });

    test('a value that only refers to variables is not a secret', () {
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acmeToken'), 'tok', scopes: {RefactorScope.auth});
      final change = plan.changes.single;
      expect(change.secret, isFalse);
      expect(change.edits.single.shownBefore, 'acmeToken');
      expect(change.edits.single.lead, '{{');
    });
  });

  group('what counts as part of an auth', () {
    test('the leftover of a type the user switched away from is listed, marked unused', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', auth: const RequestAuth(type: AuthType.none, basicUsername: 'acme-old'))]);
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'x');
      expect(plan.changes.single.label, 'Auth: user name (unused)');
    });

    test('a default that every new auth carries is not worth listing', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R')]);
      // A new auth holds Bearer as the JWT prefix, us-east-1 as the AWS region, and so on.
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'Bearer'), 'x').isEmpty, isTrue);
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'us-east-1'), 'x').isEmpty, isTrue);
    });

    test('but the default of the type in use is listed', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', auth: const RequestAuth(type: AuthType.jwtBearer))]);
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'Bearer'), 'x').editCount, 1);
    });

    test('an OAuth 2.0 token the app fetched is state, not text to search', () {
      final auth = const RequestAuth(type: AuthType.oauth2).withOAuth2Token('acme-access', null, refreshToken: 'acme-refresh');
      final snapshot = WorkspaceSnapshot([req(1, 'R', auth: auth)]);
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'x').isEmpty, isTrue);
    });
  });

  group('bodies', () {
    test('parts of a body of another type are listed, marked unused', () {
      final snapshot = WorkspaceSnapshot([
        req(1, 'R', body: const RequestBody(type: BodyType.none, rawText: 'acme raw', graphqlQuery: 'acme gql')),
      ]);
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'acme'), 'x');
      expect([for (final c in plan.changes) c.label], ['Raw body (unused)', 'GraphQL query (unused)']);
    });

    test('the "{}" a new GraphQL body holds is not worth listing', () {
      final snapshot = WorkspaceSnapshot([req(1, 'R', body: const RequestBody(type: BodyType.none))]);
      expect(WorkspaceFinder.plan(snapshot, const FindOptions(query: '{}'), 'x').isEmpty, isTrue);
    });
  });

  group('performance', () {
    test('10,000 requests are searched in well under a second', () {
      final units = [
        for (var i = 1; i <= 10000; i++)
          req(
            i,
            'Request $i',
            url: 'https://api.example.com/v1/items/$i',
            query: [row('page', '1'), row('q', 'term$i')],
            headers: [row('Accept', 'application/json'), row('X-Trace', 'trace-$i')],
            body: RequestBody(type: BodyType.raw, rawText: '{"id":$i,"name":"item $i","host":"{{baseUrl}}"}'),
            auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
            description: 'Request number $i of the benchmark.',
          ),
      ];
      final snapshot = WorkspaceSnapshot(units);

      final stopwatch = Stopwatch()..start();
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: 'example.com'), 'example.org');
      stopwatch.stop();

      // One occurrence in every URL, none anywhere else.
      expect(plan.editCount, 10000);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), reason: 'took ${stopwatch.elapsedMilliseconds} ms');
    });

    test('a regular expression over the same 10,000 requests is as quick', () {
      final snapshot = WorkspaceSnapshot([
        for (var i = 1; i <= 10000; i++)
          req(i, 'Request $i', url: 'https://api.example.com/v1/items/$i', headers: [row('X-Trace', 'trace-$i')]),
      ]);

      final stopwatch = Stopwatch()..start();
      final plan = WorkspaceFinder.plan(snapshot, const FindOptions(query: r'items/(\d+)', regex: true), r'things/$1');
      stopwatch.stop();

      expect(plan.editCount, 10000);
      expect(plan.edits.first.after, 'things/1');
      expect(plan.edits.last.after, 'things/10000');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), reason: 'took ${stopwatch.elapsedMilliseconds} ms');
    });
  });

  test('RequestUnit.fields skips what is empty, so a bare request lists only its name', () {
    expect([for (final f in req(1, 'Bare').fields()) f.path], ['name']);
  });

  test('a request unit sets any field it lists, and the copy lists the new text', () {
    final unit = req(1, 'R', url: 'u', query: [row('k', 'v')], headers: [row('H', 'x')], description: 'd', tags: ['t']);
    for (final field in unit.fields()) {
      final changed = field.write('NEW:${field.path}') as RequestUnit;
      final after = {for (final f in changed.fields()) f.path: f.value};
      expect(after[field.path], 'NEW:${field.path}', reason: field.path);
      // And nothing else moved.
      for (final other in unit.fields().where((f) => f.path != field.path)) {
        expect(after[other.path], other.value, reason: '${field.path} changed ${other.path}');
      }
    }
  });
}
