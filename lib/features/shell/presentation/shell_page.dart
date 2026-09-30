import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../auth/presentation/widgets/account_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../collections/presentation/widgets/collections_sidebar.dart';
import '../../console/presentation/widgets/console_dialog.dart';
import '../../cookies/presentation/widgets/cookies_dialog.dart';
import '../../environments/presentation/widgets/environment_selector.dart';
import '../../history/presentation/widgets/history_dialog.dart';
import '../../import_export/presentation/backup_dialog.dart';
import '../../request_builder/presentation/request_builder_page.dart';
import '../../settings/presentation/widgets/settings_dialog.dart';
import '../../team/presentation/widgets/team_dialog.dart';
import 'shell_view_model.dart';
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _narrowWidthBreakpoint;
        // Wrapped inside the route (not above MaterialApp) so dialogs, which
        // push their own focus scope, do not receive the shortcuts.
        return AppShortcuts(
          handlers: _handlers(context),
          child: Scaffold(
            key: _scaffoldKey,
            drawer: narrow ? const Drawer(child: CollectionsSidebar()) : null,
            body: Row(
              children: [
                if (!narrow) ...[
                  const SizedBox(width: 280, child: CollectionsSidebar()),
                  VerticalDivider(width: 1, color: context.colors.border),
                ],
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.colors.border))),
                        child: Row(
                          children: [
                            if (narrow)
                              Builder(
                                builder: (context) => IconButton(
                                  icon: const Icon(Icons.menu, size: 20),
                                  tooltip: 'Collections',
                                  onPressed: () => Scaffold.of(context).openDrawer(),
                                ),
                              ),
                            // Right-aligned while it fits; on a phone it scrolls instead of
                            // overflowing, starting at the end so the environment picker stays in view.
                            const Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: _TopBarActions(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const RequestTabBar(),
                      const Expanded(child: _MainContent()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ShortcutHandlers _handlers(BuildContext context) {
    final shell = context.read<ShellViewModel>();
    return ShortcutHandlers(
      sendRequest: shell.sendSelected,
      newRequest: () => _createRequest(context),
      focusSearch: () => _focusSearch(shell),
      closeRequest: shell.closeRequest,
      openHistory: () => HistoryDialog.show(context),
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
    // Beside the active request, so working in one collection keeps new
    // requests there; the first collection is only the fallback for no tab.
    final beside = await shell.selectedRequestLocation();
    final collectionId = beside?.collectionId ?? collections.collections.firstOrNull?.id;
    if (collectionId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a collection first')));
      }
      return;
    }
    final id = await collections.createRequest(collectionId, folderId: beside?.folderId);
    if (!context.mounted) return;
    if (!collections.isExpanded(collectionId)) collections.toggleExpand(collectionId);
    shell.selectRequest(id);
    _scaffoldKey.currentState?.closeDrawer();
  }
}

class _TopBarActions extends StatelessWidget {
  const _TopBarActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _MoreMenu(),
        IconButton(
          icon: const Icon(Icons.history, size: 20),
          tooltip: 'History',
          onPressed: () => HistoryDialog.show(context),
        ),
        IconButton(
          icon: const Icon(Icons.group_outlined, size: 20),
          tooltip: 'Team',
          onPressed: () => TeamDialog.show(context),
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
        IconButton(
          icon: const Icon(Icons.account_circle_outlined, size: 20),
          tooltip: 'Account',
          onPressed: () => AccountDialog.show(context),
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
  const _MainContent();

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellViewModel>();
    final selectedId = shell.selectedRequestId;
    if (selectedId == null) {
      return const Center(child: Text('Select or create a request to get started'));
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
