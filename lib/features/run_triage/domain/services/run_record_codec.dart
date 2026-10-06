// Pure Dart: the command line uses it too.
import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';
import '../entities/run_record_doc.dart';

/// A record ready for the `run_records` table: every text masked, the results within the size cap.
final class PreparedRunRecord {
  final String environmentName;
  final String source;
  final int passed;
  final int failed;
  final int skipped;
  final int durationMs;
  final String summaryJson;
  final String resultsJson;
  final DateTime startedAt;

  const PreparedRunRecord({
    required this.environmentName,
    required this.source,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.durationMs,
    required this.summaryJson,
    required this.resultsJson,
    required this.startedAt,
  });
}

/// Makes a run safe to keep: masks every text (a failure message can quote a URL with a token, a check can quote a
/// response value), drops the query string and credentials from addresses, cuts long texts and keeps the whole
/// record under a size cap, failures first. Records stay on this device, but a log, a report or an issue made from
/// one must never carry a secret, so it is masked once, here, and everything downstream reads the masked copy.
abstract final class RunRecordCodec {
  /// The most characters the `resultsJson` column holds.
  static const maxResultsChars = 400000;

  /// Records kept per collection (see `RunRecordsDao.pruneCollection`).
  static const keepPerCollection = 50;

  static const _maxName = 160;
  static const _maxUrl = 240;
  static const _maxError = 400;
  static const _maxFailure = 300;
  static const _maxFailures = 8;
  static const _tightError = 160;
  static const _tightFailure = 120;
  static const _tightFailures = 3;

  static final _userInfo = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*://)[^/@\s]*@');

  /// [url] as a record keeps it: `https://api.test/orders/{{id}}`, without credentials, query and fragment.
  static String safeUrl(String url) {
    var text = url.trim();
    final cut = text.indexOf(RegExp(r'[?#]'));
    if (cut >= 0) text = text.substring(0, cut);
    text = text.replaceFirstMapped(_userInfo, (m) => m[1]!);
    return _clip(SecretMasker.maskMessage(text), _maxUrl);
  }

  /// A free text, masked and cut to [max] characters.
  static String safeText(String text, int max) => _clip(SecretMasker.maskMessage(text), max);

  static final _inheritedFrom = RegExp(r'\s*\(from [^)]*\)\s*$');

  /// A line a check wrote. Its name carries what it expects (`Header Authorization equals Bearer abc`,
  /// `data.apiKey equals s3cr3t`), and a value that is not a recognisable token would get past [SecretMasker.maskMessage],
  /// so when what the check looks at has the name of a credential, the expected value (and what was seen) is dropped.
  static String safeFailure(String line, int max) {
    final origin = _inheritedFrom.firstMatch(line);
    final body = origin == null ? line : line.substring(0, origin.start);
    final at = body.indexOf(' equals ');
    if (at > 0) {
      final subject = body.substring(0, at).trim();
      final name = subject.split(RegExp(r'\s+')).last;
      if (SecretMasker.isSensitiveName(name)) {
        return _clip(SecretMasker.maskMessage('$subject equals ${SecretMasker.mask}${origin?[0] ?? ''}'), max);
      }
    }
    return safeText(line, max);
  }

  static String _clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

  /// [doc] with every text masked and clipped, ready to store; the totals are kept as they are.
  static RunRecordDoc sanitize(RunRecordDoc doc) => doc.copyWith(
        environment: safeText(doc.environment, _maxName),
        results: [for (final r in doc.results) _sanitizeEntry(r, tight: false)],
      );

  static RunResultEntry _sanitizeEntry(RunResultEntry r, {required bool tight}) => RunResultEntry(
        requestId: r.requestId,
        name: safeText(r.name, _maxName),
        folder: safeText(r.folder, _maxName),
        method: safeText(r.method, 16),
        url: safeUrl(r.url),
        iteration: r.iteration,
        status: r.status,
        durationMs: r.durationMs,
        passed: r.passed,
        skipped: r.skipped == null ? null : safeText(r.skipped!, _maxError),
        error: r.error == null ? null : safeText(r.error!, tight ? _tightError : _maxError),
        failures: [
          for (final f in r.failures.take(tight ? _tightFailures : _maxFailures))
            safeFailure(f, tight ? _tightFailure : _maxFailure),
        ],
      );

