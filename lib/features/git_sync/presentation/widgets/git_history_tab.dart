import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../git_formatting.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_widgets.dart';

class GitHistoryTab extends StatelessWidget {
  const GitHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final link = vm.link;
    if (link == null) return const SizedBox.shrink();
    final textStyles = context.textStyles;
    final colors = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Commits on ${link.branch} that changed this collection',
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh history',
                onPressed: vm.isBusy ? null : vm.loadHistory,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !vm.historyLoaded && vm.isBusy
              ? const Center(child: CircularProgressIndicator())
              : vm.history.isEmpty
                  ? Center(
                      child: Text(
                        'No commits yet for this collection.',
                        style: textStyles.caption.copyWith(color: colors.secondaryText),
                      ),
                    )
                  : ListView.builder(
                      itemCount: vm.history.length,
                      itemBuilder: (context, index) {
                        final commit = vm.history[index];
                        return ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: 72,
                            child: Text(
                              commit.shortSha,
                              style: gitMono(context).copyWith(color: colors.mainAccent),
                            ),
                          ),
                          title: Text(
                            commit.title.trim().isEmpty ? '(no message)' : commit.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${commit.authorName} · ${relativeTime(commit.date)}',
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.caption.copyWith(color: colors.secondaryText),
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 14),
                          onTap: () => vm.openUrl(commit.url ?? link.repo.commitUrl(commit.sha)),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
