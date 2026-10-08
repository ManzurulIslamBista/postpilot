import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/presentation/view_models/collections_view_model.dart';
import '../../shell/presentation/shell_view_model.dart';
import '../data/recorder_engine.dart';
import 'exchange_detail_pane.dart';
import 'exchange_table.dart';
import 'recorder_connect_panel.dart';
import 'recording_collection_dialog.dart';
import 'traffic_recorder_view_model.dart';

/// Record the calls an app really makes, without Charles, a certificate or a system proxy setting: the app's base URL is
/// pointed at a recorder on this computer, which forwards every call to the real server and keeps a copy. Keeps recording
/// after the dialog is closed.
class TrafficRecorderDialog extends StatefulWidget {
  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final TrafficRecorderViewModel? viewModel;

  const TrafficRecorderDialog({super.key, this.viewModel});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const TrafficRecorderDialog());

  @override
  State<TrafficRecorderDialog> createState() => _TrafficRecorderDialogState();
}

class _TrafficRecorderDialogState extends State<TrafficRecorderDialog> {
  late final TrafficRecorderViewModel _vm = widget.viewModel ?? locator<TrafficRecorderViewModel>();
  late final _upstream = TextEditingController(text: _vm.upstreamText);
  late final _port = TextEditingController(text: _vm.portText);
  late final _filter = TextEditingController(text: _vm.filter);

