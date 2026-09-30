import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/console_entry_entity.dart';
import '../view_models/request_console_log.dart';

enum _ConsoleFilter { all, errors }

class ConsoleDialog extends StatefulWidget {
  const ConsoleDialog({super.key});

  // The log is provided here rather than in app.dart so opening the console
  // needs no change to the app-wide provider list.
  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => ChangeNotifierProvider.value(
          value: locator<RequestConsoleLog>(),
          child: const ConsoleDialog(),
        ),
      );

  @override
  State<ConsoleDialog> createState() => _ConsoleDialogState();
}

class _ConsoleDialogState extends State<ConsoleDialog> {
  _ConsoleFilter _filter = _ConsoleFilter.all;

  @override
  Widget build(BuildContext context) {
    final log = context.watch<RequestConsoleLog>();
    final entries = _filter == _ConsoleFilter.errors ? log.errors : log.entries;
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
                  Expanded(child: Text('Console', style: context.textStyles.heading)),
                  SegmentedButton<_ConsoleFilter>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _ConsoleFilter.all, label: Text('All')),
                      ButtonSegment(value: _ConsoleFilter.errors, label: Text('Errors')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) => setState(() => _filter = selection.first),
                  ),
                  if (log.entries.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      tooltip: 'Clear console',
                      onPressed: log.clear,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(_filter == _ConsoleFilter.errors ? 'No errors' : 'No requests sent yet'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) => _ConsoleEntryTile(entry: entries[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleEntryTile extends StatelessWidget {
  final ConsoleEntryEntity entry;
  const _ConsoleEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.isPending
        ? context.colors.secondaryText
        : entry.isSuccess
            ? context.colors.statusSuccess
            : context.colors.statusError;
    final caption = context.textStyles.caption;

    return ListTile(
      dense: true,
      isThreeLine: entry.errorMessage != null,
      leading: SizedBox(
        width: 52,
        child: Text(
          entry.method,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.forMethod(entry.method), fontWeight: FontWeight.bold, fontSize: 11),
        ),
      ),
      title: Text(entry.url, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_formatTime(entry.sentAt)}  ·  ${entry.headersCount} headers  ·  ${_formatSize(entry.bodySize)} body',
            style: caption,
          ),
          if (entry.errorMessage != null)
            Text(
              entry.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: caption.copyWith(color: context.colors.statusError),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.statusCode?.toString() ?? (entry.isPending ? 'Pending' : 'ERR'),
            style: context.textStyles.body.copyWith(color: statusColor, fontWeight: FontWeight.bold),
          ),
          if (entry.durationMs != null) ...[
            const SizedBox(width: 8),
            Text('${entry.durationMs} ms', style: caption),
          ],
          if (entry.responseSize != null) ...[
            const SizedBox(width: 8),
            Text(_formatSize(entry.responseSize!), style: caption),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _formatSize(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
