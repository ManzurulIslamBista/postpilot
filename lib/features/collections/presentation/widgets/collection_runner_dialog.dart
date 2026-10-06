import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../safety/domain/services/production_guard.dart';
import '../../../safety/presentation/production_confirm_dialog.dart';
import '../../../request_builder/domain/services/collection_run_report.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../../../run_triage/presentation/run_results_tabs.dart';
import '../../../run_triage/presentation/run_triage_controller.dart';
import '../../../run_triage/presentation/run_triage_wiring.dart';
import '../view_models/collection_runner_view_model.dart';

class CollectionRunnerDialog extends StatefulWidget {
  final int collectionId;

  /// Opens with only this folder's requests (and those of the folders under it) ticked; null ticks everything.
  final int? folderId;

  /// Opens with exactly these requests ticked (the run history's "Re-run failed only"); null leaves the choice as it is.
  final List<int>? onlyRequestIds;
  const CollectionRunnerDialog({super.key, required this.collectionId, this.folderId, this.onlyRequestIds});

  static Future<void> show(BuildContext context, {required int collectionId, int? folderId, List<int>? onlyRequestIds}) => showDialog(
        context: context,
        builder: (_) => CollectionRunnerDialog(collectionId: collectionId, folderId: folderId, onlyRequestIds: onlyRequestIds),
      );

  @override
  State<CollectionRunnerDialog> createState() => _CollectionRunnerDialogState();
}

class _CollectionRunnerDialogState extends State<CollectionRunnerDialog> {
  late final CollectionRunnerViewModel _viewModel;
  // Groups the failures of a finished run by cause and stores the run in the run history.
  late final RunTriageController _triage;
  final _iterations = TextEditingController(text: '1');
  final _delay = TextEditingController(text: '0');
  final _data = TextEditingController();
  bool _showSetup = true;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<CollectionRunnerViewModel>();
    _triage = createRunTriageController(_viewModel, widget.collectionId);
    _viewModel.load(widget.collectionId, folderId: widget.folderId).then((_) {
      final only = widget.onlyRequestIds;
      if (only != null && mounted) _viewModel.selectOnly(only);
    });
  }

  @override
  void dispose() {
    _iterations.dispose();
    _delay.dispose();
    _data.dispose();
    _triage.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// "Re-run failed only" in the Triage tab: tick exactly those requests and run (the production lock asks as usual).
  Future<void> _rerunFailed(List<int> requestIds) async {
    _viewModel.selectOnly(requestIds);
    await _run();
  }

  Future<void> _run() async {
    if (!_viewModel.canRun) return;
    // The production lock: a run sends every ticked request, so ask once up front about exactly those.
    final guard = locator.isRegistered<ProductionGuard>() ? locator<ProductionGuard>() : null;
    final warning = await guard?.checkRunRequests(
      await _viewModel.fullRequests(widget.collectionId),
      _viewModel.allSelected ? 'this collection' : 'the selected requests',
    );
    if (warning != null) {
      if (!mounted) return;
      final ok = await confirmProductionSend(context, warning, onSilence: () => guard?.silenceForSession(warning.environmentName));
      if (!ok || !mounted) return;
    }
    _viewModel.start(widget.collectionId);
    setState(() => _showSetup = false);
  }

  void _copy(RunExportFormat format) {
    Clipboard.setData(ClipboardData(text: _viewModel.export(format)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${format.label} results copied')));
  }

  Future<void> _download(RunExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _viewModel.downloadExport(format);
      if (path != null) messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save file: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CollectionRunnerViewModel>.value(
      value: _viewModel,
      child: Consumer<CollectionRunnerViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 720,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Collection Runner', style: context.textStyles.heading),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(_caption(vm), style: context.textStyles.caption),
                  const Divider(),
                  Expanded(
                    child: _showSetup
                        ? _Setup(vm: vm, iterations: _iterations, delay: _delay, data: _data)
                        : RunResultsTabs(results: _Results(vm: vm), triage: _triage, onRerunFailed: _rerunFailed),
                  ),
                  const SizedBox(height: 8),
                  _buildActions(vm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(CollectionRunnerViewModel vm) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!_showSetup && vm.hasResults) ...[
            OutlinedButton.icon(
              onPressed: () => _copy(RunExportFormat.json),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy JSON'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy(RunExportFormat.csv),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy CSV'),
            ),
            PopupMenuButton<RunExportFormat>(
              tooltip: 'Download results',
              icon: const Icon(Icons.download, size: 20),
              onSelected: _download,
              itemBuilder: (_) => [
                for (final format in RunExportFormat.values)
                  PopupMenuItem(value: format, child: Text('Download ${format.label}')),
              ],
            ),
          ],
          if (_showSetup && vm.hasStarted)
            TextButton(onPressed: () => setState(() => _showSetup = false), child: const Text('View results')),
          if (!_showSetup && !vm.isRunning)
            TextButton(onPressed: () => setState(() => _showSetup = true), child: const Text('Edit setup')),
          if (vm.isRunning)
            OutlinedButton(onPressed: vm.stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: vm.canRun ? _run : null, child: Text(_showSetup ? 'Run' : 'Run again')),
        ],
      ),
    );
  }

  String _caption(CollectionRunnerViewModel vm) {
    if (_showSetup) {
      if (vm.isLoading) return 'Loading requests...';
      if (vm.selectionError != null) return 'Nothing is selected, so there is nothing to run.';
      return '${_plural(vm.requests.length, 'request')} x ${_plural(vm.plannedIterations, 'iteration')}: '
          '${_plural(vm.plannedRequestCount, 'request')} will really be sent, in the order shown, using the active environment.';
    }
    if (vm.isRunning) return 'Running iteration ${vm.currentIteration} of ${vm.totalIterations}...';
    if (vm.runError != null) return 'The run failed: ${vm.runError}';
    if (vm.stoppedOnFailure) return 'Stopped at the first failure';
    return vm.wasStopped ? 'Stopped' : 'Finished';
  }
}

