import '../../../../core/utils/variable_resolver.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../entities/flow_settings.dart';

/// How the request that ran just before this one in the run ended.
final class PreviousResult {
  final String name;
  final bool passed;
  const PreviousResult(this.name, this.passed);
}

/// What a run remembers between requests for Run if and Always run: the request before (only requests that were
/// really sent count; a skipped one is neither passed nor failed, so it is stepped over), and whether "stop on
/// failure" has ended the run's normal course.
final class FlowRunPass {
  PreviousResult? previous;

  /// A request failed and "stop on failure" is on: from here only requests marked "always run" are sent.
  bool stopped = false;

  void sent(String name, {required bool passed}) => previous = PreviousResult(name, passed);
}

/// What [RunIfEvaluator.evaluate] decided.
final class RunIfDecision {
  final bool run;

  /// Why the request is skipped, e.g. `Skipped: {{region}} is "us", not "eu"`; null when it runs.
  final String? reason;

  const RunIfDecision.run() : run = true, reason = null;
  const RunIfDecision.skip(String this.reason) : run = false;
}

/// Everything a condition can look at.
final class RunIfContext {
  final VariableResolver resolver;

  /// The active environment; null for "No Environment".
  final String? environmentName;
  final PreviousResult? previous;

  const RunIfContext({required this.resolver, this.environmentName, this.previous});
}

/// Decides, before a request is sent in a run, whether its Run if conditions hold. Every condition has to hold;
/// the first one that does not decides the reason. Skipped is not failed: a skipped request is reported as
/// skipped and neither stops a run on failure nor counts as a failure.
abstract final class RunIfEvaluator {
  static RunIfDecision evaluate(RunIfPolicy policy, RunIfContext context) {
    if (!policy.isActive) return const RunIfDecision.run();
    for (final condition in policy.conditions) {
      final why = _unmet(condition, context);
      if (why != null) return RunIfDecision.skip(SecretMasker.maskMessage('Skipped: $why'));
    }
    return const RunIfDecision.run();
  }

  /// True when [policy] cannot hold in [environmentName] whatever the variables turn out to be: a request that is
  /// left out of the production check because it will certainly be skipped.
  static bool surelySkippedIn(RunIfPolicy policy, String? environmentName) {
    if (!policy.isActive) return false;
    return policy.conditions.any((c) => c.kind.isEnvironment && _environmentUnmet(c, environmentName) != null);
  }

  /// The reason [condition] does not hold, or null when it does.
  static String? _unmet(RunCondition condition, RunIfContext context) {
    final invalid = condition.error;
    if (invalid != null) return 'a Run if condition is incomplete ($invalid)';
    switch (condition.kind) {
      case RunConditionKind.environmentIs:
      case RunConditionKind.environmentIsNot:
        return _environmentUnmet(condition, context.environmentName);
      case RunConditionKind.previousPassed:
      case RunConditionKind.previousFailed:
        final previous = context.previous;
        final wantPassed = condition.kind == RunConditionKind.previousPassed;
        if (previous == null) return 'there is no previous request in this run to look at';
        if (previous.passed == wantPassed) return null;
        return 'the previous request "${previous.name}" ${previous.passed ? 'passed' : 'failed'}, '
            'but this one runs only when it ${wantPassed ? 'passed' : 'failed'}';
      case RunConditionKind.variableEquals:
      case RunConditionKind.variableNotEquals:
      case RunConditionKind.variableExists:
      case RunConditionKind.variableMissing:
      case RunConditionKind.variableNotEmpty:
        return _variableUnmet(condition, context.resolver);
    }
  }

  static String? _environmentUnmet(RunCondition condition, String? environmentName) {
    final wanted = condition.name.trim().toLowerCase();
    final same = environmentName != null && environmentName.trim().toLowerCase() == wanted;
    final shown = environmentName == null ? 'No Environment' : '"$environmentName"';
    if (condition.kind == RunConditionKind.environmentIs) {
      return same ? null : 'the environment is $shown, but this runs only in "${condition.name.trim()}"';
    }
    return same ? 'the environment is $shown, where this does not run' : null;
  }

  static String? _variableUnmet(RunCondition condition, VariableResolver resolver) {
    final name = condition.variableName;
    final token = '{{$name}}';
    final defined = resolver.undefinedIn(token).isEmpty;
    final value = defined ? resolver.resolve(token) : null;
    // A credential's value never goes into a message: "does not match" says enough.
    final secret = SecretMasker.isSensitiveName(name);
    String shown(String? text) => secret ? 'the expected value' : '"$text"';
    switch (condition.kind) {
      case RunConditionKind.variableExists:
        return defined ? null : '$token is not defined';
      case RunConditionKind.variableMissing:
        return defined ? '$token is defined' : null;
      case RunConditionKind.variableNotEmpty:
        if (!defined) return '$token is not defined';
        return value!.trim().isEmpty ? '$token is empty' : null;
      case RunConditionKind.variableEquals:
        final expected = resolver.resolve(condition.value).trim();
        if (!defined) return '$token is not defined, but this runs only when it equals ${shown(expected)}';
        if (value!.trim() == expected) return null;
        return secret
            ? '$token does not equal ${shown(expected)}'
            : '$token is "${value.trim()}", but this runs only when it equals "$expected"';
      case RunConditionKind.variableNotEquals:
        final unwanted = resolver.resolve(condition.value).trim();
        if (!defined || value!.trim() != unwanted) return null;
        return '$token equals ${shown(unwanted)}, which this does not run for';
      default:
        return null;
    }
  }
}
