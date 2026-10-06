import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../safety/domain/services/production_guard.dart';
import '../../../safety/presentation/production_confirm_dialog.dart';
import '../../../request_builder/domain/services/collection_run_report.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../view_models/collection_runner_view_model.dart';

class CollectionRunnerDialog extends StatefulWidget {
  final int collectionId;
  const CollectionRunnerDialog({super.key, required this.collectionId});

  static Future<void> show(BuildContext context, {required int collectionId}) =>
      showDialog(context: context, builder: (_) => CollectionRunnerDialog(collectionId: collectionId));

  @override
  State<CollectionRunnerDialog> createState() => _CollectionRunnerDialogState();
}

class _CollectionRunnerDialogState extends State<CollectionRunnerDialog> {
  late final CollectionRunnerViewModel _viewModel;
  final _iterations = TextEditingController(text: '1');
  final _delay = TextEditingController(text: '0');
  final _data = TextEditingController();
  bool _showSetup = true;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<CollectionRunnerViewModel>();
    _viewModel.load(widget.collectionId);
  }

  @override
  void dispose() {
    _iterations.dispose();
    _delay.dispose();
    _data.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (!_viewModel.canRun) return;
    // The production lock: a run sends every request, so ask once up front.
    final guard = locator.isRegistered<ProductionGuard>() ? locator<ProductionGuard>() : null;
    final warning = await guard?.checkRunRequests(await _viewModel.fullRequests(widget.collectionId), 'this collection');
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
                        : _Results(vm: vm),
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
      return '${_plural(vm.requests.length, 'request')} x ${_plural(vm.plannedIterations, 'iteration')}: '
          '${_plural(vm.plannedRequestCount, 'request')} will really be sent, in order, using the active environment.';
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
            child: Text('Requests', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        if (vm.isLoading)
          const SliverToBoxAdapter(
            child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          )
        else if (vm.requests.isEmpty)
          const SliverToBoxAdapter(
            child: Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No requests in this collection'))),
          )
        else
          SliverList.builder(
            itemCount: vm.requests.length,
            itemBuilder: (context, index) => _PlanTile(request: vm.requests[index]),
          ),
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
                  const Text('Stop on first failure'),
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

class _PlanTile extends StatelessWidget {
  final RequestSummaryEntity request;
  const _PlanTile({required this.request});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
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
      title: Text(request.name, overflow: TextOverflow.ellipsis),
    );
  }
}

class _Results extends StatelessWidget {
  final CollectionRunnerViewModel vm;
  const _Results({required this.vm});

  @override
  Widget build(BuildContext context) {
    final grouped = vm.totalIterations > 1;
    final entries = <Object>[
      for (final iteration in vm.runIterations) ...[if (grouped) iteration, ...iteration.results],
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
                    CollectionRunResult result => _ResultTile(result: result),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
      ],
    );
  }
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
            '${iteration.passedCount}/${iteration.results.length} passed',
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
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final response = result.response;
    final statusText = response == null ? 'Error' : '${response.statusCode} · ${response.duration.inMilliseconds}ms';
    final statusColor = result.isSuccess ? context.colors.statusSuccess : context.colors.statusError;
    final passedColor = result.passed ? context.colors.statusSuccess : context.colors.statusError;
    final subtitle = result.error ?? _testsSummary();

    return ListTile(
      dense: true,
      leading: Icon(result.passed ? Icons.check_circle_outline : Icons.error_outline, color: passedColor, size: 18),
      title: Text(result.request.name, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
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
