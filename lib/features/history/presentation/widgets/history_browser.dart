import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../view_models/history_view_model.dart';
import 'history_compare_view.dart';
import 'history_detail_pane.dart';
import 'history_filter_bar.dart';
import 'history_row.dart';

/// Below this width the list and the entry on show cannot sit side by side:
/// the list fills the panel, and picking an entry swaps it for the entry.
const historyWideBreakpoint = 760.0;

/// The History panel's body: search and filters, the list grouped by day, and the entry on show.
class HistoryBrowser extends StatelessWidget {
  final HistoryViewModel viewModel;
  const HistoryBrowser({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.notice != null) _NoticeStrip(notice: vm.notice!, onClose: vm.dismissNotice),
        Expanded(
          child: vm.entries.isEmpty
              ? const EmptyHint(
                  icon: Icons.history,
                  title: 'No requests sent yet',
                  message: 'Every request you send shows up here with what was sent and what came back, '
                      'so you can search it, send it again or export it.',
                )
              : LayoutBuilder(builder: (context, box) => box.maxWidth >= historyWideBreakpoint ? _wide(context) : _narrow(context)),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 42, child: _ListColumn(viewModel: viewModel, autofocusSearch: true)),
        VerticalDivider(width: 1, color: context.colors.border),
        Expanded(flex: 58, child: _Detail(viewModel: viewModel, narrow: false)),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    final showsDetail = viewModel.comparison != null || viewModel.selected != null;
    return showsDetail ? _Detail(viewModel: viewModel, narrow: true) : _ListColumn(viewModel: viewModel, autofocusSearch: false);
  }
}

/// The answer to the last action, as a strip above the panel. A snackbar would sit behind the dialog.
class _NoticeStrip extends StatelessWidget {
  final HistoryNotice notice;
  final VoidCallback onClose;
  const _NoticeStrip({required this.notice, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final kind = switch (notice.kind) {
      HistoryNoticeKind.info => BannerKind.info,
      HistoryNoticeKind.success => BannerKind.success,
      HistoryNoticeKind.warning => BannerKind.warning,
      HistoryNoticeKind.error => BannerKind.error,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: InfoBanner(
        kind: kind,
        message: notice.message,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 16),
          tooltip: 'Dismiss',
          visualDensity: VisualDensity.compact,
          onPressed: onClose,
        ),
      ),
    );
  }
}

class _ListColumn extends StatelessWidget {
  final HistoryViewModel viewModel;
  final bool autofocusSearch;
  const _ListColumn({required this.viewModel, required this.autofocusSearch});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final items = vm.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HistoryFilterBar(viewModel: vm, autofocus: autofocusSearch),
        Divider(height: 1, color: context.colors.border),
        Expanded(
          child: items.isEmpty
              ? EmptyHint(
                  icon: Icons.search_off,
                  title: 'Nothing matches',
                  message: 'No request matches the search and filters. Try other words, or show everything again.',
                  action: TextButton(onPressed: vm.clearFilters, child: const Text('Clear filters')),
                )
              // Built as it scrolls: a long history is a thousand rows, most of them off screen.
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => switch (items[index]) {
                    HistoryDayHeader(:final label, :final count) => HistoryDayHeaderRow(label: label, count: count),
                    HistoryEntryItem(:final entry) => HistoryEntryRow(
                        key: ValueKey(entry.id),
                        entry: entry,
                        needle: vm.needle,
                        selected: vm.selectedId == entry.id,
                        selecting: vm.selecting,
                        checked: vm.checked.contains(entry.id),
                        onTap: () => vm.selecting ? vm.toggleChecked(entry.id) : vm.select(entry.id),
                      ),
                  },
                ),
        ),
        if (vm.selecting) _SelectionBar(viewModel: vm),
      ],
    );
  }
}

/// While selecting: how many are ticked, and what can be done with them.
class _SelectionBar extends StatelessWidget {
  final HistoryViewModel viewModel;
  const _SelectionBar({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final colors = context.colors;
    final count = vm.checked.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: colors.sidebarBackground, border: Border(top: BorderSide(color: colors.border))),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$count selected', style: context.textStyles.body),
          FilledButton.tonal(
            onPressed: count == 2 && !vm.comparing ? vm.compareChecked : null,
            child: BusyLabel(busy: vm.comparing, label: 'Compare', busyLabel: 'Comparing...', icon: Icons.compare_arrows, iconSize: 16),
          ),
          OutlinedButton(
            onPressed: count > 0 && !vm.exporting ? () => vm.exportHar(selectedOnly: true) : null,
            child: BusyLabel(busy: vm.exporting, label: 'Export HAR', busyLabel: 'Exporting...', icon: Icons.file_download_outlined, iconSize: 16),
          ),
          TextButton(onPressed: count > 0 ? vm.clearChecked : null, child: const Text('Clear selection')),
          TextButton(onPressed: vm.toggleSelecting, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final HistoryViewModel viewModel;
  final bool narrow;
  const _Detail({required this.viewModel, required this.narrow});

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final comparison = vm.comparison;
    if (comparison != null) {
      return HistoryCompareView(viewModel: vm, comparison: comparison, onBack: vm.closeComparison);
    }
    final entry = vm.selected;
    if (entry == null) {
      return const EmptyHint(
        icon: Icons.touch_app_outlined,
        title: 'Pick a request',
        message: 'Choose one from the list to see exactly what was sent and what came back.',
      );
    }
    return HistoryDetailPane(
      key: ValueKey(entry.id),
      viewModel: vm,
      entry: entry,
      onBack: narrow ? () => vm.select(null) : null,
    );
  }
}
