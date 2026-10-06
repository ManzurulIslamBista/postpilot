import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/presentation/widgets/variables/variable_text_form_field.dart';
import '../../domain/entities/default_variable.dart';

/// Editable list of the variables of a collection or folder. Same row-ownership pattern as
/// `KeyValueEditor`: each row keeps a local, synchronously-updated copy so a fast edit of its name
/// and its value cannot clobber each other, and rows are keyed by [DefaultVariable.id] so field
/// state never leaks from one row to another after an add or a removal.
///
/// With [allowSecret] a row has a lock: a secret's value is hidden on screen and is kept out of a
/// workspace file that gets shared.
class DefaultVariablesEditor extends StatelessWidget {
  final List<DefaultVariable> items;
  final ValueChanged<List<DefaultVariable>> onChanged;
  final bool allowSecret;

  const DefaultVariablesEditor({super.key, required this.items, required this.onChanged, this.allowSecret = true});

  void _replace(DefaultVariable item) {
    final index = items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    onChanged(List<DefaultVariable>.of(items)..[index] = item);
  }

  void _removeAt(int index) => onChanged(List<DefaultVariable>.of(items)..removeAt(index));

  void _add() => onChanged([...items, DefaultVariable(key: '')]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No variables yet.',
              style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
            ),
          ),
        for (var i = 0; i < items.length; i++)
          _VariableRow(
            key: ValueKey(items[i].id),
            item: items[i],
            allowSecret: allowSecret,
            onChanged: _replace,
            onRemove: () => _removeAt(i),
          ),
        TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('Add variable')),
      ],
    );
  }
}

class _VariableRow extends StatefulWidget {
  final DefaultVariable item;
  final bool allowSecret;
  final ValueChanged<DefaultVariable> onChanged;
  final VoidCallback onRemove;

  const _VariableRow({
    super.key,
    required this.item,
    required this.allowSecret,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late DefaultVariable _local = widget.item;

  void _apply({String? key, String? value, bool? isSecret, bool? enabled}) {
    _local = _local.copyWith(key: key, value: value, isSecret: isSecret, enabled: enabled);
    widget.onChanged(_local);
  }

  /// The resolver only substitutes names its `{{name}}` pattern matches whole.
  static String? _nameError(String key) {
    final name = key.trim();
    if (name.isEmpty) return null;
    final token = '{{$name}}';
    return AppConstants.variablePattern.matchAsPrefix(token)?.end == token.length
        ? null
        : r'Use letters, digits, _ - . or $ only';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: _local.enabled, onChanged: (v) => setState(() => _apply(enabled: v))),
          Expanded(
            child: TextFormField(
              initialValue: _local.key,
              decoration: InputDecoration(hintText: 'Name', isDense: true, errorText: _nameError(_local.key)),
              onChanged: (v) => setState(() => _apply(key: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: VariableTextFormField(
              initialValue: _local.value,
              obscureText: _local.isSecret,
              decoration: const InputDecoration(hintText: 'Value', isDense: true),
              onChanged: (v) => _apply(value: v),
            ),
          ),
          if (widget.allowSecret)
            IconButton(
              icon: Icon(_local.isSecret ? Icons.lock : Icons.lock_open, size: 16),
              color: _local.isSecret ? colors.mainAccent : colors.secondaryText,
              tooltip: _local.isSecret
                  ? 'Secret: the value is hidden and kept out of shared workspace files. Click to show it.'
                  : 'Make this a secret: hide the value and keep it out of shared workspace files',
              onPressed: () => setState(() => _apply(isSecret: !_local.isSecret)),
            ),
          IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove'),
        ],
      ),
    );
  }
}