  /// The columns of [doc]. A record over [maxResultsChars] loses detail in steps, never a failure before a pass:
  /// first the texts of passing requests go, then failures are shortened, then the passing requests beyond what
  /// fits are dropped, and only as a last resort the failures at the end. A record that lost anything says
  /// `truncated`; the totals always count every request.
  static PreparedRunRecord prepare(RunRecordDoc doc, {int maxChars = maxResultsChars}) {
    var clean = sanitize(doc);
    var entries = clean.results;
    var truncated = clean.truncated;

    String encode(List<RunResultEntry> list) => jsonEncode([for (final r in list) r.toJson()]);

    var text = encode(entries);
    if (text.length > maxChars) {
      // Step 1: a passing request needs its name, its status and its time, not its address.
      entries = [
        for (final r in entries)
          r.isFailed || r.isSkipped ? r : RunResultEntry(
            requestId: r.requestId,
            name: r.name,
            folder: r.folder,
            method: r.method,
            iteration: r.iteration,
            status: r.status,
            durationMs: r.durationMs,
            passed: r.passed,
          ),
      ];
      text = encode(entries);
    }
    if (text.length > maxChars) {
      // Step 2: shorter failure texts.
      entries = [for (final r in entries) r.isFailed ? _sanitizeEntry(r, tight: true) : r];
      text = encode(entries);
    }
    if (text.length > maxChars) {
      // Step 3: keep every failure and as many of the other requests, from the start, as still fit.
      truncated = true;
      final others = [for (final (i, r) in entries.indexed) if (!r.isFailed) i];
      List<RunResultEntry> keeping(int count) {
        final keep = others.take(count).toSet();
        return [for (final (i, r) in entries.indexed) if (r.isFailed || keep.contains(i)) r];
      }

      var low = 0;
      var high = others.length;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (encode(keeping(mid)).length <= maxChars) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      entries = keeping(low);
      text = encode(entries);
    }
    if (text.length > maxChars) {
      // Step 4: last resort, the failures at the end.
      truncated = true;
      final kept = [...entries];
      while (kept.isNotEmpty && text.length > maxChars) {
        kept.removeRange(kept.length - (kept.length > 50 ? kept.length ~/ 10 : 1), kept.length);
        text = encode(kept);
      }
      entries = kept;
    }

    clean = clean.copyWith(results: entries, truncated: truncated);
    return PreparedRunRecord(
      environmentName: clean.environment,
      source: clean.source,
      passed: clean.passed,
      failed: clean.failed,
      skipped: clean.skipped,
      durationMs: clean.durationMs,
      summaryJson: jsonEncode(clean.summaryJson()),
      resultsJson: encode(entries),
      startedAt: clean.startedAt,
    );
  }

  /// Reads the text of a run record file. Throws a [FormatException] saying what is wrong with it.
  static RunRecordDoc parseFile(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('The file is not valid JSON: ${e.message}');
    }
    return sanitize(RunRecordDoc.fromJson(decoded));
  }

  /// A record read back from the `run_records` columns. Unreadable JSON gives an empty run rather than an error,
  /// so one damaged row cannot break a list.
  static RunRecordDoc fromColumns({
    required String collectionName,
    required String environmentName,
    required String source,
    required int passed,
    required int failed,
    required int skipped,
    required int durationMs,
    required String summaryJson,
    required String resultsJson,
    required DateTime startedAt,
  }) {
    Map<String, Object?> summary = const {};
    try {
      final decoded = jsonDecode(summaryJson);
      if (decoded is Map) summary = Map<String, Object?>.from(decoded);
    } catch (_) {}
    var results = <RunResultEntry>[];
    try {
      final decoded = jsonDecode(resultsJson);
      if (decoded is List) {
        results = [
          for (final r in decoded)
            if (r is Map) RunResultEntry.fromJson(Map<String, Object?>.from(r)),
        ];
      }
    } catch (_) {}
    return RunRecordDoc(
      source: source,
      trigger: summary['trigger'] is String ? summary['trigger'] as String : (source == 'cli' ? 'cli' : 'manual'),
      collection: summary['collection'] is String ? summary['collection'] as String : collectionName,
      environment: environmentName,
      startedAt: startedAt,
      durationMs: durationMs,
      iterations: summary['iterations'] is int ? summary['iterations'] as int : 1,
      passed: passed,
      failed: failed,
      skipped: skipped,
      stoppedOnFailure: summary['stoppedOnFailure'] == true,
      truncated: summary['truncated'] == true,
      results: results,
    );
  }
}
