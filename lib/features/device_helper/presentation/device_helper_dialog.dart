import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../data/network_info.dart';
import '../domain/services/device_targets.dart';

/// "Why can't my phone reach localhost?" answered: the right host for each
/// kind of device, your computer's network addresses, a QR code to open the
/// server from a phone, and a URL rewriter.
class DeviceHelperDialog extends StatefulWidget {
  final String initialUrl;
  final int? initialPort;
  const DeviceHelperDialog({super.key, this.initialUrl = '', this.initialPort});

  static Future<void> show(BuildContext context, {String initialUrl = '', int? initialPort}) =>
      ToolDialog.show(context, (_) => DeviceHelperDialog(initialUrl: initialUrl, initialPort: initialPort));

  @override
  State<DeviceHelperDialog> createState() => _DeviceHelperDialogState();
}

class _DeviceHelperDialogState extends State<DeviceHelperDialog> {
  late final _url = TextEditingController(text: widget.initialUrl);
  late final _port = TextEditingController(text: '${widget.initialPort ?? DeviceTargets.portOf(widget.initialUrl)}');
  List<LocalAddress>? _addresses;
  String? _qrHost;

  @override
  void initState() {
    super.initState();
    listLocalAddresses().then((a) {
      if (mounted) {
        setState(() {
          _addresses = a;
          _qrHost = a.firstOrNull?.ip;
        });
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _port.dispose();
    super.dispose();
  }

  int get _portNumber => int.tryParse(_port.text.trim()) ?? 3000;

  Future<void> _copy(String text, [String? message]) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message ?? 'Copied $text')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final addresses = _addresses;
    final targets = DeviceTargets.forEmulators();
    final qrData = _qrHost == null ? null : 'http://$_qrHost:$_portNumber';
    // Any host stands in for the real ones: only the scheme of the rewritten URLs matters here.
    final rewriteSample = _url.text.trim().isEmpty ? null : DeviceTargets.rewrite(_url.text, 'x');
    return ToolDialog(
      icon: Icons.phonelink_setup,
      title: 'Device helper',
      subtitle: "Reach the server on your computer from an emulator or a real phone",
      width: 820,
      height: 640,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            message: 'On a phone or emulator, "localhost" means the phone itself, not your computer. '
                'Use the address below instead of localhost.',
          ),
          const SizedBox(height: 14),
          ToolSection(
            title: 'Emulators and simulators',
            child: Column(
              children: [
                for (final t in targets)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smartphone, size: 20, color: colors.mainAccent),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t.note, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    trailing: OutlinedButton(onPressed: () => _copy(t.host), child: Text(t.host, style: context.textStyles.mono)),
                  ),
              ],
            ),
          ),
          ToolSection(
            title: 'Real device on the same Wi-Fi',
            hint: addresses == null ? 'Looking up your network addresses…' : (addresses.isEmpty ? 'No network address found. Connect to Wi-Fi or Ethernet, or use the desktop app (a browser cannot list addresses).' : null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (addresses != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final a in addresses)
                        ChoiceChip(
                          label: Text('${a.ip}  ·  ${a.adapter}'),
                          selected: _qrHost == a.ip,
                          onSelected: (_) => setState(() => _qrHost = a.ip),
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Port'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (qrData != null)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                              child: QrImageView(data: qrData, size: 132, backgroundColor: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Scan with the phone camera', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  SelectableText(qrData, style: context.textStyles.mono.copyWith(color: colors.mainAccent)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'The server must listen on all interfaces (in the Mock server, tick "Allow other devices"), and the '
                                    "firewall must allow the port. The phone and this computer must be on the same network.",
                                    style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(onPressed: () => _copy(qrData), icon: const Icon(Icons.copy, size: 14), label: const Text('Copy address')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // The address above is http://, which Android and iOS refuse to open until the app allows it.
                if (qrData != null && DeviceTargets.usesCleartext(qrData)) ...const [
                  SizedBox(height: 12),
                  _CleartextNote(key: ValueKey('cleartext-note-device')),
                ],
              ],
            ),
          ),
          ToolSection(
            title: 'USB-connected Android phone',
            hint: 'Makes localhost on the phone point at this computer, with no network setup.',
            child: Row(
              children: [
                Expanded(child: SelectableText(DeviceTargets.adbReverse(_portNumber), style: context.textStyles.mono)),
                OutlinedButton.icon(onPressed: () => _copy(DeviceTargets.adbReverse(_portNumber), 'Command copied'), icon: const Icon(Icons.copy, size: 14), label: const Text('Copy')),
              ],
            ),
          ),
          ToolSection(
            title: 'Rewrite a URL',
            hint: 'Paste a URL that uses localhost and get the version for each device.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(hintText: 'http://localhost:3000/api/users', prefixIcon: Icon(Icons.link, size: 18)),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                if (_url.text.trim().isNotEmpty && DeviceTargets.rewrite(_url.text, 'x') == null)
                  const InfoBanner(kind: BannerKind.warning, message: 'That URL is built from a {{variable}}. Change the variable in your environment instead.')
                else if (_url.text.trim().isNotEmpty)
                  for (final entry in [
                    ('Android emulator', '10.0.2.2'),
                    if (_qrHost != null) ('Real device', _qrHost!),
                  ])
                    Builder(builder: (context) {
                      final rewritten = DeviceTargets.rewrite(_url.text, entry.$2)!;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: SelectableText(rewritten, style: context.textStyles.mono),
                        subtitle: Text(entry.$1, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                        trailing: IconButton(icon: const Icon(Icons.copy, size: 16), tooltip: 'Copy', onPressed: () => _copy(rewritten, 'URL copied')),
                      );
                    }),
                if (rewriteSample != null && DeviceTargets.usesCleartext(rewriteSample))
                  const Padding(padding: EdgeInsets.only(top: 8), child: _CleartextNote(key: ValueKey('cleartext-note-rewrite'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What an app needs before it may open an `http://` address on a phone.
class _CleartextNote extends StatelessWidget {
  const _CleartextNote({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner(
        kind: BannerKind.warning,
        title: 'Plain http:// needs a setting in your app',
        message: DeviceTargets.cleartextNote,
      );
}
