import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../scripting/presentation/widgets/editor_row_layout.dart';
import '../../domain/entities/flow_settings.dart';
import 'flow_section.dart';

/// The settings of "Run if": the conditions a request must meet to be sent in a run. Same row-ownership pattern as
/// the other editors: each row keeps a local copy so fast edits across its fields cannot clobber each other, and is
/// keyed by [RunCondition.id].
class RunIfEditor extends StatelessWidget {
  final RunIfPolicy policy;
  final ValueChanged<RunIfPolicy> onChanged;

  const RunIfEditor({super.key, required this.policy, required this.onChanged});

  void _replace(RunCondition item) {
    final index = policy.conditions.indexWhere((c) => c.id == item.id);
    if (index == -1) return;
    onChanged(policy.copyWith(conditions: List<RunCondition>.of(policy.conditions)..[index] = item));
  }

  void _removeAt(int index) =>
      onChanged(policy.copyWith(conditions: List<RunCondition>.of(policy.conditions)..removeAt(index)));

  void _add() => onChanged(
        policy.copyWith(
          conditions: [...policy.conditions, RunCondition(kind: RunConditionKind.variableNotEmpty)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowHint(
          'In a collection run (and from the command line) this request is sent only when every condition holds. '
          'Otherwise it is shown as skipped, with the reason: skipped is not failed, so it never stops a run on failure '
          'and a production request you skip is not asked about. Sending it by hand always sends it.',
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < policy.conditions.length; i++)
          _ConditionRow(
            key: ValueKey(policy.conditions[i].id),
            item: policy.conditions[i],
            onChanged: _replace,
            onRemove: () => _removeAt(i),
          ),
        TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add condition'),
        ),
      ],
    );
  }
}

class _ConditionRow extends StatefulWidget {
  final RunCondition item;
  final ValueChanged<RunCondition> onChanged;
  final VoidCallback onRemove;

  const _ConditionRow({super.key, required this.item, required this.onChanged, required this.onRemove});

  @override
  State<_ConditionRow> createState() => _ConditionRowState();
}

class _ConditionRowState extends State<_ConditionRow> {
  late RunCondition _local = widget.item;

  void _apply({RunConditionKind? kind, String? name, String? value}) {
    _local = _local.copyWith(kind: kind, name: name, value: value);
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _local.kind;
    final kindDropdown = DropdownButton<RunConditionKind>(
      value: kind,
      isExpanded: true,
      isDense: true,
      onChanged: (k) => k == null ? null : setState(() => _apply(kind: k)),
      items: [for (final k in RunConditionKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
    );
    final remove = IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove');
    final problem = _local.error;
    // Keyed so a kind switch that adds or removes a field never hands one field's text to another.
    final fields = <Widget>[
      if (kind.usesName)
        Expanded(
          key: const ValueKey('name'),
          child: TextFormField(
            initialValue: _local.name,
            decoration: InputDecoration(
              hintText: kind.isVariable ? 'Variable name, e.g. region' : 'Environment name, e.g. Staging',
              isDense: true,
            ),
            onChanged: (v) => _apply(name: v),
          ),
        ),
      if (kind.usesName && kind.usesValue) const SizedBox(width: 8),
      if (kind.usesValue)
        Expanded(
          key: const ValueKey('value'),
          child: TextFormField(
            initialValue: _local.value,
            decoration: const InputDecoration(hintText: 'Value (can use {{variables}})', isDense: true),
            onChanged: (v) => _apply(value: v),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < editorRowNarrowWidth) {
                return Column(
                  children: [
                    Row(children: [Expanded(child: kindDropdown), remove]),
                    if (fields.isNotEmpty) Row(children: fields),
                    const SizedBox(height: 6),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 220, child: kindDropdown),
                  const SizedBox(width: 8),
                  if (fields.isEmpty) const Spacer() else ...fields,
                  remove,
                ],
              );
            },
          ),
          if (problem != null)
            Text(problem, style: context.textStyles.caption.copyWith(color: context.colors.statusError)),
        ],
      ),
    );
  }
}
