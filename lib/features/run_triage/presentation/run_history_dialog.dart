import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/shared_features/prompt_dialog.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../collections/presentation/widgets/collection_runner_dialog.dart';
import '../../request_builder/domain/repositories/request_repository.dart';
import '../domain/entities/run_record_doc.dart';
import '../domain/repositories/run_record_repository.dart';
import 'run_history_view_model.dart';
import 'triage_pane.dart';

/// A run record file chosen by the person, as text; null when the dialog was closed. A record is a few kilobytes, so
/// a large file is refused before it is read.
Future<String?> pickRunRecordText() async {
  const group = XTypeGroup(label: 'PostPilot run record', extensions: ['json']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  if (await file.length() > 8 * 1024 * 1024) {
    throw const FormatException('The file is larger than 8 MB; a run record is much smaller than that.');
  }
  return file.readAsString();
}

/// The runs of one collection that were kept on this device (the last 50): from the runner dialog, from the monitor
/// and imported from the command line. Open one to see its triage, compared with the runs before it.
class RunHistoryDialog extends StatefulWidget {
  final int collectionId;
  final String collectionName;

  /// Replaces the view model and the file picker the app builds, for a test.
  @visibleForTesting
  final RunHistoryViewModel? viewModel;
  @visibleForTesting
  final Future<String?> Function()? pickFile;

  const RunHistoryDialog({super.key, required this.collectionId, required this.collectionName, this.viewModel, this.pickFile});

  /// Opens the history. When a run's "Re-run failed only" is pressed the history closes and the runner opens with
  /// exactly those requests ticked.
  static Future<void> show(BuildContext context, {required int collectionId, required String collectionName}) async {
    final ids = await ToolDialog.show<List<int>>(
      context,
      (_) => RunHistoryDialog(collectionId: collectionId, collectionName: collectionName),
    );
    if (ids != null && ids.isNotEmpty && context.mounted) {
      await CollectionRunnerDialog.show(context, collectionId: collectionId, onlyRequestIds: ids);
    }
  }

  @override
  State<RunHistoryDialog> createState() => _RunHistoryDialogState();
}

class _RunHistoryDialogState extends State<RunHistoryDialog> {
  late final RunHistoryViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = widget.viewModel ?? _build();
    _vm.load();
  }

  RunHistoryViewModel _build() => RunHistoryViewModel(
        records: locator<RunRecordRepository>(),
        collectionId: widget.collectionId,
        collectionName: widget.collectionName,
        loadRequests: () => locator<RequestRepository>().watchByCollection(widget.collectionId).first,
        loadFolders: () => locator<CollectionRepository>().watchFolders(widget.collectionId).first,
      );

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final String? text;
    try {
      text = await (widget.pickFile ?? pickRunRecordText)();
    } on FormatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read the file: ${e.message}')));
      return;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the file: $e')));
      return;
    }
    if (text == null) return;
    await _vm.importText(text);
  }

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear the run history',
      message: 'Forget all ${_vm.runs.length} stored runs of "${widget.collectionName}"? Nothing else is deleted.',
      confirmLabel: 'Clear',
    );
    if (ok) await _vm.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => ToolDialog(
        icon: Icons.fact_check_outlined,
        title: 'Run history',
        subtitle: '${widget.collectionName}: the last ${RunRecordRepository.keepPerCollection} runs, kept on this device only',
        width: 1040,
        height: 720,
        footerLeading: _vm.message == null
            ? null
            : Text(
                _vm.message!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.caption.copyWith(color: _vm.messageIsError ? context.colors.statusError : context.colors.secondaryText),
              ),
        actions: [
          OutlinedButton.icon(
            onPressed: _vm.runs.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('Clear history'),
          ),
          FilledButton(
            onPressed: _vm.isImporting ? null : _import,
            child: BusyLabel(busy: _vm.isImporting, label: 'Import CLI run…', busyLabel: 'Importing…', icon: Icons.file_open_outlined),
          ),
        ],
        child: _vm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 800;
                  final list = _RunList(vm: _vm);
                  final detail = _Detail(vm: _vm, showBack: !wide, onRerun: (ids) => Navigator.of(context).pop(ids));
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 340, child: list),
                        VerticalDivider(width: 1, color: context.colors.border),
                        Expanded(child: detail),
                      ],
                    );
                  }
                  return _vm.selectedId == null ? list : detail;
                },
              ),
      ),
    );
  }
}

class _RunList extends StatelessWidget {
  final RunHistoryViewModel vm;
  const _RunList({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.runs.isEmpty) {
      return const EmptyHint(
        icon: Icons.history_toggle_off,
        title: 'No runs yet',
        message: 'Runs from the collection runner, the monitor and imported command-line runs are listed here. '
            'Run the collection, or import a run written with --records-dir.',
      );
    }
    return ListView.builder(
      itemCount: vm.runs.length,
      itemBuilder: (context, index) => _RunTile(run: vm.runs[index], selected: vm.runs[index].id == vm.selectedId, onTap: () => vm.select(vm.runs[index].id)),
    );
  }
}

class _RunTile extends StatelessWidget {
  final StoredRun run;
  final bool selected;
  final VoidCallback onTap;
  const _RunTile({required this.run, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = run.doc;
    final failing = d.failed > 0;
    return ListTile(
      key: ValueKey('run-${run.id}'),
      dense: true,
      selected: selected,
      selectedTileColor: colors.hover,
      onTap: onTap,
      leading: Icon(
        failing ? Icons.error_outline : (d.passed > 0 ? Icons.check_circle_outline : Icons.remove_circle_outline),
        color: failing ? colors.statusError : (d.passed > 0 ? colors.statusSuccess : colors.secondaryText),
      ),
      title: Text(formatRunTime(run.startedAt), style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${d.passed} passed · ${d.failed} failed${d.skipped > 0 ? ' · ${d.skipped} skipped' : ''} · ${_seconds(d.durationMs)}'
        '${d.environment.isEmpty ? '' : '\n${d.environment}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusChip(label: _sourceLabel(d)),
    );
  }

  static String _sourceLabel(RunRecordDoc d) => switch (d.trigger) {
        'monitor' => 'Monitor',
        'cli' => 'CLI',
        _ => d.source == 'cli' ? 'CLI' : 'App',
      };
}

class _Detail extends StatelessWidget {
  final RunHistoryViewModel vm;
  final bool showBack;
  final ValueChanged<List<int>> onRerun;
  const _Detail({required this.vm, required this.showBack, required this.onRerun});

  @override
  Widget build(BuildContext context) {
    final analysis = vm.analysis;
    if (analysis == null) {
      return const EmptyHint(icon: Icons.touch_app_outlined, title: 'Pick a run', message: 'Its failures are grouped by cause here, and compared with the run before it.');
    }
    final run = analysis.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              if (showBack) IconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back to the list', onPressed: () => vm.select(null)),
              Expanded(
                child: Text(
                  '${formatRunTime(run.startedAt)}${run.environment.isEmpty ? '' : ' · ${run.environment}'}',
                  style: context.textStyles.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (vm.message != null && vm.messageIsError)
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: InfoBanner(kind: BannerKind.error, message: vm.message!)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TriagePane(analysis: analysis, onRerunFailed: onRerun),
          ),
        ),
      ],
    );
  }
}

/// `2026-10-06 10:42` in the local time zone.
String formatRunTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String _seconds(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
