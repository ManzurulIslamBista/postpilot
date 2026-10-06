import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/layout/layout_prefs.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/split_handle.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../collections/presentation/widgets/collection_runner_dialog.dart';
import '../../collections/presentation/widgets/collections_sidebar.dart';
import '../../command_palette/presentation/command_palette_dialog.dart';
import '../../command_palette/presentation/palette_items.dart';
import '../../environments/presentation/view_models/environments_view_model.dart';
import '../../../core/di/injector.dart';
import '../../console/presentation/widgets/console_dialog.dart';
import '../../mock_server/presentation/mock_server_dialog.dart';
import '../../templates/presentation/templates_dialog.dart';
import '../../tour/presentation/tour_dialog.dart';
import '../../mock_server/presentation/mock_server_view_model.dart';
import '../../cookies/presentation/widgets/cookies_dialog.dart';
import '../../environments/presentation/widgets/environment_selector.dart';
import '../../history/presentation/widgets/history_dialog.dart';
import '../../import_export/presentation/backup_dialog.dart';
import '../../request_builder/presentation/request_builder_page.dart';
import '../../settings/presentation/widgets/settings_dialog.dart';
import '../../workplace/presentation/view_models/workplace_view_model.dart';
import '../../workplace/presentation/widgets/push_to_git.dart';
import 'new_request_action.dart';
import 'shell_view_model.dart';
import '../../import_export/presentation/import_any_dialog.dart';
import 'widgets/empty_workspace.dart';
import 'widgets/request_tab_bar.dart';

