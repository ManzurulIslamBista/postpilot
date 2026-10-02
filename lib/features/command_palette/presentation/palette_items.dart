import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../console/presentation/widgets/console_dialog.dart';
import '../../cookies/presentation/widgets/cookies_dialog.dart';
import '../../ai_assistant/presentation/ai_request_dialog.dart';
import '../../dart_codegen/presentation/widgets/dart_studio_dialog.dart';
import '../../device_helper/presentation/device_helper_dialog.dart';
import '../../graphql/presentation/graphql_explorer_dialog.dart';
import '../../import_export/presentation/openapi_refresh_dialog.dart';
import '../../mock_server/presentation/mock_server_dialog.dart';
import '../../realtime/presentation/realtime_dialog.dart';
import '../../environments/presentation/view_models/environments_view_model.dart';
import '../../history/presentation/widgets/history_dialog.dart';
import '../../import_export/domain/services/collection_loader.dart';
import '../../import_export/presentation/backup_dialog.dart';
import '../../odoo/presentation/widgets/odoo_studio_dialog.dart';
import '../../settings/presentation/widgets/settings_dialog.dart';
import '../../templates/presentation/templates_dialog.dart';
import '../../tour/presentation/tour_dialog.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../domain/entities/palette_item.dart';

/// Where the palette's content comes from. Adding a tool to the app means
/// adding one line to [tools] so it can be found with Ctrl+Shift+P.
abstract final class PaletteItems {
  static List<PaletteItem> tools() => [
        PaletteItem(
          id: 'ai.request',
          title: 'AI: create a request from a description',
          subtitle: 'Bring your own Anthropic key; credentials are masked before anything is sent',
          icon: Icons.auto_awesome,
          keywords: const ['ai', 'claude', 'anthropic', 'generate', 'assistant', 'llm', 'gpt'],
          run: (c) => AiRequestDialog.show(c),
        ),
        PaletteItem(
          id: 'templates',
          title: 'Starter templates',
          subtitle: 'REST, auth, GraphQL and Odoo collections you can add and try at once',
          icon: Icons.auto_awesome_mosaic_outlined,
          keywords: const ['template', 'example', 'sample', 'starter', 'demo', 'getting started'],
          run: (c) => TemplatesDialog.show(c),
        ),
        PaletteItem(
          id: 'dart.models',
          title: 'Dart Studio: JSON to Dart models',
          subtitle: 'Generate classes (plain, json_serializable, freezed) from a response',
          icon: Icons.flutter_dash,
          keywords: const ['flutter', 'class', 'dto', 'serializable', 'freezed', 'model'],
          run: (c) => DartStudioDialog.show(c),
        ),
        PaletteItem(
          id: 'dart.api',
          title: 'Dart Studio: collection to API layer',
          subtitle: 'Dio data source, DTOs, repository and use cases from a collection',
          icon: Icons.account_tree_outlined,
          keywords: const ['flutter', 'dio', 'retrofit', 'repository', 'usecase', 'client'],
          run: (c) => DartStudioDialog.show(c, initialTab: 1),
        ),
        PaletteItem(
          id: 'mock.server',
          title: 'Mock server: serve a collection as a live API',
          subtitle: 'Saved examples answer real HTTP calls on this computer',
          icon: Icons.dns_outlined,
          keywords: const ['mock', 'backend', 'fake', 'stub', 'server', 'examples'],
          run: (c) => MockServerDialog.show(c),
        ),
        PaletteItem(
          id: 'openapi.refresh',
          title: 'Update a collection from OpenAPI',
          subtitle: 'Add new endpoints from a newer spec without touching your edits',
          icon: Icons.sync_alt,
          keywords: const ['openapi', 'swagger', 'spec', 'refresh', 'sync', 'endpoints'],
          run: (c) => OpenApiRefreshDialog.show(c),
        ),
        PaletteItem(
          id: 'graphql.explorer',
          title: 'GraphQL explorer',
          subtitle: 'Browse a schema, build queries and mutations from it',
          icon: Icons.hexagon_outlined,
          keywords: const ['graphql', 'schema', 'introspection', 'query', 'mutation', 'gql'],
          run: (c) => GraphqlExplorerDialog.show(c),
        ),
        PaletteItem(
          id: 'realtime',
          title: 'Realtime: WebSocket and Server-Sent Events',
          subtitle: 'Connect, send messages, watch the live log',
          icon: Icons.swap_vert_circle_outlined,
          keywords: const ['websocket', 'ws', 'wss', 'sse', 'event stream', 'socket', 'live', 'bus'],
          run: (c) => RealtimeDialog.show(c),
        ),
        PaletteItem(
          id: 'device.helper',
          title: 'Device helper: reach localhost from a phone or emulator',
          subtitle: '10.0.2.2, your Wi-Fi address, QR code, adb reverse',
          icon: Icons.phonelink_setup,
          keywords: const ['android', 'ios', 'emulator', 'simulator', 'localhost', 'qr', 'lan', 'ip', 'adb'],
          run: (c) => DeviceHelperDialog.show(c),
        ),
        PaletteItem(
          id: 'odoo.connect',
          title: 'Odoo Studio: connect to a server',
          subtitle: 'JSON-2 API, API key, save as environment, ready-made requests',
          icon: Icons.hub_outlined,
          keywords: const ['odoo', 'erp', 'json-2', 'api key'],
          run: (c) => OdooStudioDialog.show(c),
        ),
        PaletteItem(
          id: 'odoo.explorer',
          title: 'Odoo Studio: explore models and fields',
          subtitle: 'fields_get, pick fields, run search_read',
          icon: Icons.travel_explore,
          keywords: const ['odoo', 'model', 'fields', 'search_read', 'ir.model'],
          run: (c) => OdooStudioDialog.show(c, initialTab: 1),
        ),
        PaletteItem(
          id: 'odoo.domain',
          title: 'Odoo Studio: domain builder',
          subtitle: 'Build a domain visually, copy as JSON or Python',
          icon: Icons.filter_alt_outlined,
          keywords: const ['odoo', 'domain', 'filter', 'prefix', 'search'],
          run: (c) => OdooStudioDialog.show(c, initialTab: 2),
        ),
        PaletteItem(
          id: 'odoo.migrate',
          title: 'Odoo Studio: migrate old XML-RPC / JSON-RPC calls',
          subtitle: 'execute_kw, /jsonrpc and call_kw to JSON-2',
          icon: Icons.swap_horiz,
          keywords: const ['odoo', 'xmlrpc', 'jsonrpc', 'execute_kw', 'convert', 'deprecated'],
          run: (c) => OdooStudioDialog.show(c, initialTab: 3),
        ),
        PaletteItem(
          id: 'odoo.dart',
          title: 'Odoo Studio: Dart model from an Odoo model',
          subtitle: 'A class that reads Odoo JSON (false for empty, [id, name] relations)',
          icon: Icons.flutter_dash,
          keywords: const ['odoo', 'flutter', 'dart', 'fields_get'],
          run: (c) => OdooStudioDialog.show(c, initialTab: 4),
        ),
      ];

