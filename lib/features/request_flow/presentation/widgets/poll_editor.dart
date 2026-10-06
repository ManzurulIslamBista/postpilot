import 'package:flutter/material.dart';
import '../../../scripting/presentation/widgets/assertions_editor.dart';
import '../../../settings/presentation/widgets/setting_number_field.dart';
import '../../domain/entities/flow_settings.dart';
import 'flow_section.dart';

/// The settings of "Poll until": what to wait for, how often to ask, and when to give up.
class PollEditor extends StatelessWidget {
  final PollPolicy policy;
  final ValueChanged<PollPolicy> onChanged;

  const PollEditor({super.key, required this.policy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowHint(
          'The request is sent again until every condition holds on the response, for example JSON path status equals done. '
          'Values can use {{variables}}. The conditions work like assertions.',
        ),
        const SizedBox(height: 6),
        AssertionsEditor(
          items: policy.until,
          addLabel: 'Add condition',
          onChanged: (items) => onChanged(policy.copyWith(until: items)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SettingNumberField(
              key: const ValueKey('poll-interval'),
              value: policy.intervalMs,
              labelText: 'Ask every',
              suffixText: 'ms',
              width: 140,
              onChanged: (value) => onChanged(policy.copyWith(intervalMs: value)),
            ),
            SettingNumberField(
              key: const ValueKey('poll-attempts'),
              value: policy.maxAttempts,
              labelText: 'At most',
              suffixText: 'requests',
              width: 160,
              onChanged: (value) => onChanged(policy.copyWith(maxAttempts: value)),
            ),
            SettingNumberField(
              key: const ValueKey('poll-seconds'),
              value: policy.maxSeconds,
              labelText: 'Give up after',
              suffixText: 's',
              width: 150,
              onChanged: (value) => onChanged(policy.copyWith(maxSeconds: value)),
            ),
          ],
        ),
        const FlowHint(
          'The result shows how many times it asked. If the conditions never hold, the request fails with the last response '
          'and what it was still waiting for. Tests and variable saves run on the last response.',
        ),
      ],
    );
  }
}
