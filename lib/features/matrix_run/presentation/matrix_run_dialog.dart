import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../safety/domain/services/production_guard.dart';
import '../../safety/presentation/production_confirm_dialog.dart';
import '../domain/entities/matrix_identity.dart';
import '../domain/services/matrix_body.dart';
import 'matrix_cell_diff_dialog.dart';
import 'matrix_grid_view.dart';
import 'matrix_identity_dialog.dart';
import 'matrix_run_view_model.dart';
import 'matrix_setup_view.dart';

/// Run a collection once per environment, per identity or both, and see on one grid where the answers differ: dev
/// against staging against production, or admin against user against anonymous.
class MatrixRunDialog extends StatefulWidget {
  final MatrixRunViewModel viewModel;

  /// The collection to open on; the first one when null.
  final int? collectionId;

  /// Replaces the production confirmation dialog, for a test.
  @visibleForTesting
  final Future<bool> Function(ProductionWarning warning)? confirm;

  const MatrixRunDialog({super.key, required this.viewModel, this.collectionId, this.confirm});

  @override
  State<MatrixRunDialog> createState() => _MatrixRunDialogState();
}

class _MatrixRunDialogState extends State<MatrixRunDialog> {
  MatrixRunViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.load(initialCollectionId: widget.collectionId);
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<bool> _confirm(ProductionWarning warning) async {
    if (!mounted) return false;
    final custom = widget.confirm;
    if (custom != null) return custom(warning);
    final guard = locator.isRegistered<ProductionGuard>() ? locator<ProductionGuard>() : null;
    return confirmProductionSend(context, warning, onSilence: () => guard?.silenceForSession(warning.environmentName));
  }

  Future<void> _editIdentity(MatrixIdentity identity, {required bool isNew}) async {
    final edit = await MatrixIdentityDialog.show(context, identity: identity, isNew: isNew);
    if (edit == null || !mounted) return;
    if (edit.isDelete) {
      await vm.deleteIdentity(identity.id);
    } else {
      await vm.saveIdentity(edit.identity!);
    }
  }

  Future<void> _copy(MatrixExportFormat format) async {
    await Clipboard.setData(ClipboardData(text: vm.export(format)));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${format.label} copied')));
  }

  Future<void> _download(MatrixExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await vm.downloadExport(format);
      if (path != null) messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save the file: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final colors = context.colors;
        final running = vm.phase == MatrixPhase.running;
        final done = vm.phase == MatrixPhase.done;
        final columns = vm.columns;
        final footer = switch (vm.phase) {
          MatrixPhase.setup => vm.isLoading
              ? 'Loading…'
              : vm.setupError ??
                  '${columns.length} columns × ${vm.sendable.length} request${vm.sendable.length == 1 ? '' : 's'} = '
                      '${columns.length * vm.sendable.length} requests will really be sent.',
          MatrixPhase.running => vm.runningColumn == null ? 'Running…' : 'Running ${vm.grid?.columns[vm.runningColumn!].label ?? ''} (${vm.runningColumn! + 1} of ${vm.grid?.columns.length ?? 0})…',
          MatrixPhase.done => vm.runError != null ? 'The run failed.' : (vm.wasStopped ? 'Stopped.' : 'Finished.'),
        };
        return ToolDialog(
          icon: Icons.grid_on_outlined,
          title: 'Matrix run',
          subtitle: vm.collectionName.isEmpty ? 'Compare environments or users' : '${vm.collectionName}: compare environments or users',
          width: 1000,
          height: 740,
          footerLeading: Text(
            footer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.caption.copyWith(color: vm.phase == MatrixPhase.setup && vm.setupError != null ? colors.statusWarning : colors.secondaryText),
          ),
          actions: [
            if (done) ...[
              OutlinedButton.icon(onPressed: () => _copy(MatrixExportFormat.markdown), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy Markdown')),
              OutlinedButton.icon(onPressed: () => _copy(MatrixExportFormat.csv), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy CSV')),
              PopupMenuButton<MatrixExportFormat>(
                tooltip: 'Save the grid',
                icon: const Icon(Icons.download, size: 20),
                onSelected: _download,
                itemBuilder: (_) => [for (final f in MatrixExportFormat.values) PopupMenuItem(value: f, child: Text('Save as ${f.label}'))],
              ),
              TextButton(onPressed: vm.editSetup, child: const Text('Edit setup')),
            ],
            if (vm.phase == MatrixPhase.setup && vm.grid != null) TextButton(onPressed: vm.showResults, child: const Text('View results')),
            if (running) OutlinedButton(onPressed: vm.stop, child: const Text('Stop')),
            FilledButton(
              onPressed: vm.canRun ? () => vm.start(confirm: _confirm) : null,
              child: BusyLabel(busy: running, label: done ? 'Run again' : 'Run matrix', busyLabel: 'Running…', icon: Icons.play_arrow),
            ),
          ],
          child: switch (vm.phase) {
            MatrixPhase.setup => MatrixSetupView(
                vm: vm,
                onEditIdentity: _editIdentity,
                onAddIdentity: () => _editIdentity(MatrixIdentity(id: vm.newIdentityId(), name: ''), isNew: true),
                onAddAnonymous: () => _editIdentity(MatrixIdentity(id: vm.newIdentityId(), name: 'anonymous', variables: const {'token': ''}), isNew: true),
              ),
            _ => _Results(vm: vm),
          },
        );
      },
    );
  }
}

