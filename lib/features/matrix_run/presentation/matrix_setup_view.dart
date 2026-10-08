import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../collections/presentation/view_models/collection_runner_view_model.dart';
import '../domain/entities/matrix_identity.dart';
import '../domain/services/matrix_analysis.dart';
import '../domain/services/matrix_body.dart';
import '../domain/services/matrix_read_only.dart';
import 'matrix_run_view_model.dart';

/// Everything chosen before a matrix run: the collection, the requests, the columns (environments and identities) and
/// the options.
class MatrixSetupView extends StatelessWidget {
  final MatrixRunViewModel vm;
  final void Function(MatrixIdentity identity, {required bool isNew}) onEditIdentity;
  final VoidCallback onAddIdentity;
  final VoidCallback onAddAnonymous;

  const MatrixSetupView({super.key, required this.vm, required this.onEditIdentity, required this.onAddIdentity, required this.onAddAnonymous});

  @override
  Widget build(BuildContext context) {
    if (vm.isLoading) return const Center(child: CircularProgressIndicator());
    if (vm.collections.isEmpty) {
      return const EmptyHint(icon: Icons.grid_on, title: 'No collection yet', message: 'Create a collection with some requests, then compare it across environments here.');
    }
    final colors = context.colors;
    final columns = vm.columns;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToolSection(
            title: 'Collection',
            child: DropdownButtonFormField<int>(
              key: ValueKey('collection-${vm.collectionId}'),
              initialValue: vm.collectionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Run this collection'),
              items: [for (final c in vm.collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
              onChanged: (id) {
                if (id != null) vm.setCollection(id);
              },
            ),
          ),
          ToolSection(
            title: 'Requests',
            hint: 'In the order of the sidebar. Every ticked request is sent once in every column.',
            child: _RequestPicker(vm: vm),
          ),
          ToolSection(
            title: 'Columns',
            hint: 'Each ticked environment is a column. Tick identities to ask as someone else in each of them: '
                'every environment is then run once per identity.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Environments', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (vm.environments.isEmpty)
                  Text('There are no environments yet, so the columns use no environment variables.', style: context.textStyles.caption.copyWith(color: colors.secondaryText))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in vm.environments)
                        Tooltip(
                          message: vm.isProduction(e.name) ? 'Looks like production: the production lock applies to this column.' : e.name,
                          child: FilterChip(
                            avatar: vm.isProduction(e.name) ? Icon(Icons.shield_outlined, size: 16, color: colors.statusError) : null,
                            label: Text(e.name),
                            selected: vm.isEnvironmentSelected(e.name),
                            onSelected: (_) => vm.toggleEnvironment(e.name),
                          ),
                        ),
                    ],
                  ),
                if (vm.environments.isNotEmpty && !vm.environments.any((e) => vm.isEnvironmentSelected(e.name)))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No environment ticked: the columns use the environment that is active now.',
                      style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                    ),
                  ),
                const SizedBox(height: 14),
                Text('Identities', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final i in vm.identities)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilterChip(
                            avatar: i.isAnonymous ? const Icon(Icons.person_off_outlined, size: 16) : null,
                            label: Text(i.name),
                            selected: vm.isIdentitySelected(i.id),
                            onSelected: (_) => vm.toggleIdentity(i.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            tooltip: 'Edit ${i.name}',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onEditIdentity(i, isNew: false),
                          ),
                        ],
                      ),
                    ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Add identity'), onPressed: onAddIdentity),
                    ActionChip(avatar: const Icon(Icons.person_off_outlined, size: 16), label: const Text('Add anonymous'), onPressed: onAddAnonymous),
                  ],
                ),
                const SizedBox(height: 10),
                if (columns.isNotEmpty)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${columns.length} column${columns.length == 1 ? '' : 's'}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: columns.map((c) => c.label).join(', ')),
                    ]),
                    style: context.textStyles.caption,
                  ),
                if (columns.length >= 2) ...[
                  const SizedBox(height: 14),
                  Text('Expected results (optional)', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'For a permission matrix: say what each column should get, for example that anonymous is denied. A result that is not what '
                    'you expected is marked on the grid. After the run you can set it per request too.',
                    style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final c in columns)
                        PopupMenuButton<MatrixExpect>(
                          tooltip: 'What is expected of ${c.label}',
                          onSelected: (e) => vm.setColumnExpectation(c.key, e),
                          itemBuilder: (_) => [
                            for (final e in MatrixExpect.values) CheckedPopupMenuItem(value: e, checked: vm.columnExpectationOf(c.key) == e, child: Text(e.label)),
                          ],
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(_expectIcon(vm.columnExpectationOf(c.key)), size: 16),
                            label: Text('${c.label}: ${_expectWord(vm.columnExpectationOf(c.key))}'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ToolSection(
            title: 'Options',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Read-only requests only (recommended)'),
                  subtitle: const Text('Sends GET, HEAD and OPTIONS only. Replaying a write in three environments writes three times.'),
                  value: vm.readOnlyOnly,
                  onChanged: vm.setReadOnly,
                ),
                const SizedBox(height: 4),
                Text('Compare', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in MatrixCompareMode.values)
                      ChoiceChip(label: Text(m.label), selected: vm.mode == m, onSelected: (_) => vm.setMode(m)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  vm.mode == MatrixCompareMode.full
                      ? 'Fields that change on every call (ids, timestamps, tokens, counters) are ignored.'
                      : 'Only keys and types are compared, so different data of the same shape is not a difference.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ],
            ),
          ),
          if (vm.setupError != null)
            InfoBanner(kind: BannerKind.warning, message: vm.setupError!)
          else
            const InfoBanner(
              kind: BannerKind.info,
              message: 'Requests are really sent, one column after the other, through the normal pipeline: the production lock asks as usual, '
                  'an undefined variable stops its request, and tests and saved variables run as in the Collection Runner. '
                  'Each column\'s environment is made the active one while it runs, and yours is put back afterwards.',
            ),
        ],
      ),
    );
  }
}