  /// App-level actions. The shell passes the ones only it can perform.
  static List<PaletteItem> app({
    required VoidCallback newRequest,
    required VoidCallback toggleSidebar,
    required VoidCallback openImport,
  }) =>
      [
        PaletteItem(id: 'app.new', title: 'New request', icon: Icons.add_rounded, category: PaletteCategory.app, shortcut: AppShortcut.newRequest.keyLabel, run: (_) => newRequest()),
        PaletteItem(id: 'app.import', title: 'Import…', subtitle: 'Postman, OpenAPI, Insomnia, HAR, cURL', icon: Icons.file_download_outlined, category: PaletteCategory.app, keywords: const ['curl', 'swagger', 'openapi', 'postman'], run: (_) => openImport()),
        PaletteItem(id: 'app.sidebar', title: 'Show or hide the sidebar', icon: Icons.menu_open, category: PaletteCategory.app, shortcut: AppShortcut.toggleSidebar.keyLabel, run: (_) => toggleSidebar()),
        PaletteItem(id: 'app.history', title: 'History', subtitle: 'Recently sent requests', icon: Icons.history, category: PaletteCategory.app, shortcut: AppShortcut.openHistory.keyLabel, run: (c) => HistoryDialog.show(c)),
        PaletteItem(id: 'app.console', title: 'Console', subtitle: 'Every request and response PostPilot sent', icon: Icons.terminal, category: PaletteCategory.app, run: (c) => ConsoleDialog.show(c)),
        PaletteItem(id: 'app.cookies', title: 'Cookies', icon: Icons.cookie_outlined, category: PaletteCategory.app, run: (c) => CookiesDialog.show(c)),
        PaletteItem(id: 'app.backup', title: 'Backup and restore', icon: Icons.backup_outlined, category: PaletteCategory.app, run: (c) => BackupDialog.show(c)),
        PaletteItem(
          id: 'app.settings',
          title: 'Settings',
          icon: Icons.settings_outlined,
          category: PaletteCategory.app,
          run: (c) => SettingsDialog.show(c, onOpenBackup: () => BackupDialog.show(c), onOpenShortcuts: () => ShortcutsHelpDialog.show(c)),
        ),
        PaletteItem(id: 'app.tour', title: 'Take the quick tour', subtitle: 'What PostPilot can do, in six steps', icon: Icons.tour_outlined, category: PaletteCategory.app, keywords: const ['help', 'guide', 'welcome', 'onboarding', 'tutorial'], run: (c) => TourDialog.show(c)),
        PaletteItem(id: 'app.shortcuts', title: 'Keyboard shortcuts', icon: Icons.keyboard_outlined, category: PaletteCategory.app, run: (c) => ShortcutsHelpDialog.show(c)),
      ];

