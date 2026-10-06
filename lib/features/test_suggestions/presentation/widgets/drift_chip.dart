import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../domain/entities/drift_report.dart';
import '../../domain/repositories/request_baseline_repository.dart';
import '../../domain/services/drift_detector.dart';

/// The "Drift" chip of the response area: how the response differs from the request's recorded baseline. Nothing
/// is shown for a request that has none. Pressing it opens the baseline view of the response tools.
class DriftChip extends StatefulWidget {
  final int requestId;
  final ApiResponseEntity response;

  /// Opens the baseline view; null leaves the chip as a plain readout.
  final VoidCallback? onOpen;

  /// The baselines to read; the app's own when null (and none when the app has not set them up).
  final RequestBaselineRepository? repository;

  const DriftChip({super.key, required this.requestId, required this.response, this.onOpen, this.repository});

  @override
  State<DriftChip> createState() => _DriftChipState();
}

class _DriftChipState extends State<DriftChip> {
  StreamSubscription<StoredBaseline?>? _subscription;
  StoredBaseline? _baseline;
  DriftReport? _report;

  RequestBaselineRepository? get _repository =>
      widget.repository ?? (locator.isRegistered<RequestBaselineRepository>() ? locator<RequestBaselineRepository>() : null);

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(covariant DriftChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId || oldWidget.repository != widget.repository) {
      _watch();
    } else if (!identical(oldWidget.response, widget.response)) {
      setState(_compare);
    }
  }

  void _watch() {
    _subscription?.cancel();
    _baseline = null;
    _report = null;
    _subscription = _repository?.watch(widget.requestId).listen((stored) {
      if (!mounted) return;
      setState(() {
        _baseline = stored;
        _compare();
      });
    }, onError: (Object _) {});
  }

  void _compare() {
    final snapshot = _baseline?.snapshot;
    // A body cut off at the size limit would read as "no longer JSON": it is not compared.
    _report = snapshot == null || widget.response.truncated ? null : DriftDetector.compare(snapshot, widget.response);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_baseline == null) return const SizedBox.shrink();
    final colors = context.colors;
    final report = _report;
    final (label, icon, color, hint) = report == null
        ? ('Drift: not checked', Icons.help_outline, null, 'The response was cut off at the size limit, so it was not compared with the baseline.')
        : switch (report.verdict) {
            DriftVerdict.clean => ('Drift: clean', Icons.check_circle_outline, colors.statusSuccess, 'This response matches the baseline.'),
            DriftVerdict.info => ('Drift: ${report.info} info', Icons.info_outline, colors.methodPut, report.changes.first.message),
            DriftVerdict.nonBreaking => (
                'Drift: ${report.nonBreaking} non-breaking',
                Icons.change_circle_outlined,
                colors.statusWarning,
                report.changes.first.message,
              ),
            DriftVerdict.breaking => (
                'Drift: ${report.breaking} breaking',
                Icons.warning_amber_rounded,
                colors.statusError,
                report.changes.first.message,
              ),
          };
    final chip = StatusChip(label: label, icon: icon, color: color);
    return Tooltip(
      message: widget.onOpen == null ? hint : '$hint\nPress to see what changed.',
      child: widget.onOpen == null
          ? chip
          : InkWell(borderRadius: BorderRadius.circular(20), onTap: widget.onOpen, child: chip),
    );
  }
}
