import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../domain/entities/cleanup_entry.dart';
import '../production_gate.dart';
import '../view_models/cleanup_ledger.dart';
import 'cleanup_entry_tile.dart';

/// The records created in this session by requests that have "Clean up what this request creates" switched on: what
/// made each one, what will undo it and where it stands, with a delete for one entry or for all that are left. Opened from
/// the command palette. Nothing here is saved; closing PostPilot forgets the list.
class CleanupLedgerDialog extends StatefulWidget {
  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final CleanupLedger? ledger;

  const CleanupLedgerDialog({super.key, this.ledger});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const CleanupLedgerDialog());

  @override
  State<CleanupLedgerDialog> createState() => _CleanupLedgerDialogState();
}

class _CleanupLedgerDialogState extends State<CleanupLedgerDialog> {
  late final CleanupLedger _ledger = widget.ledger ?? locator<CleanupLedger>();

  Future<void> _delete(List<CleanupEntry> entries) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final run = await _ledger.cleanup(entries, gate: productionGate(context));
    if (!mounted) return;
    if (run.declined) messenger?.showSnackBar(const SnackBar(content: Text('Nothing was deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ledger,
      builder: (context, _) {
        final entries = _ledger.entries.reversed.toList();
        final left = _ledger.deletableCount;
        final busy = _ledger.isBusy;
        final finished = entries.any((e) => e.state == CleanupState.deleted || e.state == CleanupState.skipped);
        return ToolDialog(
          icon: Icons.cleaning_services_outlined,
          title: 'Cleanup ledger',
          subtitle: 'Records created in this session',
          width: 720,
          height: 560,
          footerLeading: Text(
            'Kept until you close PostPilot',
            style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
          ),
          actions: [
            if (finished) TextButton(onPressed: _ledger.clearFinished, child: const Text('Clear finished')),
            FilledButton(
              onPressed: left == 0 || busy ? null : () => _delete(_ledger.entries.where((e) => e.canDelete).toList()),
              child: BusyLabel(busy: busy, label: 'Delete all pending ($left)', busyLabel: 'Deleting…', icon: Icons.delete_outline),
            ),
          ],
          child: entries.isEmpty ? const _Empty() : _List(entries: entries, ledger: _ledger, onDelete: _delete),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const EmptyHint(
        icon: Icons.cleaning_services_outlined,
        title: 'Nothing was created yet',
        message: 'Switch on "Clean up what this request creates" in a request\'s Settings tab. The records it makes show up here, '
            'and a collection run offers to delete them when it is done.',
      );
}

class _List extends StatelessWidget {
  final List<CleanupEntry> entries;
  final CleanupLedger ledger;
  final Future<void> Function(List<CleanupEntry> entries) onDelete;

  const _List({required this.entries, required this.ledger, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final left = ledger.deletableCount;
    final records = [for (final e in entries) if (e.canDelete) e].fold<int>(0, (sum, e) => sum + e.recordCount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoBanner(
          kind: left == 0 ? BannerKind.success : BannerKind.info,
          message: left == 0
              ? 'Everything this session created has been dealt with.'
              : '$records ${records == 1 ? 'record is' : 'records are'} still on the server, newest first below. '
                  'Each delete goes through the normal send, so a production environment asks before anything is deleted.',
          margin: const EdgeInsets.only(bottom: 12),
        ),
        for (final entry in entries)
          CleanupEntryTile(
            key: ValueKey('cleanup-entry-${entry.id}'),
            entry: entry,
            working: ledger.isWorking(entry.id),
            actions: [
              if (entry.canDelete)
                OutlinedButton.icon(
                  key: ValueKey('cleanup-delete-${entry.id}'),
                  onPressed: ledger.isWorking(entry.id) ? null : () => onDelete([entry]),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(entry.state == CleanupState.failed ? 'Retry' : 'Delete'),
                ),
              TextButton(
                key: ValueKey('cleanup-forget-${entry.id}'),
                onPressed: ledger.isWorking(entry.id) ? null : () => ledger.forget(entry.id),
                child: const Tooltip(message: 'Remove it from this list. Nothing is deleted.', child: Text('Forget')),
              ),
            ],
          ),
      ],
    );
  }
}
