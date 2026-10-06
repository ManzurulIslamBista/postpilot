import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../settings/presentation/widgets/setting_number_field.dart';
import '../../../settings/presentation/widgets/synced_text_field.dart';
import '../../domain/entities/flow_settings.dart';
import 'flow_section.dart';

/// The statuses offered as chips; any other code or class goes in the text field next to them.
const _chipStatuses = ['5xx', '429', '408'];

/// The settings of "Retry": how many times, on what, and how long to wait between tries.
class RetryEditor extends StatelessWidget {
  final RetryPolicy policy;
  final ValueChanged<RetryPolicy> onChanged;

  const RetryEditor({super.key, required this.policy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final others = policy.statuses.where((s) => !_chipStatuses.contains(s)).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SettingNumberField(
              key: const ValueKey('retry-max'),
              value: policy.maxRetries,
              labelText: 'Retries (1 to 10)',
              width: 150,
              onChanged: (value) => onChanged(policy.copyWith(maxRetries: value)),
            ),
            SettingNumberField(
              key: const ValueKey('retry-delay'),
              value: policy.delayMs,
              labelText: 'First wait',
              suffixText: 'ms',
              width: 140,
              onChanged: (value) => onChanged(policy.copyWith(delayMs: value)),
            ),
            if (policy.backoff == BackoffKind.exponential)
              SettingNumberField(
                key: const ValueKey('retry-max-delay'),
                value: policy.maxDelayMs,
                labelText: 'Longest wait',
                suffixText: 'ms',
                width: 150,
                onChanged: (value) => onChanged(policy.copyWith(maxDelayMs: value)),
              ),
            SettingNumberField(
              key: const ValueKey('retry-total'),
              value: policy.maxTotalSeconds,
              labelText: 'Time limit',
              suffixText: 's',
              width: 130,
              onChanged: (value) => onChanged(policy.copyWith(maxTotalSeconds: value)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Retry when', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              key: const ValueKey('retry-network'),
              label: const Text('Network error'),
              selected: policy.onNetworkError,
              onSelected: (on) => onChanged(policy.copyWith(onNetworkError: on)),
            ),
            for (final token in _chipStatuses)
              FilterChip(
                key: ValueKey('retry-status-$token'),
                label: Text(token == '5xx' ? '5xx server error' : 'HTTP $token'),
                selected: policy.statuses.contains(token),
                onSelected: (on) => onChanged(policy.copyWith(statuses: _toggled(token, on))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 300,
          child: SyncedTextField(
            key: const ValueKey('retry-other-statuses'),
            value: others,
            labelText: 'Other codes or classes',
            hintText: 'e.g. 409, 425, 4xx',
            onChanged: (text) => onChanged(policy.copyWith(statuses: _withOthers(text))),
          ),
        ),
        const SizedBox(height: 12),
        Text('Wait between tries', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
        const SizedBox(height: 4),
        SegmentedButton<BackoffKind>(
          key: const ValueKey('retry-backoff'),
          showSelectedIcon: false,
          segments: [for (final kind in BackoffKind.values) ButtonSegment(value: kind, label: Text(kind.label))],
          selected: {policy.backoff},
          onSelectionChanged: (selection) => onChanged(policy.copyWith(backoff: selection.first)),
        ),
        const SizedBox(height: 4),
        FlowCheckbox(
          key: const ValueKey('retry-jitter'),
          title: 'Randomise the waits (jitter)',
          description: 'Wait 50 to 100% of the planned time, so many clients do not retry in step.',
          value: policy.jitter,
          onChanged: (on) => onChanged(policy.copyWith(jitter: on)),
        ),
        FlowCheckbox(
          key: const ValueKey('retry-after'),
          title: 'Wait as long as Retry-After asks',
          description: 'A server that says how long to wait is believed, within the time limit.',
          value: policy.honourRetryAfter,
          onChanged: (on) => onChanged(policy.copyWith(honourRetryAfter: on)),
        ),
        const FlowHint(
          'Every try shows in the Console as "attempt 2/3 after 1.2 s", and in run results. '
          'GET, HEAD, OPTIONS and PUT are retried; POST, PATCH and DELETE only when you tick '
          '"I know repeating this request is safe" below.',
        ),
      ],
    );
  }

  /// The statuses with [token] added or removed, the other codes kept.
  List<String> _toggled(String token, bool on) =>
      on ? [...policy.statuses.where((s) => s != token), token] : [for (final s in policy.statuses) if (s != token) s];

  /// The chip statuses already chosen, plus what [text] holds.
  List<String> _withOthers(String text) {
    final chips = policy.statuses.where(_chipStatuses.contains);
    return [...chips, ...StatusTokens.parseList(text).where((token) => !_chipStatuses.contains(token))];
  }
}
