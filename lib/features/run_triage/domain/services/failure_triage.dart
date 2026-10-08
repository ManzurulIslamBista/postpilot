// Pure Dart.
import '../../../auth_doctor/domain/entities/auth_doctor_input.dart';
import '../../../auth_doctor/domain/entities/auth_finding.dart';
import '../../../auth_doctor/domain/services/auth_doctor.dart';
import '../entities/run_record_doc.dart';
import 'failure_fingerprinter.dart';

/// The failed requests of a run that share one cause.
final class FailureGroup {
  final FailureFingerprint fingerprint;

  /// Every failed result with this cause, in the order the run sent them.
  final List<RunResultEntry> results;

  /// One plain-language sentence saying what probably broke and what to do about it. For a 401 or 403 it ends with what
  /// the 401/403 doctor makes of the run, when that is more than a guess (see `AuthDoctor.diagnoseRun`).
  final String hint;

  const FailureGroup({required this.fingerprint, required this.results, required this.hint});

  int get count => results.length;

  /// The first request that failed this way: the one to look at.
  RunResultEntry get first => results.first;

  /// How many different requests are in the group (a data-driven run repeats a request once per row).
  int get requestCount => {for (final r in results) r.requestKey}.length;
}

/// A run's failures sorted into causes.
final class TriageReport {
  final List<FailureGroup> groups;
  final int totalResults;
  final int failedResults;
  final int skippedResults;

  const TriageReport({
    required this.groups,
    required this.totalResults,
    required this.failedResults,
    required this.skippedResults,
  });

  bool get hasFailures => failedResults > 0;

  /// The headline: `12 failures, 2 causes`.
  String get headline {
    if (failedResults == 0) return 'Nothing failed';
    final causes = groups.length;
    return '$failedResults ${failedResults == 1 ? 'failure' : 'failures'}, $causes ${causes == 1 ? 'cause' : 'causes'}';
  }
}

