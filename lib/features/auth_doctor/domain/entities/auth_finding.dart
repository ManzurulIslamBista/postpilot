// Pure Dart (no Flutter, no database).

/// How sure the doctor is that a finding is why the server said no.
enum FindingConfidence {
  /// The request or the response proves it: an empty token, a token whose `exp` has passed, a server that says so.
  certain('Certain'),

  /// Fits what was sent and what came back, but the server never said so.
  likely('Likely'),

  /// Worth ruling out, with nothing in the exchange that points at it.
  possible('Possible');

  const FindingConfidence(this.label);

  final String label;
}

/// One reason a request may have been rejected: what it is, what it means, what to do, and what in the exchange says so.
final class AuthFinding {
  /// A stable name for tests and for telling findings apart (`jwt.expired`, `credential.variable-empty`).
  final String id;
  final FindingConfidence confidence;
  final String title;

  /// What it means, in plain words.
  final String explanation;

  /// The concrete thing to do about it.
  final String fix;

  /// What in the request and the response the finding rests on, one line each. A token shows only its first four
  /// characters and its length; no secret value is ever in here.
  final List<String> evidence;

  const AuthFinding({
    required this.id,
    required this.confidence,
    required this.title,
    required this.explanation,
    required this.fix,
    this.evidence = const [],
  });

  /// Everything the finding says as plain text, for a bug report.
  String toPlainText() => [
        '[${confidence.label}] $title',
        explanation,
        'Fix: $fix',
        for (final line in evidence) '  - $line',
      ].join('\n');

  @override
  String toString() => 'AuthFinding($id, ${confidence.name})';
}
