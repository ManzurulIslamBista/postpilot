import 'package:flutter/material.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/entities/drift_report.dart';
import '../../domain/services/field_path.dart';
import '../view_models/baseline_view_model.dart';

/// The recorded baseline of a request and how the response differs from it: record, accept changes, reset, enforce
/// in runs, export for the command line.
class BaselineView extends StatelessWidget {
  final BaselineViewModel viewModel;

  /// Whether the Suggestions half has sent the request twice, so the recording knows what changes by itself.
  final bool probed;

  const BaselineView({super.key, required this.viewModel, this.probed = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        if (!vm.loaded) return const Center(child: CircularProgressIndicator());
        final stored = vm.stored;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            if (vm.notice case final notice?) ...[
              InfoBanner(kind: vm.noticeIsError ? BannerKind.error : BannerKind.success, message: notice),
              const SizedBox(height: 10),
            ],
            if (stored == null) _NoBaseline(viewModel: vm, probed: probed) else ..._withBaseline(context, vm, stored.recordedAt),
          ],
        );
      },
    );
  }

  List<Widget> _withBaseline(BuildContext context, BaselineViewModel vm, DateTime recordedAt) {
    final colors = context.colors;
    final snapshot = vm.stored!.snapshot;
    final report = vm.report;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Baseline recorded ${_ago(recordedAt)}', style: context.textStyles.heading.copyWith(fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              '${snapshot.summary}${snapshot.volatile.isEmpty ? '' : ' · ${snapshot.volatile.length} changing ${snapshot.volatile.length == 1 ? 'field' : 'fields'} left out'}. '
              'It stays on this device and is not part of the workspace file or Git.',
              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: vm.busy ? null : vm.record,
                  icon: const Icon(Icons.fiber_manual_record_outlined, size: 16),
                  label: const Text('Record again from this response'),
                ),
                OutlinedButton.icon(
                  onPressed: vm.busy ? null : () => _confirmReset(context, vm),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset baseline'),
                ),
                OutlinedButton.icon(
                  onPressed: vm.busy ? null : vm.exportAll,
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export baselines…'),
                ),
              ],
            ),
          ],
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: vm.enforce,
        onChanged: vm.busy ? null : vm.setEnforce,
        title: const Text('Enforce baseline in runs'),
        subtitle: Text(
          'The collection runner and the command line add a result row "Baseline: N breaking changes" to this request, and fail it when a change can break a client.',
          style: context.textStyles.caption.copyWith(color: colors.secondaryText),
        ),
      ),
      const SizedBox(height: 4),
      if (report == null)
        const InfoBanner(
          kind: BannerKind.warning,
          message: 'This response was cut off at the size limit, so it cannot be compared with the baseline. Raise the limit in Settings and send again.',
        )
      else
        ..._drift(context, vm, report),
    ];
  }

  List<Widget> _drift(BuildContext context, BaselineViewModel vm, DriftReport report) {
    final colors = context.colors;
    if (report.isClean) {
      return const [InfoBanner(kind: BannerKind.success, title: 'No drift', message: 'This response matches the baseline.')];
    }
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '${report.breaking} breaking · ${report.nonBreaking} non-breaking · ${report.info} info',
              style: context.textStyles.heading.copyWith(fontSize: 13, color: report.breaking > 0 ? colors.statusError : null),
            ),
          ),
          TextButton(onPressed: vm.busy ? null : vm.acceptAll, child: const Text('Accept all')),
        ],
      ),
      for (final severity in DriftSeverity.values)
        if (report.ofSeverity(severity).isNotEmpty) ...[
          _SeverityHeader(severity: severity, count: report.ofSeverity(severity).length),
          for (final change in report.ofSeverity(severity)) _ChangeRow(key: ValueKey(change.id), viewModel: vm, change: change),
        ],
    ];
  }

  Future<void> _confirmReset(BuildContext context, BaselineViewModel vm) async {
    final go = await showConfirmDialog(
      context,
      title: 'Reset the baseline?',
      message: 'The recorded baseline of this request is removed from this device, and "Enforce baseline in runs" is turned off. '
          'You can record a new one from any response.',
      confirmLabel: 'Reset',
    );
    if (go) await vm.reset();
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return 'on ${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }
}

class _NoBaseline extends StatelessWidget {
  final BaselineViewModel viewModel;
  final bool probed;
  const _NoBaseline({required this.viewModel, required this.probed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final blocked = viewModel.recordBlockedReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_outlined, size: 20, color: colors.mainAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('No baseline yet', style: context.textStyles.heading)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'A baseline remembers what a good answer looks like: the status, the content type, field names and types, '
                'values that stay the same, and how long it took. Every later answer is compared with it, and a chip next to '
                'the response says whether the API drifted. The baseline stays on this device.',
                style: context.textStyles.body,
              ),
              const SizedBox(height: 6),
              Text(
                probed
                    ? 'The second answer from "Send again" is used to leave out values that change by themselves.'
                    : 'Tip: use "Send again" in the Suggestions section first, so values that change by themselves are left out.',
                style: context.textStyles.caption.copyWith(color: colors.secondaryText),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: viewModel.busy || blocked != null ? null : viewModel.record,
                  child: BusyLabel(busy: viewModel.busy, icon: Icons.fiber_manual_record_outlined, label: 'Record baseline', busyLabel: 'Recording…'),
                ),
              ),
            ],
          ),
        ),
        if (blocked != null) ...[const SizedBox(height: 8), InfoBanner(kind: BannerKind.warning, message: blocked)],
      ],
    );
  }
}

class _SeverityHeader extends StatelessWidget {
  final DriftSeverity severity;
  final int count;
  const _SeverityHeader({required this.severity, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = _color(context, severity);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '${severity.label.toUpperCase()} · $count',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 0.6),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final BaselineViewModel viewModel;
  final DriftChange change;
  const _ChangeRow({super.key, required this.viewModel, required this.change});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _color(context, change.severity);
    final where = change.path.isEmpty ? null : (change.kind == DriftKind.contentTypeChanged || change.kind == DriftKind.headerChanged ? 'header ${change.path}' : FieldPath.display(change.path));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(switch (change.severity) {
              DriftSeverity.breaking => Icons.warning_amber_rounded,
              DriftSeverity.nonBreaking => Icons.change_circle_outlined,
              DriftSeverity.info => Icons.info_outline,
            }, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(change.message, style: context.textStyles.body),
                if (where != null) Text(where, style: context.textStyles.mono.copyWith(fontSize: 11, color: colors.secondaryText)),
              ],
            ),
          ),
          TextButton(onPressed: viewModel.busy ? null : () => viewModel.accept(change), child: const Text('Accept')),
        ],
      ),
    );
  }
}

Color _color(BuildContext context, DriftSeverity severity) {
  final colors = context.colors;
  return switch (severity) {
    DriftSeverity.breaking => colors.statusError,
    DriftSeverity.nonBreaking => colors.statusWarning,
    DriftSeverity.info => colors.methodPut,
  };
}