String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

/// Run settings, then what a run would send, shown before the user commits.
class _Setup extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  final TextEditingController iterations;
  final TextEditingController delay;
  final TextEditingController data;
  const _Setup({required this.vm, required this.iterations, required this.delay, required this.data});

  @override
  Widget build(BuildContext context) {
    final rows = vm.treeRows;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Settings(vm: vm, iterations: iterations, delay: delay, data: data),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('Requests', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                if (!vm.isLoading) Text('${vm.selectedCount} of ${vm.totalRequestCount} selected', style: context.textStyles.caption),
                TextButton(
                  onPressed: vm.isLoading || vm.allSelected ? null : vm.selectAll,
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: vm.isLoading || vm.selectedCount == 0 ? null : vm.selectNone,
                  child: const Text('Select none'),
                ),
              ],
            ),
          ),
        ),
        if (vm.isLoading)
          const SliverToBoxAdapter(
            child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          )
        else if (vm.totalRequestCount == 0)
          const SliverToBoxAdapter(
            child: Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No requests in this collection'))),
          )
        else ...[
          if (vm.selectionError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  vm.selectionError!,
                  style: context.textStyles.caption.copyWith(color: context.colors.statusWarning),
                ),
              ),
            ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              RunFolderRow row => _PlanFolderTile(vm: vm, row: row),
              RunRequestRow row => _PlanRequestTile(vm: vm, row: row),
            },
          ),
        ],
      ],
    );
  }
}

