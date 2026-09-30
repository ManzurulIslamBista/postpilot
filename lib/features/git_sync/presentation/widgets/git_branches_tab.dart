import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_widgets.dart';

class GitBranchesTab extends StatelessWidget {
  const GitBranchesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final link = vm.link;
    if (link == null) return const SizedBox.shrink();
    final textStyles = context.textStyles;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Current branch', style: textStyles.caption.copyWith(color: colors.secondaryText)),
              GitChip(label: link.branch, color: colors.methodPut, icon: Icons.call_split),
              OutlinedButton.icon(
                onPressed: vm.isBusy ? null : () => _create(context, vm, link.branch),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New branch from current'),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh branches',
                onPressed: vm.isBusy ? null : vm.loadBranches,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Switching replaces this collection with the other branch's version, so push or discard local changes first.",
              style: textStyles.caption.copyWith(color: colors.secondaryText),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !vm.branchesLoaded && vm.isBusy
              ? const Center(child: CircularProgressIndicator())
              : vm.branches.isEmpty
                  ? Center(
                      child: Text(
                        'No branches to show yet.',
                        style: textStyles.caption.copyWith(color: colors.secondaryText),
                      ),
                    )
                  : ListView.builder(
                      itemCount: vm.branches.length,
                      itemBuilder: (context, index) {
                        final name = vm.branches[index];
                        final isCurrent = name == link.branch;
                        return ListTile(
                          dense: true,
                          selected: isCurrent,
                          leading: Icon(isCurrent ? Icons.check_circle_outline : Icons.call_split, size: 18),
                          title: Text(name, overflow: TextOverflow.ellipsis),
                          trailing: isCurrent
                              ? Text('Current', style: textStyles.caption.copyWith(color: colors.mainAccent))
                              : OutlinedButton(
                                  onPressed: vm.isBusy ? null : () => vm.switchBranch(name),
                                  child: const Text('Switch'),
                                ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, GitSyncViewModel vm, String current) async {
    final name = await showPromptDialog(context, title: 'New branch from $current', confirmLabel: 'Create');
    if (name != null) await vm.createBranch(name);
  }
}
