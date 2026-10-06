import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../data/mock_server_engine.dart';
import 'mock_server_view_model.dart';

/// Every request the server received: method, path, the route that matched, the scenario that was applied, the status and the time.
/// A row opens to the (masked) headers and bodies and can be copied as a cURL command.
class MockRequestsTab extends StatelessWidget {
  final MockServerViewModel vm;
  final Future<void> Function(String text, [String? what]) onCopy;

  const MockRequestsTab({super.key, required this.vm, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = vm.log;
    final port = vm.port;
    final base = 'http://localhost:${port ?? vm.portText}';
    if (entries.isEmpty) {
      return const EmptyHint(icon: Icons.history_toggle_off, title: 'Waiting for requests', message: 'Point your app at the server URL. Every call shows up here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${entries.length} request${entries.length == 1 ? '' : 's'}. Passwords, tokens and keys are masked here and in the cURL command.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ),
              TextButton(onPressed: vm.clearLog, child: const Text('Clear')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
            itemBuilder: (context, i) => _EntryTile(
              key: ValueKey('${entries[i].at.microsecondsSinceEpoch}-${entries[i].method}-${entries[i].path}-$i'),
              entry: entries[i],
              baseUrl: base,
              onCopy: onCopy,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  final MockLogEntry entry;
  final String baseUrl;
  final Future<void> Function(String text, [String? what]) onCopy;

  const _EntryTile({super.key, required this.entry, required this.baseUrl, required this.onCopy});

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final e = entry;
    final t = e.at;
    final detail = [
      e.route ?? 'No route matched',
      if (e.scenario != null) 'scenario: ${e.scenario}',
      if (e.preview.isNotEmpty) e.preview,
    ].join('  ·  ');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          Text('${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}', style: context.textStyles.mono.copyWith(fontSize: 11, color: colors.secondaryText)),
          const SizedBox(width: 8),
          Text(e.method, style: context.textStyles.mono.copyWith(color: colors.forMethod(e.method), fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(child: Text(e.path, overflow: TextOverflow.ellipsis, style: context.textStyles.mono)),
          const SizedBox(width: 8),
          Text(
            e.neverAnswered ? 'no answer' : '${e.status} · ${e.duration.inMilliseconds} ms',
            style: TextStyle(color: e.neverAnswered ? colors.statusWarning : colors.forStatus(e.status), fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
      subtitle: Text(
        detail,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: e.route == null ? colors.statusWarning : colors.secondaryText, fontSize: 11),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCopy(e.toCurl(baseUrl), 'cURL command'),
                icon: const Icon(Icons.terminal, size: 16),
                label: const Text('Copy as cURL'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(e.path, e.path),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Copy path'),
              ),
            ],
          ),
        ),
        if (e.requestHeaders.isNotEmpty) _block(context, 'Request headers', e.requestHeaders.entries.map((h) => '${h.key}: ${h.value}').join('\n')),
        if (e.requestBody.isNotEmpty) _block(context, 'Request body', e.requestBody),
        if (e.responseBody.isNotEmpty) _block(context, 'Answer body', e.responseBody),
        if (e.neverAnswered)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: InfoBanner(kind: BannerKind.warning, message: 'The timeout scenario held this connection open and sent nothing.'),
          ),
      ],
    );
  }

  Widget _block(BuildContext context, String title, String text) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: colors.border)),
            child: SingleChildScrollView(primary: false, child: SelectableText(text, style: context.textStyles.mono)),
          ),
        ],
      ),
    );
  }
}
