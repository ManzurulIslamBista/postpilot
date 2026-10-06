import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/context_theme_extensions.dart';

enum AppShortcut {
  sendRequest(LogicalKeyboardKey.enter, 'Send current request'),
  newRequest(LogicalKeyboardKey.keyN, 'New request', browserReserved: true),
  focusSearch(LogicalKeyboardKey.keyK, 'Search collections'),
  closeRequest(LogicalKeyboardKey.keyW, 'Close current request', browserReserved: true),
  openHistory(LogicalKeyboardKey.keyH, 'Open history', shift: true),
  toggleSidebar(LogicalKeyboardKey.keyB, 'Show or hide the sidebar', browserReserved: true),
  findInResponse(LogicalKeyboardKey.keyF, 'Find in the response', browserReserved: true),
  commandPalette(LogicalKeyboardKey.keyP, 'Command palette: tools, requests, environments', shift: true, browserReserved: true),
  reopenClosedTab(LogicalKeyboardKey.keyT, 'Reopen the last closed request', shift: true, browserReserved: true),
  focusUrl(LogicalKeyboardKey.keyL, 'Focus the URL bar', browserReserved: true),
  nextTab(LogicalKeyboardKey.pageDown, 'Next request tab', browserReserved: true),
  previousTab(LogicalKeyboardKey.pageUp, 'Previous request tab', browserReserved: true),
  duplicateRequest(LogicalKeyboardKey.keyD, 'Duplicate the current request', browserReserved: true),
  saveResponseExample(LogicalKeyboardKey.keyS, 'Save the response as an example', shift: true, browserReserved: true),
  switchEnvironment(LogicalKeyboardKey.keyE, 'Switch environment', shift: true, browserReserved: true),
  runCollection(LogicalKeyboardKey.keyR, 'Run the current collection', shift: true, browserReserved: true);

  const AppShortcut(this.key, this.description, {this.shift = false, this.browserReserved = false});

  final LogicalKeyboardKey key;
  final String description;
  final bool shift;

  /// Ctrl/Cmd+N and Ctrl/Cmd+W belong to the browser (new window, close tab):
  /// a page never sees them and cannot cancel them, so on web they move to Alt.
  final bool browserReserved;

  static bool get _usesMeta =>
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

  bool get _usesAlt => kIsWeb && browserReserved;

  SingleActivator get activator => SingleActivator(
    key,
    control: !_usesAlt && !_usesMeta,
    meta: !_usesAlt && _usesMeta,
    alt: _usesAlt,
    shift: shift,
    includeRepeats: false,
  );

  String get keyLabel =>
      [if (_usesAlt) 'Alt' else if (_usesMeta) 'Cmd' else 'Ctrl', if (shift) 'Shift', key.keyLabel].join('+');
}

/// What each [AppShortcut] does. Built by the shell, which is the one place
/// that can reach every feature's view model; this file stays free of them.
final class ShortcutHandlers {
  final VoidCallback sendRequest;
  final VoidCallback newRequest;
  final VoidCallback focusSearch;
  final VoidCallback closeRequest;
  final VoidCallback openHistory;
  final VoidCallback toggleSidebar;
  final VoidCallback findInResponse;

  /// Optional so a screen that has no palette (or a test) need not provide one.
  final VoidCallback? openCommandPalette;
  final VoidCallback? reopenClosedTab;
  final VoidCallback? focusUrl;
  final VoidCallback? nextTab;
  final VoidCallback? previousTab;
  final VoidCallback? duplicateRequest;
  final VoidCallback? saveResponseExample;
  final VoidCallback? switchEnvironment;
  final VoidCallback? runCollection;

  const ShortcutHandlers({
    required this.sendRequest,
    required this.newRequest,
    required this.focusSearch,
    required this.closeRequest,
    required this.openHistory,
    required this.toggleSidebar,
    required this.findInResponse,
    this.openCommandPalette,
    this.reopenClosedTab,
    this.focusUrl,
    this.nextTab,
    this.previousTab,
    this.duplicateRequest,
    this.saveResponseExample,
    this.switchEnvironment,
    this.runCollection,
  });

  VoidCallback handlerFor(AppShortcut shortcut) => switch (shortcut) {
    AppShortcut.sendRequest => sendRequest,
    AppShortcut.newRequest => newRequest,
    AppShortcut.focusSearch => focusSearch,
    AppShortcut.closeRequest => closeRequest,
    AppShortcut.openHistory => openHistory,
    AppShortcut.toggleSidebar => toggleSidebar,
    AppShortcut.findInResponse => findInResponse,
    AppShortcut.commandPalette => openCommandPalette ?? () {},
    AppShortcut.reopenClosedTab => reopenClosedTab ?? () {},
    AppShortcut.focusUrl => focusUrl ?? () {},
    AppShortcut.nextTab => nextTab ?? () {},
    AppShortcut.previousTab => previousTab ?? () {},
    AppShortcut.duplicateRequest => duplicateRequest ?? () {},
    AppShortcut.saveResponseExample => saveResponseExample ?? () {},
    AppShortcut.switchEnvironment => switchEnvironment ?? () {},
    AppShortcut.runCollection => runCollection ?? () {},
  };
}

class AppShortcuts extends StatelessWidget {
  final ShortcutHandlers handlers;
  final Widget child;

  const AppShortcuts({super.key, required this.handlers, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {for (final shortcut in AppShortcut.values) shortcut.activator: handlers.handlerFor(shortcut)},
      // Key events only reach CallbackShortcuts from a focused descendant.
      // Blurring a text field hands focus to the nearest enclosing scope, so
      // without a scope of our own it would land on the route's scope — an
      // ancestor — and every binding would silently stop working.
      child: FocusScope(autofocus: true, child: child),
    );
  }
}

class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const ShortcutsHelpDialog());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      // Sixteen rows no longer fit a short window.
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final shortcut in AppShortcut.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(shortcut.description, style: context.textStyles.body)),
                    const SizedBox(width: 16),
                    _KeyCap(label: shortcut.keyLabel),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.appBackground,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: context.textStyles.mono.copyWith(fontSize: 12)),
    );
  }
}