  static List<PaletteItem> environments(EnvironmentsViewModel vm) => [
        for (final e in vm.environments)
          PaletteItem(
            id: 'env.${e.id}',
            title: 'Switch to ${e.name}',
            subtitle: e.isActive ? 'Active environment' : 'Environment',
            icon: e.isActive ? Icons.check_circle_outline : Icons.layers_outlined,
            category: PaletteCategory.environments,
            keywords: ['environment', e.name],
            run: (c) => c.read<EnvironmentsViewModel>().setActive(e.id),
          ),
        if (vm.environments.any((e) => e.isActive))
          PaletteItem(
            id: 'env.none',
            title: 'Use no environment',
            icon: Icons.layers_clear_outlined,
            category: PaletteCategory.environments,
            keywords: const ['environment', 'clear'],
            run: (c) => c.read<EnvironmentsViewModel>().clearActive(),
          ),
      ];

  /// Every request of every collection, searchable by name, method, URL and body.
  static Future<List<PaletteItem>> requests() async {
    final collections = await locator<CollectionLoader>().loadAll();
    final items = <PaletteItem>[];
    for (final loaded in collections) {
      final folders = {for (final f in loaded.folders) f.id: f.name};
      for (final r in loaded.requests) {
        final where = [loaded.collection.name, if (r.folderId != null && folders[r.folderId] != null) folders[r.folderId]!].join(' / ');
        items.add(PaletteItem(
          id: 'req.${r.id}',
          title: r.name,
          subtitle: '$where · ${r.url}',
          category: PaletteCategory.requests,
          badge: r.method.label,
          keywords: [r.method.label, r.url],
          hiddenText: '${r.url}\n${r.body.rawText}\n${r.body.graphqlQuery}',
          run: (c) => c.read<ShellViewModel>().selectRequest(r.id),
        ));
      }
    }
    return items;
  }
}
