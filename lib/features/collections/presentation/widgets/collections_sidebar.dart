import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import '../../../defaults/presentation/defaults_dialog.dart';
import '../../../documentation/domain/entities/entity_kind.dart';
import '../../../documentation/presentation/widgets/collection_docs_dialog.dart';
import '../../../documentation/presentation/widgets/entity_description_dialog.dart';
import '../../../documentation/presentation/widgets/tag_filter_bar.dart';
import '../../../git_sync/presentation/widgets/git_clone_dialog.dart';
import '../../../git_sync/presentation/widgets/git_link_badge.dart';
import '../../../git_sync/presentation/widgets/git_sync_dialog.dart';
import '../../../import_export/presentation/export_collection_dialog.dart';
import '../../../import_export/presentation/export_postman_dialog.dart';
import '../../../import_export/presentation/import_any_dialog.dart';
import '../../../import_export/presentation/openapi_refresh_dialog.dart';
import '../../../mock_server/presentation/mock_server_dialog.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../../workplace/presentation/view_models/workplace_view_model.dart';
import '../../../workplace/presentation/widgets/workplace_sidebar_header.dart';
import '../../domain/entities/collection_entity.dart';
import '../../domain/services/collection_order.dart';
import '../view_models/collections_view_model.dart';
import 'collection_auth_dialog.dart';
import 'collection_runner_dialog.dart';
import 'collection_variables_dialog.dart';
import 'move_to_dialog.dart';
import 'sidebar_drag_drop.dart';

class CollectionsSidebar extends StatefulWidget {
  const CollectionsSidebar({super.key});

  @override
  State<CollectionsSidebar> createState() => _CollectionsSidebarState();
}

class _CollectionsSidebarState extends State<CollectionsSidebar> {
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  late final _drag = SidebarDragState(scroll: _scroll, viewportKey: _listKey);

