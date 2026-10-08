// Pure Dart (no Flutter, no database).
import '../entities/auth_finding.dart';
import 'auth_context.dart';
import 'environment_words.dart';

/// The environment as a cause: the credential variable lives in an environment that is not the active one, or the URL
/// points at production while the active environment is staging (or the other way round).
abstract final class EnvironmentChecks {
  static List<AuthFinding> run(AuthContext ctx) {
    final out = <AuthFinding>[];
    out.addAll(_variableElsewhere(ctx));
    final mismatch = hostAgainstEnvironment(ctx.input.environmentName, ctx.host);
    if (mismatch != null) out.add(mismatch);
    return out;
  }

  static List<AuthFinding> _variableElsewhere(AuthContext ctx) {
    final input = ctx.input;
    final out = <AuthFinding>[];
    final seen = <String>{};
    for (final credential in ctx.credentials) {
      for (final name in credential.variables) {
        if (!seen.add(name)) continue;
        final fact = input.variables[name];
        if (fact != null && !fact.isEmpty) continue;
        final others = [
          for (final environment in input.otherEnvironments)
            if (environment.filledVariables.contains(name)) environment.name,
        ];
        if (others.isEmpty) continue;
        final active = input.environmentName;
        final problem = fact == null ? 'is not defined' : 'is empty';
        final here = active == null ? '(no environment is active)' : 'in the active environment "$active"';
        out.add(AuthFinding(
          id: 'environment.variable-elsewhere',
          confidence: FindingConfidence.likely,
          title: '{{$name}} has a value in ${AuthText.list(others.map((o) => '"$o"'))}, not here',
          explanation: '${_cap(credential.label)} is fed by {{$name}}, which $problem $here but is filled in for '
              '${AuthText.list(others.map((o) => '"$o"'))}. The credential you meant is probably in the other environment.',
          fix: 'Switch to ${others.length == 1 ? '"${others.first}"' : 'the environment you meant'} in the environment picker, '
              'or fill {{$name}} in ${active == null ? 'the environment you use' : '"$active"'}.',
          evidence: [
            active == null ? 'No environment is active.' : 'Active environment: $active.',
            '{{$name}} ${fact == null ? 'is undefined' : 'is empty'} there and has a value in: ${others.join(', ')}.',
          ],
        ));
      }
    }
    return out;
  }

  /// A host that looks like one kind of server against an environment name that says the other; null when either says
  /// nothing or they agree.
  static AuthFinding? hostAgainstEnvironment(String? environment, String host) {
    if (environment == null || environment.isEmpty || host.isEmpty) return null;
    final environmentKind = EnvironmentWords.kindOf(environment);
    final hostKind = EnvironmentWords.kindOfHost(host);
    if (environmentKind == null || hostKind == null || environmentKind == hostKind) return null;
    final hostSays = hostKind == ServerKind.production ? 'production' : 'a test or staging server';
    final envSays = environmentKind == ServerKind.production ? 'production' : 'staging or development';
    return AuthFinding(
      id: 'environment.host-mismatch',
      confidence: FindingConfidence.likely,
      title: 'The URL looks like ${hostKind == ServerKind.production ? 'production' : 'staging'}, the environment like '
          '${environmentKind == ServerKind.production ? 'production' : 'staging'}',
      explanation: 'The request goes to "$host", which looks like $hostSays, while the active environment "$environment" looks like $envSays. '
          'Tokens and keys of one are rarely accepted by the other.',
      fix: 'Decide which one you meant: switch the environment, or correct the base URL (check the baseUrl variable).',
      evidence: ['Active environment: $environment', 'Request host: $host'],
    );
  }

  static String _cap(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}
