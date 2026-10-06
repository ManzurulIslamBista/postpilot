// The GitLab CI job and the shell script that do what the GitHub workflow does.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/ci/domain/entities/ci_options.dart';
import 'package:postpilot/features/ci/domain/services/other_ci_builders.dart';
import 'package:yaml/yaml.dart';

Map<String, Object?> _parse(String text) => (jsonDecode(jsonEncode(loadYaml(text))) as Map).cast<String, Object?>();

const _secrets = [CiSecret('odooApiKey', 'ODOO_API_KEY'), CiSecret('db.password', 'DB_PASSWORD')];

void main() {
  group('GitLab CI', () {
    test('one job in the test stage on an image that has Flutter, with a JUnit report artifact', () {
      final doc = _parse(GitlabCiBuilder.build(const CiOptions(environment: 'Staging')));
      final job = doc['postpilot-api-tests'] as Map;
      expect(job['stage'], 'test');
      expect(job['image'], 'ghcr.io/cirruslabs/flutter:stable');
      expect(job['artifacts'], {
        'when': 'always',
        'paths': ['report.xml'],
        'reports': {'junit': 'report.xml'},
      });
    });

    test('the script clones PostPilot at the ref, runs pub get and then the command', () {
      final script = ((_parse(GitlabCiBuilder.build(const CiOptions(environment: 'Staging', postpilotRef: 'v1.2.3')))['postpilot-api-tests'] as Map)['script'] as List).cast<String>();
      expect(script, hasLength(4));
      expect(script[0], r'git clone https://github.com/ManzurulIslamBista/postpilot.git "$CI_PROJECT_DIR/.postpilot"');
      expect(script[1], r'git -C "$CI_PROJECT_DIR/.postpilot" checkout v1.2.3');
      expect(script[2], r'(cd "$CI_PROJECT_DIR/.postpilot" && flutter pub get)');
      expect(
        script[3],
        r'cd "$CI_PROJECT_DIR/.postpilot" && dart run bin/postpilot.dart run "$CI_PROJECT_DIR/workspace.json" '
        r'--env Staging --report junit --out "$CI_PROJECT_DIR/report.xml"',
      );
    });

    test('a colon-and-space or a quote in a name cannot turn a script line into a YAML mapping', () {
      final script = ((_parse(GitlabCiBuilder.build(const CiOptions(environment: "Ann's: EU")))['postpilot-api-tests'] as Map)['script'] as List).cast<String>();
      expect(script.last, contains(r"--env 'Ann'\''s: EU'"));
    });

    test('secrets are CI/CD variables mapped by name; the secret names are listed in a comment', () {
      final text = GitlabCiBuilder.build(const CiOptions(secrets: _secrets));
      final variables = ((_parse(text)['postpilot-api-tests'] as Map)['variables'] as Map).cast<String, Object?>();
      expect(variables, {'POSTPILOT_VAR_odooApiKey': r'$ODOO_API_KEY', 'POSTPILOT_VAR_db.password': r'$DB_PASSWORD'});
      expect(text, contains('#   ODOO_API_KEY  (the value of the PostPilot variable odooApiKey)'));
    });

    test('no secrets, no variables block', () {
      expect(((_parse(GitlabCiBuilder.build(const CiOptions()))['postpilot-api-tests']) as Map).containsKey('variables'), isFalse);
    });

    test('a schedule is explained in a comment (GitLab keeps schedules outside the YAML) with the cron pattern', () {
      final text = GitlabCiBuilder.build(const CiOptions(schedule: CiSchedulePreset.weekdays));
      expect(text, contains('Pipeline schedules'));
      expect(text, contains('17 6 * * 1-5'));
    });

    test('flags and the production warning follow the options', () {
      final text = GitlabCiBuilder.build(const CiOptions(failOnSkip: true, allowProduction: true));
      expect(text, contains('--fail-on-skip --allow-production'));
      expect(text, contains('WARNING: --allow-production is on'));
    });

    test('refuses a value that must not reach a command', () {
      expect(() => GitlabCiBuilder.build(const CiOptions(environment: 'a\nb')), throwsArgumentError);
    });
  });

  group('shell script', () {
    test('is a strict bash script that clones PostPilot into a temporary folder and cleans up', () {
      final text = ShellScriptBuilder.build(const CiOptions(environment: 'Staging', postpilotRef: 'main'));
      final lines = text.split('\n');
      expect(lines.first, '#!/usr/bin/env bash');
      expect(text, contains('set -euo pipefail'));
      expect(text, contains(r'WORK="$(mktemp -d)"'));
      expect(text, contains(r"""trap 'rm -rf "$WORK"' EXIT"""));
      expect(text, contains(r'git clone https://github.com/ManzurulIslamBista/postpilot.git "$WORK/postpilot"'));
      expect(text, contains(r'git -C "$WORK/postpilot" checkout main'));
      expect(text, contains(r'(cd "$WORK/postpilot" && flutter pub get)'));
      expect(
        text,
        contains(r'dart run bin/postpilot.dart run "$ROOT/workspace.json" --env Staging --report junit --out "$ROOT/report.xml"'),
      );
    });

    test('secrets are read from the environment, checked first and passed through env', () {
      final text = ShellScriptBuilder.build(const CiOptions(secrets: _secrets));
      expect(text, contains(r': "${ODOO_API_KEY:?Set ODOO_API_KEY (the value of the PostPilot variable odooApiKey)}"'));
      expect(text, contains(r': "${DB_PASSWORD:?Set DB_PASSWORD (the value of the PostPilot variable db.password)}"'));
      // `env` can set a name with a dot, which a shell assignment cannot.
      expect(text, contains(r'env "POSTPILOT_VAR_odooApiKey=$ODOO_API_KEY" "POSTPILOT_VAR_db.password=$DB_PASSWORD" \'));
      // The required-variable checks come before anything is downloaded.
      expect(text.indexOf('ODOO_API_KEY:?'), lessThan(text.indexOf('git clone')));
    });

    test('no secrets: no env prefix and no checks', () {
      final text = ShellScriptBuilder.build(const CiOptions());
      expect(text, isNot(contains(':?')));
      expect(text, isNot(contains('env "POSTPILOT_VAR_')));
    });

    test('writes no secret value, only names', () {
      final text = ShellScriptBuilder.build(const CiOptions(secrets: _secrets));
      expect(RegExp(r'=\s*["\x27]?[A-Za-z0-9+/]{20,}').hasMatch(text), isFalse);
    });

    test('a ref with a dash at the start is refused', () {
      expect(() => ShellScriptBuilder.build(const CiOptions(postpilotRef: '-x')), throwsArgumentError);
    });
  });
}
