import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../environments/presentation/view_models/environments_view_model.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Connect to an Odoo server (version 19 and later, which has the JSON-2 API),
/// test it, and save it as an environment so every request can use
/// `{{odooUrl}}`, `{{odooDb}}` and `{{odooApiKey}}`.
class OdooConnectTab extends StatefulWidget {
  final OdooStudioViewModel viewModel;
  const OdooConnectTab({super.key, required this.viewModel});

  @override
  State<OdooConnectTab> createState() => _OdooConnectTabState();
}

class _OdooConnectTabState extends State<OdooConnectTab> {
  late final _url = TextEditingController(text: widget.viewModel.url);
  late final _db = TextEditingController(text: widget.viewModel.database);
  late final _key = TextEditingController(text: widget.viewModel.apiKey);
  final _envName = TextEditingController();
  final _collectionName = TextEditingController(text: 'Odoo');
  final _models = TextEditingController(text: 'res.partner');
  bool _obscure = true;

  OdooStudioViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_syncFromViewModel);
  }

  /// The active environment's values arrive after the first frame.
  void _syncFromViewModel() {
    if (_url.text.isEmpty && _vm.url.isNotEmpty) _url.text = _vm.url;
    if (_db.text.isEmpty && _vm.database.isNotEmpty) _db.text = _vm.database;
    if (_key.text.isEmpty && _vm.apiKey.isNotEmpty) _key.text = _vm.apiKey;
  }

  @override
  void dispose() {
    _vm.removeListener(_syncFromViewModel);
    for (final c in [_url, _db, _key, _envName, _collectionName, _models]) {
      c.dispose();
    }
    super.dispose();
  }

  void _push() => _vm.setConnection(url: _url.text, database: _db.text, apiKey: _key.text);

  /// Pushes the fields to the view model and refreshes what depends on the URL text
  /// (the plain-http warning, the Save button).
  void _edited() {
    _push();
    setState(() {});
  }

  String get _defaultEnvName {
    final host = Uri.tryParse(_url.text.contains('://') ? _url.text : 'https://${_url.text}')?.host ?? '';
    return 'Odoo · ${_db.text.trim().isNotEmpty ? _db.text.trim() : (host.isNotEmpty ? host : 'server')}';
  }

  Future<void> _saveEnvironment() async {
    _push();
    final name = _envName.text.trim().isEmpty ? _defaultEnvName : _envName.text.trim();
    final id = await _vm.saveEnvironment(name);
    if (id != null && mounted) {
      context.read<EnvironmentsViewModel>().watchVariables(id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Environment "$name" saved and selected, with the URL ${_vm.connection.normalizedUrl}')),
      );
    }
  }

  Future<void> _createRequests() async {
    final models = _models.text.split(RegExp(r'[,\s]+')).where((m) => m.isNotEmpty).toList();
    if (models.isEmpty) return;
    final result = await _vm.createCollection(_collectionName.text.trim().isEmpty ? 'Odoo' : _collectionName.text.trim(), models);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created ${result.requestCount} requests in "${_collectionName.text.trim()}"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            message: 'Odoo 19 and later expose the External JSON-2 API at /json/2/<model>/<method>, authenticated with an API key '
                '(Odoo: Preferences, Account Security, New API Key). The old XML-RPC and JSON-RPC endpoints are deprecated.',
          ),
          const SizedBox(height: 14),
          ToolSection(
            title: 'Server',
            child: Column(
              children: [
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://mycompany.odoo.com', prefixIcon: Icon(Icons.dns_outlined, size: 18)),
                  onChanged: (_) => _edited(),
                ),
                if (_vm.connection.sendsKeyUnencrypted) ...[
                  const SizedBox(height: 10),
                  const InfoBanner(
                    kind: BannerKind.warning,
                    title: 'This URL uses plain http://',
                    message: 'The API key is sent unencrypted, so anyone on the path to the server can read it. '
                        'Use https:// unless the server is on this computer or your own network.',
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _db,
                        decoration: const InputDecoration(labelText: 'Database (optional)', helperText: 'Needed on servers with several databases', prefixIcon: Icon(Icons.storage_outlined, size: 18)),
                        onChanged: (_) => _push(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _key,
                        obscureText: _obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          prefixIcon: const Icon(Icons.key, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        onChanged: (_) => _push(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _vm.isBusy
                          ? null
                          : () {
                              _push();
                              _vm.testConnection();
                            },
                      child: BusyLabel(busy: _vm.busyLabel == 'Testing connection', icon: Icons.bolt, label: 'Test connection', busyLabel: 'Testing…'),
                    ),
                    const SizedBox(width: 12),
                    if (_vm.connectionOk != null)
                      Expanded(child: Row(children: [Icon(Icons.check_circle, size: 16, color: colors.statusSuccess), const SizedBox(width: 6), Flexible(child: Text(_vm.connectionOk!, style: TextStyle(color: colors.statusSuccess)))])),
                  ],
                ),
                if (_vm.error != null) ...[
                  const SizedBox(height: 10),
                  InfoBanner(kind: BannerKind.error, title: _vm.errorInfo?.title, message: _vm.errorInfo?.hint ?? _vm.error!),
                ],
              ],
            ),
          ),
          ToolSection(
            title: 'Save as environment',
            hint: 'Stores odooUrl, odooDb and odooApiKey (secret) so requests use {{variables}}. Switch environment to switch server.',
            child: Row(
              children: [
                Expanded(child: TextField(controller: _envName, decoration: InputDecoration(labelText: 'Environment name', hintText: _defaultEnvName))),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: _vm.isBusy || _url.text.trim().isEmpty ? null : _saveEnvironment, icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Save and select')),
              ],
            ),
          ),
          ToolSection(
            title: 'Create ready-made requests',
            hint: 'One folder per model with search, read, create, update, delete, fields and more. Separate models with commas.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: TextField(controller: _collectionName, decoration: const InputDecoration(labelText: 'Collection name'))),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: TextField(controller: _models, decoration: const InputDecoration(labelText: 'Models', hintText: 'res.partner, sale.order'))),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: _vm.isBusy ? null : _createRequests, icon: const Icon(Icons.library_add_outlined, size: 16), label: const Text('Create')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
