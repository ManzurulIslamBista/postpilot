import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/variable_renamer.dart';
import '../view_models/workspace_refactor_view_model.dart';
import 'preview_layout.dart';
import 'refactor_chrome.dart';

/// Renames a variable in every place at once: its definitions (environments, globals, collections, folders,
/// extractors) and every `{{reference}}` to it. Shows the whole change first, and the conflicts when the new name
/// already exists.
class RenameVariablePane extends StatefulWidget {
  final WorkspaceRefactorViewModel viewModel;
  const RenameVariablePane({super.key, required this.viewModel});

  @override
  State<RenameVariablePane> createState() => _RenameVariablePaneState();
}

class _RenameVariablePaneState extends State<RenameVariablePane> {
  WorkspaceRefactorViewModel get vm => widget.viewModel;
  late final TextEditingController _old = TextEditingController(text: vm.oldName);
  late final TextEditingController _new = TextEditingController(text: vm.newName);

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (vm.snapshot == null) return WorkspaceLoading(viewModel: vm);
        // A rename that finished empties the fields; the boxes follow the view model.
        if (_old.text != vm.oldName) _old.text = vm.oldName;
        if (_new.text != vm.newName) _new.text = vm.newName;
        return PreviewLayout(
          controls: _controls(context),
          rows: vm.renameRows,
          isTicked: (_) => true,
          empty: _empty(context),
          footer: _footer(context),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    if (vm.renamePlan.error != null) return const SizedBox.shrink();
    final typed = VariableRenamer.clean(vm.oldName).isNotEmpty && VariableRenamer.clean(vm.newName).isNotEmpty;
    return EmptyHint(
      icon: Icons.drive_file_rename_outline,
      title: typed ? 'Nothing uses this name' : 'Rename a variable everywhere',
      message: typed
          ? '{{${VariableRenamer.clean(vm.oldName)}}} is neither defined nor used anywhere in the workspace.'
          : 'Pick a variable and type its new name. Its definitions and every {{reference}} are listed here before anything changes.',
    );
  }

  Widget _controls(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final oldField = TextField(
      controller: _old,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Variable to rename', prefixIcon: Icon(Icons.data_object, size: 18)),
      onChanged: vm.setOldName,
    );
    final newField = TextField(
      controller: _new,
      decoration: const InputDecoration(labelText: 'New name', prefixIcon: Icon(Icons.drive_file_rename_outline, size: 18)),
      onChanged: vm.setNewName,
    );
    final suggestions = vm.suggestions(vm.oldName);
    final plan = vm.renamePlan;
    final error = plan.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 560
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: oldField), const SizedBox(width: 12), Expanded(child: newField)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [oldField, const SizedBox(height: 10), newField]),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Defined:', style: caption),
              for (final name in suggestions)
                Tooltip(
                  message: name.homes.join('\n'),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(name.definitions > 1 ? '${name.name} ×${name.definitions}' : name.name),
                    onPressed: () => vm.setOldName(name.name),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (error != null && VariableRenamer.clean(vm.newName).isNotEmpty)
          InfoBanner(kind: BannerKind.error, message: error)
        else if (plan.editCount > 0 || plan.deletions.isNotEmpty)
          Text(
            '${vm.definitionCount} ${vm.definitionCount == 1 ? 'definition' : 'definitions'} and '
            '${vm.referenceCount} ${vm.referenceCount == 1 ? 'reference' : 'references'} in ${plan.changes.length} '
            '${plan.changes.length == 1 ? 'place' : 'places'}. Spaces inside the braces are kept, {{\$dynamic}} variables and longer names are left alone.',
            style: caption,
          )
        else
          Text(
            'Only whole names change: renaming baseUrl leaves {{baseUrlV2}} alone. Secret values stay masked here.',
            style: caption,
          ),
        if (plan.needsConfirmation) ...[const SizedBox(height: 10), _conflicts(context)],
      ],
    );
  }

  Widget _conflicts(BuildContext context) {
    final plan = vm.renamePlan;
    final to = VariableRenamer.clean(vm.newName);
    final from = VariableRenamer.clean(vm.oldName);
    final lines = [
      for (final c in plan.conflicts)
        c.collides
            ? '${c.where} has both: {{$to}} = ${c.existingValue} stays, {{$from}} = ${c.oldValue} is deleted.'
            : '${c.where} already defines {{$to}} = ${c.existingValue}.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InfoBanner(
          kind: BannerKind.warning,
          title: '{{$to}} already exists',
          message: lines.join('\n'),
        ),
        CheckboxListTile(
          key: const ValueKey('confirm-merge'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: vm.mergeConfirmed,
          onChanged: (v) => vm.confirmMerge(v ?? false),
          title: Text('Merge into the existing {{$to}}', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Every {{$from}} then means {{$to}}; where both are defined the existing value is kept and the old definition is deleted.',
            style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final plan = vm.renamePlan;
    return RefactorFooter(
      leading: Text(
        plan.needsConfirmation && !vm.mergeConfirmed
            ? 'Confirm the merge to rename. Or pick another name.'
            : 'Everything listed is changed together. Undo stays available until PostPilot closes.',
        style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
      ),
      actions: [
        FilledButton(
          onPressed: vm.canRename ? vm.applyRename : null,
          child: BusyLabel(busy: vm.isApplying, label: 'Rename everywhere', busyLabel: 'Renaming…', icon: Icons.drive_file_rename_outline),
        ),
      ],
    );
  }
}