/// Groups the failures of a run by cause, biggest first, so twelve failures that are one expired token read as one
/// line instead of twelve.
abstract final class FailureTriage {
  /// [environment] is the name of the environment the run used; with it the doctor can tell that a 401 came from a production
  /// host reached with a staging environment, or the other way round.
  static TriageReport analyse(List<RunResultEntry> results, {String environment = ''}) {
    final byKey = <String, List<RunResultEntry>>{};
    final fingerprints = <String, FailureFingerprint>{};
    final firstSeen = <String, int>{};
    var failed = 0;
    for (final (index, result) in results.indexed) {
      if (!result.isFailed) continue;
      failed++;
      final fingerprint = FailureFingerprinter.of(result);
      fingerprints.putIfAbsent(fingerprint.key, () => fingerprint);
      firstSeen.putIfAbsent(fingerprint.key, () => index);
      byKey.putIfAbsent(fingerprint.key, () => []).add(result);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) {
        final byCount = byKey[b]!.length.compareTo(byKey[a]!.length);
        if (byCount != 0) return byCount;
        final byKind = fingerprints[a]!.kind.index.compareTo(fingerprints[b]!.kind.index);
        return byKind != 0 ? byKind : firstSeen[a]!.compareTo(firstSeen[b]!);
      });
    return TriageReport(
      groups: [
        for (final key in keys)
          FailureGroup(
            fingerprint: fingerprints[key]!,
            results: byKey[key]!,
            hint: hintFor(fingerprints[key]!, byKey[key]!.length, failed: byKey[key]!, run: results, environment: environment),
          ),
      ],
      totalResults: results.length,
      failedResults: failed,
      skippedResults: results.where((r) => r.isSkipped).length,
    );
  }

  /// What probably happened and what to do, for [count] requests that failed with [fingerprint]. [failed] are those
  /// requests and [run] every result of the run, which the 401/403 doctor compares them with.
  static String hintFor(
    FailureFingerprint fingerprint,
    int count, {
    List<RunResultEntry> failed = const [],
    List<RunResultEntry> run = const [],
    String environment = '',
  }) {
    final many = count != 1;
    final subject = many ? '$count requests' : '1 request';
    final verb = many ? 'were' : 'was';
    final host = fingerprint.host;
    final where = host ?? 'the server';
    switch (fingerprint.kind) {
      case FailureKind.auth:
        final base = switch (fingerprint.status) {
          401 => '$subject failed with 401 (Unauthorized): the token or API key was probably rejected or has expired. '
              'Renew the auth (or run the login request again) and re-run the failed requests.',
          403 => '$subject failed with 403 (Forbidden): the credentials were accepted but are not allowed to do this. '
              'Check the role or scopes of the user and that this is the right environment.',
          _ => '$subject could not be sent because the access token could not be renewed. '
              'Check the OAuth settings (token URL, client id and secret) and sign in again if needed.',
        };
        return _withDoctor(base, fingerprint.status, count, failed, run, environment);
      case FailureKind.network:
        return switch (fingerprint.detail) {
          'timeout' => '$subject timed out waiting for $where: the service is slow or down. '
              'Check its health first; raise the timeout only if it is just slow.',
          'dns' => '${host == null ? 'The host name' : '"$host"'} could not be found ($subject affected): '
              'check the base URL of the environment, your network, DNS or VPN.',
          'refused' => '$where refused the connection or could not be reached ($subject affected): '
              'the service is probably not running on that port, or a firewall blocks it.',
          'tls' => '$subject failed to set up a secure connection to $where: '
              'the certificate is untrusted, expired or for another host, or the URL uses https where http is expected.',
          _ => '$subject lost the connection to $where while it answered: it may have crashed or restarted. '
              'Re-run in a minute and check the service.',
        };
      case FailureKind.config:
        final target = fingerprint.target == null
            ? 'a variable'
            : fingerprint.target!.split(', ').map((name) => '{{$name}}').join(', ');
        return fingerprint.key == 'config:build'
            ? '$subject could not be built from the request as saved. Open the first one and fix what it reports.'
            : '$subject ${many ? 'use' : 'uses'} $target, which no variable defines. '
                'Choose an environment that defines it, add it to the collection or the globals, or run the request that saves it first.';
      case FailureKind.blocked:
        return '$subject $verb refused by the production lock because they change data and the environment looks like production. '
            'Nothing was sent. Run only read-only requests here, or use a staging environment for these.';
      case FailureKind.http:
        return _httpHint(fingerprint.status ?? 0, subject);
      case FailureKind.assertion:
        return _assertionHint(fingerprint, subject, many);
      case FailureKind.extraction:
        final name = fingerprint.target ?? 'a value';
        return '$subject could not save {{$name}} from the response, so requests that use it will fail too. '
            'Check the path of the extractor against the response, and whether the request answered as before.';
      case FailureKind.other:
        return '$subject failed with the same message. Open the first one to read the full text.';
    }
  }

  /// [hint] followed by the top finding of the 401/403 doctor for these requests, when it is at least a likely cause. A run
  /// record keeps no headers and no body, so the doctor can only say what the status, the host, the environment and the
  /// rest of the run show; a hedged finding is left out and the hint stays as it was.
  static String _withDoctor(
    String hint,
    int? status,
    int count,
    List<RunResultEntry> failed,
    List<RunResultEntry> run,
    String environment,
  ) {
    if (status == null || (status != 401 && status != 403) || failed.isEmpty) return hint;
    final first = failed.first;
    final host = Uri.tryParse(first.url)?.host.toLowerCase() ?? '';
    final passed = host.isEmpty
        ? 0
        : run.where((r) => r.passed && !r.isSkipped && (r.status ?? 0) >= 200 && (r.status ?? 0) < 300 && Uri.tryParse(r.url)?.host.toLowerCase() == host).length;
    final findings = AuthDoctor.diagnoseRun(
      AuthRunFacts(status: status, url: first.url, environment: environment, rejected: count, passedOnSameHost: passed),
    );
    final top = findings.firstOrNull;
    if (top == null || top.confidence == FindingConfidence.possible) return hint;
    return '$hint ${top.explanation} ${top.fix}';
  }

  static String _httpHint(int status, String subject) {
    final summary = switch (status) {
      400 || 422 => 'the server rejected what was sent (validation). Compare the body and parameters with the API\'s current contract.',
      404 => 'nothing was found at that address: the URL or an id in it is wrong, or the item was deleted. '
          'Check the base URL of the environment and the ids saved by earlier requests.',
      405 => 'the endpoint does not allow that method. Check the method against the API\'s documentation.',
      408 => 'the server gave up waiting for the request. Check the service and your connection.',
      409 => 'the request conflicts with the server\'s current state (often a duplicate or a stale version).',
      415 => 'the server does not accept that body type. Check the Content-Type header and the body type.',
      429 => 'the server is rate limiting. Add a delay between requests ("Delay (ms)" in the runner, --delay on the command line).',
      502 || 503 || 504 => 'the service, or something behind it, is down, overloaded or restarting. '
          'Check its health and re-run in a minute.',
      >= 500 => 'the server failed while answering: a server problem, not a test problem. '
          'Read the body of the first example and look at the server\'s logs.',
      >= 400 => 'the server refused the request. Read the response of the first example.',
      >= 300 => 'the server redirected instead of answering. Check the URL (http vs https, a trailing slash).',
      _ => 'the status code was not a success.',
    };
    return '$subject failed with $status${_reasonSuffix(status)}: $summary';
  }

  static String _reasonSuffix(int status) {
    final reason = switch (status) {
      400 => 'Bad Request',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      408 => 'Request Timeout',
      409 => 'Conflict',
      415 => 'Unsupported Media Type',
      422 => 'Unprocessable Entity',
      429 => 'Too Many Requests',
      500 => 'Internal Server Error',
      502 => 'Bad Gateway',
      503 => 'Service Unavailable',
      504 => 'Gateway Timeout',
      _ => null,
    };
    return reason == null ? '' : ' ($reason)';
  }

  static String _assertionHint(FailureFingerprint fingerprint, String subject, bool many) {
    final target = fingerprint.target ?? '';
    return switch (fingerprint.detail) {
      'statusEquals' => '$subject did not return the status code the test expects: the API changed its behaviour, '
          'or the expectation is outdated.',
      'statusIn2xx' => '$subject did not return a 2xx status code. Read the response of the first one.',
      'bodyContains' => '$subject no longer ${many ? 'contain' : 'contains'} the text the test looks for: the response changed.',
      'jsonPathEquals' => '$subject returned another value at $target than the test expects: the data or the API changed, '
          'or the expected value is outdated.',
      'jsonPathExists' => '$subject ${many ? 'have' : 'has'} no $target in the response: the shape of the response changed, or the request failed to return data.',
      'headerEquals' => '$subject returned another value for the header $target than the test expects.',
      'headerExists' => '$subject did not return the header $target.',
      'responseTimeBelowMs' => '$subject answered slower than the limit in the test: the service is slow right now, or the limit is too tight.',
      'jsonSchema' => '$subject returned a response that does not match the JSON Schema: a field was added, removed or changed type.',
      _ => '$subject failed a test. Open the first one to see which.',
    };
  }
}
