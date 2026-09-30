import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_token_section.dart';
import 'git_widgets.dart';

class GitSettingsTab extends StatelessWidget {
  const GitSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final link = vm.link;
    if (link == null) return const SizedBox.shrink();
    final textStyles = context.textStyles;
    final secondary = context.colors.secondaryText;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoRow(label: 'Repository', value: link.repo.fullName),
        _InfoRow(label: 'Branch', value: link.branch),
        _InfoRow(label: 'Folder', value: link.basePath.isEmpty ? 'Repository root' : link.basePath),
        const Divider(height: 32),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include credentials in commits'),
          value: link.includeSecrets,
          onChanged: vm.isBusy ? null : (value) => _toggleSecrets(context, vm, value),
        ),
        const GitCredentialsWarning(),
        const Divider(height: 32),
        GitTokenSection(
          title: 'Update token',
          hasToken: vm.hasToken,
          verifiedLogin: vm.verifiedLogin,
          isBusy: vm.isBusy,
          onSave: vm.saveToken,
          onOpenLink: vm.openUrl,
        ),
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: vm.isBusy ? null : () => _disconnect(context, vm),
            style: OutlinedButton.styleFrom(foregroundColor: context.colors.statusError),
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Disconnect'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Stops syncing. The collection stays on this device and the repository is left untouched.',
          style: textStyles.caption.copyWith(color: secondary),
        ),
      ],
    );
  }

  Future<void> _toggleSecrets(BuildContext context, GitSyncViewModel vm, bool include) async {
    if (include) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Include credentials?',
        message: 'Tokens, passwords and API keys stored in this collection will be committed and visible to '
            'everyone who can access the repository.',
        confirmLabel: 'Include credentials',
      );
      if (!confirmed) return;
    }
    await vm.setIncludeSecrets(include);
  }

  Future<void> _disconnect(BuildContext context, GitSyncViewModel vm) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect from Git',
      message: 'Stop syncing with ${vm.link?.repo.fullName ?? 'the repository'}? The collection stays on this '
          'device and nothing is deleted in the repository.',
      confirmLabel: 'Disconnect',
    );
    if (confirmed) await vm.disconnect();
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          ),
          Expanded(child: SelectableText(value, style: context.textStyles.body)),
        ],
      ),
    );
  }
}
