import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/global_variable_entity.dart';
import '../view_models/environments_view_model.dart';

/// Left-list selection id for the "Globals" entry. Environment ids are
/// autoincrement and start at 1, so 0 can never collide with one.
const _globalsId = 0;

/// Radio value of the "No Environment" row, for the same reason.
const _noEnvironmentId = 0;

class EnvironmentsManagerDialog extends StatefulWidget {
  const EnvironmentsManagerDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const EnvironmentsManagerDialog());

  @override
  State<EnvironmentsManagerDialog> createState() => _EnvironmentsManagerDialogState();
}

class _EnvironmentsManagerDialogState extends State<EnvironmentsManagerDialog> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EnvironmentsViewModel>();
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Row(
          children: [
            SizedBox(width: 200, child: _EnvironmentList(vm: vm, selectedId: _selectedId, onSelect: _select)),
            const VerticalDivider(width: 1),
            Expanded(
              child: switch (_selectedId) {
                null => const Center(child: Text('Select an environment')),
                _globalsId => _GlobalsEditor(vm: vm),
                final int id => _VariablesEditor(vm: vm, environmentId: id),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _select(int id) {
    setState(() => _selectedId = id);
    final vm = context.read<EnvironmentsViewModel>();
    if (id == _globalsId) {
      vm.watchGlobals();
    } else {
      vm.watchVariables(id);
    }
  }
}

class _EnvironmentList extends StatelessWidget {
  final EnvironmentsViewModel vm;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  const _EnvironmentList({required this.vm, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RadioGroup<int>(
            groupValue: vm.environments.where((e) => e.isActive).map((e) => e.id).firstOrDefault(_noEnvironmentId),
            onChanged: (id) {
              if (id == null) return;
              if (id == _noEnvironmentId) {
                vm.clearActive();
              } else {
                vm.setActive(id);
              }
            },
            child: ListView(
              children: [
                ListTile(
                  dense: true,
                  selected: selectedId == _globalsId,
                  leading: const Icon(Icons.public, size: 18),
                  title: const Text('Globals'),
                  onTap: () => onSelect(_globalsId),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('No Environment'),
                  leading: const Radio<int>(value: _noEnvironmentId),
                  onTap: vm.clearActive,
                ),
                for (final env in vm.environments)
                  ListTile(
                    dense: true,
                    selected: env.id == selectedId,
                    title: Text(env.name, overflow: TextOverflow.ellipsis),
                    leading: Radio<int>(value: env.id),
                    onTap: () => onSelect(env.id),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 16),
                      onSelected: (action) async {
                        switch (action) {
                          case 'rename':
                            final name =
                                await showPromptDialog(context, title: 'Rename environment', initialValue: env.name);
                            if (name != null) {
                              await vm.renameEnvironment(env.id, name);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('Renamed to "$name"')));
                              }
                            }
                          case 'delete':
                            final confirmed = await showConfirmDialog(context,
                                title: 'Delete environment', message: 'Delete "${env.name}" and all its variables?');
                            if (confirmed) {
                              await vm.deleteEnvironment(env.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('Deleted "${env.name}"')));
                              }
                            }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add environment'),
            onPressed: () async {
              final name = await showPromptDialog(context, title: 'New environment');
              if (name != null) {
                await vm.createEnvironment(name);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created "$name"')));
                }
              }
            },
          ),
        ),
      ],
    );
  }
}

extension _FirstOrDefault<T> on Iterable<T> {
  T firstOrDefault(T fallback) => isEmpty ? fallback : first;
}

class _VariablesEditor extends StatelessWidget {
  final EnvironmentsViewModel vm;
  final int environmentId;
  const _VariablesEditor({required this.vm, required this.environmentId});

  @override
  Widget build(BuildContext context) {
    return _VariablesPane(
      title: 'Variables',
      rows: [
        for (final v in vm.variablesFor(environmentId))
          _VariableRow(
            key: ValueKey(v.id),
            initial: (key: v.key, value: v.value, isSecret: v.isSecret, enabled: v.enabled),
            onChanged: (f) => vm.upsertVariable(EnvironmentVariableEntity(
              id: v.id,
              environmentId: v.environmentId,
              key: f.key,
              value: f.value,
              isSecret: f.isSecret,
              enabled: f.enabled,
            )),
            onDelete: () => vm.deleteVariable(v.id),
          ),
      ],
      onAdd: () => vm.upsertVariable(EnvironmentVariableEntity(
        id: 0,
        environmentId: environmentId,
        key: '',
        value: '',
        isSecret: false,
        enabled: true,
      )),
    );
  }
}