  @override
  void dispose() {
    _drag.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final visibleCollections = [
      for (final collection in vm.collections)
        if (vm.isCollectionVisible(collection)) collection,
    ];
    // A Material rather than a coloured Container: the ListTiles below paint
    // their selection and ink on the nearest Material, which a ColoredBox in
    // between would cover.
    return Material(
      color: context.colors.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkplaceSidebarHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'COLLECTIONS',
                    style: context.textStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      fontSize: 11,
                      color: context.colors.secondaryText,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, size: 17),
                  tooltip: 'Import…',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ImportAnyDialog.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined, size: 17),
                  tooltip: 'Clone from Git',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _cloneFromGit(context, vm),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'New collection',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _createCollection(context, vm),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              focusNode: context.read<ShellViewModel>().searchFocusNode,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: vm.setSearchQuery,
            ),
          ),
          const TagFilterBar(),
          Expanded(
            child: vm.collections.isEmpty
                ? NoCollectionsPrompt(
                    onCreate: () => _createCollection(context, vm),
                    onImport: () => ImportAnyDialog.show(context),
                  )
                : vm.isFiltering && visibleCollections.isEmpty
                ? Center(child: Text('Nothing matches', style: _emptyStyle(context)))
                : Provider<SidebarDragState>.value(
                    value: _drag,
                    child: ListView(
                      key: _listKey,
                      controller: _scroll,
                      children: [for (final collection in visibleCollections) _CollectionTile(collection: collection)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _createCollection(BuildContext context, CollectionsViewModel vm) async {
    final name = await showPromptDialog(context, title: 'New collection');
    if (name == null) return;
    await vm.createCollection(name);
    if (context.mounted) _showSnack(context, 'Collection created');
  }

  Future<void> _cloneFromGit(BuildContext context, CollectionsViewModel vm) async {
    final id = await GitCloneDialog.show(context);
    if (id == null || !context.mounted) return;
    if (!vm.isExpanded(id)) vm.toggleExpand(id);
    _showSnack(context, 'Collection cloned');
  }
}

/// A 28 px "more" button. Its size is the button's: PopupMenuButton.constraints sizes the opened menu, and a menu
/// held to 28 px is a sliver nobody can read.
final _compactIconButton = IconButton.styleFrom(
  minimumSize: const Size(28, 28),
  maximumSize: const Size(28, 28),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

TextStyle _emptyStyle(BuildContext context) => context.textStyles.caption.copyWith(color: context.colors.secondaryText);

/// The sidebar of a fresh install: one button that does the first thing anyone needs, not a hint about a "+".
class NoCollectionsPrompt extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onImport;
  const NoCollectionsPrompt({super.key, required this.onCreate, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No collections yet', style: _emptyStyle(context)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('New collection'),
            ),
            TextButton(onPressed: onImport, child: const Text('or import one')),
          ],
        ),
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// In the narrow layout the sidebar lives in a Drawer that would otherwise
/// keep covering the tab it just opened.
void _openRequest(BuildContext context, int id) {
  context.read<ShellViewModel>().selectRequest(id);
  Scaffold.maybeOf(context)?.closeDrawer();
}

// ---- moving and reordering ----

/// A dragged folder cannot be dropped on, beside or inside anything that is inside it.
bool _insideDraggedFolder(CollectionsViewModel vm, SidebarDragItem dragged, int collectionId, int? folderId) {
  if (!dragged.ref.isFolder || folderId == null || dragged.collectionId != collectionId) return false;
  return vm.orderOf(collectionId).folderSubtree(dragged.ref.id).contains(folderId);
}

OrderRef? _nextSibling(CollectionOrder order, OrderRef ref) {
  final siblings = order.siblingsOf(ref);
  final at = siblings.indexWhere((e) => e.ref == ref);
  return at >= 0 && at + 1 < siblings.length ? siblings[at + 1].ref : null;
}

/// The name of a place for a message: the folder, or the collection at its top level.
String _placeName(CollectionsViewModel vm, int collectionId, int? folderId) {
  if (folderId != null) {
    final folder = vm.foldersByCollection[collectionId]?.where((f) => f.id == folderId).firstOrNull;
    if (folder != null) return folder.name;
  }
  return vm.collections.where((c) => c.id == collectionId).firstOrNull?.name ?? 'the collection';
}

/// Moves what was dropped (or picked in "Move to…") to [spot] and says what happened, with a way back.
Future<void> _moveTo(BuildContext context, CollectionsViewModel vm, SidebarDragItem item, DropSpot spot) async {
  final messenger = ScaffoldMessenger.of(context);
  final workplace = context.read<WorkplaceViewModel>();
  final outcome = item.ref.isFolder
      ? await vm.moveFolder(
          item.ref.id,
          collectionId: spot.collectionId,
          parentFolderId: spot.parentFolderId,
          before: spot.before,
        )
      : await vm.moveRequest(
          item.ref.id,
          collectionId: spot.collectionId,
          folderId: spot.parentFolderId,
          before: spot.before,
        );
  final receipt = outcome.receipt;
  if (receipt == null) {
    messenger.showSnackBar(SnackBar(content: Text(outcome.error ?? "Couldn't move it.")));
    return;
  }
  if (receipt.isNoop) return;

  final sameLevel = item.collectionId == spot.collectionId && item.parentFolderId == spot.parentFolderId;
  final destination = _placeName(vm, spot.collectionId, spot.parentFolderId);
  final collection = _placeName(vm, spot.collectionId, null);
  final message = StringBuffer('Moved "${item.name}"')
    ..write(sameLevel ? '.' : ' to "$destination".')
    ..write(
      receipt.changedCollection
          ? ' What it inherits (variables, auth) now comes from "$collection".'
          : '',
    );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message.toString()),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undone = await vm.undoMove(receipt);
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  undone ? 'Move undone.' : "Couldn't undo the move: the collection has changed since.",
                ),
              ),
            );
            workplace.saveCurrentWorkplace();
          },
        ),
      ),
    );
  workplace.saveCurrentWorkplace();
}

/// One step up or down among its siblings (the menu and screen-reader way to reorder).
Future<void> _step(BuildContext context, CollectionsViewModel vm, SidebarDragItem item, int delta) async {
  final messenger = ScaffoldMessenger.of(context);
  final workplace = context.read<WorkplaceViewModel>();
  final outcome = await vm.moveStep(item.ref, collectionId: item.collectionId, delta: delta);
  if (outcome.error != null) messenger.showSnackBar(SnackBar(content: Text(outcome.error!)));
  workplace.saveCurrentWorkplace();
}