  @override
  void dispose() {
    _upstream.dispose();
    _port.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, [String? what]) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${what ?? text}')));
  }

  /// Opens the call as a new request in the first collection (a "My collection" is made on a fresh install), with no
  /// credential in it.
  Future<void> _resend(RecordedExchange exchange) async {
    final collections = context.read<CollectionsViewModel>();
    final shell = context.read<ShellViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final draft = _vm.resendRequestFor(exchange);
    try {
      final target = await collections.ensureCollection();
      final id = await collections.createRequestFrom(target.id, draft.request);
      collections.expandCollection(target.id);
      shell.selectRequest(id);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
          draft.secrets.isEmpty
              ? 'Opened as a new request.'
              : 'Opened as a new request. ${draft.secrets.map((s) => '{{$s}}').join(', ')} stand for the secret values: '
                  'add them to an environment before you send it.',
        ),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't open the call as a request (${error.runtimeType}).")));
    }
  }

  Future<void> _saveHar() async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await _vm.saveHar();
    messenger.showSnackBar(SnackBar(
      content: Text(path == null ? (_vm.error ?? 'Nothing was saved.') : 'Saved the recording as $path (credentials masked).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final running = _vm.isRunning;
        return ToolDialog(
          icon: Icons.sensors,
          title: 'Traffic recorder',
          subtitle: 'Record the calls your app really makes and turn them into a collection',
          width: 1100,
          height: 760,
          headerActions: [
            if (running)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_vm.paused ? colors.statusWarning : colors.statusSuccess).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_vm.paused ? Icons.pause_circle : Icons.circle, size: 8, color: _vm.paused ? colors.statusWarning : colors.statusSuccess),
                  const SizedBox(width: 6),
                  Text(
                    _vm.paused ? 'Paused :${_vm.port}' : 'Recording :${_vm.port}',
                    style: TextStyle(color: _vm.paused ? colors.statusWarning : colors.statusSuccess, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ]),
              ),
          ],
          child: !_vm.isSupported
              ? EmptyHint(
                  icon: Icons.web_asset_off,
                  title: 'Not available in the browser',
                  message: PlatformFeature.trafficRecorder.reason(web: true)!,
                )
              : _layout(context, controls: _controls(context, running), body: _panel(context, running)),
        );
      },
    );
  }

  /// The controls above, the table below. The controls take at most as much height as they need and never more than 45% (40%
  /// on a phone), and scroll beyond that, so the table never ends up squeezed to nothing by a row of chips or the connect panel.
  Widget _layout(BuildContext context, {required List<Widget> controls, required Widget body}) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * (narrow ? 0.4 : 0.45)),
              child: SingleChildScrollView(primary: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: controls)),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  List<Widget> _controls(BuildContext context, bool running) {
    Widget chip(String label, String tip, bool selected, ValueChanged<bool> onChanged) => Tooltip(
          message: tip,
          child: FilterChip(label: Text(label), selected: selected, onSelected: running ? null : onChanged),
        );
    return [
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: _upstream,
              enabled: !running,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Upstream: the real server', hintText: 'https://api.example.com'),
              onChanged: (v) => _vm.upstreamText = v,
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
              onChanged: (v) => _vm.portText = v,
            ),
          ),
          chip(
            'Also reachable from phones on my network',
            'Listens on every network interface so a phone on the same Wi-Fi can use it. Anyone on that network can then use it too.',
            _vm.allowOtherDevices,
            (v) => setState(() => _vm.allowOtherDevices = v),
          ),
          chip(
            'Allow a self-signed upstream',
            'Accept the real server\'s TLS certificate even when it is self-signed or expired. Only for that one server. Use it for test servers.',
            _vm.allowSelfSigned,
            (v) => setState(() => _vm.allowSelfSigned = v),
          ),
          chip(
            'Rewrite Host, Origin and Referer',
            'Send the real server\'s address in Host, and replace the recorder\'s address in Origin and Referer, so a server that checks them accepts the call.',
            _vm.rewriteHostHeaders,
            (v) => setState(() => _vm.rewriteHostHeaders = v),
          ),
          chip(
            'Ask for gzip, not brotli',
            'The recorder can read gzip and deflate but not brotli. With this on the real server is asked for gzip, so the recording is readable. '
                'What it answers is still passed to the app unchanged.',
            _vm.keepResponsesReadable,
            (v) => setState(() => _vm.keepResponsesReadable = v),
          ),
          GradientButton(
            label: running ? 'Stop' : 'Start',
            icon: running ? Icons.stop_rounded : Icons.fiber_manual_record,
            loading: _vm.isBusy,
            onPressed: running ? _vm.stop : _vm.start,
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_vm.allowOtherDevices)
        const InfoBanner(
          kind: BannerKind.warning,
          title: 'Reachable from your network',
          message: 'While it runs, any device on your Wi-Fi can send calls to your real server through this computer, with whatever '
              'credentials those calls carry. Use it on a network you trust and stop it when you are done. Windows may ask to allow '
              'access: choose Private networks.',
          margin: EdgeInsets.only(bottom: 8),
        ),
      if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
      if (running)
        RecorderConnectPanel(vm: _vm, onCopy: _copy)
      else
        const InfoBanner(
          title: 'How it works',
          message: 'Point your app at the recorder instead of the real server. The recorder forwards every call to the real server, '
              'hands the answer back unchanged and keeps a copy. No certificate and no system proxy setting are needed.',
          margin: EdgeInsets.only(bottom: 8),
        ),
    ];
  }

  Widget _panel(BuildContext context, bool running) {
    final colors = context.colors;
    final rows = _vm.visible;
    if (_vm.recordedCount == 0) {
      return EmptyHint(
        icon: Icons.sensors,
        title: running ? (_vm.paused ? 'Recording is paused' : 'Waiting for the app') : 'Nothing recorded yet',
        message: running
            ? 'Use the app now. Each call shows up here as soon as it has finished.'
            : 'Start the recorder and point your app at the address it shows.',
      );
    }
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final ticked = _vm.checkedIds.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _filter,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Filter by method, path or status',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: _vm.setFilter,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${rows.length == _vm.recordedCount ? '${rows.length} call${rows.length == 1 ? '' : 's'}' : '${rows.length} of ${_vm.recordedCount} calls'}'
              '${ticked > 0 ? ', $ticked ticked' : ''}'
              '${_vm.buffer.dropped > 0 ? ', ${_vm.buffer.dropped} oldest dropped' : ''}'
              '${_vm.paused && _vm.missedWhilePaused > 0 ? ', ${_vm.missedWhilePaused} not recorded while paused' : ''}',
              style: caption,
            ),
            TextButton.icon(
              onPressed: running ? _vm.togglePause : null,
              icon: Icon(_vm.paused ? Icons.play_arrow : Icons.pause, size: 16),
              label: Text(_vm.paused ? 'Resume' : 'Pause'),
            ),
            TextButton.icon(onPressed: _vm.clear, icon: const Icon(Icons.delete_sweep_outlined, size: 16), label: const Text('Clear')),
            Tooltip(
              message: 'Shows tokens and passwords in this window and in "Copy as cURL" for this session only. '
                  'Nothing saved or exported ever holds them.',
              child: FilterChip(
                label: const Text('Show real values'),
                avatar: Icon(Icons.visibility_outlined, size: 16, color: _vm.showRealValues ? colors.statusWarning : null),
                selected: _vm.showRealValues,
                onSelected: _vm.setShowRealValues,
              ),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty ? null : () => RecordingCollectionDialog.show(context, _vm),
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: Text(ticked > 0 ? 'Create collection ($ticked)…' : 'Create collection…'),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty ? null : _saveHar,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Save as HAR'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? const EmptyHint(icon: Icons.filter_alt_off, title: 'No call matches the filter')
              : LayoutBuilder(builder: (context, constraints) => _tableAndDetail(context, constraints, rows)),
        ),
      ],
    );
  }

  Widget _tableAndDetail(BuildContext context, BoxConstraints constraints, List<RecordedExchange> rows) {
    final colors = context.colors;
    final selected = _vm.selected;
    final table = DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ExchangeTable(vm: _vm, rows: rows)),
    );
    ExchangeDetailPane detail({VoidCallback? onBack}) => ExchangeDetailPane(
          vm: _vm,
          exchange: selected!,
          onBack: onBack,
          onResend: _resend,
          onCopy: _copy,
        );
    if (constraints.maxWidth >= 760) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: table),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(10)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: selected == null
                    ? const EmptyHint(icon: Icons.touch_app_outlined, title: 'Pick a call', message: 'Select a row to see what the app sent and what it got back.')
                    : detail(),
              ),
            ),
          ),
        ],
      );
    }
    return selected == null ? table : detail(onBack: () => _vm.select(null));
  }
}
