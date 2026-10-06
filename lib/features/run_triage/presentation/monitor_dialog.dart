import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../environments/domain/entities/environment_entity.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../domain/entities/monitor_config.dart';
import '../domain/repositories/run_record_repository.dart';
import 'monitor_service.dart';
import 'run_history_dialog.dart';

/// Runs a collection again and again while PostPilot is open, and says when it starts failing.
class MonitorDialog extends StatefulWidget {
  final int collectionId;
  final String collectionName;

  /// Replace what the app wires, for a test.
  @visibleForTesting
  final MonitorService? service;
  @visibleForTesting
  final RunRecordRepository? records;
  @visibleForTesting
  final EnvironmentRepository? environments;

  const MonitorDialog({super.key, required this.collectionId, required this.collectionName, this.service, this.records, this.environments});

  static Future<void> show(BuildContext context, {required int collectionId, required String collectionName}) =>
      ToolDialog.show(context, (_) => MonitorDialog(collectionId: collectionId, collectionName: collectionName));

  @override
  State<MonitorDialog> createState() => _MonitorDialogState();
}

class _MonitorDialogState extends State<MonitorDialog> {
  late final MonitorService _service = widget.service ?? locator<MonitorService>();
  late final RunRecordRepository _records = widget.records ?? locator<RunRecordRepository>();
  late final EnvironmentRepository _environmentRepository = widget.environments ?? locator<EnvironmentRepository>();
  final _minutes = TextEditingController(text: '${MonitorConfig.defaultMinutes}');

  bool _enabled = false;
  String? _environment;
  List<EnvironmentEntity> _environments = const [];
  List<StoredRun> _runs = const [];
  DateTime? _runsFor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = _service.configOf(widget.collectionId);
    if (saved != null) {
      _enabled = saved.enabled;
      _minutes.text = '${saved.everyMinutes}';
      _environment = saved.environment;
    }
    _service.addListener(_onService);
    _environmentRepository.watchAll().first.then((list) {
      if (mounted) setState(() => _environments = list);
    });
    _loadRuns();
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    _minutes.dispose();
    super.dispose();
  }

  void _onService() {
    // A new run finished: its record is there to list.
    final last = _service.statusOf(widget.collectionId).lastRunAt;
    if (last != _runsFor) _loadRuns();
    if (mounted) setState(() {});
  }

  Future<void> _loadRuns() async {
    _runsFor = _service.statusOf(widget.collectionId).lastRunAt;
    try {
      final runs = [for (final r in await _records.recent(widget.collectionId, limit: 40)) if (r.doc.trigger == 'monitor') r].take(8).toList();
      if (mounted) setState(() => _runs = runs);
    } catch (_) {
      // The list is a convenience; the monitor itself does not depend on it.
    }
  }

  String? get _intervalError => MonitorConfig.intervalError(_minutes.text);

  MonitorConfig get _draft => MonitorConfig(
        enabled: _enabled,
        everyMinutes: int.tryParse(_minutes.text.trim()) ?? MonitorConfig.defaultMinutes,
        environment: _environment,
      );

  Future<void> _save() async {
    if (_enabled && _intervalError != null) return;
    setState(() => _saving = true);
    await _service.setConfig(widget.collectionId, _enabled ? _draft : const MonitorConfig());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_enabled ? 'Monitoring "${widget.collectionName}" every ${_draft.everyMinutes} min' : 'Monitoring of "${widget.collectionName}" is off')),
    );
  }

  Future<void> _runNow() async {
    final saved = _service.configOf(widget.collectionId);
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn the monitor on and save it first.')));
      return;
    }
    await _service.runNow(widget.collectionId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = _service.statusOf(widget.collectionId);
    final saved = _service.configOf(widget.collectionId);
    final activeName = _environments.where((e) => e.isActive).firstOrNull?.name;
    final environmentGone = _environment != null && _environments.isNotEmpty && !_environments.any((e) => e.name == _environment);
    return ToolDialog(
      icon: Icons.monitor_heart_outlined,
      title: 'Monitor',
      subtitle: widget.collectionName,
      width: 760,
      height: 720,
      footerLeading: Text(
        saved == null ? 'The monitor is off.' : 'Saved: every ${saved.everyMinutes} min while PostPilot is open.',
        style: context.textStyles.caption.copyWith(color: colors.secondaryText),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: saved == null || status.state == MonitorState.running ? null : _runNow,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Run now'),
        ),
        FilledButton(
          onPressed: _saving || (_enabled && _intervalError != null) ? null : _save,
          child: BusyLabel(busy: _saving, label: 'Save', busyLabel: 'Saving…', icon: Icons.check),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Run this collection automatically while PostPilot is open'),
            subtitle: const Text('It stops when you close the app. Requests are really sent, every time.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _minutes,
                  enabled: _enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: 'Every (minutes)', errorText: _enabled ? _intervalError : null, errorMaxLines: 3),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('env-$_environment-${_environments.length}'),
                  initialValue: environmentGone ? null : _environment,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Environment'),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(activeName == null ? 'The active environment' : 'The active environment ($activeName)', overflow: TextOverflow.ellipsis),
                    ),
                    for (final e in _environments) DropdownMenuItem<String?>(value: e.name, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _enabled ? (v) => setState(() => _environment = v) : null,
                ),
              ),
            ],
          ),
          if (_enabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final m in const [5, 15, 30, 60, 360, 1440])
                    ChoiceChip(
                      label: Text(m >= 60 ? '${m ~/ 60} h' : '$m min'),
                      selected: _minutes.text.trim() == '$m',
                      onSelected: (_) => setState(() => _minutes.text = '$m'),
                    ),
                ],
              ),
            ),
          if (environmentGone)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: InfoBanner(kind: BannerKind.warning, message: 'The environment chosen for this monitor no longer exists. Pick another one and save.'),
            ),
          const SizedBox(height: 16),
          const InfoBanner(
            kind: BannerKind.warning,
            title: 'Production is never changed',
            message: 'When the environment looks like production (or a request goes to a production host from Settings > Safety), '
                'the monitor leaves out every request that changes data (POST, PUT, PATCH, DELETE, an Odoo write, a GraphQL mutation) '
                'and lists them in the run record. Reads still run. A login that is a POST counts as a write: use an API key or a token variable for a production monitor.',
          ),
          const SizedBox(height: 8),
          const InfoBanner(
            message: 'When a run goes from passing to failing, a banner appears at the top of the sidebar. '
                'PostPilot does not send desktop notifications. Runs are kept in the collection\'s Run history.',
          ),
          const SizedBox(height: 16),
          _StatusBlock(status: status),
          const SizedBox(height: 16),
          Text('RECENT MONITOR RUNS', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.9, color: colors.secondaryText)),
          const SizedBox(height: 6),
          if (_runs.isEmpty)
            Text('No monitor run has been recorded yet.', style: context.textStyles.body.copyWith(color: colors.secondaryText))
          else
            for (final r in _runs) _RunRow(run: r, onTap: () => RunHistoryDialog.show(context, collectionId: widget.collectionId, collectionName: widget.collectionName)),
        ],
      ),
    );
  }
}

