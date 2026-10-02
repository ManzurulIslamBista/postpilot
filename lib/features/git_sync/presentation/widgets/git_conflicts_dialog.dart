import '../../../../core/widgets/busy_label.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/git_sync_results.dart';
import '../git_formatting.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_widgets.dart';

/// Pulls, and when the merge needs decisions asks for them. The outcome lands in [viewModel].
Future<void> pullAndResolve(BuildContext context, GitSyncViewModel viewModel) async {
  await viewModel.pull();
  if (!context.mounted || viewModel.conflicts.isEmpty) return;
  await GitConflictsDialog.show(context, viewModel: viewModel);
}

class GitConflictsDialog extends StatelessWidget {
  const GitConflictsDialog({super.key});

  /// True when the merge was applied. Anything else (cancel, Escape) drops the pending conflicts untouched.
  static Future<bool> show(BuildContext context, {required GitSyncViewModel viewModel}) async {
    final merged = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ChangeNotifierProvider<GitSyncViewModel>.value(value: viewModel, child: const GitConflictsDialog()),
    );
    if (merged != true) viewModel.cancelConflicts();
    return merged == true;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final conflicts = vm.conflicts;
    final count = conflicts.length;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resolve conflicts', style: context.textStyles.heading),
                  const SizedBox(height: 4),
                  Text(
                    count == 1
                        ? '1 item was changed both here and on GitHub. Choose which version to keep.'
                        : '$count items were changed both here and on GitHub. Choose which version to keep for each.',
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
                ],
              ),
            ),
            GitBusyBar(busy: vm.isBusy),
            if (vm.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: GitBanner(message: vm.errorMessage!, kind: GitBannerKind.error),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final conflict = conflicts[index];
                  return _ConflictCard(
                    conflict: conflict,
                    choice: vm.choiceFor(conflict.uid),
                    enabled: !vm.isBusy,
                    onChanged: (choice) => vm.setChoice(conflict.uid, choice),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing changes until you apply the merge.',
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: vm.isBusy ? null : () => _cancel(context, vm),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: vm.isBusy || count == 0 ? null : () => _apply(context, vm),
                          child: BusyLabel(
                            busy: vm.isBusy,
                            icon: Icons.merge_type,
                            label: 'Apply merge',
                            busyLabel: 'Applying…',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cancel(BuildContext context, GitSyncViewModel vm) {
    vm.cancelConflicts();
    Navigator.pop(context, false);
  }

  Future<void> _apply(BuildContext context, GitSyncViewModel vm) async {
    final applied = await vm.applyResolutions();
    if (applied && vm.conflicts.isEmpty && context.mounted) Navigator.pop(context, true);
  }
}

class _ConflictCard extends StatelessWidget {
  final SyncConflict conflict;
  final ConflictChoice choice;
  final bool enabled;
  final ValueChanged<ConflictChoice> onChanged;

  const _ConflictCard({required this.conflict, required this.choice, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(gitKindIcon(conflict.kind), size: 18, color: colors.secondaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conflict.name.isEmpty ? '(unnamed)' : conflict.name,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              GitChip(label: gitKindLabel(conflict.kind), color: colors.secondaryText),
            ],
          ),
          const SizedBox(height: 4),
          Text(_description(conflict.type), style: textStyles.caption.copyWith(color: colors.secondaryText)),
          for (final field in conflict.fields) ...[
            const SizedBox(height: 10),
            _FieldComparison(field: field, choice: choice),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<ConflictChoice>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ConflictChoice.local, label: Text('Keep mine')),
                  ButtonSegment(value: ConflictChoice.remote, label: Text('Keep theirs')),
                ],
                selected: {choice},
                onSelectionChanged: enabled ? (selection) => onChanged(selection.first) : null,
              ),
              Text(_outcome(conflict.type, choice), style: textStyles.caption),
            ],
          ),
        ],
      ),
    );
  }

  static String _description(ConflictKind kind) => switch (kind) {
    ConflictKind.bothModified => 'Changed both here and on GitHub. The fields that differ are listed below.',
    ConflictKind.deletedLocallyModifiedRemotely => 'You deleted this here, but it was changed on GitHub.',
    ConflictKind.modifiedLocallyDeletedRemotely => 'You changed this here, but it was deleted on GitHub.',
  };

  static String _outcome(ConflictKind kind, ConflictChoice choice) => switch ((kind, choice)) {
    (ConflictKind.bothModified, ConflictChoice.local) => 'Every field above keeps your value.',
    (ConflictKind.bothModified, ConflictChoice.remote) => 'Every field above takes their value.',
    (ConflictKind.deletedLocallyModifiedRemotely, ConflictChoice.local) => 'The item stays deleted.',
    (ConflictKind.deletedLocallyModifiedRemotely, ConflictChoice.remote) => 'The item is restored with their changes.',
    (ConflictKind.modifiedLocallyDeletedRemotely, ConflictChoice.local) => 'Your changes are kept and the item stays.',
    (ConflictKind.modifiedLocallyDeletedRemotely, ConflictChoice.remote) =>
      'The item is deleted and your changes are dropped.',
  };
}

class _FieldComparison extends StatelessWidget {
  final FieldConflict field;
  final ConflictChoice choice;
  const _FieldComparison({required this.field, required this.choice});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.field, style: gitMono(context).copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final cells = [
              _ValueCell(label: 'Base', value: field.base, highlighted: false),
              _ValueCell(label: 'Mine', value: field.local, highlighted: choice == ConflictChoice.local),
              _ValueCell(label: 'Theirs', value: field.remote, highlighted: choice == ConflictChoice.remote),
            ];
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cells.length; i++) ...[if (i > 0) const SizedBox(height: 6), cells[i]],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: cells[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String label;
  final Object? value;
  final bool highlighted;
  const _ValueCell({required this.label, required this.value, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: formatConflictValue(value, maxLength: 600),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: highlighted ? colors.mainAccent.withValues(alpha: 0.08) : colors.appBackground,
          border: Border.all(color: highlighted ? colors.mainAccent : colors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(formatConflictValue(value), maxLines: 4, overflow: TextOverflow.ellipsis, style: gitMono(context)),
          ],
        ),
      ),
    );
  }
}
