import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/services/collection_order.dart';
import '../view_models/collections_view_model.dart';

/// The keyboard-and-screen-reader way to move something: a list of every collection and folder to pick from. The
/// item goes to the end of the chosen place.
Future<MoveDestination?> showMoveToDialog(
  BuildContext context, {
  required CollectionsViewModel viewModel,
  required OrderRef moving,
  required String name,
}) => showDialog<MoveDestination>(
  context: context,
  builder: (_) => _MoveToDialog(viewModel: viewModel, moving: moving, name: name),
);

class _MoveToDialog extends StatefulWidget {
  final CollectionsViewModel viewModel;
  final OrderRef moving;
  final String name;
  const _MoveToDialog({required this.viewModel, required this.moving, required this.name});

  @override
  State<_MoveToDialog> createState() => _MoveToDialogState();
}

class _MoveToDialogState extends State<_MoveToDialog> {
  late final Future<List<MoveDestination>> _destinations = widget.viewModel.moveDestinations(moving: widget.moving);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Move "${widget.name}" to…', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 360,
        height: 360,
        child: FutureBuilder<List<MoveDestination>>(
          future: _destinations,
          builder: (context, snapshot) {
            final destinations = snapshot.data;
            if (destinations == null) {
              return snapshot.hasError
                  ? Center(child: Text("Couldn't list the collections: ${snapshot.error}"))
                  : const Center(child: CircularProgressIndicator());
            }
            if (destinations.isEmpty) return const Center(child: Text('There is no collection to move it to.'));
            return ListView(
              children: [
                for (final destination in destinations)
                  ListTile(
                    dense: true,
                    enabled: destination.enabled,
                    contentPadding: EdgeInsets.only(left: 8.0 + 16 * destination.depth, right: 8),
                    leading: Icon(
                      destination.folderId == null ? Icons.library_books_outlined : Icons.folder_outlined,
                      size: 18,
                      color: destination.enabled ? null : context.colors.secondaryText.withValues(alpha: 0.5),
                    ),
                    title: Text(destination.label, overflow: TextOverflow.ellipsis),
                    subtitle: destination.enabled ? null : const Text("A folder can't go inside itself"),
                    onTap: () => Navigator.pop(context, destination),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
