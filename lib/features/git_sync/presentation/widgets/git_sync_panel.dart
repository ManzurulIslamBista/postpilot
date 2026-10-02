import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/git_link.dart';
import '../git_formatting.dart';
import '../view_models/git_sync_view_model.dart';
import 'git_branches_tab.dart';
import 'git_changes_tab.dart';
import 'git_conflicts_dialog.dart';
import 'git_connect_view.dart';
import 'git_history_tab.dart';
import 'git_settings_tab.dart';
import 'git_team_tab.dart';
import 'git_widgets.dart';

class GitSyncPanel extends StatelessWidget {
  final int collectionId;
  final String collectionName;
  const GitSyncPanel({super.key, required this.collectionId, required this.collectionName});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    if (vm.link != null) return const _LinkedView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GitPanelTitle(title: 'Git sync', subtitle: collectionName, busyLabel: vm.busyLabel, canClose: vm.canClose),
        GitBusyBar(busy: vm.isBusy),
        _Messages(vm: vm),
        Expanded(
          child: !vm.isLoaded
              ? vm.isBusy
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: TextButton.icon(
                        onPressed: () => vm.load(collectionId, collectionName: collectionName),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try again'),
                      ),
                    )
              : const GitConnectView(),
        ),
      ],
    );
  }
}

class _Messages extends StatelessWidget {
  final GitSyncViewModel vm;
  const _Messages({required this.vm});

  @override
  Widget build(BuildContext context) {
    final error = vm.errorMessage;
    final info = vm.infoMessage;
    if (error == null && info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          if (error != null) GitBanner(message: error, kind: GitBannerKind.error),
          if (error != null && info != null) const SizedBox(height: 6),
          if (info != null) GitBanner(message: info, kind: GitBannerKind.success),
        ],
      ),
    );
  }
}

class _LinkedView extends StatefulWidget {
  const _LinkedView();

  @override
  State<_LinkedView> createState() => _LinkedViewState();
}

class _LinkedViewState extends State<_LinkedView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(_onTabChanged);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The lists behind the other tabs cost a network call each, so they load the first time their tab opens.
  void _onTabChanged() {
    final vm = context.read<GitSyncViewModel>();
    switch (_tabs.index) {
      case 1:
        vm.ensureHistory();
      case 2:
        vm.ensureBranches();
      case 3:
        vm.ensureContributors();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GitSyncViewModel>();
    final link = vm.link;
    if (link == null) return const SizedBox.shrink();
    final changeCount = vm.localChanges.length;
    return Column(
      children: [
        _LinkedHeader(vm: vm, link: link),
        GitBusyBar(busy: vm.isBusy),
        _Messages(vm: vm),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: changeCount > 0 ? 'Changes ($changeCount)' : 'Changes'),
            const Tab(text: 'History'),
            const Tab(text: 'Branches'),
            const Tab(text: 'Team'),
            const Tab(text: 'Settings'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [GitChangesTab(), GitHistoryTab(), GitBranchesTab(), GitTeamTab(), GitSettingsTab()],
          ),
        ),
      ],
    );
  }
}

class _LinkedHeader extends StatelessWidget {
  final GitSyncViewModel vm;
  final GitLink link;
  const _LinkedHeader({required this.vm, required this.link});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.merge_type, size: 18, color: colors.mainAccent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: GitLinkText(
                        label: link.repo.fullName,
                        url: link.repo.webUrl,
                        onOpen: vm.openUrl,
                        style: context.textStyles.heading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    GitChip(label: link.branch, color: colors.methodPut, icon: Icons.call_split),
                    ..._statusChips(context),
                    Text(_syncedText(link), style: caption.copyWith(color: colors.secondaryText)),
                    if (vm.isBusy && vm.busyLabel != null)
                      Text(vm.busyLabel!, style: caption.copyWith(color: colors.mainAccent)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for changes',
            onPressed: vm.isBusy ? null : () => vm.refresh(checkRemote: true),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: vm.canClose ? () => Navigator.pop(context) : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _statusChips(BuildContext context) {
    final colors = context.colors;
    final count = vm.localChanges.length;
    if (vm.status == null) return [GitChip(label: 'Status unknown', color: colors.secondaryText)];
    return [
      if (vm.needsPull)
        GitChip(
          label: 'Behind remote — pull',
          color: colors.methodPost,
          icon: Icons.south,
          onTap: vm.isBusy ? null : () => pullAndResolve(context, vm),
        ),
      if (count > 0)
        GitChip(
          label: count == 1 ? '1 local change' : '$count local changes',
          color: colors.mainAccent,
          icon: Icons.edit_outlined,
        ),
      if (!vm.needsPull && count == 0)
        GitChip(
          label: vm.remoteChecked ? 'Up to date' : 'No local changes',
          color: colors.statusSuccess,
          icon: Icons.check,
        ),
    ];
  }

  static String _syncedText(GitLink link) {
    final at = link.lastSyncedAt;
    final sha = link.lastSyncedSha;
    if (at == null) return 'Not synced yet';
    return 'Synced ${relativeTime(at)}${sha == null ? '' : ' · ${shortSha(sha)}'}';
  }
}
