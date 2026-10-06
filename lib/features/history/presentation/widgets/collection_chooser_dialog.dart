import 'package:flutter/material.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../collections/domain/entities/collection_entity.dart';

/// "Which collection should this request go in?", asked when the one an entry was
/// sent from is gone (or was never recorded). Returns the id chosen, a new
/// collection's id, or null when the person backs out. Nothing is chosen for them.
Future<int?> showCollectionChooser(
  BuildContext context, {
  required List<CollectionEntity> collections,
  required String reason,
  required Future<int> Function(String name) createCollection,
}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _CollectionChooser(collections: collections, reason: reason, createCollection: createCollection),
    );

class _CollectionChooser extends StatefulWidget {
  final List<CollectionEntity> collections;
  final String reason;
  final Future<int> Function(String name) createCollection;
  const _CollectionChooser({required this.collections, required this.reason, required this.createCollection});

  @override
  State<_CollectionChooser> createState() => _CollectionChooserState();
}

class _CollectionChooserState extends State<_CollectionChooser> {
  int? _selected;
  bool _creating = false;

  Future<void> _create() async {
    final name = await showPromptDialog(context, title: 'New collection', confirmLabel: 'Create');
    if (name == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final id = await widget.createCollection(name);
      if (mounted) Navigator.of(context).pop(id);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: const Text('Open in which collection?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.reason, style: context.textStyles.body.copyWith(color: colors.secondaryText)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<int>(
                  groupValue: _selected,
                  onChanged: (value) => setState(() => _selected = value),
                  child: Column(
                    children: [
                      for (final collection in widget.collections)
                        RadioListTile<int>(
                          value: collection.id,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(collection.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _creating ? null : _create, child: const Text('New collection...')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected == null || _creating ? null : () => Navigator.of(context).pop(_selected),
          child: const Text('Open here'),
        ),
      ],
    );
  }
}
