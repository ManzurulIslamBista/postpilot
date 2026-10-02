import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/method_badge.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../device_helper/data/network_info.dart';
import '../../device_helper/presentation/device_helper_dialog.dart';
import 'mock_server_view_model.dart';

/// Serve a collection's saved examples as a real HTTP API on this computer, so
/// an app can be built before its backend exists. Keeps running after the
/// dialog is closed; the top bar shows it while it does.
class MockServerDialog extends StatefulWidget {
  final int? collectionId;
  const MockServerDialog({super.key, this.collectionId});

  static Future<void> show(BuildContext context, {int? collectionId}) =>
      ToolDialog.show(context, (_) => MockServerDialog(collectionId: collectionId));

  @override
  State<MockServerDialog> createState() => _MockServerDialogState();
}

class _MockServerDialogState extends State<MockServerDialog> {
  final MockServerViewModel _vm = locator<MockServerViewModel>();
  late final _port = TextEditingController(text: _vm.portText);
  late final _delay = TextEditingController(text: '${_vm.delayMs}');
  String? _lanIp;

  @override
  void initState() {
    super.initState();
    final collections = context.read<CollectionsViewModel>().collections;
    if (widget.collectionId != null && !_vm.isRunning) {
      _vm.collectionId = widget.collectionId;
    } else {
      _vm.collectionId ??= collections.firstOrNull?.id;
    }
    listLocalAddresses().then((a) {
      if (mounted) setState(() => _lanIp = a.firstOrNull?.ip);
    });
  }

