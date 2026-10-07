import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../device_helper/domain/services/device_targets.dart';
import '../domain/services/recorder_connect.dart';
import 'traffic_recorder_view_model.dart';

/// What to put in the app: the address of the running recorder, big, with a copy button, and the variants for an Android
/// emulator, a phone on USB (`adb reverse`) and a phone on the same Wi-Fi.
class RecorderConnectPanel extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final Future<void> Function(String text, [String? what]) onCopy;

  const RecorderConnectPanel({super.key, required this.vm, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = vm.primaryUrl;
    if (url == null) return const SizedBox.shrink();
    final options = vm.connectOptions;
    final qrOption = options.where((o) => o.available && o.command == null && o.url.isNotEmpty && !o.url.contains('localhost') && !o.url.contains('10.0.2.2')).firstOrNull;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    return Container(
      key: const ValueKey('recorder-connect-panel'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      decoration: BoxDecoration(
        color: colors.statusSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.statusSuccess.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APP-FACING URL',
            style: caption.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  key: const ValueKey('recorder-primary-url'),
                  style: context.textStyles.mono.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: colors.mainAccent),
                ),
              ),
              IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: 'Copy URL', onPressed: () => onCopy(url)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: Text(
              'Ask the app to use this: set its API base URL to this address, use the app, and every call it makes appears below. '
              'Forwarding to ${vm.baseUrl ?? ''}.',
              style: context.textStyles.body,
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('connect-more-${vm.listensForOtherDevices}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8, right: 8),
              dense: true,
              initiallyExpanded: vm.listensForOtherDevices,
              title: Text('Emulator, USB phone and Wi-Fi phone addresses', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
              children: [
                for (final option in options) _OptionRow(option: option, onCopy: onCopy),
                if (qrOption != null) _QrBlock(url: qrOption.url, onCopy: onCopy),
                if (DeviceTargets.usesCleartext(url))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: InfoBanner(
                      kind: BannerKind.warning,
                      title: 'Plain http:// needs a setting in your app',
                      message: DeviceTargets.cleartextNote,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final RecorderConnectOption option;
  final Future<void> Function(String text, [String? what]) onCopy;
  const _OptionRow({required this.option, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    Widget copyLine(String text, String what) => Row(
          children: [
            Expanded(child: SelectableText(text, style: mono.copyWith(color: option.available ? colors.mainAccent : colors.secondaryText))),
            if (option.available) IconButton(icon: const Icon(Icons.copy, size: 16), tooltip: 'Copy $what', visualDensity: VisualDensity.compact, onPressed: () => onCopy(text, what)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Opacity(
        opacity: option.available ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(option.label, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
            Text(option.note, style: caption),
            if (option.command != null) copyLine(option.command!, 'command'),
            if (option.url.isNotEmpty) copyLine(option.url, 'URL'),
          ],
        ),
      ),
    );
  }
}

class _QrBlock extends StatelessWidget {
  final String url;
  final Future<void> Function(String text, [String? what]) onCopy;
  const _QrBlock({required this.url, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: QrImageView(data: url, size: 104, backgroundColor: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Scan with the phone camera to copy the address ($url) onto the phone, then paste it where the app asks for the server.',
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
