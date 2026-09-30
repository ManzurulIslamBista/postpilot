import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/cloud_collection_entity.dart';
import '../../domain/entities/cloud_folder_entity.dart';
import '../../domain/entities/cloud_request_entity.dart';
import '../../domain/services/cloud_request_mapper.dart';
import '../view_models/team_view_model.dart';
import 'move_to_folder_dialog.dart';
import 'request_form_dialog.dart';

/// Folder/request tree for the selected cloud collection, Postman-style:
/// folders (nestable, expandable) first, then the requests that sit directly
/// under the same parent; ungrouped requests appear at the root. Mirrors
/// `_FolderChildren` in the local collections sidebar. All writes are
/// gated by [canEdit] (owner/editor per RLS).
class CloudRequestTree extends StatelessWidget {
  final CloudCollectionEntity collection;
  final bool canEdit;

  const CloudRequestTree({super.key, required this.collection, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final isEmpty = vm.folders.isEmpty && vm.requests.isEmpty;
    return Column(
      children: [
        Expanded(
          child: !vm.treeLoaded
              ? Center(child: vm.collectionSyncFailed ? const Text("Couldn't load requests") : const CircularProgressIndicator())
              : isEmpty
                  ? const Center(child: Text('No requests yet'))
                  : ListView(children: [_TreeChildren(collection: collection, parentFolderId: null, depth: 0, canEdit: canEdit)]),
        ),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add request'),
                  onPressed: () => _addRequest(context, collection.id, folderId: null),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                  label: const Text('New folder'),
                  onPressed: () => _addFolder(context, collection.id, parentFolderId: null),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TreeChildren extends StatelessWidget {
  final CloudCollectionEntity collection;
  final int? parentFolderId;
  final int depth;
  final bool canEdit;

  const _TreeChildren({required this.collection, required this.parentFolderId, required this.depth, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeamViewModel>();
    final childFolders = vm.childFolders(parentFolderId);
    final childRequests = vm.requestsIn(parentFolderId);

    if (childFolders.isEmpty && childRequests.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: 16.0 * depth + 16, top: 4, bottom: 4),
        child: Text('Empty folder', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final folder in childFolders)
          _FolderTile(key: ValueKey('folder-${folder.id}'), collection: collection, folder: folder, depth: depth, canEdit: canEdit),
        for (final request in childRequests)
          _RequestTile(key: ValueKey('request-${request.id}'), request: request, depth: depth, canEdit: canEdit),
      ],
    );
  }
}

class _FolderTile extends StatefulWidget {
  final CloudCollectionEntity collection;
  final CloudFolderEntity folder;
  final int depth;
  final bool canEdit;

  const _FolderTile({super.key, required this.collection, required this.folder, required this.depth, required this.canEdit});

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 16.0 * widget.depth),
          child: ListTile(
            dense: true,
            leading: Icon(_expanded ? Icons.folder_open : Icons.folder, size: 18),
            title: Text(widget.folder.name, overflow: TextOverflow.ellipsis),
            onTap: () => setState(() => _expanded = !_expanded),
            trailing: widget.canEdit
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (action) => _handleAction(context, action),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'add_request', child: Text('Add request')),
                      PopupMenuItem(value: 'add_folder', child: Text('Add sub-folder')),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                : null,
          ),
        ),
        if (_expanded)
          _TreeChildren(
            collection: widget.collection,
            parentFolderId: widget.folder.id,
            depth: widget.depth + 1,
            canEdit: widget.canEdit,
          ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final vm = context.read<TeamViewModel>();
    switch (action) {
      case 'add_request':
        await _addRequest(context, widget.collection.id, folderId: widget.folder.id);
      case 'add_folder':
        await _addFolder(context, widget.collection.id, parentFolderId: widget.folder.id);
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename folder', initialValue: widget.folder.name);
        if (name == null || !context.mounted) return;
        final ok = await vm.renameFolder(widget.folder.id, name);
        if (context.mounted) _showSnack(context, ok ? 'Folder renamed' : 'Failed to rename folder');
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete folder',
          message: 'Delete "${widget.folder.name}" and every request inside it for all members? This cannot be undone.',
        );
        if (!confirmed || !context.mounted) return;
        final ok = await vm.deleteFolder(widget.folder.id);
        if (context.mounted) _showSnack(context, ok ? 'Folder deleted' : 'Failed to delete folder');
    }
  }
}

