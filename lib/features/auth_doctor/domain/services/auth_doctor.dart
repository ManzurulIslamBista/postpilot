// Pure Dart (no Flutter, no database).
import '../entities/auth_doctor_input.dart';
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'challenge_checks.dart';
import 'credential_checks.dart';
import 'environment_checks.dart';
import 'environment_words.dart';
import 'rejection_checks.dart';
import 'server_words.dart';
import 'token_checks.dart';

/// "Why was I rejected?": works out, offline and the same way every time, what probably made a server answer 401, 403 or
/// 407 (or say its token is invalid or expired), from the request as it was sent, the response, the active environment
/// and the clock it is given. Nothing is sent anywhere, and no secret value appears in a finding: a token is written as its
/// first four characters and its length.
///
/// The findings come back most certain first; inside one level, in the order the checks ran (the credential itself,
/// then the token's contents, what the server said, the environment, and the causes that have nothing to do with the
/// credential).
abstract final class AuthDoctor {
  /// The statuses that are a refusal of the caller.
  static const rejectionStatuses = {401, 403, 407};

  /// Statuses that mean a token problem by their definition: 419 (page expired), 498 (invalid token).
  static const _tokenStatuses = {419, 498};

  static final _authWords = RegExp(
    r'(?:token|jwt|session|credential|api[\s_-]?key|signature|authoriz|authentic)[^.\n]{0,40}(?:invalid|expired|revoked|missing|malformed|failed|required)|'
    r'(?:invalid|expired|revoked|missing|malformed|bad)[^.\n]{0,40}(?:token|jwt|session|credential|api[\s_-]?key|signature)|'
    r'unauthori[sz]ed|not authenticated|token (?:has )?expired|session (?:has )?expired',
  );

  /// Whether [status] with [body] is a rejection the doctor can explain: 401, 403 and 407, 419 and 498, and a 400 whose
  /// body says the token is invalid or expired.
  static bool appliesTo(int status, [String body = '']) {
    if (rejectionStatuses.contains(status) || _tokenStatuses.contains(status)) return true;
    if (status != 400 || body.isEmpty) return false;
    final text = body.length > 64 * 1024 ? body.substring(0, 64 * 1024) : body;
    return _authWords.hasMatch(text.toLowerCase());
  }

  static List<AuthFinding> diagnose(AuthDoctorInput input) {
    if (!appliesTo(input.status, input.responseBody)) return const [];
    final ctx = AuthContext.of(input);
    final found = <AuthFinding>[
      ...CredentialChecks.run(ctx),
      ...TokenChecks.run(ctx),
    ];
    found.addAll(ChallengeChecks.run(ctx, found));
    found
      ..addAll(EnvironmentChecks.run(ctx))
      ..addAll(RejectionChecks.run(ctx));
    if (!found.any((f) => f.confidence != FindingConfidence.possible)) found.add(_generic(ctx));
    if (!found.any((f) => f.confidence == FindingConfidence.certain)) {
      final opaque = TokenChecks.opaque(ctx);
      if (opaque != null) found.add(opaque);
    }
    return _ordered(found);
  }