class _Results extends StatelessWidget {
  final MatrixRunViewModel vm;
  const _Results({required this.vm});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final analysis = vm.analysis;
    final running = vm.phase == MatrixPhase.running;
    if (vm.runError != null) {
      return Padding(padding: const EdgeInsets.all(16), child: InfoBanner(kind: BannerKind.error, title: 'The run failed', message: vm.runError!));
    }
    if (analysis == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (analysis.rows.isEmpty) {
      return const EmptyHint(icon: Icons.grid_off, title: 'Nothing was sent', message: 'None of the ticked requests could be sent in this run.');
    }
    final first = analysis.grid.columns.first.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running) const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (analysis.hasDifferences)
                StatusChip(label: '${analysis.differingRows} of ${analysis.rows.length} request${analysis.rows.length == 1 ? '' : 's'} differ', icon: Icons.difference_outlined, color: colors.statusWarning)
              else
                StatusChip(label: running ? 'No differences so far' : 'No differences', icon: Icons.check_circle_outline, color: colors.statusSuccess),
              if (analysis.unexpectedCells > 0)
                StatusChip(label: '${analysis.unexpectedCells} unexpected', icon: Icons.gpp_maybe_outlined, color: colors.statusError),
              if (vm.leftOut > 0) StatusChip(label: '${vm.leftOut} left out (changes data)', icon: Icons.edit_off_outlined),
              for (final m in MatrixCompareMode.values)
                ChoiceChip(label: Text(m.label), selected: vm.mode == m, visualDensity: VisualDensity.compact, onSelected: (_) => vm.setMode(m)),
            ],
          ),
        ),
        for (final entry in vm.notes.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: InfoBanner(
              kind: BannerKind.warning,
              message: '${analysis.grid.columns.where((c) => c.key == entry.key).map((c) => c.label).firstOrNull ?? entry.key}: ${entry.value}',
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Tap a cell to see its response against $first. The rule icon in a cell or column header says what is expected there: '
            'a result that is not what was expected is marked.',
            style: context.textStyles.caption.copyWith(color: colors.secondaryText),
          ),
        ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: MatrixGridView(
            analysis: analysis,
            runningColumn: vm.runningColumn,
            onOpenCell: (row, column) => MatrixCellDiffDialog.show(context, row: row, column: column, mode: vm.mode),
            onExpect: vm.setExpectation,
            onExpectColumn: vm.setColumnExpectation,
          ),
        ),
      ],
    );
  }
}
