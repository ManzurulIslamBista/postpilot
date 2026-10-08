import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/tool_dialog.dart';
import '../../domain/entities/cleanup_entry.dart';
import '../production_gate.dart';
import '../view_models/cleanup_ledger.dart';

/// What a finished collection run left on the server: "3 records were created by this run", the list of what would be
/// deleted (newest first, each ticked) and the choice, "Delete them" or "Keep". Nothing is deleted until the person
/// presses the button, unless "Auto clean up after the run" was ticked, and then the production lock still asks. Shows
/// nothing when the run created nothing, so a run without cleanup looks as it always did.
///
/// Where there is room the list is part of the panel. In a narrow dialog it would leave the results no space, so the panel
/// stays a short bar and "Review" opens the same list in a dialog of its own.
class RunCleanupPanel extends StatefulWidget {
  /// `CleanupLedger.mark` taken when the run started: the entries made after it are this run's.
  final int since;

  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final CleanupLedger? ledger;

  const RunCleanupPanel({super.key, required this.since, this.ledger});

  @override
  State<RunCleanupPanel> createState() => _RunCleanupPanelState();
}

/// Narrower than this the list does not fit beside the results.
const _inlineListMinWidth = 480.0;

class _RunCleanupPanelState extends State<RunCleanupPanel> {
  late final CleanupLedger _ledger = widget.ledger ?? locator<CleanupLedger>();

  /// Entries the person took the tick off; everything else that can be deleted is ticked.
  final ValueNotifier<Set<int>> _unticked = ValueNotifier(const {});
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (_ledger.autoCleanup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _delete(everything: true);
      });
    }
  }

  @override
  void dispose() {
    _unticked.dispose();
    super.dispose();
  }

  List<CleanupEntry> get _mine => _ledger.since(widget.since);

  void _toggle(int id) => _unticked.value = _unticked.value.contains(id) ? ({..._unticked.value}..remove(id)) : {..._unticked.value, id};

  Future<void> _delete({bool everything = false}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final chosen = [
      for (final e in _mine)
        if (e.canDelete && (everything || !_unticked.value.contains(e.id))) e,
    ];
    final run = await _ledger.cleanup(chosen, gate: productionGate(context, what: 'the cleanup of this run'));
    if (!mounted) return;
    if (run.declined) messenger?.showSnackBar(const SnackBar(content: Text('Nothing was deleted.')));
  }

  Future<void> _review() => ToolDialog.show(
        context,
        (_) => _ReviewDialog(ledger: _ledger, since: widget.since, unticked: _unticked, onToggle: _toggle, onDelete: _delete),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ledger, _unticked]),
      builder: (context, _) {
        final mine = _mine;
        if (mine.isEmpty || _dismissed) return const SizedBox.shrink();
        final colors = context.colors;
        final created = mine.where((e) => e.state != CleanupState.skipped).fold<int>(0, (sum, e) => sum + e.recordCount);
        final skipped = mine.where((e) => e.state == CleanupState.skipped).toList();
        final deletable = mine.where((e) => e.canDelete).toList();
        final failed = mine.where((e) => e.state == CleanupState.failed).length;
        final working = mine.any((e) => _ledger.isWorking(e.id));
        final ticked = deletable.where((e) => !_unticked.value.contains(e.id)).toList();
        final done = deletable.isEmpty;
        final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);

        final title = created == 0
            ? 'Nothing from this run can be cleaned up'
            : working
                ? 'Deleting what this run created…'
                : done
                    ? '$created ${created == 1 ? 'record was' : 'records were'} created by this run, and deleted'
                    : '$created ${created == 1 ? 'record was' : 'records were'} created by this run';
        return LayoutBuilder(
          builder: (context, constraints) {
            final inline = constraints.maxWidth >= _inlineListMinWidth;
            return Container(
              key: const ValueKey('run-cleanup-panel'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.sidebarBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: failed > 0 ? colors.statusError.withValues(alpha: 0.5) : colors.mainAccent.withValues(alpha: 0.45)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          done && created > 0 ? Icons.check_circle_outline : Icons.cleaning_services_outlined,
                          size: 18,
                          color: done && created > 0 ? colors.statusSuccess : colors.mainAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!done)
                        FilledButton(
                          key: const ValueKey('run-cleanup-delete'),
                          onPressed: ticked.isEmpty || working ? null : _delete,
                          child: BusyLabel(busy: working, label: 'Delete them', busyLabel: 'Deleting…', icon: Icons.delete_outline),
                        ),
                      if (!inline)
                        OutlinedButton(
                          key: const ValueKey('run-cleanup-review'),
                          onPressed: _review,
                          child: Text(done || failed > 0 ? 'Details' : 'Review'),
                        ),
                      TextButton(
                        key: const ValueKey('run-cleanup-keep'),
                        onPressed: working ? null : () => setState(() => _dismissed = true),
                        child: Text(done ? 'Close' : 'Keep'),
                      ),
                    ],
                  ),
                  // Narrow, the sentence lives in Review: the bar has to stay short to leave the results their room.
                  if (!done && inline)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        working
                            ? 'Each one is sent as a normal request; one that fails does not stop the others.'
                            : 'This is what would be deleted, newest first. Nothing is deleted until you press Delete them; '
                                '"Keep" leaves the records on the server and in the Cleanup ledger.',
                        style: caption,
                      ),
                    ),
                  if (inline) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 168),
                      child: SingleChildScrollView(
                        child: _EntryRows(entries: mine, ledger: _ledger, unticked: _unticked.value, onToggle: _toggle, locked: working),
                      ),
                    ),
                    for (final entry in skipped.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${entry.requestName}: ${entry.reason ?? 'cannot be cleaned up'}', style: caption.copyWith(color: colors.statusWarning)),
                      ),
                  ] else if (skipped.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${skipped.length} ${skipped.length == 1 ? 'create' : 'creates'} cannot be undone (see Review).',
                        style: caption.copyWith(color: colors.statusWarning),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The entries of a run, newest first, each with its tick (or its outcome once it has been tried).
class _EntryRows extends StatelessWidget {
  final List<CleanupEntry> entries;
  final CleanupLedger ledger;
  final Set<int> unticked;
  final void Function(int id) onToggle;

  /// A delete is under way: the ticks cannot be changed now.
  final bool locked;

  const _EntryRows({required this.entries, required this.ledger, required this.unticked, required this.onToggle, required this.locked});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries.reversed.where((e) => e.state != CleanupState.skipped))
          _Row(
            key: ValueKey('run-cleanup-row-${entry.id}'),
            entry: entry,
            working: ledger.isWorking(entry.id),
            ticked: !unticked.contains(entry.id),
            onToggle: entry.canDelete && !locked ? () => onToggle(entry.id) : null,
          ),
      ],
    );
  }
}

