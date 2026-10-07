import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../history/presentation/widgets/history_detail_views.dart';
import '../../history/presentation/widgets/history_format.dart';
import '../data/recorder_engine.dart';
import 'traffic_recorder_view_model.dart';

/// One recorded call: what the app sent and what it got back, with the two actions that matter (open it as a request, copy
/// it as cURL). Credentials are masked unless the session's "Show real values" is on.
class ExchangeDetailPane extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final RecordedExchange exchange;

  /// Set on a narrow screen, where the detail replaces the table and needs a way back.
  final VoidCallback? onBack;
  final Future<void> Function(RecordedExchange exchange) onResend;
  final Future<void> Function(String text, String what) onCopy;

  const ExchangeDetailPane({
    super.key,
    required this.vm,
    required this.exchange,
    required this.onResend,
    required this.onCopy,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final e = exchange;
    // The summary and the buttons above the tabs take at most half the height and scroll beyond that, so a small window
    // still leaves room for the headers and the body.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.5),
            child: SingleChildScrollView(primary: false, child: _summary(context)),
          ),
          Expanded(
            child: DefaultTabController(
              key: ValueKey('exchange-tabs-${e.id}'),
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [Tab(height: 36, text: 'Request'), Tab(height: 36, text: 'Response')],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _SideView(
                          vm: vm,
                          headers: e.requestHeaders,
                          text: e.requestText,
                          contentType: e.requestContentType,
                          size: e.requestBodySize,
                          truncated: e.requestBodyTruncated,
                          what: 'request',
                        ),
                        _SideView(
                          vm: vm,
                          headers: e.responseHeaders,
                          text: e.responseText,
                          contentType: e.responseContentType,
                          size: e.responseBodySize,
                          truncated: e.responseBodyTruncated,
                          undecodedEncoding: e.responseUndecoded ? e.responseEncoding : null,
                          what: 'answer',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The method and path, the status line, the two buttons and, when the recorder answered itself, why.
  Widget _summary(BuildContext context) {
    final colors = context.colors;
    final e = exchange;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null) IconButton(icon: const Icon(Icons.arrow_back, size: 20), tooltip: 'Back to the list', onPressed: onBack),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: onBack == null ? 6 : 0, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText.rich(
                        TextSpan(
                          style: context.textStyles.mono,
                          children: [
                            TextSpan(text: '${e.method} ', style: TextStyle(color: colors.forMethod(e.method), fontWeight: FontWeight.w700)),
                            TextSpan(text: vm.pathFor(e)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${e.status} ${e.statusMessage}  ·  ${formatDuration(e.duration.inMilliseconds)}  ·  ${formatClock(e.startedAt)}'
                        '${e.clientAddress == null ? '' : '  ·  from ${e.clientAddress}'}',
                        style: caption.copyWith(color: colors.forStatus(e.status), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: e.kind == RecordedKind.refused ? null : () => onResend(e),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Resend in PostPilot'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(vm.curlFor(e), vm.showRealValues ? 'cURL command (with real values)' : 'cURL command'),
                icon: const Icon(Icons.terminal, size: 16),
                label: const Text('Copy as cURL'),
              ),
            ],
          ),
        ),
        if (e.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: InfoBanner(
              kind: e.kind == RecordedKind.refused ? BannerKind.warning : BannerKind.error,
              title: e.kind == RecordedKind.refused ? 'The recorder did not forward this call' : 'The upstream call failed',
              message: e.error!,
            ),
          ),
      ],
    );
  }
}

/// The headers and the body of one side of an exchange.
class _SideView extends StatelessWidget {
  final TrafficRecorderViewModel vm;
  final List<RecordedHeader> headers;
  final String? text;
  final String? contentType;
  final int size;
  final bool truncated;
  final String? undecodedEncoding;
  final String what;

  const _SideView({
    required this.vm,
    required this.headers,
    required this.text,
    required this.contentType,
    required this.size,
    required this.truncated,
    required this.what,
    this.undecodedEncoding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final shown = vm.headersFor(headers);
    final body = text;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ToolSection(
          title: 'Headers',
          child: shown.isEmpty ? Text('No headers.', style: caption) : _HeaderRows(headers: shown),
        ),
        ToolSection(
          title: 'Body${size > 0 ? ' (${formatBytes(size)})' : ''}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (size == 0)
                Text('No $what body.', style: caption)
              else if (undecodedEncoding != null)
                InfoBanner(
                  kind: BannerKind.warning,
                  message: 'The answer is compressed with $undecodedEncoding, which the recorder cannot decode, so it cannot show it. '
                      'The app got it unchanged. Switch on "Ask for gzip, not brotli" next time.',
                )
              else if (body == null)
                Text('Not text: $size bytes${contentType == null ? '' : ' of $contentType'}.', style: caption)
              else ...[
                if (truncated)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Only the start of this body is kept (${formatBytes(body.length)} of ${formatBytes(size)}).', style: caption),
                  ),
                HistoryTextBlock(
                  key: ValueKey('${vm.showRealValues}-$what'),
                  text: vm.bodyFor(body),
                  contentType: contentType ?? 'text/plain',
                  needle: '',
                  height: 280,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `Name: value` rows.
class _HeaderRows extends StatelessWidget {
  final List<RecordedHeader> headers;
  const _HeaderRows({required this.headers});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in headers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText.rich(
              TextSpan(
                style: mono,
                children: [
                  TextSpan(text: '${h.name}: ', style: TextStyle(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                  TextSpan(text: h.value),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
