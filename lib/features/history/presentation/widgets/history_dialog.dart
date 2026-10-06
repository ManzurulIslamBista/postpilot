import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../view_models/history_view_model.dart';
import 'history_browser.dart';

/// Everything sent from PostPilot: searchable, filterable, with what was sent and
/// what came back for each request, and ways to open it again, send it again,
/// compare two, copy it as cURL or export it as a HAR file.
class HistoryDialog extends StatefulWidget {
  const HistoryDialog({super.key});

  static Future<void> show(BuildContext context) {
    // Each visit starts from the whole list, not from the filters of the last one.
    context.read<HistoryViewModel>().resetView();
    return showDialog(context: context, builder: (_) => const HistoryDialog());
  }

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  @override
  void initState() {
    super.initState();
    // Honours a smaller limit set in Settings > History before the list is read.
    context.read<HistoryViewModel>().applyRetention();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoryViewModel>();
    final total = vm.entries.length;
    return ToolDialog(
      icon: Icons.history,
      title: 'History',
      subtitle: total == 0
          ? 'Nothing sent yet'
          : vm.visible.length == total
              ? '$total request${total == 1 ? '' : 's'}'
              : '${vm.visible.length} of $total requests',
      width: 1120,
      height: 720,
      headerActions: [
        if (total > 0) ...[
          IconButton(
            icon: Icon(vm.selecting ? Icons.checklist_rtl : Icons.checklist, size: 20),
            tooltip: vm.selecting ? 'Stop selecting' : 'Select requests to compare or export',
            visualDensity: VisualDensity.compact,
            onPressed: vm.toggleSelecting,
          ),
          PopupMenuButton<bool>(
            tooltip: 'Export as HAR',
            icon: const Icon(Icons.file_download_outlined, size: 20),
            enabled: !vm.exporting,
            onSelected: (selectedOnly) => vm.exportHar(selectedOnly: selectedOnly),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                enabled: vm.visible.isNotEmpty,
                child: Text('Export the ${vm.visible.length} shown as HAR'),
              ),
              PopupMenuItem(
                value: true,
                enabled: vm.checked.isNotEmpty,
                child: Text('Export the ${vm.checked.length} selected as HAR'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: 'Clear history',
            visualDensity: VisualDensity.compact,
            onPressed: () => _clear(context, vm),
          ),
        ],
      ],
      child: HistoryBrowser(viewModel: vm),
    );
  }

  Future<void> _clear(BuildContext context, HistoryViewModel vm) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear history',
      message: 'Delete all ${vm.entries.length} recorded requests, with the request and response details kept for them? '
          'This cannot be undone. Your collections and saved requests are not touched.',
      confirmLabel: 'Clear history',
    );
    if (confirmed) await vm.clear();
  }
}
