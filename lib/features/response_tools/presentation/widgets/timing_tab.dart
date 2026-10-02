import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../../data/network_probe.dart';
import '../view_models/response_tools_view_model.dart';

/// How long the request took, and how much of a cold request is spent just
/// reaching the server (DNS, TCP, TLS), measured on a separate connection.
class TimingTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const TimingTab({super.key, required this.viewModel});

  @override
  State<TimingTab> createState() => _TimingTabState();
}

class _TimingTabState extends State<TimingTab> {
  NetworkProbe? _probe;
  bool _busy = false;
  String? _error;

  Future<void> _measure() async {
    final request = widget.viewModel.request;
    if (request == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resolver = await locator<BuildVariableResolverUseCase>()(request.collectionId);
      var url = resolver.resolve(request.url).trim();
      if (!url.contains('://')) url = 'https://$url';
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) {
        _error = 'The request URL has no host to measure.';
      } else {
        final probe = await probeNetwork(uri);
        if (probe == null) _error = "Couldn't open a connection to ${uri.host}.";
        _probe = probe;
      }
    } catch (e) {
      _error = "Couldn't measure: ${e.toString().replaceFirst('Exception: ', '')}";
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = widget.viewModel.data.response.duration;
    final probe = _probe;
    final rows = <(String, Duration, Color, String)>[
      if (probe != null) ('DNS lookup', probe.dns, colors.methodPatch, 'Finding the server address for ${probe.host}'),
      if (probe != null) ('TCP connect', probe.tcp, colors.methodPut, 'Opening the connection to ${probe.ip}:${probe.port}'),
      if (probe?.tls != null) ('TLS handshake', probe!.tls!, colors.methodPost, 'Encrypting the connection (HTTPS)'),
      ('This request, in total', total, colors.statusSuccess, 'What the send took, including the server and the download'),
    ];
    final longest = rows.map((r) => r.$2.inMicroseconds).fold<int>(1, (a, b) => a > b ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final figure = Text('${total.inMilliseconds} ms', style: context.textStyles.heading.copyWith(fontSize: 26));
            final caption = Text('total for this request', style: context.textStyles.body.copyWith(color: colors.secondaryText));
            final measure = canProbeNetwork
                ? FilledButton(
                    onPressed: _busy || widget.viewModel.request == null ? null : _measure,
                    child: BusyLabel(busy: _busy, icon: Icons.speed, label: probe == null ? 'Measure connection' : 'Measure again', busyLabel: 'Measuring…'),
                  )
                : null;
            // The figure, its caption and the button cannot share one line on a phone: stack them instead.
            if (box.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [figure, caption]),
                  if (measure != null) ...[const SizedBox(height: 10), measure],
                ],
              );
            }
            return Row(
              children: [
                figure,
                const SizedBox(width: 10),
                caption,
                const Spacer(),
                ?measure,
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (!canProbeNetwork)
          const InfoBanner(message: 'A browser does not expose connection timing. Use the desktop or mobile app to measure DNS, TCP and TLS.')
        else
          const InfoBanner(
            message: 'DNS, TCP and TLS are measured on a separate, fresh connection, so they estimate what the first call to a server pays. '
                'A request that reused an open connection skips them.',
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBanner(kind: BannerKind.error, message: _error!)),
        const SizedBox(height: 16),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.$1, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600))),
                    Text(_format(r.$2), style: context.textStyles.mono.copyWith(color: r.$3, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(value: (r.$2.inMicroseconds / longest).clamp(0.02, 1.0), minHeight: 10, color: r.$3, backgroundColor: colors.borderSubtle),
                ),
                const SizedBox(height: 4),
                Text(r.$4, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
              ],
            ),
          ),
        if (probe != null)
          InfoBanner(
            kind: probe.total > total ? BannerKind.warning : BannerKind.info,
            message: probe.total > total
                ? 'Opening a new connection (${_format(probe.total)}) cost more than this whole request: the request reused an existing connection. '
                    'Expect the slower figure on a cold start or after the connection idles.'
                : 'A cold start adds about ${_format(probe.total)} on top of the server time.',
          ),
      ],
    );
  }

  String _format(Duration d) => d.inMilliseconds >= 10 ? '${d.inMilliseconds} ms' : '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}
