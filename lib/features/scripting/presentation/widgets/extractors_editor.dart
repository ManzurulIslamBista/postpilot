import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/extractor_entity.dart';
import 'editor_row_layout.dart';

/// Editable extractor list; same row-ownership pattern as `AssertionsEditor`.
class ExtractorsEditor extends StatelessWidget {
  final List<ExtractorEntity> items;
  final ValueChanged<List<ExtractorEntity>> onChanged;

  const ExtractorsEditor({super.key, required this.items, required this.onChanged});

  void _replace(ExtractorEntity item) {
    final index = items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    onChanged(List<ExtractorEntity>.of(items)..[index] = item);
  }

  void _removeAt(int index) => onChanged(List<ExtractorEntity>.of(items)..removeAt(index));

  void _addRow() => onChanged([...items, ExtractorEntity()]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _ExtractorRow(
            key: ValueKey(items[i].id),
            item: items[i],
            onChanged: _replace,
            onRemove: () => _removeAt(i),
          ),
        TextButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add extractor'),
        ),
      ],
    );
  }
}

class _ExtractorRow extends StatefulWidget {
  final ExtractorEntity item;
  final ValueChanged<ExtractorEntity> onChanged;
  final VoidCallback onRemove;

  const _ExtractorRow({super.key, required this.item, required this.onChanged, required this.onRemove});

  @override
  State<_ExtractorRow> createState() => _ExtractorRowState();
}

class _ExtractorRowState extends State<_ExtractorRow> {
  late ExtractorEntity _local = widget.item;

  void _apply({ExtractorSource? source, String? path, ExtractorScope? scope, String? variableKey}) {
    _local = _local.copyWith(source: source, path: path, scope: scope, variableKey: variableKey);
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    // A blank name is just an unfinished row, so only a typed-but-unusable one is flagged.
    final keyError = _local.variableKey.trim().isEmpty ? null : _local.keyError;
    final sourceDropdown = DropdownButton<ExtractorSource>(
      value: _local.source,
      isExpanded: true,
      isDense: true,
      onChanged: (s) => s == null ? null : setState(() => _apply(source: s)),
      items: [for (final s in ExtractorSource.values) DropdownMenuItem(value: s, child: Text(s.label))],
    );
    final scopeDropdown = DropdownButton<ExtractorScope>(
      value: _local.scope,
      isExpanded: true,
      isDense: true,
      onChanged: (s) => s == null ? null : setState(() => _apply(scope: s)),
      items: [for (final s in ExtractorScope.values) DropdownMenuItem(value: s, child: Text(s.label))],
    );
    final pathField = TextFormField(
      initialValue: _local.path,
      decoration: InputDecoration(
        hintText: _local.source == ExtractorSource.header ? 'Header name' : 'JSON path, e.g. data.token',
        isDense: true,
      ),
      onChanged: (v) => _apply(path: v),
    );
    final keyField = TextFormField(
      initialValue: _local.variableKey,
      decoration: const InputDecoration(hintText: 'Variable name', isDense: true),
      onChanged: (v) => setState(() => _apply(variableKey: v)),
    );
    const arrow = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.arrow_forward, size: 16),
    );
    final removeButton =
        IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.close, size: 16), tooltip: 'Remove');

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
                    Row(children: [Expanded(child: sourceDropdown), arrow, Expanded(child: scopeDropdown), removeButton]),
                    Row(children: [Expanded(child: pathField), const SizedBox(width: 8), Expanded(child: keyField)]),
                    const SizedBox(height: 6),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 110, child: sourceDropdown),
                  const SizedBox(width: 8),
                  Expanded(child: pathField),
                  arrow,
                  SizedBox(width: 120, child: scopeDropdown),
                  const SizedBox(width: 8),
                  Expanded(child: keyField),
                  removeButton,
                ],
              );
            },
          ),
          if (keyError != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(keyError, style: context.textStyles.caption.copyWith(color: context.colors.statusError)),
            ),
        ],
      ),
    );
  }
}
