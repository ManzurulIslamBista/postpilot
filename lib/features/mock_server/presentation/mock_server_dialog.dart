import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../device_helper/data/network_info.dart';
import '../../device_helper/presentation/device_helper_dialog.dart';
import 'mock_openapi_tab.dart';
import 'mock_requests_tab.dart';
import 'mock_routes_tab.dart';
import 'mock_scenarios_tab.dart';
import 'mock_server_view_model.dart';

/// An OpenAPI document chosen by the person, as text; null when the dialog was closed. A spec is rarely more than a few
/// megabytes, so a larger file is refused before it is read.
Future<String?> pickOpenApiText() async {
  const group = XTypeGroup(label: 'OpenAPI or Swagger document', extensions: ['json', 'yaml', 'yml']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('The file is larger than 20 MB; an API document is much smaller than that.');
  }
  return file.readAsString();
}

/// Serve a collection's saved examples, or an OpenAPI document, as a live API on this computer, so an app can be built
/// before its backend exists. Keeps running after the dialog is closed; the top bar shows it while it does.
class MockServerDialog extends StatefulWidget {
  final int? collectionId;

  /// Replaces the file dialog, for a test.
  @visibleForTesting
  final Future<String?> Function()? pickSpecFile;

  const MockServerDialog({super.key, this.collectionId, this.pickSpecFile});

  static Future<void> show(BuildContext context, {int? collectionId}) =>
      ToolDialog.show(context, (_) => MockServerDialog(collectionId: collectionId));

  @override
  State<MockServerDialog> createState() => _MockServerDialogState();
}

class _MockServerDialogState extends State<MockServerDialog> {
  final MockServerViewModel _vm = locator<MockServerViewModel>();
  late final _port = TextEditingController(text: _vm.portText);
  late final _delay = TextEditingController(text: '${_vm.delayMs}');
  late final _origin = TextEditingController(text: _vm.allowedOrigin);
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
    _origin.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, [String? what]) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${what ?? text}')));
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
        final fromSpec = _vm.source == MockSourceKind.openApi;
        return ToolDialog(
          icon: Icons.dns_outlined,
          title: 'Mock server',
          subtitle: 'Serve saved examples or an OpenAPI document as a live API on this computer',
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
              : collections.isEmpty && !fromSpec && _vm.spec == null
                  ? _noCollections(context)
                  : _layout(
                      context,
                      controls: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.end,
                            children: [
                              SegmentedButton<MockSourceKind>(
                                showSelectedIcon: false,
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                segments: [
                                  for (final k in MockSourceKind.values) ButtonSegment(value: k, label: Text(k.label, style: const TextStyle(fontSize: 12))),
                                ],
                                selected: {_vm.source},
                                onSelectionChanged: (s) => _vm.useSource(s.first),
                              ),
                              if (!fromSpec && collections.isNotEmpty)
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
                              SizedBox(
                                width: 250,
                                child: TextField(
                                  controller: _origin,
                                  enabled: !running && _vm.cors,
                                  autocorrect: false,
                                  decoration: const InputDecoration(labelText: 'Allowed origin', hintText: '* or http://localhost:5173'),
                                  onChanged: (v) => _vm.update(origin: v),
                                ),
                              ),
                              FilterChip(label: const Text('Allow other devices'), selected: _vm.allowOtherDevices, onSelected: running ? null : (v) => _vm.update(others: v)),
                              if (running && !fromSpec)
                                OutlinedButton.icon(onPressed: _vm.reload, icon: const Icon(Icons.refresh, size: 16), label: const Text('Reload examples')),
                              GradientButton(
                                label: running ? 'Stop' : 'Start',
                                icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                loading: _vm.isBusy,
                                onPressed: running ? _vm.stop : _vm.start,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_vm.allowsEveryWebsite)
                            const InfoBanner(
                              kind: BannerKind.warning,
                              title: 'Every website can read these answers',
                              message: 'CORS is on for any origin (*): while the server runs, any page open in your browser can fetch these '
                                  'responses from this computer. Put the origin of your app (for example http://localhost:5173) in Allowed origin to limit that, '
                                  'or switch CORS off.',
                              margin: EdgeInsets.only(bottom: 8),
                            ),
                          if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
                          if (running)
                            InfoBanner(
                              kind: BannerKind.success,
                              title: 'Serving ${_vm.routes.length} routes${fromSpec ? ' from ${_vm.spec?.title ?? 'the document'}' : ''}',
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
                          if (!fromSpec && _vm.table.skipped.isNotEmpty)
                            InfoBanner(
                              kind: BannerKind.warning,
                              message: '${_vm.table.skipped.length} request${_vm.table.skipped.length == 1 ? ' has' : 's have'} no saved example and ${_vm.table.skipped.length == 1 ? 'is' : 'are'} not served: '
                                  '${_vm.table.skipped.take(4).join(', ')}${_vm.table.skipped.length > 4 ? '…' : ''}. Send them and use "Save as example".',
                              margin: const EdgeInsets.only(bottom: 8),
                            ),
                      ],
                      tabs: ToolTabs(
                        tabs: [
                          ToolTab(
                            label: 'Routes',
                            icon: Icons.alt_route,
                            child: MockRoutesTab(vm: _vm, lanIp: _lanIp, onCopy: _copy),
                          ),
                          ToolTab(
                            label: 'From OpenAPI',
                            icon: Icons.description_outlined,
                            child: MockOpenApiTab(vm: _vm, pickFile: widget.pickSpecFile ?? pickOpenApiText),
                          ),
                          ToolTab(
                            label: 'Scenarios',
                            icon: Icons.bolt_outlined,
                            child: MockScenariosTab(vm: _vm),
                          ),
                          ToolTab(
                            label: 'Requests',
                            icon: Icons.history_toggle_off,
                            child: MockRequestsTab(vm: _vm, onCopy: _copy),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  /// The server controls above, the tabs below. On a phone the controls take at most two fifths of the height and scroll, so the tabs
  /// never end up squeezed to nothing by a row of chips.
  Widget _layout(BuildContext context, {required List<Widget> controls, required Widget tabs}) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: controls),
                  ),
                ),
                Expanded(flex: 3, child: tabs),
              ],
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...controls, Expanded(child: tabs)]),
    );
  }

  /// With no collection to serve, the OpenAPI source is still there: say so instead of showing a dead end.
  Widget _noCollections(BuildContext context) => EmptyHint(
        icon: Icons.folder_open,
        title: 'No collections yet',
        message: 'Create or import a collection, send its requests and save the responses as examples. '
            'Or serve an OpenAPI document, which needs no examples.',
        action: OutlinedButton.icon(
          onPressed: () => _vm.useSource(MockSourceKind.openApi),
          icon: const Icon(Icons.description_outlined, size: 16),
          label: const Text('Serve an OpenAPI document'),
        ),
      );
}