/// "Move to…": the user picks a collection or folder from a list and the item goes to the end of it.
Future<void> _chooseDestination(BuildContext context, CollectionsViewModel vm, SidebarDragItem item) async {
  final destination = await showMoveToDialog(context, viewModel: vm, moving: item.ref, name: item.name);
  if (destination == null || !context.mounted) return;
  await _moveTo(context, vm, item, DropSpot(destination.collectionId, destination.folderId));
}

/// The menu entries that move something. Disabled when there is no sibling to swap with in that direction.
List<PopupMenuEntry<String>> _moveMenuItems(CollectionsViewModel vm, OrderRef ref, int collectionId) => [
  const PopupMenuDivider(),
  PopupMenuItem(
    value: 'move_up',
    enabled: vm.canStep(ref, collectionId: collectionId, delta: -1),
    child: const Text('Move up'),
  ),
  PopupMenuItem(
    value: 'move_down',
    enabled: vm.canStep(ref, collectionId: collectionId, delta: 1),
    child: const Text('Move down'),
  ),
  const PopupMenuItem(value: 'move_to', child: Text('Move to…')),
  const PopupMenuDivider(),
];

/// Screen-reader actions on a row, the same two steps as the menu.
Map<CustomSemanticsAction, VoidCallback> _moveActions(
  BuildContext context,
  CollectionsViewModel vm,
  SidebarDragItem item,
) => {
  if (vm.canStep(item.ref, collectionId: item.collectionId, delta: -1))
    const CustomSemanticsAction(label: 'Move up'): () => _step(context, vm, item, -1),
  if (vm.canStep(item.ref, collectionId: item.collectionId, delta: 1))
    const CustomSemanticsAction(label: 'Move down'): () => _step(context, vm, item, 1),
};

