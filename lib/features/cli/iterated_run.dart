// Pure Dart (no Flutter): part of the command-line build.
import 'workspace_runner.dart';

/// A run made of one or more passes over the selected requests: `--iterations N`, or one pass per row of `--data`.
final class IteratedRun {
  /// One summary per pass that was made, in order.
  final List<RunSummary> passes;

  /// The data row each pass used (empty without `--data`).
  final List<Map<String, String>> rows;

  /// The total wall-clock time of every pass.
  final Duration duration;
  final bool failOnSkip;

  /// The run ended before the last planned pass because `--bail` stopped it.
  final bool stoppedEarly;

  const IteratedRun({
    required this.passes,
    required this.rows,
    required this.duration,
    this.failOnSkip = false,
    this.stoppedEarly = false,
  });

  bool get repeated => passes.length > 1;

  /// Every outcome of every pass, in the order they ran.
  List<RequestOutcome> get outcomes => [for (final pass in passes) ...pass.outcomes];

  /// The 1-based pass of each of [outcomes], same order.
  List<int> get iterations => [
        for (final (i, pass) in passes.indexed)
          for (final _ in pass.outcomes) i + 1,
      ];

  /// All passes as one summary, so the reports and the exit code treat a repeated run like any other.
  RunSummary get combined => RunSummary(outcomes, duration, failOnSkip: failOnSkip);
}

/// Runs [runner] once per pass. [optionsFor] builds the options of a pass from its data row (an empty map without
/// data); a column beats a `--var` of the same name, as in the app's runner, where the data row is the top scope.
///
/// Every pass starts from the same variables: what a request saved in one pass is not seen by the next (the app's
/// runner keeps it in the environment between passes; here nothing is written anywhere).
///
/// [bail] ends the whole run after the first pass in which something failed. [delay] is waited between passes too.
Future<IteratedRun> runIterated(
  WorkspaceRunner runner, {
  required RunOptions Function(Map<String, String> row) optionsFor,
  required Map<String, String> processVariables,
  List<Map<String, String>> data = const [],
  int iterations = 1,
  bool bail = false,
  Duration delay = Duration.zero,
  bool failOnSkip = false,
  void Function(int pass, int total)? onPass,
  void Function(RequestOutcome outcome, int pass)? onResult,
}) async {
  final total = data.isEmpty ? iterations : data.length;
  final clock = Stopwatch()..start();
  final passes = <RunSummary>[];
  final rows = <Map<String, String>>[];
  var stoppedEarly = false;
  for (var pass = 1; pass <= total; pass++) {
    final row = data.isEmpty ? const <String, String>{} : data[pass - 1];
    onPass?.call(pass, total);
    final summary = await runner.run(
      optionsFor(row),
      processVariables: processVariables,
      onResult: onResult == null ? null : (o) => onResult(o, pass),
    );
    passes.add(summary);
    rows.add(row);
    if (bail && summary.failed > 0) {
      stoppedEarly = pass < total;
      break;
    }
    if (pass < total && delay > Duration.zero) await Future<void>.delayed(delay);
  }
  return IteratedRun(passes: passes, rows: rows, duration: clock.elapsed, failOnSkip: failOnSkip, stoppedEarly: stoppedEarly);
}
