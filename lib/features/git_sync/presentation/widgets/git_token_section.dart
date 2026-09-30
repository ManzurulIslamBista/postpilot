import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import 'git_widgets.dart';

const gitTokenCreationUrl = 'https://github.com/settings/personal-access-tokens/new';

class GitTokenSection extends StatefulWidget {
  final bool hasToken;
  final String? verifiedLogin;
  final bool isBusy;
  final Future<bool> Function(String token) onSave;
  final ValueChanged<String> onOpenLink;
  final String title;

  const GitTokenSection({
    super.key,
    required this.hasToken,
    required this.verifiedLogin,
    required this.isBusy,
    required this.onSave,
    required this.onOpenLink,
    this.title = 'GitHub access token',
  });

  @override
  State<GitTokenSection> createState() => _GitTokenSectionState();
}

class _GitTokenSectionState extends State<GitTokenSection> {
  final _controller = TextEditingController();
  bool _obscured = true;

  bool get _canSave => !widget.isBusy && _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final saved = await widget.onSave(_controller.text);
    if (saved && mounted) setState(_controller.clear);
  }

  @override
  Widget build(BuildContext context) {
    final textStyles = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.title, style: textStyles.body.copyWith(fontWeight: FontWeight.w600))),
            GitLinkText(label: 'Create a token', url: gitTokenCreationUrl, onOpen: widget.onOpenLink),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Use a fine-grained token: choose the repository and set the permission Contents: Read and write.',
          style: textStyles.caption.copyWith(color: context.colors.secondaryText),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.isBusy,
                obscureText: _obscured,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: widget.hasToken ? 'Paste a new token to replace the saved one' : 'Paste your token',
                  suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  suffixIcon: IconButton(
                    icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off, size: 18),
                    tooltip: _obscured ? 'Show token' : 'Hide token',
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _canSave ? _save : null, child: const Text('Save token')),
          ],
        ),
        const SizedBox(height: 6),
        _TokenStatus(hasToken: widget.hasToken, verifiedLogin: widget.verifiedLogin),
      ],
    );
  }
}

class _TokenStatus extends StatelessWidget {
  final bool hasToken;
  final String? verifiedLogin;
  const _TokenStatus({required this.hasToken, required this.verifiedLogin});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final login = verifiedLogin;
    final (text, icon, color) = login != null
        ? ('Signed in to GitHub as $login', Icons.check_circle_outline, colors.statusSuccess)
        : hasToken
            ? ('A token is saved on this device', Icons.check_circle_outline, colors.statusSuccess)
            : ('No token saved yet', Icons.info_outline, colors.secondaryText);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: context.textStyles.caption.copyWith(color: color))),
      ],
    );
  }
}
