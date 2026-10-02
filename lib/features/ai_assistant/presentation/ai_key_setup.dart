import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../data/ai_settings_store.dart';

/// Asks for the person's own Anthropic API key and the model to use. The key
/// is kept in the platform keychain, and only ever sent to api.anthropic.com.
class AiKeySetup extends StatefulWidget {
  /// Called after the key was saved or removed.
  final VoidCallback onChanged;
  final bool hasKey;

  const AiKeySetup({super.key, required this.onChanged, this.hasKey = false});

  @override
  State<AiKeySetup> createState() => _AiKeySetupState();
}

class _AiKeySetupState extends State<AiKeySetup> {
  final _store = locator<AiSettingsStore>();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _store.model().then((m) {
      if (mounted) _model.text = m;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_key.text.trim().isNotEmpty) await _store.saveApiKey(_key.text.trim());
    await _store.saveModel(_model.text);
    _key.clear();
    widget.onChanged();
  }

  Future<void> _remove() async {
    await _store.clearApiKey();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          title: widget.hasKey ? 'AI is set up' : 'Bring your own key',
          message: 'PostPilot sends only what you choose to the Anthropic API, with your own API key, billed to your account. '
              'Credentials in the request are masked first. The key stays in this device\'s keychain.',
          trailing: TextButton(
            onPressed: () => launchUrl(Uri.parse('https://console.anthropic.com/settings/keys')),
            child: const Text('Get a key'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: widget.hasKey ? 'New API key (leave empty to keep the saved one)' : 'Anthropic API key',
            hintText: 'sk-ant-…',
            prefixIcon: const Icon(Icons.key, size: 18),
            suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18), onPressed: () => setState(() => _obscure = !_obscure)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model', prefixIcon: Icon(Icons.memory, size: 18))),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Save')),
            const SizedBox(width: 8),
            if (widget.hasKey) TextButton(onPressed: _remove, child: Text('Remove key', style: TextStyle(color: colors.statusError))),
          ],
        ),
      ],
    );
  }
}
