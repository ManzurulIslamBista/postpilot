import 'dart:convert';
import '../documentation/domain/services/secret_masker.dart';
import '../request_flow/domain/entities/flow_report.dart';
import 'workspace_runner.dart';

/// Turns a finished run into text for a terminal, a CI system or another program.
abstract final class RunReporters {
  /// One line while it runs (`✔ GET  200  120 ms  Get user`).
  static String line(RequestOutcome o, {bool color = false, int? iteration}) {
    String paint(String code, String s) => color ? '\u001b[${code}m$s\u001b[0m' : s;
    // A repeated run (--iterations, --data) says which pass the line belongs to.
    final label = iteration == null ? _label(o) : '${_label(o)} (iteration $iteration)';
    if (o.skipped != null) return '${paint('33', '–')} ${o.method.padRight(6)} ${'skip'.padLeft(4)}  ${''.padLeft(7)}  $label  ${paint('2', o.skipped!)}';
    final mark = o.passed ? paint('32', '✔') : paint('31', '✖');
    final status = o.status == null ? 'ERR' : '${o.status}';
    final shown = o.passed ? status : paint('31', status);
    final time = '${o.duration.inMilliseconds} ms'.padLeft(7);
    final buffer = StringBuffer('$mark ${o.method.padRight(6)} ${shown.padLeft(4)}  $time  $label');
    for (final f in o.failures) {
      buffer.write('\n    ${paint('31', '↳ $f')}');
    }
    final scripts = o.scripts;
    if (scripts.assertions.isNotEmpty) {
      buffer.write('  ${paint('2', '(${scripts.passedCount}/${scripts.assertions.length} tests)')}');
    }
    // What retrying, polling and fetching pages did: "3 attempts", "polled 5 times", "5 pages, 482 items".
    if (o.flow case final flow? when flow.detailed.isNotEmpty) {
      buffer.write('  ${paint('2', '(${flow.detailed})')}');
    }
    for (final note in [...?o.flow?.notes]) {
      buffer.write('\n    ${paint('2', '↳ $note')}');
    }
    // A token renewed for this request, or a re-login that ran, is said below it: nothing happens silently.
    for (final note in o.notes) {
      buffer.write('\n    ${paint('2', '↳ $note')}');
    }
    return buffer.toString();
  }

  /// What the flow around a request did, as data: the tries one by one, the notes, and why it failed if it did.
  static Map<String, Object?>? flowJson(FlowReport? flow) => flow == null
      ? null
      : {
          'summary': flow.summary,
          'attempts': [for (final a in flow.attempts) SecretMasker.maskMessage(a.text)],
          if (flow.notes.isNotEmpty) 'notes': [for (final n in flow.notes) SecretMasker.maskMessage(n)],
          if (flow.failure != null) 'failure': SecretMasker.maskMessage(flow.failure!),
        };

  static String _label(RequestOutcome o) => [o.collection, if (o.folder.isNotEmpty) o.folder, o.name].join(' / ');

  static String console(RunSummary s, {bool color = false}) {
    String paint(String code, String t) => color ? '\u001b[${code}m$t\u001b[0m' : t;
    final b = StringBuffer()
      ..writeln()
      ..writeln('${s.total} requests, ${paint('32', '${s.passed} passed')}, '
          '${s.failed == 0 ? '0 failed' : paint('31', '${s.failed} failed')}'
          '${s.skipped == 0 ? '' : ', ${s.skipped} skipped'} in ${(s.duration.inMilliseconds / 1000).toStringAsFixed(2)} s');
    final skipped = s.outcomes.where((o) => o.skipped != null).toList();
    if (skipped.isNotEmpty) {
      // Only a request that could not run fails the run under --fail-on-skip; one left out by its Run if was asked for.
      final failing = s.failOnSkip && skipped.any((o) => !o.skippedByRule);
      b.writeln(paint('33', 'Skipped, not sent${failing ? ' (--fail-on-skip: this fails the run)' : ''}:'));
      for (final o in skipped) {
        b.writeln('  ${o.method.padRight(6)} ${_label(o)}: ${o.skipped}');
      }
    }
    return b.toString();
  }

