import 'package:flutter/material.dart';
import '../../domain/entities/assertion_entity.dart';
import 'editor_row_layout.dart';

/// Editable assertion list. Same row-ownership pattern as `KeyValueEditor`:
/// each row keeps a local, synchronously-updated copy so fast edits across
/// fields can't clobber each other, and rows are keyed by
/// [AssertionEntity.id] so field state never leaks between rows.
class AssertionsEditor extends StatelessWidget {
  final List<AssertionEntity> items;
  final ValueChanged<List<AssertionEntity>> onChanged;

  /// The label of the button that adds a row: "Add assertion" for a test, "Add condition" where the same rows say
  /// what to wait for.
  final String addLabel;

  const AssertionsEditor({super.key, required this.items, required this.onChanged, this.addLabel = 'Add assertion'});

  void _replace(AssertionEntity item) {
    final index = items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    onChanged(List<AssertionEntity>.of(items)..[index] = item);
  }

  void _removeAt(int index) => onChanged(List<AssertionEntity>.of(items)..removeAt(index));

  void _addRow() => onChanged([...items, AssertionEntity(type: AssertionType.statusIn2xx)]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _AssertionRow(
            key: ValueKey(items[i].id),
            item: items[i],
            onChanged: _replace,
            onRemove: () => _removeAt(i),
          ),
        TextButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add, size: 16),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

class _AssertionRow extends StatefulWidget {
  final AssertionEntity item;
  final ValueChanged<AssertionEntity> onChanged;
  final VoidCallback onRemove;

  const _AssertionRow({super.key, required this.item, required this.onChanged, required this.onRemove});

  @override
  State<_AssertionRow> createState() => _AssertionRowState();
}

class _AssertionRowState extends State<_AssertionRow> {
  late AssertionEntity _local = widget.item;

  void _apply({AssertionType? type, String? path, String? expected}) {
    _local = _local.copyWith(type: type, path: path, expected: expected);
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    final type = _local.type;
    final typeDropdown = DropdownButton<AssertionType>(
      value: type,
      isExpanded: true,
      isDense: true,
      onChanged: (t) => t == null ? null : setState(() => _apply(type: t)),
      items: [for (final t in AssertionType.values) DropdownMenuItem(value: t, child: Text(t.label))],
    );
    final removeButton =
        IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove');
    // Keyed so a type switch that adds/removes the path field never hands
    // the path field's text state to the expected field (or vice versa).
    final List<Widget> fields = [
      if (type.usesPath)
        Expanded(
          key: const ValueKey('path'),
          child: TextFormField(
            initialValue: _local.path,
            decoration: InputDecoration(
              hintText: type.isHeader
                  ? 'Header name'
                  : type.isSchema
                      ? 'JSON path (blank = whole body)'
                      : 'JSON path, e.g. data.items[0].id',
              isDense: true,
            ),
            onChanged: (v) => _apply(path: v),
          ),
        ),
      if (type.usesPath && type.usesExpected) const SizedBox(width: 8),
      if (type.usesExpected)
        Expanded(
          key: const ValueKey('expected'),
          child: TextFormField(
            initialValue: _local.expected,
            minLines: type.isSchema ? 3 : 1,
            maxLines: type.isSchema ? 8 : 1,
            decoration: InputDecoration(hintText: _expectedHint(type), isDense: true),
            onChanged: (v) => _apply(expected: v),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < editorRowNarrowWidth) {
            return Column(
              children: [
                Row(children: [Expanded(child: typeDropdown), removeButton]),
                if (fields.isNotEmpty) Row(children: fields),
                const SizedBox(height: 6),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 190, child: typeDropdown),
              const SizedBox(width: 8),
              if (fields.isEmpty) const Spacer() else ...fields,
              removeButton,
            ],
          );
        },
      ),
    );
  }

  String _expectedHint(AssertionType type) => switch (type) {
        AssertionType.statusEquals => 'Status code, e.g. 200 (or 4xx, or 401, 403)',
        AssertionType.bodyContains => 'Text to find',
        AssertionType.responseTimeBelowMs => 'Milliseconds, e.g. 500',
        AssertionType.jsonSchema => 'JSON Schema, e.g. {"type":"object","required":["id"]}',
        _ => 'Expected value',
      };
}
