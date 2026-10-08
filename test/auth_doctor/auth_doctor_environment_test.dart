// The environment as a cause: a credential variable that lives in another environment, and a URL that points at one kind of server while
// the active environment says another. Also: the order of the findings, and what a run record can tell.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_doctor_input.dart';
import 'package:postpilot/features/auth_doctor/domain/entities/auth_finding.dart';
import 'package:postpilot/features/auth_doctor/domain/services/auth_doctor.dart';
import 'package:postpilot/features/auth_doctor/domain/services/environment_words.dart';
import 'auth_doctor_fixtures.dart';

void main() {
  group('a variable that lives in another environment', () {
    test('an undefined {{token}} that Staging fills in: the certain cause first, the likely fix after it', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer {{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
        others: const [AuthEnvironmentFacts('Staging', {'token'}), AuthEnvironmentFacts('Dev', {'baseUrl'})],
      ));

      expect(findings.first.id, 'credential.variable-undefined');
      expect(findings.first.fix, contains('It has a value in "Staging": switch to it.'));
      final elsewhere = byId(findings, 'environment.variable-elsewhere');
      expect(elsewhere.confidence, FindingConfidence.likely);
      expect(elsewhere.title, '{{token}} has a value in "Staging", not here');
      expect(elsewhere.fix, contains('Switch to "Staging"'));
      expect(elsewhere.evidence, contains('{{token}} is undefined there and has a value in: Staging.'));
      expect(findings.indexOf(elsewhere), greaterThan(0));
    });

    test('an empty variable, with two environments that fill it in', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer '},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
        variables: const {'token': AuthVariableFact(name: 'token', isEmpty: true, scopeName: 'Production')},
        others: const [AuthEnvironmentFacts('Staging', {'token'}), AuthEnvironmentFacts('Dev', {'token'})],
      ));

      final elsewhere = byId(findings, 'environment.variable-elsewhere');
      expect(elsewhere.title, '{{token}} has a value in "Staging" and "Dev", not here');
      expect(elsewhere.evidence, contains('{{token}} is empty there and has a value in: Staging, Dev.'));
    });

    test('when the active environment has the value there is nothing to say', () {
      final findings = AuthDoctor.diagnose(rejected(
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Production',
        variables: const {'token': AuthVariableFact(name: 'token', scopeName: 'Production')},
        others: const [AuthEnvironmentFacts('Staging', {'token'})],
      ));

      expect(ids(findings), isNot(contains('environment.variable-elsewhere')));
    });

    test('with no environment selected at all, the suggestion is to pick one', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer {{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        others: const [AuthEnvironmentFacts('Staging', {'token'})],
      ));

      expect(byId(findings, 'environment.variable-elsewhere').explanation, contains('no environment is active'));
    });
  });

  group('the host against the environment name', () {
    Iterable<AuthFinding> run(String url, String? environment) => AuthDoctor.diagnose(rejected(url: url, environment: environment));

    test('a production host with a staging environment', () {
      final finding = byId(run('https://prod.acme.com/v1/orders', 'Staging'), 'environment.host-mismatch');

      expect(finding.confidence, FindingConfidence.likely);
      expect(finding.title, 'The URL looks like production, the environment like staging');
      expect(finding.evidence, ['Active environment: Staging', 'Request host: prod.acme.com']);
    });

    test('a staging host with a production environment, and a local server with one', () {
      expect(byId(run('https://staging.acme.com/v1/orders', 'Production'), 'environment.host-mismatch').title,
          'The URL looks like staging, the environment like production');
      expect(ids(run('http://localhost:3000/v1/orders', 'Production (EU)')), contains('environment.host-mismatch'));
      expect(ids(run('https://api-dev.acme.com/v1/orders', 'live')), contains('environment.host-mismatch'));
    });

    test('they agree, say nothing, or there is no environment: no finding', () {
      expect(ids(run('https://prod.acme.com/v1/orders', 'Production')), isNot(contains('environment.host-mismatch')));
      expect(ids(run('https://staging.acme.com/v1/orders', 'Staging')), isNot(contains('environment.host-mismatch')));
      expect(ids(run('https://api.acme.com/v1/orders', 'Staging')), isNot(contains('environment.host-mismatch')));
      expect(ids(run('https://prod.acme.com/v1/orders', 'Acme')), isNot(contains('environment.host-mismatch')));
      expect(ids(run('https://prod.acme.com/v1/orders', null)), isNot(contains('environment.host-mismatch')));
    });

    test('the company\'s own name in the host is not a word about the server', () {
      // acme-prod.com is the registrable name; only the labels in front of it describe the server.
      expect(EnvironmentWords.kindOfHost('api.acme-test.com'), isNull);
      expect(EnvironmentWords.kindOfHost('test.acme.com'), ServerKind.staging);
      expect(EnvironmentWords.kindOfHost('api.live.acme.com'), ServerKind.production);
      expect(EnvironmentWords.kindOfHost('10.0.0.5'), isNull);
    });
  });

  group('the order of the findings', () {
    test('certain before likely before possible, and each level in the order the checks ran', () {
      final findings = AuthDoctor.diagnose(rejected(
        url: 'http://prod.acme.com/v1/orders',
        headers: const {'Authorization': 'Bearer {{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}'},
        environment: 'Staging',
        others: const [AuthEnvironmentFacts('Production', {'token'})],
      ));

      final levels = findings.map((f) => f.confidence.index).toList();
      expect(levels, orderedEquals([...levels]..sort()));
      expect(ids(findings), ['credential.variable-undefined', 'environment.variable-elsewhere', 'environment.host-mismatch', 'redirect.http']);
    });

    test('the same finding is listed once even when two credentials cause it', () {
      final findings = AuthDoctor.diagnose(rejected(
        headers: const {'Authorization': 'Bearer {{token}}', 'X-Api-Key': '{{token}}'},
        headerTemplates: const {'Authorization': 'Bearer {{token}}', 'X-Api-Key': '{{token}}'},
      ));

      expect(ids(findings).where((id) => id == 'credential.variable-undefined'), hasLength(1));
    });
  });

  group('a run record', () {
    const base = 'https://api.shop.test/orders';

    test('only a hedged finding when some requests to the host passed', () {
      final findings = AuthDoctor.diagnoseRun(const AuthRunFacts(status: 401, url: base, rejected: 12, passedOnSameHost: 68));

      expect(ids(findings), ['run.some-rejected']);
      expect(findings.single.confidence, FindingConfidence.possible);
      expect(findings.single.evidence, ['68 requests to api.shop.test passed in this run.']);
    });

    test('when nothing to the host passed, the credential as a whole is the suspect', () {
      final findings = AuthDoctor.diagnoseRun(const AuthRunFacts(status: 401, url: base, rejected: 12));

      expect(findings.single.id, 'run.all-rejected');
      expect(findings.single.confidence, FindingConfidence.likely);
      expect(findings.single.title, 'Every request to api.shop.test was rejected');
      expect(findings.single.fix, contains('Renew the credential once'));
    });

    test('a single rejected request proves nothing about the others', () {
      expect(AuthDoctor.diagnoseRun(const AuthRunFacts(status: 401, url: base)), isEmpty);
    });

    test('the environment against the host, from the run\'s own environment name', () {
      final findings = AuthDoctor.diagnoseRun(const AuthRunFacts(status: 401, url: 'https://prod.shop.test/orders', environment: 'Staging', rejected: 3));

      expect(findings.first.id, 'environment.host-mismatch');
    });

    test('403 gets its own words, and anything else is not a rejection', () {
      expect(AuthDoctor.diagnoseRun(const AuthRunFacts(status: 403, url: base, rejected: 4)).single.explanation, contains('the user as a whole is refused'));
      expect(AuthDoctor.diagnoseRun(const AuthRunFacts(status: 500, url: base, rejected: 4)), isEmpty);
    });
  });
}
