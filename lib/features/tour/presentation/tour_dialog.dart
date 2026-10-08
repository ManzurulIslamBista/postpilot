import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injector.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../command_palette/presentation/command_palette_dialog.dart';
import '../../command_palette/presentation/palette_items.dart';
import '../../environments/presentation/view_models/environments_view_model.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../../templates/domain/starter_templates.dart';
import '../../templates/domain/usecases/add_starter_template_usecase.dart';

/// Remembers that the welcome tour was shown, so it opens by itself only once.
class TourPrefs {
  static const _key = 'tour.seen.v1';

  /// False when the tour was never shown (or storage is unreadable: then it stays quiet, never nags).
  Future<bool> shouldAutoShow() async {
    try {
      return !((await SharedPreferences.getInstance()).getBool(_key) ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> markSeen() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }
}

/// What a step offers to do right now, so the tour is something to try and not only something to read.
enum _StepAction { addSample, openPalette }

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  final _StepAction? action;
  const _Step(this.icon, this.title, this.body, this.points, {this.action});
}

/// A short tour of what makes PostPilot different, shown once and always
/// reachable from the command palette.
class TourDialog extends StatefulWidget {
  /// Opens the command palette the way the rest of the app does (with the actions only the shell can perform);
  /// without it the step's button opens a palette of the tools, requests and environments.
  final VoidCallback? onOpenPalette;

  const TourDialog({super.key, this.onOpenPalette});

  static Future<void> show(BuildContext context, {VoidCallback? onOpenPalette}) =>
      ToolDialog.show(context, (_) => TourDialog(onOpenPalette: onOpenPalette));

  @override
  State<TourDialog> createState() => _TourDialogState();
}

// The browser keeps the workspace in its own storage and cannot run a mock server or listen for server-sent events.
const _autosaveNote = kIsWeb
    ? 'Everything you save is autosaved in this browser; Backup and restore (Settings, Data) keeps a copy.'
    : 'Everything you save is autosaved to your workspace folder.';
const _toolsNote = kIsWeb
    ? 'Odoo Studio, Realtime (WebSocket), GraphQL explorer, Device helper. The Mock server needs the desktop app.'
    : 'Odoo Studio, Mock server, Realtime (WebSocket / SSE), GraphQL explorer, Device helper.';

class _TourDialogState extends State<TourDialog> {
  final _controller = PageController();
  int _page = 0;
  bool _addingSample = false;

