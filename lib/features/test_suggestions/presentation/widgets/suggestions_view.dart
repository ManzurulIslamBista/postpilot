import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/test_suggestion.dart';
import '../view_models/suggestions_view_model.dart';

/// The proposals for one response as a checklist: tick what to keep, find out which values change by themselves,
/// add the ticked ones to the request's Tests tab.
class SuggestionsView extends StatelessWidget {
  final SuggestionsViewModel viewModel;
  const SuggestionsView({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        if (!vm.loaded) return const Center(child: CircularProgressIndicator());
        final groups = [
          for (final group in SuggestionGroup.values)
            if (vm.inGroup(group).isNotEmpty) group,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  Text(
                    'Checks proposed from this response. Nothing is added to the request until you tick rows and press Add.',
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
                  const SizedBox(height: 10),
                  if (vm.error != null) ...[InfoBanner(kind: BannerKind.error, message: vm.error!), const SizedBox(height: 8)],
                  if (vm.lastAdded case final added?) ...[
                    InfoBanner(
                      kind: BannerKind.success,
                      title: 'Added ${added.count} ${added.count == 1 ? 'test' : 'tests'}',
                      message: 'They are in the Tests tab of this request. Nothing that was there has been changed.',
                      trailing: TextButton(onPressed: vm.adding ? null : vm.undo, child: const Text('Undo')),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _ProbeCard(viewModel: vm),
                  const SizedBox(height: 8),
                  for (final note in vm.result.notes) ...[InfoBanner(kind: BannerKind.warning, message: note), const SizedBox(height: 8)],
                  for (final group in groups) ...[
                    _GroupHeader(group: group, rows: vm.inGroup(group).length),
                    for (final suggestion in vm.inGroup(group)) _SuggestionTile(key: ValueKey(suggestion.id), viewModel: vm, suggestion: suggestion),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            _Footer(viewModel: vm),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final SuggestionGroup group;
  final int rows;
  const _GroupHeader({required this.group, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        '${group.label.toUpperCase()} · $rows',
        style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final SuggestionsViewModel viewModel;
  final TestSuggestion suggestion;
  const _SuggestionTile({super.key, required this.viewModel, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final can = viewModel.canSelect(suggestion.id);
    final detail = suggestion.detail;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: can ? () => viewModel.toggle(suggestion.id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: viewModel.isSelected(suggestion.id),
              visualDensity: VisualDensity.compact,
              onChanged: can ? (_) => viewModel.toggle(suggestion.id) : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(suggestion.label, style: context.textStyles.body.copyWith(color: can ? null : colors.secondaryText)),
                    if (detail != null) Text(detail, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: can
                  ? Tooltip(message: _confidenceHint(suggestion.confidence), child: _ConfidenceChip(confidence: suggestion.confidence))
                  : const StatusChip(label: 'In Tests tab', icon: Icons.check),
            ),
          ],
        ),
      ),
    );
  }

  String _confidenceHint(SuggestionConfidence c) => switch (c) {
        SuggestionConfidence.high => 'High: holds on any healthy answer',
        SuggestionConfidence.medium => 'Medium: relies on what this answer happened to contain',
        SuggestionConfidence.low => 'Low: may be data, not contract',
      };
}

class _ConfidenceChip extends StatelessWidget {
  final SuggestionConfidence confidence;
  const _ConfidenceChip({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StatusChip(
      label: confidence.label,
      color: switch (confidence) {
        SuggestionConfidence.high => colors.statusSuccess,
        SuggestionConfidence.medium => colors.statusWarning,
        SuggestionConfidence.low => null,
      },
    );
  }
}

/// "Send again to detect changing values", with the warning and the opt-in a request that is not a read needs.
class _ProbeCard extends StatelessWidget {
  final SuggestionsViewModel viewModel;
  const _ProbeCard({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = viewModel;
    final blocked = vm.probeBlockedReason;
    final method = vm.request?.method.label;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, size: 18, color: colors.mainAccent),
              const SizedBox(width: 8),
              Expanded(child: Text('Find values that change by themselves', style: context.textStyles.heading.copyWith(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sends the request once more and compares the two answers. A field that differs is never offered as an exact value, '
            'and a field missing from one answer becomes optional.',
            style: context.textStyles.caption.copyWith(color: colors.secondaryText),
          ),
          if (vm.canSendAgain && !vm.methodIsSafe) ...[
            const SizedBox(height: 8),
            InfoBanner(
              kind: BannerKind.warning,
              title: '$method can change data',
              message: 'Sending it again may create or change a record on the server a second time. '
                  'Where the environment looks like production, PostPilot asks before it goes out.',
            ),
            // Its own Material: a ListTile paints on the nearest one, and the card has a background colour.
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: vm.unsafeOptIn,
                onChanged: vm.probing ? null : (v) => vm.setUnsafeOptIn(v ?? false),
                title: Text('I understand: send this $method request again', style: context.textStyles.body),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: blocked == null && !vm.probing ? vm.sendAgain : null,
                child: BusyLabel(busy: vm.probing, icon: Icons.sync, label: 'Send again to detect changing values', busyLabel: 'Sending again…'),
              ),
              if (blocked != null && (vm.methodIsSafe || !vm.canSendAgain))
                Text(blocked, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
            ],
          ),
          if (vm.probeProblem != null) ...[const SizedBox(height: 8), InfoBanner(kind: BannerKind.warning, message: vm.probeProblem!)],
          if (vm.probed && vm.probeProblem == null) ...[const SizedBox(height: 8), _ProbeResult(viewModel: vm)],
        ],
      ),
    );
  }
}

class _ProbeResult extends StatelessWidget {
  final SuggestionsViewModel viewModel;
  const _ProbeResult({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fields = viewModel.result.volatile;
    final comparable = viewModel.stability != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoBanner(
          kind: comparable ? BannerKind.success : BannerKind.info,
          title: comparable ? 'Compared two answers' : 'Second answer received',
          message: !comparable
              ? 'The two answers could not be compared field by field, so only what looks like an id, a timestamp or a token is kept out of exact values.'
              : fields.isEmpty
                  ? 'Nothing changed between them.'
                  : '${fields.length} ${fields.length == 1 ? 'field changes' : 'fields change'} by itself and ${fields.length == 1 ? 'is' : 'are'} kept out of exact values:',
        ),
        if (fields.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final field in fields)
                Tooltip(
                  message: field.reason,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.hover,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(field.label, style: context.textStyles.mono.copyWith(fontSize: 11.5)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final SuggestionsViewModel viewModel;
  const _Footer({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = viewModel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.sidebarBackground.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${vm.selectedCount} selected', style: context.textStyles.caption),
              TextButton(onPressed: vm.selectRecommended, child: const Text('Recommended')),
              TextButton(onPressed: vm.selectAll, child: const Text('All')),
              TextButton(onPressed: vm.selectNone, child: const Text('None')),
            ],
          ),
          FilledButton(
            onPressed: vm.selectedCount == 0 || vm.adding ? null : vm.addSelected,
            child: BusyLabel(
              busy: vm.adding,
              icon: Icons.playlist_add,
              label: 'Add ${vm.selectedCount} selected',
              busyLabel: 'Adding…',
            ),
          ),
        ],
      ),
    );
  }
}