IconData _expectIcon(MatrixExpect expect) => switch (expect) {
      MatrixExpect.allow => Icons.lock_open_outlined,
      MatrixExpect.deny => Icons.block,
      MatrixExpect.none => Icons.rule,
    };

String _expectWord(MatrixExpect expect) => switch (expect) {
      MatrixExpect.allow => 'access',
      MatrixExpect.deny => 'denied',
      MatrixExpect.none => 'any',
    };

/// The request tree: the same checkboxes the Collection Runner has.
class _RequestPicker extends StatelessWidget {
  final MatrixRunViewModel vm;
  const _RequestPicker({required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final picker = vm.picker;
    final rows = picker.treeRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('${picker.selectedCount} of ${picker.totalRequestCount} selected', style: context.textStyles.caption),
            TextButton(onPressed: picker.isLoading || picker.allSelected ? null : picker.selectAll, child: const Text('Select all')),
            TextButton(onPressed: picker.isLoading || picker.selectedCount == 0 ? null : picker.selectNone, child: const Text('Select none')),
          ],
        ),
        if (vm.readOnlyOnly && vm.leftOutCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${vm.leftOutCount} selected request${vm.leftOutCount == 1 ? '' : 's'} change${vm.leftOutCount == 1 ? 's' : ''} data and will be left out.',
              style: context.textStyles.caption.copyWith(color: colors.statusWarning),
            ),
          ),
        Container(
          height: 240,
          decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: picker.isLoading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(child: Text('No requests in this collection'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) => switch (rows[index]) {
                        RunFolderRow row => _FolderTile(picker: picker, row: row),
                        RunRequestRow row => _RequestTile(vm: vm, row: row),
                      },
                    ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final CollectionRunnerViewModel picker;
  final RunFolderRow row;
  const _FolderTile({required this.picker, required this.row});

  @override
  Widget build(BuildContext context) {
    final folder = row.folder;
    return CheckboxListTile(
      dense: true,
      tristate: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.only(left: 8.0 + 16 * row.depth, right: 4),
      value: row.checked,
      onChanged: (_) => picker.toggleFolderSelection(folder.id),
      title: Row(
        children: [
          Icon(row.expanded ? Icons.folder_open : Icons.folder, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(folder.name, overflow: TextOverflow.ellipsis, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600))),
          Text('${row.selectedCount}/${row.requestCount}', style: context.textStyles.caption),
        ],
      ),
      secondary: IconButton(
        icon: Icon(row.expanded ? Icons.expand_less : Icons.expand_more),
        tooltip: row.expanded ? 'Collapse ${folder.name}' : 'Expand ${folder.name}',
        visualDensity: VisualDensity.compact,
        onPressed: () => picker.toggleFolderExpanded(folder.id),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final MatrixRunViewModel vm;
  final RunRequestRow row;
  const _RequestTile({required this.vm, required this.row});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final request = row.request;
    final leftOut = vm.readOnlyOnly && row.checked && !MatrixReadOnly.allows(request.method);
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.only(left: 8.0 + 16 * row.depth, right: 12),
      value: row.checked,
      onChanged: (_) => vm.picker.toggleRequest(request.id),
      title: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              request.method.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.forMethod(request.method.label), fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          Expanded(child: Text(request.name, overflow: TextOverflow.ellipsis, style: leftOut ? TextStyle(color: colors.secondaryText, decoration: TextDecoration.lineThrough) : null)),
          if (leftOut)
            Tooltip(message: 'Changes data: left out while the run is read-only', child: Icon(Icons.edit_off_outlined, size: 16, color: colors.statusWarning)),
        ],
      ),
    );
  }
}
