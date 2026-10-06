import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_script_translator.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';

/// `(type, path, expected)` of each assertion, so a test states the whole expectation in one line.
List<(AssertionType, String, String)> _checks(ScriptTranslation t) => [for (final a in t.assertions) (a.type, a.path, a.expected)];

List<(ExtractorSource, String, ExtractorScope, String)> _extracted(ScriptTranslation t) => [
  for (final x in t.extractors) (x.source, x.path, x.scope, x.variableKey),
];

void main() {
  ScriptTranslation translate(String script) => PostmanScriptTranslator.translateTests(script);

  group('status and header checks', () {
    test('pm.response.to.have.status inside a pm.test', () {
      final t = translate('''
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});
''');
      expect(_checks(t), [(AssertionType.statusEquals, '', '200')]);
      expect(t.untranslated, isEmpty);
    });

    test('pm.expect(pm.response.code) with eql, equal and be.equal', () {
      final t = translate('''
pm.expect(pm.response.code).to.eql(201);
pm.expect(pm.response.code).to.equal(204);
pm.expect(pm.response.code).to.be.equal(404);
''');
      expect(_checks(t), [
        (AssertionType.statusEquals, '', '201'),
        (AssertionType.statusEquals, '', '204'),
        (AssertionType.statusEquals, '', '404'),
      ]);
    });

    test('the named status shortcuts map to their documented codes', () {
      final t = translate('''
pm.response.to.be.ok;
pm.response.to.be.accepted;
pm.response.to.be.badRequest;
pm.response.to.be.unauthorized;
pm.response.to.be.forbidden;
pm.response.to.be.notFound;
pm.response.to.be.rateLimited;
pm.response.to.be.success;
''');
      expect(_checks(t), [
        (AssertionType.statusEquals, '', '200'),
        (AssertionType.statusEquals, '', '202'),
        (AssertionType.statusEquals, '', '400'),
        (AssertionType.statusEquals, '', '401'),
        (AssertionType.statusEquals, '', '403'),
        (AssertionType.statusEquals, '', '404'),
        (AssertionType.statusEquals, '', '429'),
        (AssertionType.statusIn2xx, '', ''),
      ]);
    });

    test('a status range of exactly 200 to 299 is the 2xx check, any other range is left out', () {
      final t = translate('''
pm.expect(pm.response.code).to.be.within(200, 299);
pm.expect(pm.response.code).to.be.within(200, 204);
''');
      expect(_checks(t), [(AssertionType.statusIn2xx, '', '')]);
      expect(t.untranslated, ['pm.expect(pm.response.code).to.be.within(200, 204)']);
    });

    test('a status given as a reason phrase cannot be checked and is listed', () {
      final t = translate('pm.response.to.have.status("OK");');
      expect(t.assertions, isEmpty);
      expect(t.untranslated, ['pm.response.to.have.status("OK")']);
    });

    test('header existence and equality, both spellings', () {
      final t = translate('''
pm.response.to.have.header("Content-Type");
pm.response.to.have.header('Content-Type', 'application/json');
pm.expect(pm.response.headers.get("X-Rate")).to.eql("5");
''');
      expect(_checks(t), [
        (AssertionType.headerExists, 'Content-Type', ''),
        (AssertionType.headerEquals, 'Content-Type', 'application/json'),
        (AssertionType.headerEquals, 'X-Rate', '5'),
      ]);
    });

    test('response time and body text', () {
      final t = translate('''
pm.expect(pm.response.responseTime).to.be.below(500);
pm.expect(pm.response.responseTime).to.be.lessThan(1000);
pm.expect(pm.response.text()).to.include("success");
pm.expect(pm.response.text()).to.contain('ok');
''');
      expect(_checks(t), [
        (AssertionType.responseTimeBelowMs, '', '500'),
        (AssertionType.responseTimeBelowMs, '', '1000'),
        (AssertionType.bodyContains, '', 'success'),
        (AssertionType.bodyContains, '', 'ok'),
      ]);
    });
  });

  group('checks on the JSON body', () {
    test('equality on nested keys, indexes and quoted keys, through a jsonData variable', () {
      final t = translate('''
var jsonData = pm.response.json();
pm.test("values", function () {
    pm.expect(jsonData.user.name).to.eql("Ann");
    pm.expect(jsonData.items[0].id).to.equal(7);
    pm.expect(jsonData["a.b"]).to.eql(true);
    pm.expect(jsonData.gone).to.eql(null);
});
''');
      expect(_checks(t), [
        (AssertionType.jsonPathEquals, 'user.name', 'Ann'),
        (AssertionType.jsonPathEquals, 'items[0].id', '7'),
        (AssertionType.jsonPathEquals, '["a.b"]', 'true'),
        (AssertionType.jsonPathEquals, 'gone', 'null'),
      ]);
      expect(t.untranslated, isEmpty);
    });

    test('pm.response.json() can be used inline, and JSON.parse(responseBody) is the same thing', () {
      final t = translate('''
pm.expect(pm.response.json().data.id).to.eql(1);
const body = JSON.parse(responseBody);
pm.expect(body.ok).to.eql(true);
''');
      expect(_checks(t), [
        (AssertionType.jsonPathEquals, 'data.id', '1'),
        (AssertionType.jsonPathEquals, 'ok', 'true'),
      ]);
    });

    test('exist, and type checks through a JSON Schema', () {
      final t = translate('''
const jsonData = pm.response.json();
pm.expect(jsonData.token).to.exist;
pm.expect(jsonData.id).to.be.a("number");
pm.expect(jsonData.tags).to.be.an('array');
pm.expect(jsonData).to.be.an("object");
''');
      expect(_checks(t), [
        (AssertionType.jsonPathExists, 'token', ''),
        (AssertionType.jsonSchema, 'id', '{"type":"number"}'),
        (AssertionType.jsonSchema, 'tags', '{"type":"array"}'),
        (AssertionType.jsonSchema, '', '{"type":"object"}'),
      ]);
    });

    test('have.property, with and without a value, also on a sub-object variable', () {
      final t = translate('''
const jsonData = pm.response.json();
const user = jsonData.user;
pm.expect(jsonData).to.have.property("id");
pm.expect(jsonData).to.have.property("role", "admin");
pm.expect(user).to.have.property('email');
''');
      expect(_checks(t), [
        (AssertionType.jsonPathExists, 'id', ''),
        (AssertionType.jsonPathEquals, 'role', 'admin'),
        (AssertionType.jsonPathExists, 'user.email', ''),
      ]);
    });

    test('an expected environment variable becomes the {{variable}} the evaluator resolves', () {
      final t = translate('''
const jsonData = pm.response.json();
pm.expect(jsonData.id).to.eql(pm.environment.get("userId"));
pm.expect(jsonData.n).to.eql(pm.variables.get('n'));
''');
      expect(_checks(t), [
        (AssertionType.jsonPathEquals, 'id', '{{userId}}'),
        (AssertionType.jsonPathEquals, 'n', '{{n}}'),
      ]);
    });

    test('number and string literals are normalised to what the evaluator compares', () {
      final t = translate(r'''
const d = pm.response.json();
pm.expect(d.a).to.eql(1.50);
pm.expect(d.b).to.eql(10.0);
pm.expect(d.c).to.eql(-3);
pm.expect(d.d).to.eql('it\'s');
pm.expect(d.e).to.eql("tab\there");
pm.expect(d.f).to.eql("http://x.test/a;b");
pm.expect(d.g).to.eql({"k": [1, 2]});
''');
      expect(_checks(t), [
        (AssertionType.jsonPathEquals, 'a', '1.5'),
        (AssertionType.jsonPathEquals, 'b', '10'),
        (AssertionType.jsonPathEquals, 'c', '-3'),
        (AssertionType.jsonPathEquals, 'd', "it's"),
        (AssertionType.jsonPathEquals, 'e', 'tab\there'),
        (AssertionType.jsonPathEquals, 'f', 'http://x.test/a;b'),
        (AssertionType.jsonPathEquals, 'g', '{"k":[1,2]}'),
      ]);
      expect(t.untranslated, isEmpty);
    });

    test('a value with surrounding spaces cannot be compared exactly (the evaluator trims it) and is left out', () {
      final t = translate('''
const d = pm.response.json();
pm.expect(d.a).to.eql(" padded ");
''');
      expect(t.assertions, isEmpty);
      expect(t.untranslated, hasLength(1));
    });
  });

  group('extractors', () {
    test('environment, global and collection variables, plus the legacy postman.set* calls', () {
      final t = translate('''
const jsonData = pm.response.json();
pm.environment.set("token", jsonData.access_token);
pm.globals.set("userId", jsonData.user.id);
pm.collectionVariables.set("first", jsonData.items[0]);
postman.setEnvironmentVariable("legacy", jsonData.legacy);
postman.setGlobalVariable("legacyGlobal", jsonData.g);
''');
      expect(_extracted(t), [
        (ExtractorSource.jsonPath, 'access_token', ExtractorScope.environment, 'token'),
        (ExtractorSource.jsonPath, 'user.id', ExtractorScope.global, 'userId'),
        (ExtractorSource.jsonPath, 'items[0]', ExtractorScope.environment, 'first'),
        (ExtractorSource.jsonPath, 'legacy', ExtractorScope.environment, 'legacy'),
        (ExtractorSource.jsonPath, 'g', ExtractorScope.global, 'legacyGlobal'),
      ]);
      expect(t.untranslated, isEmpty);
      expect(t.adjusted, hasLength(1));
      expect(t.adjusted.single, contains('pm.collectionVariables.set("first")'));
    });

    test('a response header is extracted from the header', () {
      final t = translate('pm.environment.set("loc", pm.response.headers.get("Location"));');
      expect(_extracted(t), [(ExtractorSource.header, 'Location', ExtractorScope.environment, 'loc')]);
    });

    test('a variable pointing into the response is followed', () {
      final t = translate('''
const user = pm.response.json().data.user;
pm.environment.set("uid", user.id);
''');
      expect(_extracted(t), [(ExtractorSource.jsonPath, 'data.user.id', ExtractorScope.environment, 'uid')]);
    });

    test('a constant, an unknown expression, an empty path and an unusable name are not extractors', () {
      final t = translate('''
const jsonData = pm.response.json();
pm.environment.set("k", "literal");
pm.environment.set("n", jsonData.items.length);
pm.environment.set("whole", jsonData);
pm.environment.set("bad name", jsonData.x);
pm.variables.set("local", jsonData.x);
''');
      expect(t.extractors, isEmpty);
      expect(t.untranslated, hasLength(5));
    });
  });

  group('what stays untranslated', () {
    test('negations, lengths, calls and unknown matchers are listed, never guessed', () {
      final t = translate('''
const jsonData = pm.response.json();
pm.expect(jsonData.x).to.not.eql(5);
pm.expect(jsonData.items.length).to.be.above(0);
pm.expect(jsonData.a).to.eql(someVariable);
pm.expect(jsonData.name).to.be.a("string").and.to.have.length.above(2);
pm.expect(jsonData.n).to.be.oneOf([1, 2]);
pm.response.to.be.json;
tests["Body is correct"] = responseBody.has("x");
''');
      expect(t.assertions, isEmpty);
      expect(t.untranslated, [
        'pm.expect(jsonData.x).to.not.eql(5)',
        'pm.expect(jsonData.items.length).to.be.above(0)',
        'pm.expect(jsonData.a).to.eql(someVariable)',
        'pm.expect(jsonData.name).to.be.a("string").and.to.have.length.above(2)',
        'pm.expect(jsonData.n).to.be.oneOf([1, 2])',
        'pm.response.to.be.json',
        'tests["Body is correct"] = responseBody.has("x")',
      ]);
    });

    test('console calls and comments do nothing a declarative runner could miss and are dropped silently', () {
      final t = translate('''
// pm.response.to.have.status(500);
/* pm.response.to.have.status(501); */
console.log("debug");
"use strict";
pm.response.to.have.status(200); // trailing comment
''');
      expect(_checks(t), [(AssertionType.statusEquals, '', '200')]);
      expect(t.untranslated, isEmpty);
    });

    test('control flow and a variable reassigned away from the response are listed', () {
      final t = translate('''
var jsonData = pm.response.json();
jsonData = {};
pm.expect(jsonData.a).to.eql(1);
if (pm.response.code === 200) {
  pm.environment.set("ok", "yes");
}
''');
      expect(t.assertions, isEmpty);
      expect(t.untranslated, [
        'jsonData = {}',
        'pm.expect(jsonData.a).to.eql(1)',
        'if (pm.response.code === 200) { pm.environment.set("ok", "yes"); }',
      ]);
    });

    test('a long statement is shortened in the list', () {
      final t = translate('someUnknownFunction(${'x' * 200});');
      expect(t.untranslated.single.length, 83);
      expect(t.untranslated.single, endsWith('...'));
    });
  });

  group('script shapes', () {
    test('arrow callbacks, statements without semicolons and expression bodies', () {
      final t = translate('''
const jsonData = pm.response.json()
pm.test("quick", () => pm.response.to.have.status(200))
pm.test("two", () => {
  pm.expect(jsonData.a).to.eql(1)
  pm.expect(jsonData.b).to.eql(2)
})
pm.test("async", async function () { pm.expect(jsonData.c).to.exist })
''');
      expect(_checks(t), [
        (AssertionType.statusEquals, '', '200'),
        (AssertionType.jsonPathEquals, 'a', '1'),
        (AssertionType.jsonPathEquals, 'b', '2'),
        (AssertionType.jsonPathExists, 'c', ''),
      ]);
      expect(t.untranslated, isEmpty);
    });

    test('a pm.test the translator cannot read is listed as one statement', () {
      final t = translate('pm.test("name", someNamedFunction);');
      expect(t.assertions, isEmpty);
      expect(t.untranslated, ['pm.test("name", someNamedFunction)']);
    });

    test('several statements on one line, and a chained call on the next line', () {
      final t = translate('''
pm.response.to.have.status(200); pm.response.to.have.header("A");
pm.expect(pm.response.code)
  .to.eql(200);
''');
      expect(_checks(t), [
        (AssertionType.statusEquals, '', '200'),
        (AssertionType.headerExists, 'A', ''),
        (AssertionType.statusEquals, '', '200'),
      ]);
    });

    test('describeStatements lists every real statement of a pre-request script, minus console noise', () {
      expect(
        PostmanScriptTranslator.describeStatements('''
console.log("hi");
const ts = Date.now();
pm.environment.set("ts", ts);
'''),
        ['const ts = Date.now()', 'pm.environment.set("ts", ts)'],
      );
    });
  });
}
