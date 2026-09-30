import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/key_value_item.dart';
import 'bulk_edit_text.dart';

/// Editable key/value table for headers, query params and form fields.
///
/// Each row ([_KeyValueRow]) owns a local, synchronously-updated copy of its
/// [KeyValueItem]. A fast key-edit immediately followed by a value-edit on
/// the same row applies on top of that local copy rather than re-deriving
/// from the parent's (possibly not-yet-rebuilt) `items` list, so the two
/// edits can't race and clobber each other. Rows are keyed by
/// [KeyValueItem.id] so Flutter never reuses one row's field state for a
/// different logical row after an add/remove. Same fix pattern as
/// `_VariableRow` in `environments_manager_dialog.dart`.
///
/// "Bulk edit" swaps the rows for one text field (see [BulkEditText]). While
/// it is showing, its controller is the source of truth: every edit is parsed
/// and handed to [onChanged] at once, so nothing typed is lost if the editor
/// goes away, and the parent's echo of that change is ignored so it can't
/// overwrite the text or move the cursor. The rows are unmounted meanwhile,
/// so they come back with fresh local state built from the parent's items.
class KeyValueEditor extends StatefulWidget {
  final List<KeyValueItem> items;
  final ValueChanged<List<KeyValueItem>> onChanged;

  const KeyValueEditor({super.key, required this.items, required this.onChanged});

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  final _bulkController = TextEditingController();
  bool _bulk = false;

  /// The rows last handed to `onChanged` from bulk mode, which the next parse
  /// keeps identities from (the parent may not have rebuilt with them yet).
  List<KeyValueItem> _latest = const [];

  @override
  void dispose() {
    _bulkController.dispose();
    super.dispose();
  }

  void _replace(KeyValueItem item) {
    final items = widget.items;
    final index = items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    widget.onChanged(List<KeyValueItem>.of(items)..[index] = item);
  }

  void _removeAt(int index) => widget.onChanged(List<KeyValueItem>.of(widget.items)..removeAt(index));

  void _addRow() => widget.onChanged([...widget.items, KeyValueItem(key: '', value: '')]);

  void _toggleBulk() {
    if (!_bulk) {
      _latest = widget.items;
      final text = BulkEditText.serialize(widget.items);
      _bulkController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() => _bulk = !_bulk);
  }

  void _onBulkChanged(String text) {
    final parsed = BulkEditText.parse(text, previous: _latest);
    if (BulkEditText.sameRows(parsed, _latest)) return;
    _latest = parsed;
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _toggleBulk,
            icon: Icon(_bulk ? Icons.table_rows_outlined : Icons.notes, size: 16),
            label: Text(_bulk ? 'Key-Value edit' : 'Bulk edit'),
          ),
        ),
        if (_bulk)
          TextField(
            controller: _bulkController,
            autofocus: true,
            minLines: 6,
            maxLines: null,
            style: context.textStyles.mono,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              alignLabelWithHint: true,
              hintText: 'key:value  (one per line, // in front turns a row off)',
            ),
            onChanged: _onBulkChanged,
          )
        else ...[
          for (var i = 0; i < items.length; i++)
            _KeyValueRow(
              key: ValueKey(items[i].id),
              item: items[i],
              onChanged: _replace,
              onRemove: () => _removeAt(i),
            ),
          TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 16), label: const Text('Add')),
        ],
      ],
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  final KeyValueItem item;
  final ValueChanged<KeyValueItem> onChanged;
  final VoidCallback onRemove;

  const _KeyValueRow({super.key, required this.item, required this.onChanged, required this.onRemove});

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  late KeyValueItem _local = widget.item;

  void _apply({String? key, String? value, bool? enabled}) {
    _local = _local.copyWith(key: key, value: value, enabled: enabled);
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
              decoration: const InputDecoration(hintText: 'Value', isDense: true),
              onChanged: (v) => _apply(value: v),
            ),
          ),
          IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove'),
        ],
      ),
    );
  }
}
