/// How a collection run repeats. With [dataRows] the run makes one pass per row
/// and [iterations] is ignored.
final class CollectionRunOptions {
  static const maxIterations = 1000;
  static const maxDelay = Duration(minutes: 10);

  final int iterations;

  /// Pause between two consecutive requests, across iteration boundaries too.
  final Duration delay;

  /// End the whole run at the first request that doesn't pass.
  final bool stopOnFailure;

  /// One map of variable values per iteration.
  final List<Map<String, String>> dataRows;

  const CollectionRunOptions({
    this.iterations = 1,
    this.delay = Duration.zero,
    this.stopOnFailure = false,
    this.dataRows = const [],
  });

  int get iterationCount => dataRows.isEmpty ? iterations.clamp(1, maxIterations) : dataRows.length;

  /// The data variables for the 1-based [iteration]; empty without data.
  Map<String, String> dataFor(int iteration) => dataRows.isEmpty ? const {} : dataRows[iteration - 1];
}
