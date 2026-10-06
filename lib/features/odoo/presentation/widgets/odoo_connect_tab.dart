import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../environments/presentation/view_models/environments_view_model.dart';
import '../../data/odoo_smart_resolver.dart';
import '../../domain/entities/odoo_connection.dart';
import '../view_models/odoo_studio_view_model.dart';

/// Connect to an Odoo server, test it, and save it as an environment so every request can use `{{odooUrl}}`,
/// `{{odooDb}}` and either `{{odooApiKey}}` (Odoo 19 and later, JSON-2 API) or `{{odooLogin}}` and `{{odooPassword}}`
/// (Odoo 18 and older, a JSON-RPC session).
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
  late final _login = TextEditingController(text: widget.viewModel.login);
  final _envName = TextEditingController();
  final _collectionName = TextEditingController(text: 'Odoo');
  final _models = TextEditingController(text: 'res.partner');
  bool _obscure = true;

  OdooStudioViewModel get _vm => widget.viewModel;
  bool get _jsonRpc => _vm.protocol == OdooProtocol.jsonRpc;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_syncFromViewModel);
  }

  /// The active environment's values arrive after the first frame.
  void _syncFromViewModel() {
    if (_url.text.isEmpty && _vm.url.isNotEmpty) _url.text = _vm.url;
    if (_db.text != _vm.database && (_db.text.isEmpty || _vm.databases.contains(_vm.database))) _db.text = _vm.database;
    if (_key.text.isEmpty && _vm.apiKey.isNotEmpty) _key.text = _vm.apiKey;
    if (_login.text.isEmpty && _vm.login.isNotEmpty) _login.text = _vm.login;
  }

  @override
  void dispose() {
    _vm.removeListener(_syncFromViewModel);
    for (final c in [_url, _db, _key, _login, _envName, _collectionName, _models]) {
      c.dispose();
    }
    super.dispose();
  }

  void _push() => _vm.setConnection(url: _url.text, database: _db.text, apiKey: _key.text, login: _login.text);

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
          InfoBanner(
            message: _jsonRpc
                ? 'Odoo 18 and older log in with a database, a login and a password (or an API key used as the password), then call '
                    '/web/dataset/call_kw/<model>/<method> with the session cookie. Studio keeps the session for you and logs in again once if it expires.'
                : 'Odoo 19 and later expose the External JSON-2 API at /json/2/<model>/<method>, authenticated with an API key '
                    '(Odoo: Preferences, Account Security, New API Key). The old XML-RPC and JSON-RPC endpoints are deprecated.',
          ),
          const SizedBox(height: 14),
          ToolSection(
            title: 'Server',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<OdooProtocol>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: OdooProtocol.json2, label: Text('Odoo 19+ · JSON-2', overflow: TextOverflow.ellipsis)),
                    ButtonSegment(value: OdooProtocol.jsonRpc, label: Text('Odoo ≤18 · JSON-RPC', overflow: TextOverflow.ellipsis)),
                  ],
                  selected: {_vm.protocol},
                  onSelectionChanged: (s) {
                    _vm.setConnection(protocol: s.first);
                    setState(() {});
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_vm.protocol.label, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://mycompany.odoo.com', prefixIcon: Icon(Icons.dns_outlined, size: 18)),
                  onChanged: (_) => _edited(),
                ),
                if (_vm.connection.sendsKeyUnencrypted) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    kind: BannerKind.warning,
                    title: 'This URL uses plain http://',
                    message: 'The ${_jsonRpc ? 'password' : 'API key'} is sent unencrypted, so anyone on the path to the server can read it. '
                        'Use https:// unless the server is on this computer or your own network.',
                  ),
                ],
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    final narrow = box.maxWidth < 560;
                    final database = _databaseField();
                    final secret = TextField(
                      controller: _key,
                      obscureText: _obscure,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _jsonRpc ? 'Password or API key' : 'API key',
                        prefixIcon: const Icon(Icons.key, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onChanged: (_) => _push(),
                    );
                    final login = TextField(
                      controller: _login,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Login', hintText: 'admin', prefixIcon: Icon(Icons.person_outline, size: 18)),
                      onChanged: (_) => _push(),
                    );
                    if (narrow) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [database, const SizedBox(height: 10), if (_jsonRpc) ...[login, const SizedBox(height: 10)], secret]);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: database), const SizedBox(width: 10), Expanded(child: _jsonRpc ? login : secret)]),
                        if (_jsonRpc) ...[const SizedBox(height: 10), secret],
                      ],
                    );
                  },
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
                      child: BusyLabel(busy: _vm.busyLabel == 'Testing connection', icon: Icons.bolt, label: _jsonRpc ? 'Log in and test' : 'Test connection', busyLabel: 'Testing…'),
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
            hint: _jsonRpc
                ? 'Stores odooUrl, odooDb, odooProtocol, odooLogin and odooPassword (secret) so requests use {{variables}}. Switch environment to switch server.'
                : 'Stores odooUrl, odooDb and odooApiKey (secret) so requests use {{variables}}. Switch environment to switch server.',
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
            hint: _jsonRpc
                ? 'A "Log in" request and, per model, search, read, create, update, delete, fields and more in the call_kw form. Separate models with commas.'
                : 'One folder per model with search, read, create, update, delete, fields and more. Separate models with commas.',
            child: LayoutBuilder(
              builder: (context, box) {
                final name = TextField(controller: _collectionName, decoration: const InputDecoration(labelText: 'Collection name'));
                final models = TextField(controller: _models, decoration: const InputDecoration(labelText: 'Models', hintText: 'res.partner, sale.order'));
                final create = FilledButton.icon(onPressed: _vm.isBusy ? null : _createRequests, icon: const Icon(Icons.library_add_outlined, size: 16), label: const Text('Create'));
                if (box.maxWidth < 560) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, const SizedBox(height: 10), models, const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: create)]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: name), const SizedBox(width: 10), Expanded(flex: 3, child: models), const SizedBox(width: 10), create]);
              },
            ),
          ),
          const ToolSection(
            title: 'Portable references',
            hint: 'In any Odoo request body write {{xmlid:base.main_company}} or {{ref:res.partner:Azure Interior}} where an id goes: PostPilot '
                'looks the id up on the server the request goes to when it is sent (also in the runner and the command line), so one request works on every database. '
                'A reference that cannot be found stops the request.',
            child: _ReferenceCache(),
          ),
        ],
      ),
    );
  }

  /// The database: typed, or picked from the list when the server gives one.
  Widget _databaseField() {
    final names = _vm.databases;
    final field = TextField(
      controller: _db,
      decoration: InputDecoration(
        labelText: _jsonRpc ? 'Database' : 'Database (optional)',
        helperText: _vm.databaseNote ?? (_jsonRpc ? 'Needed to log in' : 'Needed on servers with several databases'),
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.storage_outlined, size: 18),
        suffixIcon: PopupMenuButton<String>(
          icon: _vm.busyLabel == 'Finding databases'
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.manage_search, size: 18),
          tooltip: names.isEmpty ? 'Find the databases of this server' : 'Pick a database',
          enabled: !_vm.isBusy,
          onSelected: (v) {
            if (v == '\u0000find') {
              _push();
              _vm.findDatabases();
            } else {
              _db.text = v;
              _push();
              setState(() {});
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: '\u0000find', child: Text('Find the databases of this server')),
            for (final n in names) PopupMenuItem(value: n, child: Text(n)),
          ],
        ),
      ),
      onChanged: (_) => _push(),
    );
    return field;
  }
}

/// How many ids are remembered from smart references, and a button to forget them (a record was deleted and created again).
class _ReferenceCache extends StatefulWidget {
  const _ReferenceCache();

  @override
  State<_ReferenceCache> createState() => _ReferenceCacheState();
}

class _ReferenceCacheState extends State<_ReferenceCache> {
  @override
  Widget build(BuildContext context) {
    if (!locator.isRegistered<OdooSmartReferenceResolver>()) return const SizedBox.shrink();
    final resolver = locator<OdooSmartReferenceResolver>();
    final count = resolver.cachedCount;
    return Row(
      children: [
        Text(count == 0 ? 'Nothing looked up yet in this session.' : '$count looked-up id${count == 1 ? '' : 's'} remembered for ${resolver.ttl.inMinutes} minutes.', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: count == 0
              ? null
              : () {
                  resolver.clearCache();
                  setState(() {});
                },
          child: const Text('Forget them'),
        ),
      ],
    );
  }
}
