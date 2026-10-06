import 'assertion_result.dart';
import 'extractor_entity.dart';

final class ExtractionResult {
  final String key;
  final ExtractorScope scope;
  final String? value;

  /// Why nothing was written (not found, no active environment, ...); `null` on success.
  final String? error;

  /// Where an inherited extractor was set (`collection "Shop"`); null for the request's own.
  final String? origin;

  const ExtractionResult({required this.key, required this.scope, this.value, this.error, this.origin});

  bool get ok => error == null;

  ExtractionResult fromOrigin(String origin) =>
      ExtractionResult(key: key, scope: scope, value: value, error: error, origin: origin);
}

final class ScriptRunResult {
  final List<AssertionResult> assertions;
  final List<ExtractionResult> extracted;

  const ScriptRunResult({required this.assertions, required this.extracted});

  static const empty = ScriptRunResult(assertions: [], extracted: []);

  int get passedCount => assertions.where((a) => a.passed).length;
  int get failedCount => assertions.length - passedCount;
  bool get allPassed => failedCount == 0;
  bool get hasFailures => !allPassed || extracted.any((e) => !e.ok);
  bool get isEmpty => assertions.isEmpty && extracted.isEmpty;
}