/// The list of "Review", for a dialog too narrow to hold it beside the results.
class _ReviewDialog extends StatelessWidget {
  final CleanupLedger ledger;
  final int since;
  final ValueNotifier<Set<int>> unticked;
  final void Function(int id) onToggle;
  final Future<void> Function({bool everything}) onDelete;

  const _ReviewDialog({required this.ledger, required this.since, required this.unticked, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, unticked]),
      builder: (context, _) {
        final mine = ledger.since(since);
        final colors = context.colors;
        final working = mine.any((e) => ledger.isWorking(e.id));
        final ticked = mine.where((e) => e.canDelete && !unticked.value.contains(e.id)).length;
        final skipped = mine.where((e) => e.state == CleanupState.skipped).toList();
        return ToolDialog(
          icon: Icons.cleaning_services_outlined,
          title: 'What this run created',
          subtitle: 'Newest first. Take the tick off what should stay.',
          width: 560,
          height: 520,
          actions: [
            TextButton(onPressed: working ? null : () => Navigator.of(context).maybePop(), child: const Text('Close')),
            FilledButton(
              key: const ValueKey('run-cleanup-review-delete'),
              onPressed: ticked == 0 || working ? null : onDelete,
              child: BusyLabel(busy: working, label: 'Delete them ($ticked)', busyLabel: 'Deleting…', icon: Icons.delete_outline),
            ),
          ],
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Nothing is deleted until you press Delete them. Each one is sent as a normal request; one that fails does not stop '
                  'the others. Closing leaves the records on the server and in the Cleanup ledger.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ),
              _EntryRows(entries: mine, ledger: ledger, unticked: unticked.value, onToggle: onToggle, locked: working),
              for (final entry in skipped)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${entry.requestName}: ${entry.reason ?? 'cannot be cleaned up'}',
                    style: context.textStyles.caption.copyWith(color: colors.statusWarning),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final CleanupEntry entry;
  final bool working;
  final bool ticked;
  final VoidCallback? onToggle;

  const _Row({super.key, required this.entry, required this.working, required this.ticked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failed = entry.state == CleanupState.failed;
    final Widget leading;
    if (working) {
      leading = Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.mainAccent)),
      );
    } else if (entry.state == CleanupState.deleted) {
      leading = Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.check_circle_outline, size: 18, color: colors.statusSuccess));
    } else {
      leading = Checkbox(
        value: ticked,
        onChanged: onToggle == null ? null : (_) => onToggle!(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onToggle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 40, height: 40, child: Center(child: leading)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.requestName}  ${entry.idsText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    failed ? '${entry.plan.summary} · ${entry.reason ?? 'failed'}' : entry.plan.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(color: failed ? colors.statusError : colors.secondaryText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
