// Pure Dart (no Flutter): part of the command-line build.
import 'dart:io';
import '../../cli/production_lock.dart';
import '../../cli/workspace_runner.dart';
import '../domain/entities/matrix_column.dart';
import '../domain/entities/matrix_grid.dart';
import '../domain/services/matrix_analysis.dart';
import '../domain/services/matrix_body.dart';
import '../domain/services/matrix_exporter.dart';

/// `postpilot run workspace.json --matrix Dev,Staging,Prod`: the same requests once per environment, then one grid that
/// shows where the environments disagree. With `--fail-on-diff` the exit code says so, for a CI job that keeps dev,
/// staging and production in step.
abstract final class MatrixCommand {
  /// `Dev, Staging ,Prod` as names; blanks and repeats dropped, the order kept.
  static List<String> parseEnvironments(String text) {
    final names = <String>[];
    for (final part in text.split(',')) {
      final name = part.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  /// The reports `--report` may name with `--matrix`.
  static const reports = {'console', 'markdown', 'csv'};

  /// The grid of [summaries], one per environment in [environments]'s order. Rows are the requests, in the order the
  /// first environment ran them (a request only a later environment ran follows); a request that appears twice under one
  /// name is told apart by its place.
  static MatrixGrid gridOf(List<String> environments, List<RunSummary> summaries) {
    final columns = [for (final e in environments) MatrixColumn(environment: e)];
    final rows = <String, MatrixRow>{};
    final cells = <(String, int), MatrixCell>{};
    for (final (index, summary) in summaries.indexed) {
      final seen = <String, int>{};
      for (final o in summary.outcomes) {
        final base = '${o.collection}/${o.folder}/${o.name}/${o.method}';
        final n = seen.update(base, (v) => v + 1, ifAbsent: () => 1);
        final key = n == 1 ? base : '$base#$n';
        rows.putIfAbsent(
          key,
          () => MatrixRow(
            key: key,
            name: o.name,
            method: o.method,
            folder: [o.collection, if (o.folder.isNotEmpty) o.folder].join(' / '),
            columns: columns.length,
          ),
        );
        cells[(key, index)] = _cellOf(o);
      }
    }
    final grid = MatrixGrid(columns, rows.values.toList());
    for (final entry in cells.entries) {
      grid.setCell(entry.key.$1, entry.key.$2, entry.value);
    }
    return grid;
  }

  static MatrixCell _cellOf(RequestOutcome o) {
    if (o.skipped != null) return MatrixCell.notSent(o.skipped!);
    final status = o.status;
    if (status == null) return MatrixCell.failed(o.error ?? 'No answer.');
    return MatrixCell.text(status: status, duration: o.duration, body: o.responseBody, contentType: _header(o.responseHeaders, 'content-type'));
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  /// Runs the matrix and prints it. Returns the process exit code: 0, 1 when `--fail-on-diff` found a difference (or
  /// nothing was compared), 2 for a usage error or a production lock refusal.
  ///
  /// [newRunner] gives a fresh [WorkspaceRunner] each time: every environment starts from the workspace as it is, with
  /// no cookie, no renewed token and no extracted variable of the one before. [base] holds the options every column
  /// shares (`--var`, `--collection`, `--timeout`, the production lock...); each column adds its environment.
  static Future<int> run({
    required String matrix,
    required WorkspaceRunner Function() newRunner,
    required RunOptions base,
    required Map<String, String> processVariables,
    required List<String> conflicting,
    required String report,
    required String? outPath,
    required bool failOnDiff,
    required bool includeWrites,
    required String workspacePath,
    required IOSink out,
    required IOSink err,
  }) async {
    final environments = parseEnvironments(matrix);
    if (conflicting.isNotEmpty) {
      err.writeln('--matrix chooses the environments itself, so it cannot be combined with ${conflicting.join(', ')}.');
      return 2;
    }
    if (environments.length < 2) {
      err.writeln('--matrix needs two or more environments to compare, for example --matrix Dev,Staging,Prod.');
      return 2;
    }
    if (!reports.contains(report)) {
      err.writeln('--report $report is not available with --matrix. Use console, markdown or csv.');
      return 2;
    }
    final known = newRunner().environmentNames;
    final unknown = [for (final e in environments) if (!known.contains(e)) e];
    if (unknown.isNotEmpty) {
      err.writeln('No environment named ${unknown.map((e) => '"$e"').join(', ')} in the workspace (it has ${known.isEmpty ? 'none' : known.join(', ')}).');
      return 2;
    }
    final options = [for (final e in environments) _columnOptions(base, e, includeWrites)];

    final unmatched = newRunner().unmatchedRequestSelectors(options.first);
    if (unmatched.isNotEmpty) {
      err.writeln(
        'No request matches ${unmatched.map((s) => '"$s"').join(', ')}. '
        'Use the request name, or Folder/Sub-folder/Name; "postpilot list $workspacePath" shows what is there.',
      );
      return 2;
    }

    // The production lock refuses the whole run up front, for every environment: sending to Dev and Staging and then
    // stopping at Production is worse than sending nothing. Reads still run, and reads are all a matrix sends unless
    // --include-writes says otherwise.
    final blocks = <ProductionBlock>[];
    final listed = <String>{};
    for (final column in options) {
      for (final block in newRunner().productionBlocks(column, processVariables: processVariables)) {
        if (listed.add('${column.environment}: ${block.line}')) blocks.add(block);
      }
    }
    if (blocks.isNotEmpty) {
      err.writeln(ProductionBlock.describe(
        blocks,
        howToAllow: 'Pass --allow-production to send them anyway, or leave out --include-writes.',
      ));
      return 2;
    }

    final summaries = <RunSummary>[];
    for (final column in options) {
      summaries.add(await newRunner().run(column, processVariables: processVariables));
    }
    final grid = gridOf(environments, summaries);
    final analysis = MatrixAnalysis.of(grid, mode: MatrixCompareMode.full);
    final title = [if (options.first.collection != null) options.first.collection!, 'matrix run'].join(' ');

    if (grid.rows.isEmpty) {
      err.writeln(
        'Nothing ran: no request matched${options.first.collection == null ? '' : ' collection "${options.first.collection}"'}'
        '${includeWrites ? '' : ' (with --matrix only GET, HEAD and OPTIONS requests are sent; --include-writes sends the others)'}.',
      );
      return 2;
    }

    final text = switch (report) {
      'markdown' => MatrixExporter.markdown(analysis, title: title),
      'csv' => MatrixExporter.csv(analysis),
      _ => MatrixExporter.text(analysis, title: title),
    };
    if (outPath != null) {
      try {
        File(outPath).writeAsStringSync(text);
        out.write(report == 'console' ? text : MatrixExporter.text(analysis, title: title));
        out.writeln('Report written to $outPath');
      } on FileSystemException catch (e) {
        err.writeln('Could not write the report to "$outPath": ${e.message}');
        out.write(text);
      }
    } else {
      out.write(text);
      if (report == 'csv') out.writeln();
    }

    if (!failOnDiff) return 0;
    final answered = grid.rows.any((r) => r.cells.any((c) => c?.hasResponse ?? false));
    if (!answered) {
      err.writeln('--fail-on-diff: nothing was compared, no request got an answer in any environment.');
      return 1;
    }
    if (analysis.hasDifferences) {
      err.writeln('--fail-on-diff: ${analysis.differingRows} of ${analysis.rows.length} request${analysis.rows.length == 1 ? '' : 's'} differ between ${environments.join(', ')}.');
      return 1;
    }
    return 0;
  }

  /// [base] for the column of [environment]: read-only unless writes were asked for.
  static RunOptions _columnOptions(RunOptions base, String environment, bool includeWrites) => RunOptions(
        environment: environment,
        variables: base.variables,
        agentVariables: base.agentVariables,
        collection: base.collection,
        folder: base.folder,
        requests: base.requests,
        bail: base.bail,
        timeout: base.timeout,
        verifySsl: base.verifySsl,
        delay: base.delay,
        production: base.production,
        failOnSkip: base.failOnSkip,
        readOnly: !includeWrites,
      );
}