class _GlobalsEditor extends StatelessWidget {
  final EnvironmentsViewModel vm;
  const _GlobalsEditor({required this.vm});

  @override
  Widget build(BuildContext context) {
    return _VariablesPane(
      title: 'Global variables',
      subtitle: 'Lowest precedence: overridden by collection variables, then by the active environment.',
      rows: [
        for (final g in vm.globals)
          _VariableRow(
            key: ValueKey(g.id),
            initial: (key: g.key, value: g.value, isSecret: g.isSecret, enabled: g.enabled),
            onChanged: (f) => vm.upsertGlobal(GlobalVariableEntity(
              id: g.id,
              key: f.key,
              value: f.value,
              isSecret: f.isSecret,
              enabled: f.enabled,
            )),
            onDelete: () => vm.deleteGlobal(g.id),
          ),
      ],
      onAdd: () => vm.upsertGlobal(const GlobalVariableEntity(id: 0, key: '', value: '', isSecret: false, enabled: true)),
    );
  }
}

class _VariablesPane extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> rows;
  final VoidCallback onAdd;
  const _VariablesPane({required this.title, this.subtitle, required this.rows, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.heading),
          if (subtitle != null)
            Text(subtitle!, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          const SizedBox(height: 8),
          Expanded(child: ListView(children: rows)),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add variable'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

typedef _VariableFields = ({String key, String value, bool isSecret, bool enabled});

/// Stateful on purpose: [onChanged] round-trips through a real DB write +
/// stream before the parent's entity (and so [initial]) reflects an edit, so
/// a StatelessWidget re-deriving each field's write from the (possibly
/// stale) prop would let a fast key-edit and value-edit race and clobber
/// each other — this was a real, reproduced bug ("2002" leaking a blank key
/// after both fields were edited quickly). Keeping one local,
/// synchronously-updated copy as the base for every edit removes the race.
class _VariableRow extends StatefulWidget {
  final _VariableFields initial;
  final ValueChanged<_VariableFields> onChanged;
  final Future<void> Function() onDelete;
  const _VariableRow({super.key, required this.initial, required this.onChanged, required this.onDelete});

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late _VariableFields _local = widget.initial;

  /// View-only peek: revealing a secret must never rewrite its persisted
  /// `isSecret` flag, so masking is `isSecret && !_revealed`.
  bool _revealed = false;

  void _apply({String? key, String? value, bool? isSecret, bool? enabled}) {
    _local = (
      key: key ?? _local.key,
      value: value ?? _local.value,
      isSecret: isSecret ?? _local.isSecret,
      enabled: enabled ?? _local.enabled,
    );
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(value: _local.enabled, onChanged: (v) => setState(() => _apply(enabled: v))),
          Expanded(
            child: TextFormField(
              initialValue: _local.key,
              decoration: const InputDecoration(hintText: 'Key', isDense: true),
              onChanged: (v) => _apply(key: v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: _local.value,
              obscureText: _local.isSecret && !_revealed,
              decoration: const InputDecoration(hintText: 'Value', isDense: true),
              onChanged: (v) => _apply(value: v),
            ),
          ),
          IconButton(
            icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility, size: 16),
            tooltip: _revealed ? 'Hide value' : 'Show value',
            onPressed: _local.isSecret ? () => setState(() => _revealed = !_revealed) : null,
          ),
          IconButton(
            icon: Icon(_local.isSecret ? Icons.lock : Icons.lock_open, size: 16),
            tooltip: _local.isSecret ? 'Unmark as secret' : 'Mark as secret',
            onPressed: () => setState(() {
              _revealed = false;
              _apply(isSecret: !_local.isSecret);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Delete variable',
            onPressed: () async {
              final confirmed = await showConfirmDialog(context,
                  title: 'Delete variable', message: 'Delete "${_local.key}"?');
              if (confirmed) await widget.onDelete();
            },
          ),
        ],
      ),
    );
  }
}
