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
  toggleSidebar(LogicalKeyboardKey.keyB, 'Show or hide the sidebar', browserReserved: true);

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

  const ShortcutHandlers({
    required this.sendRequest,
    required this.newRequest,
    required this.focusSearch,
    required this.closeRequest,
    required this.openHistory,
    required this.toggleSidebar,
  });

  VoidCallback handlerFor(AppShortcut shortcut) => switch (shortcut) {
        AppShortcut.sendRequest => sendRequest,
        AppShortcut.newRequest => newRequest,
        AppShortcut.focusSearch => focusSearch,
        AppShortcut.closeRequest => closeRequest,
        AppShortcut.openHistory => openHistory,
        AppShortcut.toggleSidebar => toggleSidebar,
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
