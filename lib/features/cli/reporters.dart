import 'dart:convert';
import '../documentation/domain/services/secret_masker.dart';
import 'workspace_runner.dart';

/// Turns a finished run into text for a terminal, a CI system or another program.
abstract final class RunReporters {
  /// One line while it runs (`✔ GET  200  120 ms  Get user`).
  static String line(RequestOutcome o, {bool color = false}) {
    String paint(String code, String s) => color ? '\u001b[${code}m$s\u001b[0m' : s;
    if (o.skipped != null) return '${paint('33', '–')} ${o.method.padRight(6)} ${'skip'.padLeft(4)}  ${''.padLeft(7)}  ${_label(o)}  ${paint('2', o.skipped!)}';
    final mark = o.passed ? paint('32', '✔') : paint('31', '✖');
    final status = o.status == null ? 'ERR' : '${o.status}';
    final shown = o.passed ? status : paint('31', status);
    final time = '${o.duration.inMilliseconds} ms'.padLeft(7);
    final buffer = StringBuffer('$mark ${o.method.padRight(6)} ${shown.padLeft(4)}  $time  ${_label(o)}');
    for (final f in o.failures) {
      buffer.write('\n    ${paint('31', '↳ $f')}');
    }
    final scripts = o.scripts;
    if (scripts.assertions.isNotEmpty) {
      buffer.write('  ${paint('2', '(${scripts.passedCount}/${scripts.assertions.length} tests)')}');
    }
    return buffer.toString();
  }

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
      b.writeln(paint('33', 'Skipped, not sent${s.failOnSkip ? ' (--fail-on-skip: this fails the run)' : ''}:'));
      for (final o in skipped) {
        b.writeln('  ${o.method.padRight(6)} ${_label(o)}: ${o.skipped}');
      }
    }
    return b.toString();
  }

  /// JUnit XML, which GitHub Actions, GitLab, Jenkins and Azure Pipelines all read.
  static String junit(RunSummary s) {
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
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
        final label = [if (o.folder.isNotEmpty) o.folder, o.name].join(' / ');
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

  static String json(RunSummary s) => const JsonEncoder.withIndent('  ').convert({
        'ok': s.ok,
        'total': s.total,
        'passed': s.passed,
        'failed': s.failed,
        'skipped': s.skipped,
        'durationMs': s.duration.inMilliseconds,
        'requests': [
          for (final o in s.outcomes)
            {
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
              // What a check saw is a piece of the response, so it is masked like the rest of the report.
              'assertions': [
                for (final a in o.scripts.assertions)
                  {'name': SecretMasker.maskMessage(a.name), 'passed': a.passed, 'actual': RequestOutcome.shownActual(a)},
              ],
            },
        ],
      });
}
