import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../domain/entities/monitor_config.dart';
import 'monitor_dialog.dart';
import 'monitor_service.dart';
import 'run_history_dialog.dart';

/// The monitor's presence in the sidebar: a chip while any collection is monitored (`Monitor: 2 failing`, or
/// `Monitor: on`), and a banner for each run that went from passing to failing. It also starts the monitor when the
/// sidebar first appears and tells it when the app goes away or comes back, so no timer outlives the app.
///
/// Shows nothing at all while no collection is monitored, and when the app has no monitor (a test).
class MonitorStatusPanel extends StatefulWidget {
  /// Replaces the monitor the injector holds, for a test.
  @visibleForTesting
  final MonitorService? service;

  const MonitorStatusPanel({super.key, this.service});

  @override
  State<MonitorStatusPanel> createState() => _MonitorStatusPanelState();
}

class _MonitorStatusPanelState extends State<MonitorStatusPanel> with WidgetsBindingObserver {
  MonitorService? get _service => widget.service ?? (locator.isRegistered<MonitorService>() ? locator<MonitorService>() : null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service?.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _service?.onLifecycle(state);

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.isActive && service.alerts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final alert in service.alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InfoBanner(
                    kind: BannerKind.error,
                    title: '${alert.collectionName} started failing',
                    message: '${alert.failed} ${alert.failed == 1 ? 'request' : 'requests'} failed in the last monitor run.',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => RunHistoryDialog.show(context, collectionId: alert.collectionId, collectionName: alert.collectionName),
                          child: const Text('Triage'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Dismiss',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => service.dismissAlert(alert.collectionId),
                        ),
                      ],
                    ),
                  ),
                ),
              if (service.isActive) _Chip(service: service),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final MonitorService service;
  const _Chip({required this.service});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failing = service.failingCount;
    final color = failing > 0 ? colors.statusError : colors.statusSuccess;
    final label = failing > 0 ? 'Monitor: $failing failing' : 'Monitor: on';
    return PopupMenuButton<int>(
      tooltip: 'Monitored collections',
      onSelected: (id) {
        final entry = service.monitored.where((m) => m.collectionId == id).firstOrNull;
        if (entry != null) MonitorDialog.show(context, collectionId: id, collectionName: entry.name);
      },
      itemBuilder: (context) => [
        for (final m in service.monitored)
          PopupMenuItem<int>(
            value: m.collectionId,
            child: Row(
              children: [
                Icon(m.status.isFailing ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: m.status.isFailing ? colors.statusError : colors.statusSuccess),
                const SizedBox(width: 8),
                Flexible(child: Text('${m.name}: ${_describe(m.status)}', overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12), overflow: TextOverflow.ellipsis)),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  static String _describe(MonitorStatus s) => switch (s.state) {
        MonitorState.failing => 'failing (${s.failed})',
        MonitorState.passing => 'passing',
        MonitorState.running => 'running',
        MonitorState.error => 'could not run',
        _ => 'waiting',
      };
}
