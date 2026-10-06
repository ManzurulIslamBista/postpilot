import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../dart_codegen/presentation/widgets/dart_studio_dialog.dart';
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
import '../view_models/collections_view_model.dart';
import 'collection_auth_dialog.dart';
import 'collection_runner_dialog.dart';
import 'collection_variables_dialog.dart';

class CollectionsSidebar extends StatelessWidget {
  const CollectionsSidebar({super.key});

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
                : ListView(
                    children: [for (final collection in visibleCollections) _CollectionTile(collection: collection)],
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

class _CollectionTile extends StatelessWidget {
  final CollectionEntity collection;
  const _CollectionTile({required this.collection});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final expanded = vm.isCollectionExpanded(collection);
    final folders = vm.foldersByCollection[collection.id] ?? const [];
    final requests = vm.requestsByCollection[collection.id] ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
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
        if (expanded)
          _FolderChildren(
            collectionId: collection.id,
            parentFolderId: null,
            allFolders: folders,
            allRequests: requests,
            depth: 1,
          ),
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
/// (null = the collection's top level), recursing into `_FolderTile` for
/// each sub-folder so folders can nest arbitrarily deep.
class _FolderChildren extends StatelessWidget {
  final int collectionId;
  final int? parentFolderId;
  final List<FolderEntity> allFolders;
  final List<RequestSummaryEntity> allRequests;
  final double depth;

  const _FolderChildren({
    required this.collectionId,
    required this.parentFolderId,
    required this.allFolders,
    required this.allRequests,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final childFolders = allFolders.where(
      (f) => f.parentFolderId == parentFolderId && vm.isFolderVisible(collectionId, f),
    );
    final childRequests = allRequests.where((r) => r.folderId == parentFolderId && vm.isRequestVisible(r));

    if (childFolders.isEmpty && childRequests.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: 16.0 * depth + 8, top: 4, bottom: 4),
        child: Text('No requests here yet', style: _emptyStyle(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final folder in childFolders)
          _FolderTile(
            key: ValueKey('folder-${folder.id}'),
            collectionId: collectionId,
            folder: folder,
            allFolders: allFolders,
            allRequests: allRequests,
            depth: depth,
          ),
        for (final request in childRequests)
          _RequestTile(key: ValueKey('request-${request.id}'), request: request, indent: 16.0 * depth + 8),
      ],
    );
  }
}

class _FolderTile extends StatefulWidget {
  final int collectionId;
  final FolderEntity folder;
  final List<FolderEntity> allFolders;
  final List<RequestSummaryEntity> allRequests;
  final double depth;

  const _FolderTile({
    super.key,
    required this.collectionId,
    required this.folder,
    required this.allFolders,
    required this.allRequests,
    required this.depth,
  });

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<CollectionsViewModel>();
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
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _handleAction(context, vm, action),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'add_request', child: Text('Add request')),
                PopupMenuItem(value: 'add_folder', child: Text('Add sub-folder')),
                PopupMenuItem(value: 'describe', child: Text('Description & tags…')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ),
        if (_expanded)
          _FolderChildren(
            collectionId: widget.collectionId,
            parentFolderId: widget.folder.id,
            allFolders: widget.allFolders,
            allRequests: widget.allRequests,
            depth: widget.depth + 1,
          ),
      ],
    );
  }

  Future<void> _handleAction(BuildContext context, CollectionsViewModel vm, String action) async {
    switch (action) {
      case 'add_request':
        final id = await vm.createRequest(widget.collectionId, folderId: widget.folder.id);
        if (context.mounted) _openRequest(context, id);
        if (context.mounted) _showSnack(context, 'Request created');
      case 'add_folder':
        final name = await showPromptDialog(context, title: 'New sub-folder');
        if (name != null) {
          await vm.createFolder(widget.collectionId, name, parentFolderId: widget.folder.id);
          if (context.mounted) _showSnack(context, 'Folder created');
        }
      case 'describe':
        await EntityDescriptionDialog.show(context, EntityKind.folder, widget.folder.id, widget.folder.name);
      case 'rename':
        final name = await showPromptDialog(context, title: 'Rename folder', initialValue: widget.folder.name);
        if (name != null) {
          await vm.renameFolder(widget.folder.id, name);
          if (context.mounted) _showSnack(context, 'Folder renamed');
        }
      case 'duplicate':
        await vm.duplicateFolder(widget.folder.id);
        if (context.mounted) _showSnack(context, 'Folder duplicated');
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete folder',
          message: 'Delete "${widget.folder.name}" and everything inside it?',
        );
        if (confirmed) {
          await vm.deleteFolder(widget.folder.id);
          if (context.mounted) _showSnack(context, 'Folder deleted');
        }
    }
    if (context.mounted) context.read<WorkplaceViewModel>().saveCurrentWorkplace();
  }
}

class _RequestTile extends StatefulWidget {
  final RequestSummaryEntity request;
  final double indent;
  const _RequestTile({super.key, required this.request, required this.indent});

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
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.indent, 1, 8, 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
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
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onSelected: (action) => _handleAction(context, vm, action),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, CollectionsViewModel vm, String action) async {
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
