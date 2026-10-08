// Renaming a variable everywhere, on plain units: which texts change, which names are left alone, and what a name
// that is already taken does. Expected texts are written out by hand.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_plan.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/unit_field.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/variable_renamer.dart';

import 'refactor_fixtures.dart';

/// The text of [snapshot]'s field [path] of [unitKey] after the accepted edits of [plan].
String after(WorkspaceSnapshot snapshot, RefactorPlan plan, String unitKey, String path) {
  final field = snapshot.unit(unitKey)!.fields().firstWhere((f) => f.path == path);
  final change = plan.changes.firstWhere((c) => c.unitKey == unitKey && c.path == path);
  return TextSplice.apply(field.value, change.edits);
}

void main() {
  group('the names it accepts', () {
    test('an empty name, the same name, a dynamic variable and a bad character are refused with a reason', () {
      expect(VariableRenamer.validate('', 'x'), 'Pick the variable to rename.');
      expect(VariableRenamer.validate('a', ''), 'Type the new name.');
      expect(VariableRenamer.validate('a', 'a'), 'The new name is the same as the old one.');
      expect(VariableRenamer.validate(r'$guid', 'id'), contains('built-in dynamic variable'));
      expect(VariableRenamer.validate('id', r'$guid'), contains('belong to the built-in dynamic variables'));
      expect(VariableRenamer.validate('a b', 'c'), contains('is not a variable name'));
      expect(VariableRenamer.validate('a', 'b}'), contains('is not a valid variable name'));
    });

    test('letters, digits, underscore, dash and dot are fine, and spaces around are ignored', () {
      expect(VariableRenamer.validate(' base-url ', ' base.url_2 '), isNull);
    });

    test('the token as it is seen is accepted too: {{ baseUrl }} is baseUrl', () {
      expect(VariableRenamer.clean('{{baseUrl}}'), 'baseUrl');
      expect(VariableRenamer.clean('  {{ base.url }}  '), 'base.url');
      expect(VariableRenamer.clean('plain'), 'plain');
      expect(VariableRenamer.validate('{{old}}', '{{new}}'), isNull);
      final snapshot = WorkspaceSnapshot([req(1, 'R', url: '{{old}}/x')]);
      final plan = VariableRenamer.plan(snapshot, '{{ old }}', '{{new}}');
      expect(after(snapshot, plan, 'request:1', 'url'), '{{new}}/x');
    });

    test('a refused rename is a plan with an error and nothing to apply', () {
      final plan = VariableRenamer.plan(WorkspaceSnapshot([req(1, 'R', url: '{{a}}')]), 'a', 'a');
      expect(plan.error, isNotNull);
      expect(plan.isEmpty, isTrue);
    });
  });

  group('references', () {
    WorkspaceSnapshot snapshotOf(String url) => WorkspaceSnapshot([req(1, 'R', url: url)]);

    test('{{baseUrl}} is renamed and {{baseUrlV2}} is not', () {
      final snapshot = snapshotOf('{{baseUrl}}/a/{{baseUrlV2}}/b/{{baseUrl}}');
      final plan = VariableRenamer.plan(snapshot, 'baseUrl', 'host');
      expect(after(snapshot, plan, 'request:1', 'url'), '{{host}}/a/{{baseUrlV2}}/b/{{host}}');
    });

    test('a longer name that merely ends with it, or contains it, is left alone', () {
      final snapshot = snapshotOf('{{myBaseUrl}} {{baseUrl}} {{base}} {{baseUrl.x}} {{x-baseUrl}}');
      final plan = VariableRenamer.plan(snapshot, 'baseUrl', 'host');
      expect(after(snapshot, plan, 'request:1', 'url'), '{{myBaseUrl}} {{host}} {{base}} {{baseUrl.x}} {{x-baseUrl}}');
    });

    test('spaces inside the braces are kept: {{ old }} becomes {{ new }}', () {
      final snapshot = snapshotOf('{{ id }}|{{id }}|{{ id}}|{{  id  }}|{{id}}');
      final plan = VariableRenamer.plan(snapshot, 'id', 'uid');
      expect(after(snapshot, plan, 'request:1', 'url'), '{{ uid }}|{{uid }}|{{ uid}}|{{  uid  }}|{{uid}}');
    });

    test('adjacent and nested-looking references are each handled', () {
      final snapshot = snapshotOf('{{a}}{{b}}{{a}}{{{a}}}');
      final plan = VariableRenamer.plan(snapshot, 'a', 'x');
      // {{{a}}} is a brace followed by {{a}}.
      expect(after(snapshot, plan, 'request:1', 'url'), '{{x}}{{b}}{{x}}{{{x}}}');
    });

    test('a dynamic variable is never touched, even by a variable of the same plain name', () {
      final snapshot = snapshotOf(r'{{$guid}} {{guid}} {{$randomInt}}');
      final plan = VariableRenamer.plan(snapshot, 'guid', 'uuid');
      expect(after(snapshot, plan, 'request:1', 'url'), r'{{$guid}} {{uuid}} {{$randomInt}}');
    });

    test('names with dots, dashes and a dollar sign inside are matched literally', () {
      final snapshot = snapshotOf('{{user.id}} {{userXid}} {{a-b}} {{aXb}} {{a\$b}}');
      expect(after(snapshot, VariableRenamer.plan(snapshot, 'user.id', 'uid'), 'request:1', 'url'), '{{uid}} {{userXid}} {{a-b}} {{aXb}} {{a\$b}}');
      expect(after(snapshot, VariableRenamer.plan(snapshot, 'a-b', 'ab'), 'request:1', 'url'), '{{user.id}} {{userXid}} {{ab}} {{aXb}} {{a\$b}}');
      expect(after(snapshot, VariableRenamer.plan(snapshot, 'a\$b', 'ab'), 'request:1', 'url'), '{{user.id}} {{userXid}} {{a-b}} {{aXb}} {{ab}}');
    });

    test('the match is exact in case: {{BaseUrl}} is another variable', () {
      final snapshot = snapshotOf('{{BaseUrl}} {{baseUrl}}');
      final plan = VariableRenamer.plan(snapshot, 'baseUrl', 'host');
      expect(after(snapshot, plan, 'request:1', 'url'), '{{BaseUrl}} {{host}}');
    });

    test('plain text that only looks like the name is not a reference', () {
      final snapshot = snapshotOf('baseUrl and {baseUrl} and {{baseUrl');
      expect(VariableRenamer.plan(snapshot, 'baseUrl', 'host').isEmpty, isTrue);
    });
  });

  group('every place a reference can be', () {
    final snapshot = WorkspaceSnapshot([
      collection(
        1,
        'Shop',
        description: 'Uses {{old}}.',
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{old}}'),
        defaults: LevelDefaults(
          headers: [row('X-Old', '{{old}}')],
          assertions: [AssertionEntity(type: AssertionType.jsonPathEquals, path: r'$.id', expected: '{{old}}')],
        ),
      ),
      collectionVar(2, 'copy', '{{old}}/copy'),
      folder(
        10,
        'Orders',
        defaults: LevelDefaults(
          headers: [row('X-Folder', '{{old}}')],
          variables: [DefaultVariable(key: 'inner', value: '{{old}}-inner')],
          auth: const RequestAuth(type: AuthType.apiKey, apiKeyName: 'k', apiKeyValue: '{{old}}'),
        ),
      ),
      req(
        100,
        'Get {{old}}',
        folderId: 10,
        parent: const ['Shop', 'Orders'],
        url: '{{old}}/x',
        query: [row('q', '{{old}}')],
        headers: [row('{{old}}', 'v')],
        body: const RequestBody(type: BodyType.raw, rawText: '{"a":"{{old}}"}', graphqlQuery: '{ {{old}} }'),
        auth: const RequestAuth(type: AuthType.basic, basicUsername: '{{old}}', basicPassword: '{{old}}'),
        assertions: [AssertionEntity(type: AssertionType.bodyContains, expected: '{{old}}')],
        extractors: [ExtractorEntity(path: r'$.x', variableKey: 'new1')],
        description: 'See {{old}}',
      ),
    ]);

    test('URL, query, header names, bodies, auth, tests, notes, defaults, names and variable values change', () {
      final plan = VariableRenamer.plan(snapshot, 'old', 'new');
      final changed = {for (final c in plan.changes) '${c.unitKey}|${c.path}'};
      expect(changed, {
        'collection:1|doc',
        'collection:1|auth.bearerToken',
        'collection:1|defaults.header.0.value',
        'collection:1|defaults.assert.0.expected',
        'collectionVariable:2|value',
        'folder:10|defaults.header.0.value',
        'folder:10|defaults.var.0.value',
        'folder:10|defaults.auth.apiKeyValue',
        'request:100|name',
        'request:100|url',
        'request:100|query.0.value',
        'request:100|header.0.key',
        'request:100|body.raw',
        'request:100|body.graphqlQuery',
        'request:100|auth.basicUsername',
        'request:100|auth.basicPassword',
        'request:100|scripts.assert.0.expected',
        'request:100|doc',
      });
      expect(after(snapshot, plan, 'request:100', 'body.raw'), '{"a":"{{new}}"}');
      expect(after(snapshot, plan, 'request:100', 'name'), 'Get {{new}}');
      expect(after(snapshot, plan, 'request:100', 'header.0.key'), '{{new}}');
      expect(after(snapshot, plan, 'folder:10', 'defaults.var.0.value'), '{{new}}-inner');
    });

    test('saved response examples and tags are data, not references', () {
      final data = WorkspaceSnapshot([
        req(
          1,
          'R',
          tags: ['{{old}}'],
          examples: [ResponseExampleEntity(id: 1, requestId: 1, name: '{{old}}', statusCode: 200, headers: const {'X': '{{old}}'}, body: '{{old}}', savedAt: DateTime.utc(2026))],
        ),
      ]);
      expect(VariableRenamer.plan(data, 'old', 'new').isEmpty, isTrue);
    });
  });

  group('definitions', () {
    final snapshot = WorkspaceSnapshot([
      collectionVar(1, 'host', 'a.test'),
      folder(
        10,
        'F',
        defaults: LevelDefaults(variables: [DefaultVariable(key: 'host', value: 'b.test'), DefaultVariable(key: 'other', value: 'x')]),
      ),
      req(100, 'Login', extractors: [ExtractorEntity(path: r'$.h', variableKey: 'host'), ExtractorEntity(path: r'$.t', variableKey: 'token')]),
      envVar(5, 'Dev', 'host', 'dev.test'),
      envVar(6, 'Prod', 'host', 'prod.test', envId: 2),
      globalVar(7, 'host', 'global.test'),
    ]);

    test('the name is renamed wherever it is defined: environments, globals, collection, folder, extractor', () {
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      final definitions = plan.changes.where((c) => c.definition).map((c) => '${c.unitKey}|${c.path}').toSet();
      expect(definitions, {
        'collectionVariable:1|key',
        'folder:10|defaults.var.0.key',
        'request:100|scripts.extract.0.key',
        'environmentVariable:5|key',
        'environmentVariable:6|key',
        'globalVariable:7|key',
      });
      expect(after(snapshot, plan, 'environmentVariable:5', 'key'), 'server');
      expect(after(snapshot, plan, 'request:100', 'scripts.extract.0.key'), 'server');
      // Their values are not references, so they stay.
      expect(plan.changes.where((c) => !c.definition), isEmpty);
    });

    test('only the exact name: "other" and "token" stay', () {
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.changes.any((c) => c.unitKey == 'folder:10' && c.path == 'defaults.var.1.key'), isFalse);
      expect(plan.changes.any((c) => c.path == 'scripts.extract.1.key'), isFalse);
    });

    test('there is no conflict when the new name is free', () {
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.conflicts, isEmpty);
      expect(plan.needsConfirmation, isFalse);
      expect(plan.deletions, isEmpty);
    });
  });

  group('a new name that is already taken', () {
    test('two environments hold both names: the old one is deleted by the merge, the existing one kept', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'host', 'old-dev', envId: 1),
        envVar(2, 'Dev', 'server', 'existing-dev', envId: 1),
        envVar(3, 'Prod', 'host', 'old-prod', envId: 2),
        req(10, 'R', url: '{{host}}/x'),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');

      expect(plan.needsConfirmation, isTrue);
      expect(plan.conflicts, hasLength(1));
      final conflict = plan.conflicts.single;
      expect(conflict.where, 'Environment "Dev"');
      expect(conflict.collides, isTrue);
      expect(conflict.existingValue, 'existing-dev');
      expect(conflict.oldValue, 'old-dev');
      // Dev's old definition is deleted; Prod, which has no "server", is simply renamed.
      expect([for (final d in plan.deletions) d.id], ['environmentVariable:1|row']);
      expect(plan.deletions.single.reason, contains('"server"'));
      final renamed = plan.changes.where((c) => c.definition).map((c) => c.unitKey).toList();
      expect(renamed, ['environmentVariable:3']);
      // The references move to the name that stays.
      expect(after(snapshot, plan, 'request:10', 'url'), '{{server}}/x');
    });

    test('the new name defined elsewhere is a conflict too, but nothing is deleted', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'host', 'h'),
        globalVar(2, 'server', 'g'),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.conflicts.single.where, 'Globals');
      expect(plan.conflicts.single.collides, isFalse);
      expect(plan.deletions, isEmpty);
      expect(plan.changes.single.unitKey, 'environmentVariable:1');
    });

    test('a secret value in a conflict is masked', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'host', 'old-secret', secret: true),
        envVar(2, 'Dev', 'server', 'existing-secret', secret: true),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.conflicts.single.existingValue, '••••••');
      expect(plan.conflicts.single.oldValue, '••••••');
      expect(plan.deletions.single.shownValue, '••••••');
    });

    test('a folder variable that collides is cut out of its folder, and its other fields are not renamed', () {
      final snapshot = WorkspaceSnapshot([
        folder(
          10,
          'F',
          defaults: LevelDefaults(
            variables: [DefaultVariable(key: 'host', value: '{{host}}-x'), DefaultVariable(key: 'server', value: 'keep')],
          ),
        ),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.deletions.single.id, 'folder:10|defaults.var.0');
      // Nothing is renamed inside the variable that is about to go.
      expect(plan.changes, isEmpty);
    });

    test('an extractor that defines the new name does not collide with anything', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'host', 'h'),
        req(10, 'Login', extractors: [ExtractorEntity(path: r'$.s', variableKey: 'server')]),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'host', 'server');
      expect(plan.conflicts.single.where, 'Extractor of request "Login"');
      expect(plan.conflicts.single.collides, isFalse);
      expect(plan.deletions, isEmpty);
    });
  });

  group('secrets in the preview', () {
    test('a reference inside a secret value is renamed, and the preview shows only the mask', () {
      final snapshot = WorkspaceSnapshot([envVar(1, 'Dev', 'basic', 'user:{{pw}}:literal-secret', secret: true)]);
      final plan = VariableRenamer.plan(snapshot, 'pw', 'password');
      final change = plan.changes.single;
      expect(change.secret, isTrue);
      final edit = change.edits.single;
      expect([edit.lead, edit.shownBefore, edit.shownAfter, edit.tail], ['', '••••••', '••••••', '']);
      expect(edit.after, '{{password}}');
    });

    test('a literal credential in an auth field is masked while a reference to a variable is shown', () {
      final snapshot = WorkspaceSnapshot([
        req(1, 'Literal', auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'abc{{pw}}def')),
        req(2, 'Reference', auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{pw}}')),
      ]);
      final plan = VariableRenamer.plan(snapshot, 'pw', 'password');
      expect(plan.changes[0].edits.single.shownBefore, '••••••');
      expect(plan.changes[1].edits.single.shownBefore, '{{pw}}');
    });
  });

  group('the catalogue the rename box suggests from', () {
    test('lists each defined name once, sorted, with how many places define it', () {
      final snapshot = WorkspaceSnapshot([
        envVar(1, 'Dev', 'host', 'a'),
        envVar(2, 'Prod', 'Host', 'b', envId: 2),
        globalVar(3, 'host', 'c'),
        collectionVar(4, 'apiKey', 'd'),
        req(10, 'Login', extractors: [ExtractorEntity(path: r'$.t', variableKey: 'token')]),
      ]);
      expect([for (final n in snapshot.variableNames) n.name], ['apiKey', 'Host', 'host', 'token']);
      final host = snapshot.variableNames.firstWhere((n) => n.name == 'host');
      expect(host.definitions, 2);
      expect(host.homes, ['Environment "Dev"', 'Globals']);
      expect(snapshot.variableNames.firstWhere((n) => n.name == 'token').homes, ['Extractor of request "Login"']);
    });
  });

  test('the variable definitions know where they are', () {
    final snapshot = WorkspaceSnapshot([envVar(1, 'Dev', 'host', 'a', secret: true, enabled: false)]);
    final definition = snapshot.definitions.single;
    expect(definition.home, VariableHome.environment);
    expect(definition.id, 'environmentVariable:1|key');
    expect(definition.secret, isTrue);
    expect(definition.enabled, isFalse);
  });
}
