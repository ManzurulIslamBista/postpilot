final class AssertionResult {
  final String name;
  final bool passed;

  /// What the response actually had, shown next to a failed check.
  final String actual;

  const AssertionResult({required this.name, required this.passed, required this.actual});
}
