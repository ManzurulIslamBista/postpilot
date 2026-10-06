import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../collections/presentation/view_models/collections_view_model.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../view_models/history_view_model.dart';

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(context: context, builder: (_) => const HistoryDialog());

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoryViewModel>();
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('History', style: context.textStyles.heading)),
                  if (vm.entries.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      tooltip: 'Clear history',
                      onPressed: () => _clear(context, vm),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: vm.entries.isEmpty
                  ? const Center(child: Text('No requests sent yet'))
                  : ListView.builder(
                      itemCount: vm.entries.length,
                      itemBuilder: (context, index) => _HistoryEntryTile(entry: vm.entries[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, HistoryViewModel vm) async {
    final confirmed =
        await showConfirmDialog(context, title: 'Clear history', message: 'Delete all recorded requests?');
    if (confirmed) await vm.clear();
  }
}

class _HistoryEntryTile extends StatelessWidget {
  final HistoryEntryEntity entry;
  const _HistoryEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.statusCode == null
        ? context.colors.secondaryText
        : entry.isSuccess
            ? context.colors.statusSuccess
            : context.colors.statusError;

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 52,
        child: Text(
          entry.method,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.forMethod(entry.method), fontWeight: FontWeight.bold, fontSize: 11),
        ),
      ),
      title: Text(entry.url, overflow: TextOverflow.ellipsis),
      subtitle: Text(_formatTimestamp(entry.sentAt), style: context.textStyles.caption),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.statusCode?.toString() ?? '—',
            style: context.textStyles.body.copyWith(color: statusColor, fontWeight: FontWeight.bold),
          ),
          if (entry.durationMs != null) ...[
            const SizedBox(width: 8),
            Text('${entry.durationMs} ms', style: context.textStyles.caption),
          ],
        ],
      ),
      onTap: () => _openInBuilder(context, entry),
    );
  }

  Future<void> _openInBuilder(BuildContext context, HistoryEntryEntity entry) async {
    // With no collection yet, the first one is created for it ("My collection") instead of refusing.
    final collection = await context.read<CollectionsViewModel>().ensureCollection();
    if (!context.mounted) return;
    final requestId = await context.read<HistoryViewModel>().openInBuilder(entry, collectionId: collection.id);
    if (!context.mounted) return;
    context.read<ShellViewModel>().selectRequest(requestId);
    Navigator.of(context).pop();
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