  @override
  void dispose() {
    _port.dispose();
    _delay.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $text')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collections = context.watch<CollectionsViewModel>().collections;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final running = _vm.isRunning;
        final localUrl = 'http://localhost:${_vm.port}';
        return ToolDialog(
          icon: Icons.dns_outlined,
          title: 'Mock server',
          subtitle: 'Serve saved examples as a live API on this computer',
          width: 960,
          height: 680,
          headerActions: [
            if (running)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: colors.statusSuccess.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: colors.statusSuccess),
                  const SizedBox(width: 6),
                  Text('Running on :${_vm.port}', style: TextStyle(color: colors.statusSuccess, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
          ],
          child: !_vm.isSupported
              ? const EmptyHint(
                  icon: Icons.web_asset_off,
                  title: 'Not available in the browser',
                  message: 'A browser cannot listen on a port. Use the desktop or mobile app to run a mock server.',
                )
              : collections.isEmpty
                  ? const EmptyHint(icon: Icons.folder_open, title: 'No collections yet', message: 'Create or import a collection, send its requests and save the responses as examples.')
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.end,
                            children: [
                              SizedBox(
                                width: 230,
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey('${_vm.collectionId}$running'),
                                  initialValue: collections.any((c) => c.id == _vm.collectionId) ? _vm.collectionId : collections.first.id,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Collection'),
                                  items: [for (final c in collections) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                                  onChanged: running ? null : (id) => _vm.update(collection: id),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: _port,
                                  enabled: !running,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(labelText: 'Port'),
                                  onChanged: (v) => _vm.update(port: v),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _delay,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(labelText: 'Delay', suffixText: 'ms'),
                                  onChanged: (v) => _vm.update(delay: int.tryParse(v) ?? 0),
                                ),
                              ),
                              FilterChip(label: const Text('CORS'), selected: _vm.cors, onSelected: running ? null : (v) => _vm.update(corsOn: v)),
                              FilterChip(label: const Text('Allow other devices'), selected: _vm.allowOtherDevices, onSelected: running ? null : (v) => _vm.update(others: v)),
                              if (running)
                                OutlinedButton.icon(onPressed: _vm.reload, icon: const Icon(Icons.refresh, size: 16), label: const Text('Reload examples'))
                              else
                                const SizedBox.shrink(),
                              GradientButton(
                                label: running ? 'Stop' : 'Start',
                                icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                loading: _vm.isBusy,
                                onPressed: running ? _vm.stop : _vm.start,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
                          if (running)
                            InfoBanner(
                              kind: BannerKind.success,
                              title: 'Serving ${_vm.table.routes.length} routes',
                              message: _vm.allowOtherDevices && _lanIp != null ? '$localUrl     or from another device: http://$_lanIp:${_vm.port}' : localUrl,
                              margin: const EdgeInsets.only(bottom: 8),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(icon: const Icon(Icons.copy, size: 16), tooltip: 'Copy URL', onPressed: () => _copy(localUrl)),
                                  IconButton(
                                    icon: const Icon(Icons.phonelink_setup, size: 18),
                                    tooltip: 'Open on a phone or emulator',
                                    onPressed: () => DeviceHelperDialog.show(context, initialPort: _vm.port),
                                  ),
                                ],
                              ),
                            ),
                          if (_vm.table.skipped.isNotEmpty)
                            InfoBanner(
                              kind: BannerKind.warning,
                              message: '${_vm.table.skipped.length} request${_vm.table.skipped.length == 1 ? ' has' : 's have'} no saved example and ${_vm.table.skipped.length == 1 ? 'is' : 'are'} not served: '
                                  '${_vm.table.skipped.take(4).join(', ')}${_vm.table.skipped.length > 4 ? '…' : ''}. Send them and use "Save as example".',
                              margin: const EdgeInsets.only(bottom: 8),
                            ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final routes = _routes(context);
                                final log = _log(context);
                                return c.maxWidth >= 760
                                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 5, child: routes), const SizedBox(width: 12), Expanded(flex: 5, child: log)])
                                    : Column(children: [Expanded(child: routes), const SizedBox(height: 10), Expanded(child: log)]);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  Widget _panel(BuildContext context, String title, Widget child, {Widget? trailing}) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              Text(title.toUpperCase(), style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 10.5)),
              const Spacer(),
              ?trailing,
            ]),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _routes(BuildContext context) {
    final routes = _vm.table.routes;
    return _panel(
      context,
      'Routes (${routes.length})',
      routes.isEmpty
          ? const EmptyHint(icon: Icons.alt_route, title: 'No routes yet', message: 'Press Start. Routes come from the saved examples of the collection\'s requests.')
          : ListView.builder(
              itemCount: routes.length,
              itemBuilder: (context, i) {
                final r = routes[i];
                return ListTile(
                  dense: true,
                  leading: MethodBadge(method: r.method, width: 44),
                  title: Text(r.path, style: context.textStyles.mono),
                  subtitle: Text('${r.requestName}${r.exampleName.isEmpty ? '' : ' · ${r.exampleName}'}', style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
                  trailing: Text('${r.status}', style: TextStyle(color: context.colors.forStatus(r.status), fontWeight: FontWeight.w700)),
                );
              },
            ),
    );
  }

  Widget _log(BuildContext context) {
    final entries = _vm.log;
    final colors = context.colors;
    return _panel(
      context,
      'Requests received (${entries.length})',
      entries.isEmpty
          ? const EmptyHint(icon: Icons.history_toggle_off, title: 'Waiting for requests', message: 'Point your app at the server URL. Every call shows up here.')
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
              itemBuilder: (context, i) {
                final e = entries[i];
                final t = e.at;
                String two(int n) => n.toString().padLeft(2, '0');
                return ListTile(
                  dense: true,
                  leading: Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)}', style: context.textStyles.mono.copyWith(fontSize: 11, color: colors.secondaryText)),
                  title: Row(children: [
                    Text(e.method, style: context.textStyles.mono.copyWith(color: colors.forMethod(e.method), fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.path, overflow: TextOverflow.ellipsis, style: context.textStyles.mono)),
                  ]),
                  subtitle: e.route == null ? Text('No route matched', style: TextStyle(color: colors.statusWarning, fontSize: 11)) : null,
                  trailing: Text('${e.status} · ${e.duration.inMilliseconds} ms', style: TextStyle(color: colors.forStatus(e.status), fontWeight: FontWeight.w600, fontSize: 12)),
                );
              },
            ),
      trailing: entries.isEmpty ? null : TextButton(onPressed: _vm.clearLog, child: const Text('Clear')),
    );
  }
}
