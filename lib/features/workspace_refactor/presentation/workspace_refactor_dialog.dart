import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../git_sync/presentation/reopen_replaced_requests.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'view_models/workspace_refactor_view_model.dart';
import 'widgets/find_replace_pane.dart';
import 'widgets/rename_variable_pane.dart';
import 'widgets/variable_report_pane.dart';

/// Which tab of the dialog opens first.
enum RefactorTab { findReplace, rename, report }

/// Changes something across the whole workspace: find and replace, rename a variable everywhere, and a report of the
/// variables nothing uses and the names that are used without being defined.
///
/// Every change goes through the repositories the screens use and can be undone while PostPilot stays open; the undo
/// copy is kept in memory only, nothing about it is saved.
class WorkspaceRefactorDialog extends StatefulWidget {
  final RefactorTab initialTab;

  /// Called once, when the dialog opens: each opening gets a view model of its own (see
  /// `showWorkspaceRefactorDialog`), which the dialog disposes with itself.
  final WorkspaceRefactorViewModel Function() createViewModel;

  const WorkspaceRefactorDialog({super.key, required this.createViewModel, this.initialTab = RefactorTab.findReplace});

  @override
  State<WorkspaceRefactorDialog> createState() => _WorkspaceRefactorDialogState();
}

class _WorkspaceRefactorDialogState extends State<WorkspaceRefactorDialog> {
  late final WorkspaceRefactorViewModel _vm = widget.createViewModel();

  /// Held from the start: the dialog may be closed while a replace is still running, and the tabs it changed must
  /// still be reloaded. The shell lives as long as the app.
  ShellViewModel? _shell;

  @override
  void initState() {
    super.initState();
    try {
      _shell = context.read<ShellViewModel>();
    } catch (_) {
      _shell = null; // no shell around (a test): there are no tabs to reload
    }
    _vm.onRequestsChanged = _reloadOpenTabs;
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  /// A request that is open in a tab holds its own copy, which its next edit would save over the replacement:
  /// close those tabs and open them again from the database.
  void _reloadOpenTabs(Set<int> requestIds) {
    final shell = _shell;
    if (shell == null || requestIds.isEmpty) return;
    reopenReplacedRequests(shell, requestIds.toList(), const []);
  }

  @override
  Widget build(BuildContext context) {
    return ToolDialog(
      icon: Icons.find_replace,
      title: 'Refactor the workspace',
      subtitle: 'Find and replace, rename a variable everywhere, and clean up unused variables across every collection',
      width: 1040,
      height: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(listenable: _vm, builder: (context, _) => _NoticeStrip(viewModel: _vm)),
          Expanded(
            child: ToolTabs(
              initialIndex: widget.initialTab.index,
              tabs: [
                ToolTab(label: 'Find and replace', icon: Icons.find_replace, child: FindReplacePane(viewModel: _vm)),
                ToolTab(label: 'Rename variable', icon: Icons.drive_file_rename_outline, child: RenameVariablePane(viewModel: _vm)),
                ToolTab(label: 'Unused and undefined', icon: Icons.rule, child: VariableReportPane(viewModel: _vm)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the last apply did, with "Undo last replace" while there is something to undo. The undo is memory only.
class _NoticeStrip extends StatelessWidget {
  final WorkspaceRefactorViewModel viewModel;
  const _NoticeStrip({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final receipt = vm.lastReceipt;
    final notice = vm.notice;
    if (receipt == null && notice == null) return const SizedBox.shrink();
    final caption = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notice != null)
            InfoBanner(
              kind: vm.noticeIsError ? BannerKind.error : BannerKind.success,
              message: notice,
              trailing: IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: vm.dismissNotice,
              ),
            ),
          if (receipt != null)
            Padding(
              padding: EdgeInsets.only(top: notice == null ? 0 : 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: vm.isApplying ? null : vm.undoLast,
                    child: BusyLabel(busy: vm.isApplying, label: 'Undo last replace', busyLabel: 'Working…', icon: Icons.undo),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      '${receipt.title}: ${receipt.unitCount} ${receipt.unitCount == 1 ? 'place' : 'places'} changed. '
                      'The undo copy lives in memory only, nothing is saved, and it is gone when PostPilot closes.',
                      style: caption,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