class _RequestTile extends StatelessWidget {
  final CloudRequestEntity request;
  final int depth;
  final bool canEdit;

  const _RequestTile({super.key, required this.request, required this.depth, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * depth),
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 52,
          child: Text(
            request.method,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.colors.forMethod(request.method), fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
        title: Text(request.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(request.url.isEmpty ? '(no URL yet)' : request.url, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'open_in_builder', child: Text('Copy to local collection and open')),
            if (canEdit) ...const [
              PopupMenuItem(value: 'move', child: Text('Move to folder…')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ],
        ),
        onTap: () => RequestFormDialog.show(context, request: request, canEdit: canEdit),
      ),
    );
  }

  /// The dialog can edit a shared request but not send it, so this copies it
  /// into the first local collection and opens that copy in the builder,
  /// where Send, environments, variables and collection auth all apply.
  Future<void> _openInBuilder(BuildContext context) async {
    final collections = context.read<CollectionsViewModel>();
    if (collections.collections.isEmpty) {
      _showSnack(context, 'Create a local collection first');
      return;
    }
    final target = collections.collections.first;
    final messenger = ScaffoldMessenger.of(context);
    final id = await collections.createRequestFrom(target.id, CloudRequestMapper.toLocal(request));
    if (!context.mounted) return;
    context.read<ShellViewModel>().selectRequest(id);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('Copied "${request.name}" to "${target.name}"')));
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final vm = context.read<TeamViewModel>();
    switch (action) {
      case 'open_in_builder':
        await _openInBuilder(context);
      case 'move':
        final choice = await MoveToFolderDialog.show(context, folders: vm.folders, currentFolderId: request.folderId);
        if (choice == null || !context.mounted) return;
        final ok = await vm.moveRequest(request.id, choice.folderId);
        if (context.mounted) _showSnack(context, ok ? 'Moved "${request.name}"' : 'Failed to move request');
      case 'delete':
        final confirmed = await showConfirmDialog(context, title: 'Delete request', message: 'Delete "${request.name}"?');
        if (!confirmed || !context.mounted) return;
        final ok = await vm.deleteRequest(request.id);
        if (context.mounted) _showSnack(context, ok ? 'Request deleted' : 'Failed to delete request');
    }
  }
}

/// Create-then-edit: the row is inserted first (with its name), and the
/// editor opens on the stored row so every subsequent edit is an update.
Future<void> _addRequest(BuildContext context, int collectionId, {required int? folderId}) async {
  final vm = context.read<TeamViewModel>();
  final name = await showPromptDialog(context, title: 'New request', initialValue: 'New Request');
  if (name == null || !context.mounted) return;
  final created = await vm.createRequest(collectionId, name, folderId: folderId);
  if (!context.mounted) return;
  if (created == null) {
    _showSnack(context, 'Failed to create request');
    return;
  }
  await RequestFormDialog.show(context, request: created, canEdit: true);
}

Future<void> _addFolder(BuildContext context, int collectionId, {required int? parentFolderId}) async {
  final vm = context.read<TeamViewModel>();
  final name = await showPromptDialog(context, title: parentFolderId == null ? 'New folder' : 'New sub-folder');
  if (name == null || !context.mounted) return;
  final ok = await vm.createFolder(collectionId, name, parentFolderId: parentFolderId);
  if (context.mounted) _showSnack(context, ok ? 'Folder created' : 'Failed to create folder');
}

void _showSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
