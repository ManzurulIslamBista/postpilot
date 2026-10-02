import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/workplace_view_model.dart';
import 'add_workplace_dialog.dart';
import 'push_to_git.dart';
import 'workplace_settings_dialog.dart';

class WorkplaceSidebarHeader extends StatelessWidget {
  const WorkplaceSidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final vm = context.watch<WorkplaceViewModel>();
    final active = vm.activeWorkplace;
    final workplaces = vm.workplaces;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Switch or manage workplaces',
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onSelected: (action) => _handleMenuAction(context, vm, action),
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String>>[];

          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text(
                'WORKPLACES',
                style: textStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontSize: 10,
                  color: colors.secondaryText,
                ),
              ),
            ),
          );

          for (final wp in workplaces) {
            final isSelected = wp.id == active?.id;
            items.add(
              PopupMenuItem<String>(
                value: 'select_${wp.id}',
                child: Row(
                  children: [
                    Icon(
                      wp.isGitConnected ? Icons.alt_route : Icons.folder_outlined,
                      size: 16,
                      color: isSelected ? colors.mainAccent : colors.secondaryText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        wp.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colors.mainAccent : null,
                        ),
                      ),
                    ),
                    if (isSelected) Icon(Icons.check, size: 16, color: colors.mainAccent),
                  ],
                ),
              ),
            );
          }

          items.add(const PopupMenuDivider());

          items.add(
            const PopupMenuItem<String>(
              value: 'add_workplace',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16),
                  SizedBox(width: 8),
                  Flexible(child: Text('Add Workplace…', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          );

          if (active != null) {
            if (vm.canRevealFolder) {
              items.add(
                PopupMenuItem<String>(
                  value: 'reveal_in_finder',
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open, size: 16),
                      const SizedBox(width: 8),
                      Flexible(child: Text('Show in ${vm.fileManagerName}', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            }

            if (active.isGitConnected) {
              items.add(
                const PopupMenuItem<String>(
                  value: 'sync_git',
                  child: Row(
                    children: [
                      Icon(Icons.sync, size: 16),
                      SizedBox(width: 8),
                      Flexible(child: Text('Sync with Git', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
              items.add(
                const PopupMenuItem<String>(
                  value: 'pull_git',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_download_outlined, size: 16),
                      SizedBox(width: 8),
                      Flexible(child: Text('Pull from Git', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            }

            items.add(
              const PopupMenuItem<String>(
                value: 'workplace_settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 16),
                    SizedBox(width: 8),
                    Flexible(child: Text('Workplace Settings…', overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            );
          }

          return items;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: colors.mainAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  active?.isGitConnected == true ? Icons.alt_route : Icons.folder_outlined,
                  size: 15,
                  color: colors.mainAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active?.name ?? 'No Workplace',
                      style: textStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            active?.isGitConnected == true ? 'Git: ${active?.gitBranch}' : 'Workplace',
                            style: textStyles.caption.copyWith(
                              fontSize: 10,
                              color: colors.secondaryText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (active?.isGitConnected == true) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.statusSuccess,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, size: 16, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, WorkplaceViewModel vm, String action) async {
    if (action.startsWith('select_')) {
      final id = action.replaceFirst('select_', '');
      final wp = vm.workplaces.firstWhere((w) => w.id == id);
      await vm.switchWorkplace(wp);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Switched to workplace "${wp.name}"')),
        );
      }
    } else if (action == 'add_workplace') {
      await AddWorkplaceDialog.show(context);
    } else if (action == 'reveal_in_finder') {
      await vm.revealWorkplaceFolder();
    } else if (action == 'sync_git') {
      await pushWorkplaceToGit(context, vm);
    } else if (action == 'pull_git') {
      await vm.pullFromGit();
      if (context.mounted) {
        final error = vm.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? 'Pulled successfully from Git repository!'),
            backgroundColor: error != null ? context.colors.statusError : null,
          ),
        );
      }
    } else if (action == 'workplace_settings') {
      if (vm.activeWorkplace != null) {
        await WorkplaceSettingsDialog.show(context, vm.activeWorkplace!);
      }
    }
  }
}
