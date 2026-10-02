import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/shortcuts/app_shortcuts.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/tool_dialog.dart';

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

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  const _Step(this.icon, this.title, this.body, this.points);
}

/// A short tour of what makes PostPilot different, shown once and always
/// reachable from the command palette.
class TourDialog extends StatefulWidget {
  const TourDialog({super.key});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const TourDialog());

  @override
  State<TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<TourDialog> {
  final _controller = PageController();
  int _page = 0;

  static final _steps = [
    const _Step(Icons.rocket_launch_outlined, 'Welcome to PostPilot', 'Design, send and test APIs, and keep them in a Git repository with your team.', [
      'Collections hold your requests; folders keep them tidy.',
      'Press New request, import from Postman, Insomnia, OpenAPI or cURL, or add a starter template.',
      'Everything you save is autosaved to your workspace folder.',
    ]),
    const _Step(Icons.send_rounded, 'Send a request', 'Pick a method, type a URL and press Send.', [
      'Paste a cURL command into the URL field: it fills the whole request.',
      'Use {{variables}} anywhere; hover one to see its value.',
      'Params, Headers, Body, Auth and Tests are one click away in the request tabs.',
    ]),
    const _Step(Icons.layers_outlined, 'Environments and safety', 'Switch between Dev, Staging and Production without editing requests.', [
      'An environment named Production turns red and asks before POST, PUT, PATCH or DELETE.',
      'Secret variables stay on your device, never in the workspace file Git carries.',
      'Chain requests: use a value from one response as a variable in the next.',
    ]),
    const _Step(Icons.auto_fix_high, 'Do more with a response', 'The wand beside a response opens the response tools.', [
      'Explore the JSON as a tree and pull values out with one click.',
      'Decode a JWT, compare with the previous response, check a JSON Schema.',
      'Generate Dart classes from the response, or write it up for an issue with secrets masked.',
    ]),
    _Step(Icons.manage_search, 'Everything is one shortcut away', 'Press ${AppShortcut.commandPalette.keyLabel} to search requests, tools and environments.', const [
      'Dart Studio: models and a whole API layer for Flutter.',
      'Odoo Studio, Mock server, Realtime (WebSocket / SSE), GraphQL explorer, Device helper.',
      'Starter templates and an optional AI helper that uses your own key.',
    ]),
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
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