class _Settings extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  final TextEditingController iterations;
  final TextEditingController delay;
  final TextEditingController data;
  const _Settings({required this.vm, required this.iterations, required this.delay, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: iterations,
                enabled: !vm.usesData,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Iterations',
                  errorText: vm.iterationsError,
                  helperText: vm.usesData ? 'One per data row' : null,
                ),
                onChanged: vm.setIterations,
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: delay,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'Delay (ms)', errorText: vm.delayError),
                onChanged: vm.setDelayMs,
              ),
            ),
            InkWell(
              onTap: () => vm.setStopOnFailure(!vm.stopOnFailure),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: vm.stopOnFailure, onChanged: (value) => vm.setStopOnFailure(value ?? false)),
                  const Tooltip(
                    message: 'Requests marked "Always run" in their Flow tab (cleanups) are still sent afterwards. '
                        'Pressing Stop yourself stops them too. A skipped request is not a failure.',
                    child: Text('Stop on first failure'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: data,
          minLines: 3,
          maxLines: 6,
          style: context.textStyles.mono,
          decoration: InputDecoration(
            labelText: 'Data (optional)',
            alignLabelWithHint: true,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: 'CSV with a header row, or a JSON array of objects.\n'
                'Each row is one iteration; {{column}} in a request becomes that row\'s value.',
            hintMaxLines: 3,
            errorText: vm.dataError,
            errorMaxLines: 3,
            helperText: vm.usesData ? '${_plural(vm.dataRowCount, 'row')} · ${vm.dataColumns.join(', ')}' : null,
            helperMaxLines: 2,
          ),
          onChanged: vm.setDataText,
        ),
      ],
    );
  }
}

/// A folder of the checkbox tree: ticks or unticks everything below it, and folds away what is in it.
class _PlanFolderTile extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  final RunFolderRow row;
  const _PlanFolderTile({required this.vm, required this.row});

  @override
  Widget build(BuildContext context) {
    final folder = row.folder;
    return CheckboxListTile(
      dense: true,
      tristate: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.only(left: 8.0 + 16 * row.depth, right: 4),
      value: row.checked,
      onChanged: (_) => vm.toggleFolderSelection(folder.id),
      title: Row(
        children: [
          Icon(row.expanded ? Icons.folder_open : Icons.folder, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folder.name,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text('${row.selectedCount}/${row.requestCount}', style: context.textStyles.caption),
        ],
      ),
      secondary: IconButton(
        icon: Icon(row.expanded ? Icons.expand_less : Icons.expand_more),
        tooltip: row.expanded ? 'Collapse ${folder.name}' : 'Expand ${folder.name}',
        visualDensity: VisualDensity.compact,
        onPressed: () => vm.toggleFolderExpanded(folder.id),
      ),
    );
  }
}

