final class AssertionResult {
  final String name;
  final bool passed;

  /// What the response actually had, shown next to a failed check.
  final String actual;

  /// Where an inherited check was set (`folder "Auth"`); null for the request's own.
  final String? origin;

  const AssertionResult({required this.name, required this.passed, required this.actual, this.origin});

  AssertionResult fromOrigin(String origin) =>
      AssertionResult(name: name, passed: passed, actual: actual, origin: origin);
}
