import '../../../../core/widgets/busy_label.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/git_sync_results.dart';
import '../git_formatting.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_conflicts_dialog.dart';
import 'git_widgets.dart';

class GitChangesTab extends StatelessWidget {
  const GitChangesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final changes = vm.localChanges;
    final textStyles = context.textStyles;
    final secondary = context.colors.secondaryText;
    return Column(
      children: [
        if (!vm.hasToken)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: GitBanner(
              kind: GitBannerKind.warning,
              message:
                  'No GitHub token is saved on this device. Save one under Settings to push your changes; '
                  'without it you can only pull.',
            ),
          )
        else if (!vm.canPush)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: GitBanner(
              kind: GitBannerKind.warning,
              message: 'You have read-only access to this repository: you can pull changes but not push yours.',
            ),
          ),
        if (vm.needsPull)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: GitBanner(
              kind: GitBannerKind.warning,
              message: 'The remote branch has new commits. Pull them before you push.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(switch (changes.length) {
              0 => 'No changes since the last sync',
              1 => '1 local change',
              final count => '$count local changes',
            }, style: textStyles.caption.copyWith(color: secondary, fontWeight: FontWeight.bold)),
          ),
        ),
        Expanded(
          child: changes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Everything is in sync. Edit the collection, then come back to commit and push.',
                      textAlign: TextAlign.center,
                      style: textStyles.caption.copyWith(color: secondary),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: changes.length,
                  itemBuilder: (context, index) => _ChangeTile(change: changes[index]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _CommitArea(vm: vm),
        ),
      ],
    );
  }
}

class _ChangeTile extends StatelessWidget {
  final DocChange change;
  const _ChangeTile({required this.change});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color) = switch (change.type) {
      DocChangeType.added => ('Added', colors.statusSuccess),
      DocChangeType.modified => ('Modified', colors.methodPost),
      DocChangeType.deleted => ('Deleted', colors.statusError),
    };
    return ListTile(
      dense: true,
      leading: Icon(gitKindIcon(change.kind), size: 18),
      title: Text(change.name.isEmpty ? '(unnamed)' : change.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [gitKindLabel(change.kind), if (change.changedFields.isNotEmpty) change.changedFields.join(', ')].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textStyles.caption.copyWith(color: colors.secondaryText),
      ),
      trailing: GitChip(label: label, color: color),
    );
  }
}

class _CommitArea extends StatelessWidget {
  final GitSyncViewModel vm;
  const _CommitArea({required this.vm});

  @override
  Widget build(BuildContext context) {
    final push = vm.lastPush;
    final link = vm.link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommitMessageField(vm: vm),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: vm.canCommit ? vm.commitPush : null,
              child: BusyLabel(
                busy: vm.isBusy && (vm.busyLabel?.startsWith('Committing') ?? false),
                icon: Icons.cloud_upload_outlined,
                label: 'Commit & push',
                busyLabel: 'Pushing…',
              ),
            ),
            OutlinedButton.icon(
              onPressed: vm.isBusy ? null : () => pullAndResolve(context, vm),
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('Pull'),
            ),
            TextButton(
              onPressed: vm.isBusy || !vm.hasLocalChanges ? null : () => _discard(context, vm),
              style: TextButton.styleFrom(foregroundColor: context.colors.statusError),
              child: BusyLabel(
                busy: vm.isBusy && (vm.busyLabel?.startsWith('Discarding') ?? false),
                icon: Icons.undo,
                label: 'Discard changes',
                busyLabel: 'Discarding…',
              ),
            ),
          ],
        ),
        if (push != null && link != null) ...[
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Icon(Icons.check_circle_outline, size: 14, color: context.colors.statusSuccess),
              Text('Pushed', style: context.textStyles.caption),
              GitLinkText(
                label: shortSha(push.commitSha),
                url: link.repo.commitUrl(push.commitSha),
                onOpen: vm.openUrl,
                style: gitMono(context),
              ),
              Text(
                push.changedFiles == 1 ? '· 1 file' : '· ${push.changedFiles} files',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _discard(BuildContext context, GitSyncViewModel vm) async {
    final count = vm.localChanges.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard local changes',
      message:
          'Throw away ${count == 1 ? 'the 1 local change' : 'all $count local changes'} and restore the last '
          'synced version of this collection? This cannot be undone.',
      confirmLabel: 'Discard',
    );
    if (confirmed) await vm.discard();
  }
}

/// The view model owns the message (a push resets it to the default), so the controller follows it.
class _CommitMessageField extends StatefulWidget {
  final GitSyncViewModel vm;
  const _CommitMessageField({required this.vm});

  @override
  State<_CommitMessageField> createState() => _CommitMessageFieldState();
}

class _CommitMessageFieldState extends State<_CommitMessageField> {
  late final _controller = TextEditingController(text: widget.vm.commitMessage);

  @override
  void didUpdateWidget(_CommitMessageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final message = widget.vm.commitMessage;
    if (_controller.text != message) {
      _controller.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: !widget.vm.isBusy,
      minLines: 2,
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Commit message', alignLabelWithHint: true),
      onChanged: (value) => widget.vm.commitMessage = value,
    );
  }
}
