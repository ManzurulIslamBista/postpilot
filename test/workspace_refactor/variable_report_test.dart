// The "unused and undefined variables" report on a small workspace built by hand, where each variable is placed so
// that the right answer can be read off the fixture.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_report.dart';

import 'refactor_fixtures.dart';

WorkspaceSnapshot workspace() => WorkspaceSnapshot([
  collection(
    1,
    'Shop',
    description: 'Set {{docOnly}} before you start.',
    auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{shopToken}}'),
    defaults: LevelDefaults(headers: [row('X-Stage', '{{stage}}')]),
  ),
  collectionVar(2, 'cvUsed', 'c'),
  collectionVar(3, 'cvUnused', 'c'),
  req(
    10,
    'List',
    url: '{{baseUrl}}/list',
    headers: [row('X-Id', '{{ spaced }}'), row('X-Guid', r'{{$guid}}'), row('X-Odoo', '{{xmlid:base.main_company}}')],
    body: const RequestBody(type: BodyType.raw, rawText: '{"c":"{{cvUsed}}","e":"{{emptyVar}}"}'),
  ),
  req(
    11,
    'Missing',
    url: '{{missingHost}}/x',
    // A row that is switched off is not sent, so what it refers to does not matter.
    headers: [row('X-Off', '{{disabledOnly}}', enabled: false)],
    body: const RequestBody(type: BodyType.raw, rawText: 'see {{ghost}}'),
    assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: '{{noTest}}')],
  ),
  req(12, 'Dormant user', url: '{{baseUrl}}/d', headers: [row('X-D', '{{dormant}}')]),
  req(
    13,
    'Login',
    extractors: [ExtractorEntity(path: r'$.id', variableKey: 'orderId'), ExtractorEntity(path: r'$.n', variableKey: 'targetNobodyReads')],
  ),
  req(14, 'Get order', url: '{{baseUrl}}/orders/{{orderId}}'),
  folder(
    20,
    'Orders',
    defaults: LevelDefaults(variables: [DefaultVariable(key: 'folderUsed', value: 'f'), DefaultVariable(key: 'folderUnused', value: 'f')]),
  ),
  req(15, 'In folder', folderId: 20, parent: const ['Shop', 'Orders'], url: '{{baseUrl}}/{{folderUsed}}'),
  collection(30, 'Other', auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{noSuchToken}}')),
  req(21, 'Inherited', collectionId: 30, parent: const ['Other'], url: 'https://other.test'),
  envVar(100, 'Dev', 'baseUrl', 'https://x.test'),
  envVar(101, 'Dev', 'shopToken', 't'),
  envVar(102, 'Dev', 'legacy', 'old'),
  envVar(103, 'Dev', 'stage', 'dev'),
  envVar(104, 'Dev', 'chained', '{{baseUrl}}/c'),
  envVar(105, 'Dev', 'spaced', 's'),
  envVar(106, 'Dev', 'orphanSecret', 'x', secret: true),
  envVar(107, 'Dev', 'dormant', 'zzz', enabled: false),
  envVar(108, 'Dev', 'chain2', '{{undefinedInValue}}'),
  envVar(109, 'Dev', 'emptyVar', ''),
  envVar(110, 'Dev', 'docOnly', 'd'),
  globalVar(200, 'gUnused', 'g'),
]);

