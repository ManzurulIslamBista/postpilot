/// How much a change matters to someone who calls the API.
enum DriftSeverity {
  /// A client that worked against the baseline can stop working.
  breaking('Breaking'),

  /// Something new, or slower, that existing clients can live with.
  nonBreaking('Non-breaking'),

  /// Worth knowing, not a change of the contract.
  info('Info');

  final String label;
  const DriftSeverity(this.label);
}

/// What kind of change was found. The severity of one change can differ from its kind's usual one (a field that
/// became null is breaking when it was required and only non-breaking when it was optional).
enum DriftKind {
  statusClassChanged(DriftSeverity.breaking),
  statusChanged(DriftSeverity.nonBreaking),
  bodyNotJson(DriftSeverity.breaking),
  bodyNowJson(DriftSeverity.info),
  fieldRemoved(DriftSeverity.breaking),
  fieldAdded(DriftSeverity.nonBreaking),
  typeChanged(DriftSeverity.breaking),
  becameNull(DriftSeverity.breaking),
  nullFilled(DriftSeverity.nonBreaking),
  becameOptional(DriftSeverity.breaking),
  optionalFieldAbsent(DriftSeverity.info),
  elementsUnknown(DriftSeverity.info),
  enumValueGone(DriftSeverity.breaking),
  enumValueAdded(DriftSeverity.nonBreaking),
  valueChanged(DriftSeverity.info),
  contentTypeChanged(DriftSeverity.breaking),
  headerChanged(DriftSeverity.info),
  slower(DriftSeverity.nonBreaking);

  final DriftSeverity severity;
  const DriftKind(this.severity);
}

/// One difference between a response and the baseline.
final class DriftChange {
  final DriftKind kind;
  final DriftSeverity severity;

  /// The column path in the body, the header name, or empty for the status and the timing.
  final String path;

  /// What changed, in a sentence.
  final String message;

  const DriftChange({required this.kind, required this.severity, required this.path, required this.message});

  /// Names this change among the others of one report, and across reports of the same response.
  String get id => '${kind.name}|$path';
}

enum DriftVerdict { clean, info, nonBreaking, breaking }

/// Everything found when a response was compared with a baseline, the most serious first.
final class DriftReport {
  final List<DriftChange> changes;
  const DriftReport(this.changes);

  static const clean = DriftReport([]);

  int get breaking => _count(DriftSeverity.breaking);
  int get nonBreaking => _count(DriftSeverity.nonBreaking);
  int get info => _count(DriftSeverity.info);

  bool get isClean => changes.isEmpty;

  DriftVerdict get verdict {
    if (breaking > 0) return DriftVerdict.breaking;
    if (nonBreaking > 0) return DriftVerdict.nonBreaking;
    if (info > 0) return DriftVerdict.info;
    return DriftVerdict.clean;
  }

  List<DriftChange> ofSeverity(DriftSeverity severity) => [
        for (final c in changes)
          if (c.severity == severity) c,
      ];

  int _count(DriftSeverity severity) => changes.where((c) => c.severity == severity).length;
}