  static final _steps = [
    const _Step(Icons.rocket_launch_outlined, 'Welcome to PostPilot', 'Design, send and test APIs, and keep them in a Git repository with your team.', [
      'Collections hold your requests; folders keep them tidy.',
      'Press New request, import from Postman, Insomnia, OpenAPI or cURL, or add a starter template.',
      _autosaveNote,
    ], action: _StepAction.addSample),
    const _Step(Icons.send_rounded, 'Send a request', 'Pick a method, type a URL and press Send.', [
      'Paste a cURL command into the URL field: it fills the whole request.',
      'Use {{variables}} anywhere; hover one to see its value.',
      'Params, Headers, Body, Auth and Tests are one click away in the request tabs.',
      'The Tests tab also holds extractors: copy a value out of the response into a variable, and the next request can use it.',
    ]),
    const _Step(Icons.layers_outlined, 'Environments and safety', 'Switch between Dev, Staging and Production without editing requests.', [
      'An environment named Production turns red and asks before POST, PUT, PATCH or DELETE.',
      'Secret variables stay on your device, never in the workspace file Git carries.',
      'Chain requests: an extractor on the Tests tab saves a value from one response as a variable for the next.',
    ]),
    const _Step(Icons.auto_fix_high, 'Do more with a response', 'The wand beside a response opens the response tools.', [
      'Explore the JSON as a tree and pull values out with one click.',
      'Decode a JWT, compare with the previous response, check a JSON Schema.',
      'Generate Dart classes from the response, or write it up for an issue with secrets masked.',
    ]),
    _Step(Icons.manage_search, 'Everything is one shortcut away', 'Press ${AppShortcut.commandPalette.keyLabel} to search requests, tools and environments.', const [
      'Dart Studio: models and a whole API layer for Flutter.',
      _toolsNote,
      'Starter templates and an optional AI helper that uses your own key.',
    ], action: _StepAction.openPalette),
    const _Step(Icons.cloud_sync_outlined, 'Teams with Git', 'Connect a workplace to a GitHub repository and push and pull with your team.', [
      'Before every push you see what changed, and a commit message is written for you.',
      'If a teammate pushed first, you are warned instead of overwriting their work.',
      'Update a collection from a newer OpenAPI spec without losing your edits.',
    ]),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Adds the REST starter collection, opens its first request and closes the tour, so the next thing on screen is
  /// something to press Send on.
  Future<void> _addSample() async {
    setState(() => _addingSample = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final collections = context.read<CollectionsViewModel>();
    final shell = context.read<ShellViewModel>();
    try {
      final template = StarterTemplates.all().firstWhere((t) => t.id == 'rest');
      final added = await locator<AddStarterTemplateUseCase>()(template);
      collections.expandCollection(added.collectionId);
      final first = await collections.firstRequestId(added.collectionId);
      if (first != null) shell.selectRequest(first);
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Added "${template.title}" with ${added.requests} requests. Press Send on the open one to try it.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't add the sample collection: $e")));
      if (mounted) setState(() => _addingSample = false);
    }
  }

  /// Closes the tour and opens the palette; everything is read from before the pop, because the tour's own
  /// context is gone after it.
  void _openPalette() {
    final navigator = Navigator.of(context);
    final open = widget.onOpenPalette;
    final environments = open == null ? context.read<EnvironmentsViewModel>() : null;
    navigator.pop();
    if (open != null) {
      open();
      return;
    }
    CommandPaletteDialog.show(
      navigator.context,
      items: [...PaletteItems.tools(), ...PaletteItems.environments(environments!)],
      loadMore: PaletteItems.requests,
    );
  }

  Widget _actionButton(_StepAction action) => switch (action) {
    _StepAction.addSample => OutlinedButton(
      onPressed: _addingSample ? null : _addSample,
      child: BusyLabel(busy: _addingSample, icon: Icons.add, label: 'Add the sample collection', busyLabel: 'Adding the sample…'),
    ),
    _StepAction.openPalette => OutlinedButton.icon(
      onPressed: _openPalette,
      icon: const Icon(Icons.manage_search, size: 18),
      label: const Text('Open the command palette'),
    ),
  };

  void _go(int page) => _controller.animateToPage(page, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final last = _page == _steps.length - 1;
    return ToolDialog(
      icon: Icons.tour_outlined,
      title: 'Quick tour',
      subtitle: 'Step ${_page + 1} of ${_steps.length}',
      width: 640,
      height: 520,
      footerLeading: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              width: i == _page ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(color: i == _page ? colors.mainAccent : colors.border, borderRadius: BorderRadius.circular(4)),
            ),
        ],
      ),
      actions: [
        if (!last) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
        if (_page > 0) OutlinedButton(onPressed: () => _go(_page - 1), child: const Text('Back')),
        GradientButton(
          label: last ? 'Get started' : 'Next',
          icon: last ? Icons.check : Icons.arrow_forward_rounded,
          onPressed: last ? () => Navigator.of(context).pop() : () => _go(_page + 1),
        ),
      ],
      child: PageView(
        controller: _controller,
        onPageChanged: (p) => setState(() => _page = p),
        children: [
          for (final s in _steps)
            Padding(
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(gradient: colors.accentGradient, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: colors.glow, blurRadius: 24, spreadRadius: -6)]),
                      child: Icon(s.icon, size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(s.title, style: context.textStyles.heading.copyWith(fontSize: 22, letterSpacing: -0.3)),
                    const SizedBox(height: 8),
                    Text(s.body, style: context.textStyles.body.copyWith(fontSize: 14.5, color: colors.secondaryText, height: 1.4)),
                    const SizedBox(height: 18),
                    for (final p in s.points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_circle, size: 17, color: colors.statusSuccess)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(p, style: context.textStyles.body.copyWith(fontSize: 14, height: 1.35))),
                          ],
                        ),
                      ),
                    if (s.action != null) ...[const SizedBox(height: 8), _actionButton(s.action!)],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