void main() {
  final report = VariableReport.build(workspace());

  group('unused variables', () {
    test('lists the variables nothing refers to, sorted, and only those', () {
      expect([for (final u in report.unused) u.name], [
        'chain2', // nothing uses it (it uses an undefined name, which does not count as a use of itself)
        'chained', // its own value refers to baseUrl, but nobody refers to it
        'cvUnused',
        'folderUnused',
        'gUnused',
        'legacy',
        'orphanSecret',
      ]);
    });

    test('a use anywhere counts: a URL, a header with spaces, a body, a default, a note, a variable value, a folder', () {
      final unused = {for (final u in report.unused) u.name};
      for (final used in ['baseUrl', 'spaced', 'cvUsed', 'stage', 'shopToken', 'docOnly', 'folderUsed', 'emptyVar', 'dormant']) {
        expect(unused, isNot(contains(used)), reason: used);
      }
    });

    test('an extractor target is a definition the report cannot delete, so it is never offered', () {
      expect(report.unused.any((u) => u.name == 'targetNobodyReads'), isFalse);
    });

    test('each place that defines an unused name is its own deletion, with the scope worded for the user', () {
      final legacy = report.unused.firstWhere((u) => u.name == 'legacy').definitions.single;
      expect(legacy.id, 'environmentVariable:102|row');
      expect(legacy.where, 'Environment "Dev"');
      expect(legacy.reason, 'Never referenced');
      expect(report.unused.firstWhere((u) => u.name == 'folderUnused').definitions.single.id, 'folder:20|defaults.var.1');
      expect(report.unused.firstWhere((u) => u.name == 'cvUnused').definitions.single.where, 'Collection "Shop"');
      expect(report.unused.firstWhere((u) => u.name == 'gUnused').definitions.single.where, 'Globals');
    });

    test('a secret value is masked', () {
      expect(report.unused.firstWhere((u) => u.name == 'orphanSecret').definitions.single.shownValue, '••••••');
      expect(report.unused.firstWhere((u) => u.name == 'legacy').definitions.single.shownValue, 'old');
    });

    test('a name defined in several scopes is one entry with a deletion for each', () {
      final snapshot = WorkspaceSnapshot([envVar(1, 'Dev', 'dup', 'a'), envVar(2, 'Prod', 'dup', 'b', envId: 2), globalVar(3, 'dup', 'c')]);
      final unused = VariableReport.build(snapshot).unused.single;
      expect(unused.name, 'dup');
      expect([for (final d in unused.definitions) d.id], ['environmentVariable:1|row', 'environmentVariable:2|row', 'globalVariable:3|row']);
    });

    test('a reference with spaces in the braces is a use, a longer name is not', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'id', 'a'),
        envVar(2, 'Dev', 'idx', 'b'),
        req(3, 'R', url: '{{ id }}/{{idx2}}'),
      ]);
      expect([for (final u in VariableReport.build(snapshot).unused) u.name], ['idx']);
    });
  });

  group('undefined variables', () {
    test('lists the names used and defined nowhere, sorted', () {
      expect([for (final u in report.undefined) u.name], ['dormant', 'ghost', 'missingHost', 'noSuchToken', 'noTest', 'undefinedInValue']);
    });

    test('says where each is used, in the words a failed send uses', () {
      Map<String, List<String>> placesOf() => {for (final u in report.undefined) u.name: u.places};
      expect(placesOf()['missingHost'], ['Shop / Missing: the URL']);
      expect(placesOf()['ghost'], ['Shop / Missing: the request body']);
      expect(placesOf()['dormant'], ['Shop / Dormant user: the "X-D" header']);
      // The token is set on the collection and only inherited by its requests, so the collection is where to fix it.
      expect(placesOf()['noSuchToken'], ['Other: Default auth: Bearer token']);
    });

    test('also looks in the tests of a request and in the value of another variable', () {
      Map<String, List<String>> placesOf() => {for (final u in report.undefined) u.name: u.places};
      expect(placesOf()['noTest'], ['Shop / Missing: Test 1 (Body contains) expected value']);
      expect(placesOf()['undefinedInValue'], ['Environments / Dev: Variable "chain2" value']);
    });

    test('a dynamic variable, a live Odoo reference, a disabled row and a variable with an empty value are not problems', () {
      final names = {for (final u in report.undefined) u.name};
      expect(names, isNot(contains(r'$guid')));
      expect(names, isNot(contains('xmlid:base.main_company')));
      expect(names, isNot(contains('disabledOnly')));
      expect(names, isNot(contains('emptyVar')));
    });

    test('a name an extractor fills is defined', () {
      expect(report.undefined.any((u) => u.name == 'orderId'), isFalse);
    });

    test('a variable that exists but is switched off is reported, with the reason', () {
      final dormant = report.undefined.firstWhere((u) => u.name == 'dormant');
      expect(dormant.hint, 'It is defined, but only while disabled: Environment "Dev".');
      expect(report.undefined.firstWhere((u) => u.name == 'ghost').hint, isNull);
    });

    test('a name used twice in one request lists the places once each', () {
      final snapshot = WorkspaceSnapshot([
        req(1, 'R', url: '{{x}}/{{x}}', headers: [row('H', '{{x}}')]),
      ]);
      final use = VariableReport.build(snapshot).undefined.single;
      expect(use.places, ['Shop / R: the URL and the "H" header']);
    });
  });

  test('an empty workspace has nothing to report', () {
    final empty = VariableReport.build(WorkspaceSnapshot.empty);
    expect(empty.unused, isEmpty);
    expect(empty.undefined, isEmpty);
  });
}
