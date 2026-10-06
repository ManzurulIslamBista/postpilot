import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/run_if_evaluator.dart';

RunIfPolicy _when(List<RunCondition> conditions) => RunIfPolicy(enabled: true, conditions: conditions);

RunCondition _c(RunConditionKind kind, [String name = '', String value = '']) =>
    RunCondition(kind: kind, name: name, value: value);

RunIfDecision _decide(
  RunIfPolicy policy, {
  Map<String, String> variables = const {},
  String? environment,
  PreviousResult? previous,
}) =>
    RunIfEvaluator.evaluate(
      policy,
      RunIfContext(resolver: VariableResolver(variables), environmentName: environment, previous: previous),
    );

void main() {
  group('no conditions to meet', () {
    test('a policy that is off, or has nothing in it, lets the request run', () {
      expect(_decide(const RunIfPolicy()).run, isTrue);
      expect(_decide(RunIfPolicy(enabled: true)).run, isTrue);
      // Off keeps its conditions but does not apply them.
      expect(_decide(RunIfPolicy(conditions: [_c(RunConditionKind.variableExists, 'x')])).run, isTrue);
    });
  });

  group('variables', () {
    test('equals compares the text, ignoring the blanks around it', () {
      final policy = _when([_c(RunConditionKind.variableEquals, 'region', 'eu')]);

      expect(_decide(policy, variables: const {'region': 'eu'}).run, isTrue);
      expect(_decide(policy, variables: const {'region': ' eu '}).run, isTrue);
      final skipped = _decide(policy, variables: const {'region': 'us'});
      expect(skipped.run, isFalse);
      expect(skipped.reason, 'Skipped: {{region}} is "us", but this runs only when it equals "eu"');
    });

    test('equals is case sensitive, as variable values are', () {
      expect(_decide(_when([_c(RunConditionKind.variableEquals, 'region', 'EU')]), variables: const {'region': 'eu'}).run, isFalse);
    });

    test('a variable that is not defined does not equal anything, and says so', () {
      final skipped = _decide(_when([_c(RunConditionKind.variableEquals, 'region', 'eu')]));

      expect(skipped.run, isFalse);
      expect(skipped.reason, contains('{{region}} is not defined'));
    });

    test('the name may be written with its braces, and the value may use another variable', () {
      final policy = _when([_c(RunConditionKind.variableEquals, '{{ region }}', '{{wanted}}')]);

      expect(_decide(policy, variables: const {'region': 'eu', 'wanted': 'eu'}).run, isTrue);
      expect(_decide(policy, variables: const {'region': 'eu', 'wanted': 'us'}).run, isFalse);
    });

    test('does not equal runs for another value and for a variable that is missing', () {
      final policy = _when([_c(RunConditionKind.variableNotEquals, 'mode', 'dry')]);

      expect(_decide(policy, variables: const {'mode': 'live'}).run, isTrue);
      expect(_decide(policy).run, isTrue);
      final skipped = _decide(policy, variables: const {'mode': 'dry'});
      expect(skipped.run, isFalse);
      expect(skipped.reason, contains('{{mode}} equals "dry"'));
    });

    test('exists is about being defined, not about having a value', () {
      final policy = _when([_c(RunConditionKind.variableExists, 'token')]);

      expect(_decide(policy, variables: const {'token': ''}).run, isTrue);
      expect(_decide(policy, variables: const {'token': 'abc'}).run, isTrue);
      expect(_decide(policy).reason, 'Skipped: {{token}} is not defined');
    });

    test('a built-in dynamic variable counts as defined', () {
      expect(_decide(_when([_c(RunConditionKind.variableExists, r'$guid')])).run, isTrue);
    });

    test('is not defined is the opposite of exists', () {
      final policy = _when([_c(RunConditionKind.variableMissing, 'token')]);

      expect(_decide(policy).run, isTrue);
      final skipped = _decide(policy, variables: const {'token': ''});
      expect(skipped.run, isFalse);
      expect(skipped.reason, contains('{{token}} is defined'));
    });

    test('is not empty needs a value that is more than blanks', () {
      final policy = _when([_c(RunConditionKind.variableNotEmpty, 'id')]);

      expect(_decide(policy, variables: const {'id': '7'}).run, isTrue);
      expect(_decide(policy, variables: const {'id': ''}).reason, 'Skipped: {{id}} is empty');
      expect(_decide(policy, variables: const {'id': '   '}).run, isFalse);
      expect(_decide(policy).reason, 'Skipped: {{id}} is not defined');
    });

    test('a variable whose value refers to another is read through it', () {
      final policy = _when([_c(RunConditionKind.variableEquals, 'a', 'one')]);

      expect(_decide(policy, variables: const {'a': '{{b}}', 'b': 'one'}).run, isTrue);
    });

    test('a credential\'s value is never written into the reason', () {
      final skipped = _decide(
        _when([_c(RunConditionKind.variableEquals, 'api_key', 'expected-secret-value')]),
        variables: const {'api_key': 'actual-secret-value'},
      );

      expect(skipped.run, isFalse);
      expect(skipped.reason, isNot(contains('actual-secret-value')));
      expect(skipped.reason, isNot(contains('expected-secret-value')));
      expect(skipped.reason, contains('{{api_key}}'));
    });
  });

  group('the environment', () {
    test('is matched by name, whatever the case', () {
      final policy = _when([_c(RunConditionKind.environmentIs, 'Staging')]);

      expect(_decide(policy, environment: 'staging').run, isTrue);
      expect(_decide(policy, environment: ' STAGING ').run, isTrue);
      final skipped = _decide(policy, environment: 'Production');
      expect(skipped.run, isFalse);
      expect(skipped.reason, 'Skipped: the environment is "Production", but this runs only in "Staging"');
    });

    test('"No Environment" is not any environment', () {
      expect(_decide(_when([_c(RunConditionKind.environmentIs, 'Staging')])).reason, contains('No Environment'));
      expect(_decide(_when([_c(RunConditionKind.environmentIsNot, 'Production')])).run, isTrue);
    });

    test('is not skips the one environment named', () {
      final policy = _when([_c(RunConditionKind.environmentIsNot, 'Production')]);

      expect(_decide(policy, environment: 'Staging').run, isTrue);
      final skipped = _decide(policy, environment: 'production');
      expect(skipped.run, isFalse);
      expect(skipped.reason, contains('where this does not run'));
    });
  });

  group('the previous request', () {
    test('passed and failed look at how the request before ended', () {
      final passed = _when([_c(RunConditionKind.previousPassed)]);
      final failed = _when([_c(RunConditionKind.previousFailed)]);

      expect(_decide(passed, previous: const PreviousResult('Login', true)).run, isTrue);
      expect(_decide(failed, previous: const PreviousResult('Login', false)).run, isTrue);
      expect(
        _decide(passed, previous: const PreviousResult('Login', false)).reason,
        'Skipped: the previous request "Login" failed, but this one runs only when it passed',
      );
      expect(
        _decide(failed, previous: const PreviousResult('Login', true)).reason,
        'Skipped: the previous request "Login" passed, but this one runs only when it failed',
      );
    });

    test('with no request before it, neither holds, and the reason says so', () {
      for (final kind in [RunConditionKind.previousPassed, RunConditionKind.previousFailed]) {
        final skipped = _decide(_when([_c(kind)]));

        expect(skipped.run, isFalse, reason: kind.name);
        expect(skipped.reason, contains('no previous request in this run'), reason: kind.name);
      }
    });

    test('FlowRunPass remembers only requests that were sent', () {
      final pass = FlowRunPass();
      expect(pass.previous, isNull);

      pass.sent('A', passed: true);
      pass.sent('B', passed: false);

      expect((pass.previous!.name, pass.previous!.passed), ('B', false));
      expect(pass.stopped, isFalse);
    });
  });

  group('several conditions', () {
    test('all of them have to hold, and the first that does not gives the reason', () {
      final policy = _when([
        _c(RunConditionKind.environmentIs, 'Staging'),
        _c(RunConditionKind.variableNotEmpty, 'id'),
        _c(RunConditionKind.previousPassed),
      ]);
      const previous = PreviousResult('Login', true);

      expect(_decide(policy, environment: 'Staging', variables: const {'id': '1'}, previous: previous).run, isTrue);
      expect(_decide(policy, environment: 'Dev', variables: const {'id': ''}, previous: previous).reason, contains('environment'));
      expect(_decide(policy, environment: 'Staging', variables: const {'id': ''}, previous: previous).reason, contains('{{id}} is empty'));
    });

    test('a condition that is not filled in skips the request with that said, instead of guessing', () {
      final skipped = _decide(_when([_c(RunConditionKind.variableEquals, '', 'x')]));

      expect(skipped.run, isFalse);
      expect(skipped.reason, contains('incomplete'));
      expect(skipped.reason, contains('variable name'));
    });
  });

  group('what is certain before a run starts', () {
    test('an environment condition that fails here means the request will be skipped', () {
      final policy = _when([_c(RunConditionKind.environmentIs, 'Staging')]);

      expect(RunIfEvaluator.surelySkippedIn(policy, 'Production'), isTrue);
      expect(RunIfEvaluator.surelySkippedIn(policy, null), isTrue);
      expect(RunIfEvaluator.surelySkippedIn(policy, 'staging'), isFalse);
      expect(RunIfEvaluator.surelySkippedIn(_when([_c(RunConditionKind.environmentIsNot, 'Production')]), 'Production'), isTrue);
    });

    test('variables and the previous request can still change, so they never make it certain', () {
      expect(RunIfEvaluator.surelySkippedIn(_when([_c(RunConditionKind.variableEquals, 'x', '1')]), 'Production'), isFalse);
      expect(RunIfEvaluator.surelySkippedIn(_when([_c(RunConditionKind.previousFailed)]), 'Production'), isFalse);
    });

    test('a policy that is off is never certain', () {
      expect(
        RunIfEvaluator.surelySkippedIn(RunIfPolicy(conditions: [_c(RunConditionKind.environmentIs, 'Staging')]), 'Production'),
        isFalse,
      );
    });
  });
}
