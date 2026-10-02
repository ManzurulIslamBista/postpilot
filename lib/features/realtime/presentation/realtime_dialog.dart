import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../data/realtime_session.dart';
import 'realtime_view_model.dart';

/// Talk to a WebSocket or listen to a Server-Sent Events stream, live. The
/// connection lives as long as the dialog; every message in and out is logged.
class RealtimeDialog extends StatefulWidget {
  final String initialUrl;
  const RealtimeDialog({super.key, this.initialUrl = ''});

  static Future<void> show(BuildContext context, {String initialUrl = ''}) =>
      ToolDialog.show(context, (_) => RealtimeDialog(initialUrl: initialUrl), barrierDismissible: false);

  @override
  State<RealtimeDialog> createState() => _RealtimeDialogState();
}

class _RealtimeDialogState extends State<RealtimeDialog> {
  late final RealtimeViewModel _vm = locator<RealtimeViewModel>();
  late final _url = TextEditingController(text: widget.initialUrl);
  final _headers = TextEditingController();
  final _protocols = TextEditingController();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;
  final _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _vm.url = widget.initialUrl;
    _vm.addListener(_stickToBottom);
  }

  @override
  void dispose() {
    _vm.removeListener(_stickToBottom);
    _vm.dispose();
    for (final c in [_url, _headers, _protocols, _composer]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _stickToBottom() {
    if (_vm.messages.length == _shown) return;
    final wasAtBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
    _shown = _vm.messages.length;
    if (!wasAtBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _send() {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    _vm.send(text);
    _composer.clear();
  }

  void _formatJson() {
    try {
      _composer.text = const JsonEncoder.withIndent('  ').convert(jsonDecode(_composer.text));
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That is not valid JSON')));
    }
  }

  String _pretty(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final connected = _vm.isConnected;
        final connecting = _vm.status == RealtimeStatus.connecting;
        final (statusText, statusColor) = switch (_vm.status) {
          RealtimeStatus.connected => ('Connected', colors.statusSuccess),
          RealtimeStatus.connecting => ('Connecting…', colors.statusWarning),
          RealtimeStatus.disconnected => ('Disconnected', colors.secondaryText),
        };
        return ToolDialog(
          icon: Icons.swap_vert_circle_outlined,
          title: 'Realtime',
          subtitle: 'WebSocket and Server-Sent Events',
          width: 960,
          height: 700,
          headerActions: [
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: statusColor),
                const SizedBox(width: 6),
                Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final modePicker = SegmentedButton<RealtimeMode>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: RealtimeMode.webSocket, label: Text('WebSocket')),
                        ButtonSegment(value: RealtimeMode.sse, label: Text('SSE')),
                      ],
                      selected: {_vm.mode},
                      onSelectionChanged: connected || connecting ? null : (s) => _vm.setMode(s.first),
                    );
                    final urlField = TextField(
                      controller: _url,
                      enabled: !connected && !connecting,
                      style: context.textStyles.mono,
                      decoration: InputDecoration(
                        hintText: _vm.mode == RealtimeMode.webSocket ? 'wss://echo.websocket.org  or  {{baseUrl}}/websocket' : 'https://example.com/events',
                        prefixIcon: const Icon(Icons.link, size: 18),
                      ),
                      onChanged: (v) => _vm.url = v,
                      onSubmitted: (_) => connected ? null : _vm.connect(),
                    );
                    final connectButton = connected || connecting
                        ? OutlinedButton.icon(onPressed: _vm.disconnect, icon: const Icon(Icons.link_off, size: 16), label: const Text('Disconnect'))
                        : GradientButton(label: 'Connect', icon: Icons.bolt, onPressed: _vm.connect);
                    // Phone width: the mode picker and button share a line (wrapping if even that is too tight) and the URL gets the full width below.
                    if (box.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [modePicker, connectButton],
                          ),
                          const SizedBox(height: 10),
                          urlField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        modePicker,
                        const SizedBox(width: 10),
                        Expanded(child: urlField),
                        const SizedBox(width: 10),
                        connectButton,
                      ],
                    );
                  },
                ),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Headers and options', style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      TextField(
                        controller: _headers,
                        enabled: !connected,
                        minLines: 2,
                        maxLines: 5,
                        style: context.textStyles.mono,
                        decoration: const InputDecoration(labelText: 'Headers (one per line)', hintText: 'Authorization: Bearer {{token}}'),
                        onChanged: (v) => _vm.headersText = v,
                      ),
                      if (_vm.mode == RealtimeMode.webSocket) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _protocols,
                          enabled: !connected,
                          decoration: const InputDecoration(labelText: 'Sub-protocols (comma separated)', hintText: 'graphql-ws, v1.json'),
                          onChanged: (v) => _vm.protocolsText = v,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_vm.error != null) InfoBanner(kind: BannerKind.error, message: _vm.error!, margin: const EdgeInsets.only(bottom: 8)),
                // Wraps instead of overflowing when the counters and both buttons do not fit on one line.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${_vm.received} received · ${_vm.sent} sent', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _vm.messages.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(ClipboardData(text: _vm.exportLog()));
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log copied')));
                                },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy log'),
                        ),
                        TextButton.icon(onPressed: _vm.messages.isEmpty ? null : _vm.clear, icon: const Icon(Icons.delete_sweep_outlined, size: 16), label: const Text('Clear')),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
                    clipBehavior: Clip.antiAlias,
                    child: _vm.messages.isEmpty
                        ? const EmptyHint(icon: Icons.forum_outlined, title: 'No messages yet', message: 'Connect to see what the server sends. For a WebSocket, type a message below to send one.')
                        : Scrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              itemCount: _vm.messages.length,
                              itemBuilder: (context, i) => _row(context, i, _vm.messages[i]),
                            ),
                          ),
                  ),
                ),
                if (_vm.mode == RealtimeMode.webSocket) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, box) {
                      final composer = CallbackShortcuts(
                        bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _send},
                        child: TextField(
                          controller: _composer,
                          enabled: connected,
                          minLines: 1,
                          maxLines: 6,
                          style: context.textStyles.mono,
                          decoration: InputDecoration(hintText: connected ? 'Message to send (Ctrl+Enter)' : 'Connect to send messages'),
                        ),
                      );
                      final formatButton = OutlinedButton(onPressed: connected ? _formatJson : null, child: const Text('Format JSON'));
                      final sendButton = FilledButton.icon(onPressed: connected ? _send : null, icon: const Icon(Icons.send_rounded, size: 16), label: const Text('Send'));
                      // Phone width: the buttons drop below the message box instead of squeezing it.
                      if (box.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            composer,
                            const SizedBox(height: 8),
                            Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [formatButton, sendButton]),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: composer),
                          const SizedBox(width: 8),
                          formatButton,
                          const SizedBox(width: 8),
                          sendButton,
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, int i, RealtimeMessage m) {
    final colors = context.colors;
    final (icon, color) = switch (m.direction) {
      RealtimeDirection.incoming => (Icons.south_west, colors.statusSuccess),
      RealtimeDirection.outgoing => (Icons.north_east, colors.methodPut),
      RealtimeDirection.system => (Icons.circle, colors.secondaryText),
    };
    String two(int n) => n.toString().padLeft(2, '0');
    final t = m.at;
    final open = _expanded.contains(i);
    final single = m.text.replaceAll('\n', ' ');
    return InkWell(
      onTap: () => setState(() => open ? _expanded.remove(i) : _expanded.add(i)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)}', style: context.textStyles.mono.copyWith(fontSize: 11, color: colors.secondaryText)),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: m.direction == RealtimeDirection.system ? 7 : 13, color: color)),
              const SizedBox(width: 8),
              if (m.label.isNotEmpty)
                // An SSE event name can be long; cap it so a narrow row keeps room for the message.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: colors.mainAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.mainAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              Expanded(
                child: open
                    ? SelectableText(_pretty(m.text), style: context.textStyles.mono.copyWith(color: m.direction == RealtimeDirection.system ? colors.secondaryText : null))
                    : Text(
                        single,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.mono.copyWith(color: m.direction == RealtimeDirection.system ? colors.secondaryText : null),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