class _StatusBlock extends StatelessWidget {
  final MonitorStatus status;
  const _StatusBlock({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color) = switch (status.state) {
      MonitorState.off => ('Off', null),
      MonitorState.waiting => ('Waiting for the first run', null),
      MonitorState.running => ('Running now', colors.mainAccent),
      MonitorState.passing => ('Passing', colors.statusSuccess),
      MonitorState.failing => ('Failing: ${status.failed} ${status.failed == 1 ? 'request' : 'requests'}', colors.statusError),
      MonitorState.error => ('Could not run', colors.statusWarning),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Status', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700)),
            StatusChip(label: label, color: color),
            if (status.lastRunAt != null) Text('last run ${formatRunTime(status.lastRunAt!)}', style: context.textStyles.caption),
            if (status.nextRunAt != null && status.state != MonitorState.off)
              Text('next run ${formatRunTime(status.nextRunAt!)}', style: context.textStyles.caption),
          ],
        ),
        if (status.skippedByLock > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${status.skippedByLock} data-changing request${status.skippedByLock == 1 ? ' was' : 's were'} left out by the production lock in the last run.',
              style: context.textStyles.caption.copyWith(color: colors.statusWarning),
            ),
          ),
        if (status.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(status.error!, style: context.textStyles.caption.copyWith(color: colors.statusError)),
          ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  final StoredRun run;
  final VoidCallback onTap;
  const _RunRow({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = run.doc;
    final failing = d.failed > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(failing ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: failing ? colors.statusError : colors.statusSuccess),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${formatRunTime(run.startedAt)}  ·  ${d.passed} passed, ${d.failed} failed${d.skipped > 0 ? ', ${d.skipped} left out' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (d.environment.isNotEmpty) Flexible(child: Text(d.environment, style: context.textStyles.caption, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
