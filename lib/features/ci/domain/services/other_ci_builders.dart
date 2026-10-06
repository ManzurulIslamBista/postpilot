// Pure Dart.
import '../entities/ci_options.dart';
import 'ci_options_validator.dart';
import 'postpilot_command.dart';

/// A `.gitlab-ci.yml` job for the same run. GitLab runs the job in a container that already holds Flutter, takes the
/// secrets from CI/CD variables of the same names as the GitHub ones, and reads `report.xml` as a JUnit report.
abstract final class GitlabCiBuilder {
  /// Where the job goes: add it to the project's `.gitlab-ci.yml`.
  static const path = '.gitlab-ci.yml';

  static String build(CiOptions o) {
    final problem = CiOptionsValidator.firstProblem(o);
    if (problem != null) throw ArgumentError(problem);
    final path = o.workspacePath.trim();
    final cron = o.cron;
    final ref = ShellQuote.word(o.postpilotRef.trim());
    final b = StringBuffer();
    b.writeln('# PostPilot API tests for GitLab CI. Add this job to .gitlab-ci.yml.');
    if (o.secrets.isNotEmpty) {
      b.writeln('#');
      b.writeln('# Create these CI/CD variables (Settings > CI/CD > Variables, masked and protected as you need), one per secret variable:');
      for (final line in PostpilotCommand.secretLines(o)) {
        b.writeln('#   $line');
      }
    }
    if (cron != null) {
      b.writeln('#');
      b.writeln('# Monitor: GitLab keeps schedules outside the YAML. Under Build > Pipeline schedules add one with the cron');
      b.writeln('# pattern $cron (choose its time zone there).');
    }
    if (o.allowProduction) {
      b.writeln('#');
      b.writeln('# WARNING: --allow-production is on. Every pipeline may send POST, PUT, PATCH and DELETE requests to production.');
    }
    b.writeln('postpilot-api-tests:');
    b.writeln('  stage: test');
    // A community image that ships the Flutter SDK; the PostPilot pubspec needs it for "pub get".
    b.writeln('  image: ghcr.io/cirruslabs/flutter:stable');
    if (o.secrets.isNotEmpty) {
      b.writeln('  variables:');
      for (final s in o.secrets) {
        b.writeln('    ${_key(s.processVariable)}: \$${s.secretName}');
      }
    }
    b.writeln('  script:');
    final command = PostpilotCommand.oneLine(
      o,
      workspace: '"\$CI_PROJECT_DIR/$path"',
      report: '"\$CI_PROJECT_DIR/${PostpilotCommand.reportFile}"',
    );
    for (final line in [
      'git clone ${PostpilotCommand.repositoryUrl}.git "\$CI_PROJECT_DIR/.postpilot"',
      'git -C "\$CI_PROJECT_DIR/.postpilot" checkout $ref',
      '(cd "\$CI_PROJECT_DIR/.postpilot" && flutter pub get)',
      'cd "\$CI_PROJECT_DIR/.postpilot" && $command',
    ]) {
      b.writeln('    - ${ShellQuote.yaml(line)}');
    }
    b.writeln('  artifacts:');
    b.writeln('    when: always');
    b.writeln('    paths:');
    b.writeln('      - ${PostpilotCommand.reportFile}');
    b.writeln('    reports:');
    b.writeln('      junit: ${PostpilotCommand.reportFile}');
    return b.toString();
  }

  static String _key(String key) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(key) ? key : ShellQuote.yaml(key);
}

/// A shell script that does the same on any machine with Flutter and git: a laptop, a cron job, Jenkins or any other CI.
abstract final class ShellScriptBuilder {
  static const fileName = 'postpilot-ci.sh';

  static String build(CiOptions o) {
    final problem = CiOptionsValidator.firstProblem(o);
    if (problem != null) throw ArgumentError(problem);
    final path = o.workspacePath.trim();
    final ref = ShellQuote.word(o.postpilotRef.trim());
    final b = StringBuffer();
    b.writeln('#!/usr/bin/env bash');
    b.writeln('# PostPilot API tests as a plain script. Run it from the root of the repository that holds "$path".');
    b.writeln('# It needs git and the Flutter SDK (PostPilot is a Flutter project: "pub get" needs it) on the PATH.');
    if (o.secrets.isNotEmpty) {
      b.writeln('#');
      b.writeln('# Set these environment variables before running it, one per secret variable:');
      for (final line in PostpilotCommand.secretLines(o)) {
        b.writeln('#   $line');
      }
    }
    if (o.allowProduction) {
      b.writeln('#');
      b.writeln('# WARNING: --allow-production is on: the run may send POST, PUT, PATCH and DELETE requests to production.');
    }
    b.writeln('set -euo pipefail');
    b.writeln();
    b.writeln('ROOT="\$(pwd)"');
    b.writeln('WORK="\$(mktemp -d)"');
    b.writeln('trap \'rm -rf "\$WORK"\' EXIT');
    b.writeln();
    for (final s in o.secrets) {
      b.writeln(': "\${${s.secretName}:?Set ${s.secretName} (the value of the PostPilot variable ${s.variable})}"');
    }
    if (o.secrets.isNotEmpty) b.writeln();
    b.writeln('git clone ${PostpilotCommand.repositoryUrl}.git "\$WORK/postpilot"');
    b.writeln('git -C "\$WORK/postpilot" checkout $ref');
    b.writeln('(cd "\$WORK/postpilot" && flutter pub get)');
    b.writeln();
    b.writeln('cd "\$WORK/postpilot"');
    // `env` takes a name such as POSTPILOT_VAR_db.password that a shell cannot assign itself.
    final prefix = o.secrets.isEmpty ? '' : 'env ${[for (final s in o.secrets) '"${s.processVariable}=\$${s.secretName}"'].join(' ')} \\\n    ';
    b.writeln('$prefix${PostpilotCommand.oneLine(o, workspace: '"\$ROOT/$path"', report: '"\$ROOT/${PostpilotCommand.reportFile}"')}');
    return b.toString();
  }
}
