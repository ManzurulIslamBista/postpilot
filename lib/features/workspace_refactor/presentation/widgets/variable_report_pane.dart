import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../view_models/workspace_refactor_view_model.dart';
import 'refactor_chrome.dart';

/// Which variables nothing uses (to delete, if the user ticks them) and which `{{names}}` are used and defined nowhere.
class VariableReportPane extends StatelessWidget {
  final WorkspaceRefactorViewModel viewModel;
  const VariableReportPane({super.key, required this.viewModel});

  WorkspaceRefactorViewModel get vm => viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (vm.snapshot == null) return WorkspaceLoading(viewModel: vm);
        final colors = context.colors;
        final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
        final items = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Read from this workspace only. A variable can still be used from outside it (a command-line run, an exported .env file, a teammate\'s copy), '
              'so nothing is ticked for you.',
              style: caption,
            ),
          ),
          _section(
            context,
            icon: Icons.delete_sweep_outlined,
            title: 'Unused variables (${vm.unused.length})',
            trailing: vm.unused.isEmpty
                ? null
                : Wrap(
                    spacing: 4,
                    children: [
                      TextButton(onPressed: () => vm.markAllForDelete(true), child: const Text('Tick all')),
                      TextButton(onPressed: () => vm.markAllForDelete(false), child: const Text('Tick none')),
                    ],
                  ),
          ),
          if (vm.unused.isEmpty)
            _note(context, 'Every variable that is defined is used somewhere.')
          else
            for (final variable in vm.unused) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(variable.name, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (final d in variable.definitions)
                CheckboxListTile(
                  key: ValueKey(d.id),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  value: vm.isMarkedForDelete(d.id),
                  onChanged: (v) => vm.setMarkedForDelete(d.id, v ?? false),
                  title: Text(d.where, style: context.textStyles.body, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    d.trail.isEmpty ? d.shownValue : '${d.shownValue.isEmpty ? '(empty)' : d.shownValue}  ·  ${d.trail.join(' / ')}',
                    style: context.textStyles.mono.copyWith(fontSize: 11.5, color: colors.secondaryText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          _section(context, icon: Icons.help_outline, title: 'Undefined variables (${vm.undefined.length})'),
          if (vm.undefined.isEmpty)
            _note(context, 'Every {{name}} that is used is defined (or built in).')
          else
            for (final use in vm.undefined)
              Padding(
                key: ValueKey('undefined:${use.name}'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, size: 15, color: colors.statusWarning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('{{${use.name}}}', style: context.textStyles.mono.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    if (use.hint != null) Padding(padding: const EdgeInsets.only(left: 21, top: 2), child: Text(use.hint!, style: caption)),
                    for (final place in use.places)
                      Padding(padding: const EdgeInsets.only(left: 21, top: 2), child: Text('used in $place', style: caption)),
                  ],
                ),
              ),
          const SizedBox(height: 12),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ListView(children: items)),
            RefactorFooter(
              leading: Text(
                vm.markedForDeleteCount == 0
                    ? 'Tick the unused variables you want to delete. Undo stays available until PostPilot closes.'
                    : '${vm.markedForDeleteCount} ticked.',
                style: caption,
              ),
              actions: [
                TextButton.icon(onPressed: vm.isLoading ? null : vm.load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
                FilledButton(
                  onPressed: vm.canDeleteUnused ? vm.deleteMarkedUnused : null,
                  child: BusyLabel(
                    busy: vm.isApplying,
                    label: 'Delete selected (${vm.markedForDeleteCount})',
                    busyLabel: 'Deleting…',
                    icon: Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, {required IconData icon, required String title, Widget? trailing}) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: colors.sidebarBackground.withValues(alpha: 0.7),
        border: Border(top: BorderSide(color: colors.border), bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.secondaryText),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          ?trailing,
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), child: InfoBanner(kind: BannerKind.success, message: text));
}
