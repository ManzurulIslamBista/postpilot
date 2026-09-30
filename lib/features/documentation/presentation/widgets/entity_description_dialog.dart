import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/entity_kind.dart';
import 'entity_docs_form.dart';

/// Edits the description and tags of a folder or collection. Closing the dialog
/// in any way still saves what was typed last.
class EntityDescriptionDialog extends StatelessWidget {
  final EntityKind kind;
  final int id;
  final String title;

  const EntityDescriptionDialog({super.key, required this.kind, required this.id, required this.title});

  static Future<void> show(BuildContext context, EntityKind kind, int id, String title) =>
      showDialog(context: context, builder: (_) => EntityDescriptionDialog(kind: kind, id: id, title: title));

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Description & tags', style: context.textStyles.heading),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: EntityDocsForm(kind: kind, localId: id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