class _CollectionTile extends StatelessWidget {
  final CollectionEntity collection;
  const _CollectionTile({required this.collection});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final expanded = vm.isCollectionExpanded(collection);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarDndRow(
          enabled: vm.canMove && !vm.isFiltering,
          layout: DropLayout.container,
          drag: context.read<SidebarDragState>(),
          accepts: (_) => true,
          spotFor: (_) => DropSpot(collection.id, null),
          onHoverOpen: expanded ? null : () => vm.expandCollection(collection.id),
          onDrop: (item, spot) => _moveTo(context, vm, item, spot),
          child: ListTile(
            dense: true,
            leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
            title: Row(
              children: [
                Expanded(child: Text(collection.name, overflow: TextOverflow.ellipsis)),
                GitLinkBadge(collection.id),
              ],
            ),
            onTap: () => vm.toggleExpand(collection.id),
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _handleAction(context, vm, action),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'add_request', child: Text('Add request')),
                PopupMenuItem(value: 'add_folder', child: Text('Add folder')),
                PopupMenuItem(value: 'import_curl', child: Text('Import cURL')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'run', child: Text('Run collection')),
                PopupMenuItem(value: 'variables', child: Text('Variables')),
                PopupMenuItem(value: 'auth', child: Text('Collection auth')),
                PopupMenuItem(value: 'defaults', child: Text('Defaults (headers, tests)…')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'describe', child: Text('Description & tags…')),
                PopupMenuItem(value: 'docs', child: Text('Documentation…')),
                PopupMenuItem(value: 'git_sync', child: Text('Git sync…')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'openapi_refresh', child: Text('Update from OpenAPI…')),
                PopupMenuItem(value: 'dart_api', child: Text('Generate Dart API layer…')),
                PopupMenuItem(value: 'mock_server', child: Text('Mock server…')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'export', child: Text('Export as Postman JSON')),
                PopupMenuItem(value: 'export_openapi', child: Text('Export as OpenAPI')),
                PopupMenuItem(value: 'export_curl', child: Text('Export cURL script')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ),
        if (expanded) _FolderChildren(collectionId: collection.id, parentFolderId: null, depth: 1),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, CollectionsViewModel vm, String action) async {
    switch (action) {
      case 'add_request':
        final id = await vm.createRequest(collection.id);
        if (context.mounted) _openRequest(context, id);
        if (context.mounted) _showSnack(context, 'Request created');
      case 'add_folder':
        final name = await showPromptDialog(context, title: 'New folder');
        if (name != null) {
          await vm.createFolder(collection.id, name);
          if (context.mounted) _showSnack(context, 'Folder created');
        }
      case 'import_curl':
        await ImportAnyDialog.show(context, collectionId: collection.id);
      case 'run':
        await CollectionRunnerDialog.show(context, collectionId: collection.id);
      case 'openapi_refresh':
        await OpenApiRefreshDialog.show(context, collectionId: collection.id);
      case 'dart_api':
        await DartStudioDialog.show(context, collectionId: collection.id, initialTab: 1);
      case 'mock_server':
        await MockServerDialog.show(context, collectionId: collection.id);
      case 'variables':
        await CollectionVariablesDialog.show(context, collectionId: collection.id, collectionName: collection.name);
      case 'auth':
        await CollectionAuthDialog.show(context, collectionId: collection.id);
      case 'defaults':
        await showDefaultsDialog(context, collectionId: collection.id);
      case 'describe':
        await EntityDescriptionDialog.show(context, EntityKind.collection, collection.id, collection.name);
      case 'docs':
        await CollectionDocsDialog.show(context, collectionId: collection.id, collectionName: collection.name);
      case 'git_sync':
        await GitSyncDialog.show(context, collectionId: collection.id, collectionName: collection.name);
      case 'export':
        await ExportPostmanDialog.show(context, collectionId: collection.id);
      case 'export_openapi':
        await ExportCollectionDialog.showOpenApi(context, collectionId: collection.id);
      case 'export_curl':
        await ExportCollectionDialog.showCurlScript(context, collectionId: collection.id);
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename collection', initialValue: collection.name);
        if (name != null) {
          await vm.renameCollection(collection.id, name);
          if (context.mounted) _showSnack(context, 'Collection renamed');
        }
      case 'duplicate':
        await vm.duplicateCollection(collection.id);
        if (context.mounted) _showSnack(context, 'Collection duplicated');
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete collection',
          message: 'Delete "${collection.name}" and everything inside it?',
        );
        if (confirmed) {
          await vm.deleteCollection(collection.id);
          if (context.mounted) _showSnack(context, 'Collection deleted');
        }
    }
    final mutatingActions = {'add_request', 'add_folder', 'rename', 'duplicate', 'delete'};
    if (mutatingActions.contains(action) && context.mounted) {
      context.read<WorkplaceViewModel>().saveCurrentWorkplace();
    }
  }
}

/// Renders the folders and requests that live directly under [parentFolderId]
/// (null = the collection's top level) in the collection's canonical order, folders and requests interleaved as
/// arranged, recursing into `_FolderTile` for each sub-folder so folders can nest arbitrarily deep.
class _FolderChildren extends StatelessWidget {
  final int collectionId;
  final int? parentFolderId;
  final double depth;

  const _FolderChildren({required this.collectionId, required this.parentFolderId, required this.depth});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final children = [
      for (final item in vm.childrenOf(collectionId, parentFolderId))
        if (item.folder != null
            ? vm.isFolderVisible(collectionId, item.folder!)
            : vm.isRequestVisible(item.request!))
          item,
    ];