  /// What can be said about a rejected request of a run, which keeps no headers and no body: the environment against the
  /// host, and whether the rest of the run got through on the same host. Never says anything about the credential itself.
  static List<AuthFinding> diagnoseRun(AuthRunFacts facts) {
    if (facts.status != 401 && facts.status != 403) return const [];
    final uri = Uri.tryParse(facts.url);
    final host = (uri?.host ?? '').toLowerCase();
    final found = <AuthFinding>[];
    final mismatch = EnvironmentChecks.hostAgainstEnvironment(facts.environment, host);
    if (mismatch != null) found.add(mismatch);

    final where = host.isEmpty ? 'the same server' : host;
    if (facts.passedOnSameHost > 0) {
      found.add(AuthFinding(
        id: 'run.some-rejected',
        confidence: FindingConfidence.possible,
        title: 'Other requests to $where passed',
        explanation: 'Not every request to $where was rejected, so the server is up and reachable. If the requests that passed are authenticated, '
            'the rejected ones use another credential, or none, or ${facts.status == 401 ? 'an endpoint that checks it differently' : 'need a role or scope the others do not'}.',
        fix: 'Compare the Auth and Headers tabs of a rejected request with one that passed.',
        evidence: ['${facts.passedOnSameHost} request${facts.passedOnSameHost == 1 ? '' : 's'} to $where passed in this run.'],
      ));
    } else if (facts.rejected >= 2) {
      found.add(AuthFinding(
        id: 'run.all-rejected',
        confidence: FindingConfidence.likely,
        title: 'Every request to $where was rejected',
        explanation: facts.status == 401
            ? 'Not one request to $where got through, so one credential is the problem (expired, revoked, or from another environment), not one endpoint.'
            : 'Not one request to $where got through, so the user as a whole is refused, not a single endpoint: the account, its role, or the address it calls from.',
        fix: facts.status == 401
            ? 'Renew the credential once (run the login request, or renew the OAuth 2.0 token), check the active environment, and re-run.'
            : 'Check the user\'s role and that the active environment is the one the user belongs to.',
        evidence: ['${facts.rejected} requests got ${facts.status}; none to $where passed.'],
      ));
    }
    final scheme = uri?.scheme;
    if (facts.status == 401 && scheme == 'http' && host.isNotEmpty && EnvironmentWords.kindOfHost(host) != ServerKind.staging && !host.startsWith('10.') && !host.startsWith('192.168.')) {
      found.add(const AuthFinding(
        id: 'redirect.http',
        confidence: FindingConfidence.possible,
        title: 'The URL uses http, not https',
        explanation: 'Servers usually redirect http to https, and a client drops the credential when the scheme changes.',
        fix: 'Use the https:// address.',
        evidence: ['Request URL scheme: http'],
      ));
    }
    return _ordered(found);
  }

  // --- helpers -------------------------------------------------------------------------------------------------

  /// Most certain first, the checks' own order inside a level, and each finding once.
  static List<AuthFinding> _ordered(List<AuthFinding> findings) {
    final seen = <String>{};
    final unique = <(int, AuthFinding)>[];
    for (final (index, finding) in findings.indexed) {
      if (seen.add('${finding.id}|${finding.title}')) unique.add((index, finding));
    }
    unique.sort((a, b) {
      final byConfidence = a.$2.confidence.index.compareTo(b.$2.confidence.index);
      return byConfidence != 0 ? byConfidence : a.$1.compareTo(b.$1);
    });
    return [for (final (_, finding) in unique) finding];
  }

  /// When nothing specific was found: the usual causes of this status.
  static AuthFinding _generic(AuthContext ctx) {
    final said = ServerWords.evidence(ctx);
    final (title, why, fix) = switch (ctx.status) {
      403 => (
          'Signed in, but not allowed',
          'The server knows who you are (or did not need to) and still refuses this action. The usual reasons are a role or permission the user '
              'lacks, a record that belongs to someone else, a plan or licence that does not include the endpoint, or an address restriction.',
          'Compare with a user that can do this, check the roles and scopes the endpoint requires, and read the response body for the rule that fired.',
        ),
      407 => (
          'The proxy did not accept the credentials',
          'The proxy between this computer and the server wants a login of its own and did not get one it accepts.',
          'Set the proxy user name and password in Settings, or ask the network administrator which scheme the proxy uses.',
        ),
      _ => (
          'The server did not accept the credential',
          'A credential was sent and refused. The usual reasons are a token that was revoked or has expired on the server, a token or key from another '
              'environment or tenant, a disabled user, or a credential that is right but for another API.',
          'Get a fresh credential (run the login request or renew the OAuth 2.0 token), check the active environment, and try the same call in another '
              'client to rule out the request itself.',
        ),
    };
    return AuthFinding(
      id: 'generic.${ctx.status}',
      confidence: FindingConfidence.possible,
      title: title,
      explanation: why,
      fix: fix,
      evidence: [
        'Status: ${ctx.status}',
        if (ctx.credentials.isEmpty) 'No credential could be identified in the request.' else 'Credentials sent: ${ctx.credentials.map((c) => c.name).toSet().join(', ')}',
        ...said,
      ],
    );
  }
}
