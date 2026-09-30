import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/git_sync_results.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_widgets.dart';

class GitTeamTab extends StatelessWidget {
  const GitTeamTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final link = vm.link;
    if (link == null) return const SizedBox.shrink();
    final textStyles = context.textStyles;
    final colors = context.colors;
    final info = vm.repoInfo;
    final (accessLabel, accessColor) = switch (info?.canPush) {
      null => ('Not checked yet', colors.secondaryText),
      true => ('Can push', colors.statusSuccess),
      false => ('Read-only', colors.methodPost),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Access to this collection is managed on GitHub', style: textStyles.heading),
        const SizedBox(height: 4),
        Text(
          'Everyone who can see the repository can pull this collection. Collaborators with write access can also '
          'push changes; read-only collaborators can pull but not push.',
          style: textStyles.caption.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => vm.openUrl(link.repo.accessSettingsUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Manage access on GitHub'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Your access', style: textStyles.body.copyWith(fontWeight: FontWeight.w600)),
            GitChip(label: accessLabel, color: accessColor),
            if (info != null)
              GitChip(
                label: info.isPrivate ? 'Private repository' : 'Public repository',
                color: colors.secondaryText,
                icon: info.isPrivate ? Icons.lock_outline : Icons.public,
              ),
          ],
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Contributors', style: textStyles.body.copyWith(fontWeight: FontWeight.w600))),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Refresh contributors',
              onPressed: vm.isBusy ? null : vm.loadContributors,
            ),
          ],
        ),
        if (!vm.contributorsLoaded && vm.isBusy)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (vm.contributors.isEmpty)
          Text('No contributors to show yet.', style: textStyles.caption.copyWith(color: colors.secondaryText))
        else
          for (final contributor in vm.contributors)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _Avatar(contributor: contributor),
              title: Text(contributor.login, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                contributor.contributions == 1 ? '1 commit' : '${contributor.contributions} commits',
                style: textStyles.caption.copyWith(color: colors.secondaryText),
              ),
              onTap: () => vm.openUrl(contributor.profileUrl ?? 'https://${link.repo.provider.host}/${contributor.login}'),
            ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final GitContributor contributor;
  const _Avatar({required this.contributor});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 14,
      backgroundColor: context.colors.border,
      child: Text(
        contributor.login.isEmpty ? '?' : contributor.login.substring(0, 1).toUpperCase(),
        style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold),
      ),
    );
    final url = contributor.avatarUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url, width: 28, height: 28, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}