  /// JUnit XML, which GitHub Actions, GitLab, Jenkins and Azure Pipelines all read.
  ///
  /// [iterations] says which pass each outcome belongs to (same order as `s.outcomes`) when the run was repeated; the pass is
  /// then part of the test name, so two passes of one request are two test cases.
  static String junit(RunSummary s, {List<int>? iterations}) {
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
    final passOf = iterations == null ? null : {for (final (i, o) in s.outcomes.indexed) o: iterations[i]};
    final byCollection = <String, List<RequestOutcome>>{};
    for (final o in s.outcomes) {
      byCollection.putIfAbsent(o.collection, () => []).add(o);
    }
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<testsuites name="PostPilot" tests="${s.total}" failures="${s.failed}" skipped="${s.skipped}" time="${(s.duration.inMilliseconds / 1000).toStringAsFixed(3)}">');
    byCollection.forEach((name, list) {
      final failed = list.where((o) => !o.passed).length;
      final skipped = list.where((o) => o.skipped != null).length;
      final time = list.fold<int>(0, (a, o) => a + o.duration.inMilliseconds) / 1000;
      b.writeln('  <testsuite name="${esc(name)}" tests="${list.length}" failures="$failed" skipped="$skipped" time="${time.toStringAsFixed(3)}">');
      for (final o in list) {
        final pass = passOf?[o];
        final label = [if (o.folder.isNotEmpty) o.folder, o.name].join(' / ') + (pass == null ? '' : ' (iteration $pass)');
        b.write('    <testcase classname="${esc(name)}" name="${esc('${o.method} $label')}" time="${(o.duration.inMilliseconds / 1000).toStringAsFixed(3)}">');
        if (o.skipped != null) {
          b.write('<skipped message="${esc(o.skipped!)}"/>');
        } else if (!o.passed) {
          final text = o.failures.join('\n');
          b.write('<failure message="${esc(o.failures.isEmpty ? 'failed' : o.failures.first)}">${esc(text)}\n${esc('${o.method} ${o.url}')}</failure>');
        }
        b.writeln('</testcase>');
      }
      b.writeln('  </testsuite>');
    });
    b.writeln('</testsuites>');
    return b.toString();
  }

  /// [iterations] as for [junit]: each request then carries its `iteration`.
  static String json(RunSummary s, {List<int>? iterations}) => const JsonEncoder.withIndent('  ').convert({
        'ok': s.ok,
        'total': s.total,
        'passed': s.passed,
        'failed': s.failed,
        'skipped': s.skipped,
        'durationMs': s.duration.inMilliseconds,
        if (iterations != null) 'iterations': iterations.isEmpty ? 0 : iterations.reduce((a, b) => a > b ? a : b),
        'requests': [
          for (final (i, o) in s.outcomes.indexed)
            {
              if (iterations != null) 'iteration': iterations[i],
              'collection': o.collection,
              'folder': o.folder,
              'name': o.name,
              'method': o.method,
              'url': o.url,
              'status': o.status,
              'durationMs': o.duration.inMilliseconds,
              'passed': o.passed,
              'skipped': o.skipped,
              'failures': o.failures,
              'blocked': o.blocked,
              if (o.notes.isNotEmpty) 'notes': o.notes,
              if (o.skippedByRule) 'skippedByRule': true,
              'flow': ?flowJson(o.flow),
              // What a check saw is a piece of the response, so it is masked like the rest of the report.
              'assertions': [
                for (final a in o.scripts.assertions)
                  {'name': SecretMasker.maskMessage(a.name), 'passed': a.passed, 'actual': RequestOutcome.shownActual(a)},
              ],
            },
        ],
      });
}
