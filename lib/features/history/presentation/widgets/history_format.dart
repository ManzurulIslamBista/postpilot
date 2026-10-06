import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/history_entry_entity.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// `4.2 KB`; whole bytes below a kilobyte.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `123 ms`, `1.25 s`.
String formatDuration(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';

/// `14:03:22`, in local time.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

/// `2026-10-06 14:03:22`, in local time.
String formatDateTime(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} ${formatClock(time)}';
}

/// The size of [entry]'s response body as it arrived (`4.2 KB`), even when only the start of it is kept; null when unknown.
String? entrySize(HistoryEntryEntity entry) {
  final bytes = entry.meta?.responseBytes;
  if (bytes == null) return null;
  return formatBytes(bytes);
}

/// The status of [entry] as a chip: `200`, or "No response" for a send that failed.
class HistoryStatusChip extends StatelessWidget {
  final HistoryEntryEntity entry;
  const HistoryStatusChip({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = entry.statusCode;
    if (status == null) return StatusChip(label: 'No response', icon: Icons.error_outline, color: colors.statusError);
    return StatusChip(label: '$status', color: colors.forStatus(status));
  }
}