/// A request of the checkbox tree, with its place in the run once it is ticked.
class _PlanRequestTile extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  final RunRequestRow row;
  const _PlanRequestTile({required this.vm, required this.row});

  @override
  Widget build(BuildContext context) {
    final request = row.request;
    final number = row.runNumber;
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.only(left: 8.0 + 16 * row.depth, right: 12),
      value: row.checked,
      onChanged: (_) => vm.toggleRequest(request.id),
      title: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              request.method.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.forMethod(request.method.label),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(child: Text(request.name, overflow: TextOverflow.ellipsis)),
          if (number != null)
            Tooltip(
              message: 'Runs number $number',
              child: Text('#$number', style: context.textStyles.caption),
            ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  const _Results({required this.vm});

  @override
  Widget build(BuildContext context) {
    final grouped = vm.totalIterations > 1;
    // Numbered by the place in the pass, the order the requests ran in.
    final entries = <Object>[
      for (final iteration in vm.runIterations) ...[
        if (grouped) iteration,
        for (final (i, result) in iteration.results.indexed) _NumberedResult(i + 1, result),
      ],
    ];
    return Column(
      children: [
        Align(alignment: Alignment.centerLeft, child: _SummaryStrip(summary: vm.summary)),
        const Divider(height: 16),
        Expanded(
          child: entries.isEmpty
              ? Center(child: vm.isRunning ? const CircularProgressIndicator() : const Text('No results'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => switch (entries[index]) {
                    RunIteration iteration => _IterationHeader(iteration: iteration),
                    _NumberedResult numbered => _ResultTile(result: numbered.result, number: numbered.number),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
      ],
    );
  }
}

class _NumberedResult {
  final int number;
  final CollectionRunResult result;
  const _NumberedResult(this.number, this.result);
}

class _SummaryStrip extends StatelessWidget {
  final CollectionRunSummary summary;
  const _SummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        _Stat(label: 'Requests', value: '${summary.requests}'),
        _Stat(label: 'Passed', value: '${summary.passed}', color: context.colors.statusSuccess),
        _Stat(
          label: 'Failed',
          value: '${summary.failed}',
          color: summary.failed > 0 ? context.colors.statusError : null,
        ),
        if (summary.skipped > 0) _Stat(label: 'Skipped', value: '${summary.skipped}'),
        if (summary.assertions > 0) _Stat(label: 'Tests', value: '${summary.passedAssertions}/${summary.assertions}'),
        _Stat(label: 'Total time', value: _formatDuration(summary.totalTime)),
        _Stat(label: 'Avg time', value: _formatDuration(summary.averageTime)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
    return '${duration.inMinutes} m ${duration.inSeconds % 60} s';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.textStyles.caption),
        Text(value, style: context.textStyles.body.copyWith(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _IterationHeader extends StatelessWidget {
  final RunIteration iteration;
  const _IterationHeader({required this.iteration});

  @override
  Widget build(BuildContext context) {
    final passedColor = iteration.allPassed ? context.colors.statusSuccess : context.colors.statusError;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: context.colors.sidebarBackground,
      child: Row(
        children: [
          Text('Iteration ${iteration.number}', style: context.textStyles.body.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Text(
            '${iteration.passedCount}/${iteration.results.length} passed${iteration.skippedCount > 0 ? ', ${iteration.skippedCount} skipped' : ''}',
            style: context.textStyles.caption.copyWith(color: passedColor),
          ),
          if (iteration.data.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                iteration.data.entries.map((e) => '${e.key}=${e.value}').join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CollectionRunResult result;

  /// Its place in the pass: the order the requests ran in.
  final int number;
  const _ResultTile({required this.result, required this.number});

  @override
  Widget build(BuildContext context) {
    final response = result.response;
    final statusText = result.isSkipped
        ? 'Skipped'
        : response == null
            ? 'Error'
            : '${response.statusCode} · ${response.duration.inMilliseconds}ms';
    final statusColor = result.isSkipped
        ? context.colors.secondaryText
        : result.isSuccess ? context.colors.statusSuccess : context.colors.statusError;
    final passedColor = result.isSkipped
        ? context.colors.secondaryText
        : result.passed ? context.colors.statusSuccess : context.colors.statusError;
    // What retrying, polling or fetching pages did (or why the request was skipped), then a token renewed for it or a
    // re-login that ran, are said on the lines below its result.
    final subtitle = [?(result.error ?? _testsSummary()), ?result.flowText, ...result.authNotes].join('\n');

    return ListTile(
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 26, child: Text('$number', textAlign: TextAlign.end, style: context.textStyles.caption)),
          const SizedBox(width: 6),
          Icon(
            result.isSkipped
                ? Icons.remove_circle_outline
                : result.passed ? Icons.check_circle_outline : Icons.error_outline,
            color: passedColor,
            size: 18,
          ),
        ],
      ),
      title: Text(result.request.name, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: Text(statusText, style: TextStyle(color: statusColor)),
    );
  }

  String? _testsSummary() {
    final scripts = result.scripts;
    if (scripts == null) return null;
    // A test inherited from a folder or the collection says where it was set.
    final failedTests = scripts.assertions.where((a) => !a.passed).map((a) => a.origin == null ? a.name : '${a.name} (from ${a.origin})');
    final failedSaves = scripts.extracted.where((e) => !e.ok);
    final parts = [
      if (scripts.assertions.isNotEmpty) '${scripts.passedCount}/${scripts.assertions.length} tests passed',
      if (failedTests.isNotEmpty) 'failed: ${failedTests.join(', ')}',
      if (failedSaves.isNotEmpty)
        'variables: ${scripts.extracted.length - failedSaves.length}/${scripts.extracted.length} saved'
            ' - ${failedSaves.map((e) => e.error).toSet().join(', ')}',
      if (result.truncated && (failedTests.isNotEmpty || failedSaves.isNotEmpty)) 'response cut off at the size limit',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
