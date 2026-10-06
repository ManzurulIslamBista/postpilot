import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/entities/history_snapshot.dart';
import '../view_models/history_view_model.dart';
import 'history_actions.dart';
import 'history_detail_views.dart';
import 'history_format.dart';

enum _More { curl, curlResolved, example, compare, har }

/// The entry on show: where it came from, what was sent and what came back, and
/// what can be done with it.
class HistoryDetailPane extends StatelessWidget {
  final HistoryViewModel viewModel;
  final HistoryEntryEntity entry;

  /// Narrow layout: goes back to the list.
  final VoidCallback? onBack;

  const HistoryDetailPane({super.key, required this.viewModel, required this.entry, this.onBack});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final detail = vm.selectedId == entry.id ? vm.detail : null;
    final snapshot = detail?.request ?? HistoryRequestSnapshot.bare(entry.method, entry.url);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The summary scrolls when the pane is short, so the tabs below always keep room.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _Summary(viewModel: vm, entry: entry, snapshot: snapshot, onBack: onBack),
            ),
          ),
          Divider(height: 1, color: context.colors.border),
          if (vm.detailLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ToolTabs(
              tabs: [
                ToolTab(
                  label: 'Request',
                  icon: Icons.north_east,
                  child: HistoryRequestView(snapshot: snapshot, needle: vm.needle),
                ),
                ToolTab(
                  label: 'Response',
                  icon: Icons.south_west,
                  child: HistoryResponseView(entry: entry, detail: detail, needle: vm.needle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final HistoryViewModel viewModel;
  final HistoryEntryEntity entry;
  final HistoryRequestSnapshot snapshot;
  final VoidCallback? onBack;
  const _Summary({required this.viewModel, required this.entry, required this.snapshot, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final meta = entry.meta;
    final size = entrySize(entry);
    final where = [if (meta?.collectionName != null) meta!.collectionName!, if (meta?.requestName != null) meta!.requestName!].join(' › ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  tooltip: 'Back to the list',
                  visualDensity: VisualDensity.compact,
                  onPressed: onBack,
                ),
              ),
            Padding(padding: const EdgeInsets.only(top: 2), child: MethodBadge(method: entry.method, width: 48)),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(entry.url, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HistoryStatusChip(entry: entry),
            StatusChip(label: formatDateTime(entry.sentAt), icon: Icons.schedule),
            if (entry.durationMs != null) StatusChip(label: formatDuration(entry.durationMs!), icon: Icons.timer_outlined),
            if (size != null) StatusChip(label: size, icon: Icons.data_usage),
            if (meta?.environmentName != null) StatusChip(label: meta!.environmentName!, icon: Icons.layers_outlined),
          ],
        ),
        if (where.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Sent from $where', style: caption),
        ],
        const SizedBox(height: 10),
        _Notes(entry: entry, snapshot: snapshot),
        _Actions(viewModel: viewModel, entry: entry),
      ],
    );
  }
}

/// What to know before using an entry: it kept no details, a credential was masked, a body was cut.
class _Notes extends StatelessWidget {
  final HistoryEntryEntity entry;
  final HistoryRequestSnapshot snapshot;
  const _Notes({required this.entry, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final notes = <Widget>[
      if (!entry.hasDetails)
        const InfoBanner(
          message: 'Only the summary of this request was kept: it was sent before History saved request details, or '
              '"Keep request/response bodies in history" was off (Settings > History). Its method and URL can still be opened or sent again.',
        ),
      if (entry.hasDetails && snapshot.hasMaskedValues)
        const InfoBanner(
          kind: BannerKind.warning,
          message: 'Passwords and tokens in this request were masked when it was recorded. Sending it again sends them '
              'empty, so use "Edit & re-send" to enter them first.',
        ),
      if (snapshot.bodyTruncated)
        const InfoBanner(
          kind: BannerKind.warning,
          message: 'The request body was longer than History keeps, so only the start of it was stored. '
              'Sending it again sends the shortened body.',
        ),
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (var i = 0; i < notes.length; i++) ...[if (i > 0) const SizedBox(height: 8), notes[i]],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final HistoryViewModel viewModel;
  final HistoryEntryEntity entry;
  const _Actions({required this.viewModel, required this.entry});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final detail = vm.selectedId == entry.id ? vm.detail : null;
    final canSaveExample = entry.statusCode != null && detail?.hasResponseBody == true && entry.meta?.requestId != null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () => HistoryActions.open(context, vm, entry, copy: true),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit & re-send'),
        ),
        OutlinedButton(
          onPressed: vm.sending ? null : () => HistoryActions.resend(context, vm, entry),
          child: BusyLabel(busy: vm.sending, label: 'Re-send as is', busyLabel: 'Sending...', icon: Icons.replay, iconSize: 16),
        ),
        OutlinedButton.icon(
          onPressed: () => HistoryActions.open(context, vm, entry, copy: false),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open as new request'),
        ),
        PopupMenuButton<_More>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz),
          onSelected: (choice) => switch (choice) {
            _More.curl => HistoryActions.copyCurl(context, vm, entry, resolved: false),
            _More.curlResolved => HistoryActions.copyCurl(context, vm, entry, resolved: true),
            _More.example => vm.saveAsExample(entry),
            _More.compare => vm.startCompareWith(entry),
            _More.har => vm.exportHar(selectedOnly: false, only: entry),
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: _More.curl, child: Text('Copy as cURL')),
            const PopupMenuItem(value: _More.curlResolved, child: Text('Copy as cURL with the active environment (contains secrets)')),
            PopupMenuItem(value: _More.example, enabled: canSaveExample, child: const Text('Save response as example')),
            const PopupMenuItem(value: _More.compare, child: Text('Compare with...')),
            const PopupMenuItem(value: _More.har, child: Text('Export this request as HAR')),
          ],
        ),
      ],
    );
  }
}