    if (children.isEmpty) {
      return SidebarDndRow(
        enabled: vm.canMove && !vm.isFiltering,
        layout: DropLayout.container,
        drag: context.read<SidebarDragState>(),
        accepts: (dragged) => !_insideDraggedFolder(vm, dragged, collectionId, parentFolderId),
        spotFor: (_) => DropSpot(collectionId, parentFolderId),
        onDrop: (item, spot) => _moveTo(context, vm, item, spot),
        child: Padding(
          padding: EdgeInsets.only(left: 16.0 * depth + 8, top: 4, bottom: 4),
          child: Text('No requests here yet', style: _emptyStyle(context)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in children)
          if (item.folder case final folder?)
            _FolderTile(key: ValueKey('folder-${folder.id}'), collectionId: collectionId, folder: folder, depth: depth)
          else
            _RequestTile(
              key: ValueKey('request-${item.request!.id}'),
              collectionId: collectionId,
              request: item.request!,
              indent: 16.0 * depth + 8,
            ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final int collectionId;
  final FolderEntity folder;
  final double depth;

  const _FolderTile({super.key, required this.collectionId, required this.folder, required this.depth});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final expanded = vm.isFolderExpanded(folder.id);
    final ref = OrderRef.folder(folder.id);
    final item = SidebarDragItem(
      ref: ref,
      collectionId: collectionId,
      parentFolderId: folder.parentFolderId,
      name: folder.name,
      icon: Icons.folder,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 16.0 * depth),
          child: SidebarDndRow(
            enabled: vm.canMove && !vm.isFiltering,
            item: item,
            layout: DropLayout.folder,
            drag: context.read<SidebarDragState>(),
            accepts: (dragged) =>
                dragged.ref != ref && !_insideDraggedFolder(vm, dragged, collectionId, folder.id),
            spotFor: (zone) => _spotFor(vm, zone),
            onHoverOpen: expanded ? null : () => vm.expandFolder(folder.id),
            onDrop: (dragged, spot) => _moveTo(context, vm, dragged, spot),
            child: Semantics(
              customSemanticsActions: vm.canMove ? _moveActions(context, vm, item) : null,
              child: ListTile(
                dense: true,
                leading: Icon(expanded ? Icons.folder_open : Icons.folder, size: 18),
                title: Text(folder.name, overflow: TextOverflow.ellipsis),
                onTap: () => vm.toggleFolder(folder.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => _handleAction(context, vm, item, action),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'add_request', child: Text('Add request')),
                    const PopupMenuItem(value: 'add_folder', child: Text('Add sub-folder')),
                    const PopupMenuItem(value: 'run', child: Text('Run folder')),
                    const PopupMenuItem(value: 'defaults', child: Text('Folder defaults (headers, auth, tests)…')),
                    const PopupMenuItem(value: 'describe', child: Text('Description & tags…')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    if (vm.canMove) ..._moveMenuItems(vm, ref, collectionId),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded) _FolderChildren(collectionId: collectionId, parentFolderId: folder.id, depth: depth + 1),
      ],
    );
  }

  /// In front of it, into it (the end of its content), or behind it. Behind an open folder is the top of its
  /// content, which is the row just below.
  DropSpot _spotFor(CollectionsViewModel vm, DropZone zone) {
    final order = vm.orderOf(collectionId);
    switch (zone) {
      case DropZone.before:
        return DropSpot(collectionId, folder.parentFolderId, OrderRef.folder(folder.id));
      case DropZone.into:
        return DropSpot(collectionId, folder.id);
      case DropZone.after:
        final content = order.childrenOf(folder.id);
        if (vm.isFolderExpanded(folder.id) && content.isNotEmpty) {
          return DropSpot(collectionId, folder.id, content.first.ref);
        }
        return DropSpot(collectionId, folder.parentFolderId, _nextSibling(order, OrderRef.folder(folder.id)));
    }
  }

  Future<void> _handleAction(BuildContext context, CollectionsViewModel vm, SidebarDragItem item, String action) async {
    switch (action) {
      case 'add_request':
        final id = await vm.createRequest(collectionId, folderId: folder.id);
        if (context.mounted) _openRequest(context, id);
        if (context.mounted) _showSnack(context, 'Request created');
      case 'add_folder':
        final name = await showPromptDialog(context, title: 'New sub-folder');
        if (name != null) {
          await vm.createFolder(collectionId, name, parentFolderId: folder.id);
          if (context.mounted) _showSnack(context, 'Folder created');
        }
      case 'run':
        await CollectionRunnerDialog.show(context, collectionId: collectionId, folderId: folder.id);
      case 'defaults':
        await showDefaultsDialog(context, collectionId: collectionId, folderId: folder.id);
      case 'describe':
        await EntityDescriptionDialog.show(context, EntityKind.folder, folder.id, folder.name);
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename folder', initialValue: folder.name);
        if (name != null) {
          await vm.renameFolder(folder.id, name);
          if (context.mounted) _showSnack(context, 'Folder renamed');
        }
      case 'duplicate':
        await vm.duplicateFolder(folder.id);
        if (context.mounted) _showSnack(context, 'Folder duplicated');
      case 'move_up':
        await _step(context, vm, item, -1);
      case 'move_down':
        await _step(context, vm, item, 1);
      case 'move_to':
        await _chooseDestination(context, vm, item);
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete folder',
          message: 'Delete "${folder.name}" and everything inside it?',
        );
        if (confirmed) {
          await vm.deleteFolder(folder.id);
          if (context.mounted) _showSnack(context, 'Folder deleted');
        }
    }
    if (context.mounted) context.read<WorkplaceViewModel>().saveCurrentWorkplace();
  }
}

class _RequestTile extends StatefulWidget {
  final int collectionId;
  final RequestSummaryEntity request;
  final double indent;
  const _RequestTile({super.key, required this.collectionId, required this.request, required this.indent});

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _hovered = false;

  RequestSummaryEntity get request => widget.request;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<CollectionsViewModel>();
    final colors = context.colors;
    final isSelected = context.select<ShellViewModel, bool>((shell) => shell.selectedRequestId == request.id);
    final background = isSelected
        ? colors.mainAccent.withValues(alpha: 0.13)
        : _hovered
        ? colors.hover
        : Colors.transparent;
    final ref = OrderRef.request(request.id);
    final item = SidebarDragItem(
      ref: ref,
      collectionId: widget.collectionId,
      parentFolderId: request.folderId,
      name: request.name,
      icon: Icons.http,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.indent, 1, 8, 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SidebarDndRow(
          enabled: vm.canMove && !vm.isFiltering,
          item: item,
          layout: DropLayout.request,
          drag: context.read<SidebarDragState>(),
          accepts: (dragged) =>
              dragged.ref != ref && !_insideDraggedFolder(vm, dragged, widget.collectionId, request.folderId),
          spotFor: (zone) => zone == DropZone.before
              ? DropSpot(widget.collectionId, request.folderId, ref)
              : DropSpot(widget.collectionId, request.folderId, _nextSibling(vm.orderOf(widget.collectionId), ref)),
          onDrop: (dragged, spot) => _moveTo(context, vm, dragged, spot),
          child: Semantics(
            customSemanticsActions: vm.canMove ? _moveActions(context, vm, item) : null,
            child: Material(
              color: background,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openRequest(context, request.id),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2, top: 4, bottom: 4),
                  child: Row(
                    children: [
                      MethodBadge(method: request.method.label),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          request.name,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.body.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? colors.primaryText : colors.primaryText.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                      // Dimmed rather than hidden until hover: a phone has no hover.
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _hovered || isSelected ? 1 : 0.4,
                        child: PopupMenuButton<String>(
                          tooltip: 'More',
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          style: _compactIconButton,
                          onSelected: (action) => _handleAction(context, vm, item, action),
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                            if (vm.canMove) ..._moveMenuItems(vm, ref, widget.collectionId),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, CollectionsViewModel vm, SidebarDragItem item, String action) async {
    switch (action) {
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename request', initialValue: request.name);
        if (name != null) {
          await vm.renameRequest(request.id, name);
          if (context.mounted) _showSnack(context, 'Request renamed');
        }
      case 'duplicate':
        await vm.duplicateRequest(request.id);
        if (context.mounted) _showSnack(context, 'Request duplicated');
      case 'move_up':
        await _step(context, vm, item, -1);
      case 'move_down':
        await _step(context, vm, item, 1);
      case 'move_to':
        await _chooseDestination(context, vm, item);
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete request',
          message: 'Delete "${request.name}"?',
        );
        if (confirmed) {
          await vm.deleteRequest(request.id);
          if (context.mounted && context.read<ShellViewModel>().selectedRequestId == request.id) {
            context.read<ShellViewModel>().closeRequest();
          }
          if (context.mounted) _showSnack(context, 'Request deleted');
        }
    }
    if (context.mounted) context.read<WorkplaceViewModel>().saveCurrentWorkplace();
  }
}