/// Below this width, the collections sidebar no longer fits alongside the
/// request builder without squeezing it unusably narrow (the URL field and
/// tab labels would clip) — it moves into a `Drawer` instead of a fixed
/// column in the `Row`.
const _narrowWidthBreakpoint = 700.0;

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  // Lets Ctrl/Cmd+K open the drawer in the narrow layout, where the search
  // field lives inside it and would otherwise receive focus unseen.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // The welcome tour opens by itself once, on the very first start.
    if (locator.isRegistered<TourPrefs>()) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = locator<TourPrefs>();
        if (await prefs.shouldAutoShow() && mounted) {
          await prefs.markSeen();
          if (mounted) unawaited(TourDialog.show(context, onOpenPalette: () => _openPalette(context)));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _narrowWidthBreakpoint;
        // Wrapped inside the route (not above MaterialApp) so dialogs, which
        // push their own focus scope, do not receive the shortcuts.
        return AppShortcuts(
          handlers: _handlers(context, narrow: narrow),
          child: Scaffold(
            key: _scaffoldKey,
            drawer: narrow ? const Drawer(child: CollectionsSidebar()) : null,
            body: AppBackdrop(
              child: Row(
                children: [
                  if (!narrow) const _DesktopSidebar(),
                  Expanded(
                    child: Column(
                      // Stretch so the tab strip spans the window instead of
                      // shrink-wrapping its tabs and sitting in the middle.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(narrow: narrow, onOpenPalette: () => _openPalette(context)),
                        const RequestTabBar(),
                        Expanded(
                          child: _MainContent(
                            onNewRequest: () => _createRequest(context),
                            onImport: () => ImportAnyDialog.show(context),
                            onTemplates: () => TemplatesDialog.show(context),
                            onCommandPalette: () => _openPalette(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ShortcutHandlers _handlers(BuildContext context, {required bool narrow}) {
    final shell = context.read<ShellViewModel>();
    return ShortcutHandlers(
      sendRequest: shell.sendSelected,
      newRequest: () => _createRequest(context),
      focusSearch: () => _focusSearch(shell),
      closeRequest: shell.closeRequest,
      openHistory: () => HistoryDialog.show(context),
      findInResponse: shell.findInResponse,
      openCommandPalette: () => _openPalette(context),
      reopenClosedTab: shell.reopenClosed,
      focusUrl: shell.focusUrl,
      nextTab: shell.selectNextTab,
      previousTab: shell.selectPreviousTab,
      duplicateRequest: () => _duplicateRequest(context),
      saveResponseExample: shell.saveResponseExample,
      switchEnvironment: () => _switchEnvironment(context),
      runCollection: () => _runCollection(context),
      toggleSidebar: () {
        if (narrow) {
          final scaffold = _scaffoldKey.currentState;
          scaffold == null || scaffold.isDrawerOpen ? scaffold?.closeDrawer() : scaffold.openDrawer();
        } else {
          context.read<LayoutPrefs>().toggleSidebar();
        }
      },
    );
  }

  /// Ctrl+Shift+P: tools, app actions and environments at once, every request loaded in the background.
  void _openPalette(BuildContext context) {
    final environments = context.read<EnvironmentsViewModel>();
    final shell = context.read<ShellViewModel>();
    CommandPaletteDialog.show(
      context,
      items: [
        ...PaletteItems.tools(),
        ...PaletteItems.app(
          newRequest: () => _createRequest(context),
          duplicateRequest: () => _duplicateRequest(context),
          nextTab: shell.selectNextTab,
          previousTab: shell.selectPreviousTab,
          focusUrl: shell.focusUrl,
          saveResponseExample: shell.saveResponseExample,
          switchEnvironment: () => _switchEnvironment(context),
          runCollection: () => _runCollection(context),
          toggleSidebar: () {
            final scaffold = _scaffoldKey.currentState;
            if (scaffold != null && scaffold.hasDrawer) {
              scaffold.isDrawerOpen ? scaffold.closeDrawer() : scaffold.openDrawer();
            } else {
              context.read<LayoutPrefs>().toggleSidebar();
            }
          },
          openImport: () => ImportAnyDialog.show(context),
        ),
        ...PaletteItems.environments(environments),
      ],
      loadMore: PaletteItems.requests,
    );
  }

  void _focusSearch(ShellViewModel shell) {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.hasDrawer && !scaffold.isDrawerOpen) scaffold.openDrawer();
    shell.searchFocusNode.requestFocus();
  }

  Future<void> _createRequest(BuildContext context) async {
    final collections = context.read<CollectionsViewModel>();
    final shell = context.read<ShellViewModel>();
    final placed = await createNewRequest(collections, shell);
    if (!context.mounted) return;
    if (placed.createdCollection) {
      _say(context, 'Created "${CollectionsViewModel.defaultCollectionName}" for your first request');
    }
    if (!collections.isExpanded(placed.collectionId)) collections.toggleExpand(placed.collectionId);
    shell.selectRequest(placed.requestId);
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Ctrl+D: a copy of the open request, opened beside it.
  Future<void> _duplicateRequest(BuildContext context) async {
    final shell = context.read<ShellViewModel>();
    final collections = context.read<CollectionsViewModel>();
    final id = shell.selectedRequestId;
    if (id == null) {
      _say(context, 'Open a request first, then duplicate it');
      return;
    }
    final copy = await collections.duplicateRequest(id);
    if (!context.mounted) return;
    shell.selectRequest(copy);
    _say(context, 'Request duplicated');
  }

  /// Ctrl+Shift+E: the palette narrowed to the "Switch to ..." entries, so the active one changes in two keystrokes.
  void _switchEnvironment(BuildContext context) {
    final environments = context.read<EnvironmentsViewModel>();
    if (environments.environments.isEmpty) {
      _say(context, 'No environments yet: create one with the button at the right of the top bar');
      return;
    }
    CommandPaletteDialog.show(context, items: PaletteItems.environments(environments));
  }

  /// Ctrl+Shift+R: the runner for the collection of the open request (or the first collection with no tab open).
  Future<void> _runCollection(BuildContext context) async {
    final shell = context.read<ShellViewModel>();
    final collections = context.read<CollectionsViewModel>();
    final beside = await shell.selectedRequestLocation();
    final collectionId = beside?.collectionId ?? collections.collections.firstOrNull?.id;
    if (!context.mounted) return;
    if (collectionId == null) {
      _say(context, 'There is no collection to run yet: create one and add requests first');
      return;
    }
    await CollectionRunnerDialog.show(context, collectionId: collectionId);
  }
}

/// The collections column with a drag handle on its right edge. Width and the
/// collapsed state live in [LayoutPrefs], so they survive a restart.
class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<LayoutPrefs>();
    if (prefs.sidebarCollapsed) return const SizedBox.shrink();
    final colors = context.colors;
    // A wide sidebar saved on a big monitor must not swallow a small window.
    final cap = MediaQuery.sizeOf(context).width * 0.4;
    final width = prefs.sidebarWidth.clamp(
      LayoutPrefs.sidebarMin,
      cap < LayoutPrefs.sidebarMin ? LayoutPrefs.sidebarMin : cap,
    );
    return Row(
      children: [
        SizedBox(width: width, child: const CollectionsSidebar()),
        ColoredBox(
          color: colors.sidebarBackground,
          child: SplitHandle(
            axis: Axis.horizontal,
            thickness: 8,
            onDrag: (dx) => prefs.setSidebarWidth(prefs.sidebarWidth + dx),
            onDragEnd: prefs.commit,
            onReset: prefs.resetSidebarWidth,
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool narrow;
  final VoidCallback onOpenPalette;
  const _TopBar({required this.narrow, required this.onOpenPalette});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final prefs = context.watch<LayoutPrefs>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (narrow)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, size: 20),
                tooltip: 'Collections',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          else
            IconButton(
              icon: Icon(prefs.sidebarCollapsed ? Icons.menu_open : Icons.menu, size: 20),
              tooltip: prefs.sidebarCollapsed ? 'Show sidebar' : 'Hide sidebar',
              onPressed: prefs.toggleSidebar,
            ),
          // The wordmark only where there is room beside the actions.
          if (!narrow)
            LayoutBuilder(
              builder: (context, _) => MediaQuery.sizeOf(context).width >= 1280
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6, right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppLogo(size: 24),
                          const SizedBox(width: 8),
                          Text('PostPilot', style: context.textStyles.heading),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          // Right-aligned while it fits; on a phone it scrolls instead of
          // overflowing, starting at the end so the environment picker stays in view.
          Expanded(
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: _TopBarActions(onOpenPalette: onOpenPalette)),
          ),
        ],
      ),
    );
  }
}

class _TopBarActions extends StatelessWidget {
  final VoidCallback onOpenPalette;
  const _TopBarActions({required this.onOpenPalette});

  @override
  Widget build(BuildContext context) {
    final workplaceVm = context.watch<WorkplaceViewModel>();
    final activeWp = workplaceVm.activeWorkplace;

    return Row(
      children: [
        if (activeWp != null) ...[
          if (activeWp.isGitConnected) ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                backgroundColor: context.colors.sidebarBackground.withValues(alpha: 0.5),
              ),
              onPressed: workplaceVm.isBusy ? null : () => pushWorkplaceToGit(context, workplaceVm),
              icon: workplaceVm.isBusy
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 14),
              label: Text(
                'Git: ${activeWp.gitBranch}',
                style: context.textStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (workplaceVm.canRevealFolder)
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, size: 19),
              tooltip: 'Show workplace in ${workplaceVm.fileManagerName} (${activeWp.name})',
              onPressed: () => workplaceVm.revealWorkplaceFolder(),
            ),
        ],
        if (locator.isRegistered<MockServerViewModel>())
          ListenableBuilder(
            listenable: locator<MockServerViewModel>(),
            builder: (context, _) {
              final mock = locator<MockServerViewModel>();
              if (!mock.isRunning) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.circle, size: 9, color: context.colors.statusSuccess),
                  label: Text('Mock :${mock.port}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  tooltip: 'Mock server is running: open it',
                  onPressed: () => MockServerDialog.show(context),
                ),
              );
            },
          ),
        IconButton(
          icon: const Icon(Icons.manage_search, size: 21),
          tooltip: 'Command palette (${AppShortcut.commandPalette.keyLabel})',
          onPressed: onOpenPalette,
        ),
        const _MoreMenu(),
        IconButton(
          icon: const Icon(Icons.history, size: 20),
          tooltip: 'History',
          onPressed: () => HistoryDialog.show(context),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: 'Settings',
          onPressed: () => SettingsDialog.show(
            context,
            onOpenBackup: () => BackupDialog.show(context),
            onOpenShortcuts: () => ShortcutsHelpDialog.show(context),
          ),
        ),
        const EnvironmentSelector(),
      ],
    );
  }
}

enum _MoreAction {
  console(Icons.terminal, 'Console'),
  cookies(Icons.cookie_outlined, 'Cookies'),
  shortcuts(Icons.keyboard_outlined, 'Keyboard shortcuts');

  const _MoreAction(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The rarely used tools, kept in one menu so the top bar still fits beside
/// the sidebar on a narrow window.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MoreAction>(
      icon: const Icon(Icons.more_horiz, size: 20),
      tooltip: 'More',
      onSelected: (action) => switch (action) {
        _MoreAction.console => ConsoleDialog.show(context),
        _MoreAction.cookies => CookiesDialog.show(context),
        _MoreAction.shortcuts => ShortcutsHelpDialog.show(context),
      },
      itemBuilder: (context) => [
        for (final action in _MoreAction.values)
          PopupMenuItem(
            value: action,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 18),
                const SizedBox(width: 12),
                Flexible(child: Text(action.label)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MainContent extends StatelessWidget {
  final VoidCallback onNewRequest;
  final VoidCallback onImport;
  final VoidCallback onTemplates;
  final VoidCallback onCommandPalette;
  const _MainContent({
    required this.onNewRequest,
    required this.onImport,
    required this.onTemplates,
    required this.onCommandPalette,
  });

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellViewModel>();
    final selectedId = shell.selectedRequestId;
    if (selectedId == null) {
      return EmptyWorkspace(
        onNewRequest: onNewRequest,
        onImport: onImport,
        onTemplates: onTemplates,
        onCommandPalette: onCommandPalette,
      );
    }
    // One builder per open tab, kept alive off-screen so each tab holds on to
    // its own response and in-progress send across tab switches. The key sits
    // directly on the Stack's child: IndexedStack wraps every child in an
    // unkeyed Visibility, which would re-create all tabs after a closed one.
    return Stack(
      children: [
        for (final id in shell.openRequestIds)
          Visibility(
            key: ValueKey('request-tab-$id'),
            visible: id == selectedId,
            maintainState: true,
            child: RequestBuilderPage(requestId: id),
          ),
      ],
    );
  }
}
