import 'variables/variable_text_form_field.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/upload_file_source.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/key_value_item.dart';
import '../file_picker_service.dart';
import 'bulk_edit_text.dart';
import 'file_field.dart';

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
///
/// With [allowFiles] (the form-data editor) a row is a text value or a file, switched per row. A file row is
/// edited with a [FileField]; "Bulk edit" only knows `key:value` lines, so in it the file rows stay as they are.
class KeyValueEditor extends StatefulWidget {
  final List<KeyValueItem> items;
  final ValueChanged<List<KeyValueItem>> onChanged;
  final bool allowFiles;

  /// Opens the file dialog of a file row; the platform's own when null.
  final FilePickerService? picker;

  /// Looks at the files of the file rows; the platform's own when null.
  final UploadFileSource? uploadSource;

  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.allowFiles = false,
    this.picker,
    this.uploadSource,
  });

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  final _bulkController = TextEditingController();
  bool _bulk = false;
  late final FilePickerService _picker = widget.picker ?? FileSelectorPicker();

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

  /// The rows bulk edit works on: all of them, or the text rows when files are allowed (file rows have no text form).
  List<KeyValueItem> get _bulkRows => [for (final i in widget.items) if (!(widget.allowFiles && i.isFile)) i];

  void _toggleBulk() {
    if (!_bulk) {
      _latest = _bulkRows;
      final text = BulkEditText.serialize(_latest);
      _bulkController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() => _bulk = !_bulk);
  }

  void _onBulkChanged(String text) {
    final parsed = BulkEditText.parse(text, previous: _latest);
    if (BulkEditText.sameRows(parsed, _latest)) return;
    _latest = parsed;
    widget.onChanged([...parsed, if (widget.allowFiles) for (final i in widget.items) if (i.isFile) i]);
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
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              alignLabelWithHint: true,
              hintText: 'key:value  (one per line, // in front turns a row off)',
              helperText: widget.allowFiles && items.any((i) => i.isFile) ? 'File rows are kept as they are.' : null,
            ),
            onChanged: _onBulkChanged,
          )
        else ...[
          for (var i = 0; i < items.length; i++)
            _KeyValueRow(
              key: ValueKey(items[i].id),
              item: items[i],
              allowFiles: widget.allowFiles,
              picker: _picker,
              uploadSource: widget.uploadSource,
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
  final bool allowFiles;
  final FilePickerService picker;
  final UploadFileSource? uploadSource;
  final ValueChanged<KeyValueItem> onChanged;
  final VoidCallback onRemove;

  const _KeyValueRow({
    super.key,
    required this.item,
    required this.allowFiles,
    required this.picker,
    required this.uploadSource,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  /// Below this width a file row puts its file under the key instead of beside it.
  static const _stackedBelow = 640.0;

  late KeyValueItem _local = widget.item;

  /// What each kind of the row held last, so switching Text to File and back does not lose what was typed.
  late String _textValue = widget.item.isFile ? '' : widget.item.value;
  late String _pathValue = widget.item.isFile ? widget.item.value : '';

  void _apply({String? key, String? value, bool? enabled, FormFieldKind? kind, String? fileName, String? contentType}) {
    _local = _local.copyWith(
      key: key,
      value: value,
      enabled: enabled,
      kind: kind,
      fileName: fileName,
      contentType: contentType,
    );
    widget.onChanged(_local);
  }

  void _setKind(FormFieldKind kind) {
    if (kind == _local.kind) return;
    setState(() {
      if (_local.isFile) {
        _pathValue = _local.value;
      } else {
        _textValue = _local.value;
      }
      _apply(kind: kind, value: kind == FormFieldKind.file ? _pathValue : _textValue);
    });
  }

  void _setFile({String? path, String? fileName, String? contentType}) {
    if (path != null) _pathValue = path;
    _apply(value: path, fileName: fileName, contentType: contentType);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = Checkbox(value: _local.enabled, onChanged: (v) => setState(() => _apply(enabled: v)));
    final key = VariableTextFormField(
      initialValue: _local.key,
      decoration: const InputDecoration(hintText: 'Key', isDense: true),
      onChanged: (v) => _apply(key: v),
    );
    final remove = IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove');

    if (!widget.allowFiles) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            enabled,
            Expanded(child: key),
            const SizedBox(width: 8),
            Expanded(child: _textField()),
            remove,
          ],
        ),
      );
    }

    final kind = _KindSwitch(kind: _local.kind, onChanged: _setKind);
    final value = _local.isFile ? _fileField() : _textField();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _stackedBelow) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _onFirstLine(enabled),
                Expanded(flex: 2, child: key),
                const SizedBox(width: 8),
                _onFirstLine(kind),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: value),
                _onFirstLine(remove),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [enabled, Expanded(child: key), const SizedBox(width: 8), kind, remove]),
              Padding(padding: const EdgeInsets.only(left: 48, right: 8, bottom: 4), child: value),
            ],
          );
        },
      ),
    );
  }

  /// The checkbox, switch and remove button sit level with the key field when the value is taller than it is.
  Widget _onFirstLine(Widget child) => SizedBox(height: 48, child: Center(child: child));

  Widget _textField() => VariableTextFormField(
        key: const ValueKey('row-text-value'),
        initialValue: _local.isFile ? _textValue : _local.value,
        decoration: const InputDecoration(hintText: 'Value', isDense: true),
        onChanged: (v) => _apply(value: v),
      );

  Widget _fileField() => FileField(
        key: const ValueKey('row-file-value'),
        path: _local.value,
        fileName: _local.fileName,
        contentType: _local.contentType,
        picker: widget.picker,
        source: widget.uploadSource,
        onChanged: _setFile,
      );
}

/// The Text / File switch of a form-data row.
class _KindSwitch extends StatelessWidget {
  final FormFieldKind kind;
  final ValueChanged<FormFieldKind> onChanged;

  const _KindSwitch({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FormFieldKind>(
      key: const ValueKey('row-kind'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      ),
      segments: const [
        ButtonSegment(value: FormFieldKind.text, label: Text('Text')),
        ButtonSegment(value: FormFieldKind.file, label: Text('File')),
      ],
      selected: {kind},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
