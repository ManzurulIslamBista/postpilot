import 'package:flutter/material.dart';
import '../../domain/entities/cloud_folder_entity.dart';

/// Wrapper so "moved to the collection root" (`folderId == null`) can be
/// told apart from "dialog cancelled" (`null` result).
final class FolderChoice {
  final int? folderId;
  const FolderChoice(this.folderId);
}

/// Lists the collection root plus every folder (indented by nesting depth)
/// and returns the picked destination.
class MoveToFolderDialog extends StatelessWidget {
  final List<CloudFolderEntity> folders;
  final int? currentFolderId;

  const MoveToFolderDialog({super.key, required this.folders, required this.currentFolderId});

  static Future<FolderChoice?> show(
    BuildContext context, {
    required List<CloudFolderEntity> folders,
    required int? currentFolderId,
  }) =>
      showDialog(
        context: context,
        builder: (_) => MoveToFolderDialog(folders: folders, currentFolderId: currentFolderId),
      );

  @override
  Widget build(BuildContext context) {
    final entries = <(CloudFolderEntity, int)>[];
    _collect(null, 0, entries);
    return AlertDialog(
      title: const Text('Move to folder'),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            _tile(context, label: 'Collection root', icon: Icons.folder_shared_outlined, folderId: null, depth: 0),
            for (final (folder, depth) in entries)
              _tile(context, label: folder.name, icon: Icons.folder_outlined, folderId: folder.id, depth: depth),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }

  void _collect(int? parentId, int depth, List<(CloudFolderEntity, int)> out) {
    for (final folder in folders.where((f) => f.parentFolderId == parentId)) {
      out.add((folder, depth));
      _collect(folder.id, depth + 1, out);
    }
  }

  Widget _tile(BuildContext context, {required String label, required IconData icon, required int? folderId, required int depth}) {
    final isCurrent = folderId == currentFolderId;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 16.0 * depth + 8, right: 8),
      leading: Icon(icon, size: 18),
      title: Text(label, overflow: TextOverflow.ellipsis),
      trailing: isCurrent ? const Icon(Icons.check, size: 16) : null,
      enabled: !isCurrent,
      onTap: () => Navigator.pop(context, FolderChoice(folderId)),
    );
  }
}
