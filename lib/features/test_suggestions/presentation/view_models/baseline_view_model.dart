import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../domain/entities/baseline_settings.dart';
import '../../domain/entities/drift_report.dart';
import '../../domain/repositories/request_baseline_repository.dart';
import '../../domain/services/baseline_recorder.dart';
import '../../domain/services/drift_accept.dart';
import '../../domain/services/drift_detector.dart';
import '../../domain/services/stability_probe.dart';
import '../../domain/services/baseline_file.dart';

/// Backs the "Baseline & drift" half of the Suggest tests tab: records the response as the request's baseline,
/// says how the response differs from it, accepts changes, resets, switches "Enforce baseline in runs" and exports
/// the baselines of this device for the command line.
final class BaselineViewModel with ChangeNotifier {
  final int requestId;
  final ApiResponseEntity response;
  final RequestBaselineRepository _baselines;
  final RequestSettingsRepository _settings;
  final Future<BaselineFile> Function()? _export;

  /// What a second response (the stability probe) showed to change by itself; null when there was none.
  final StabilityReport? Function() _stability;

  /// Offers a file to the person; returns where it went, null when they cancelled.
  final Future<String?> Function(String fileName, Uint8List bytes) _saveFile;

  BaselineViewModel({
    required this.requestId,
    required this.response,
    required this._baselines,
    required this._settings,
    this._export,
    StabilityReport? Function()? stability,
    required this._saveFile,
  }) : _stability = stability ?? (() => null);

  StoredBaseline? stored;

  /// This response against [stored]; null without a baseline.
  DriftReport? report;
  bool enforce = false;
  bool loaded = false;
  bool busy = false;

  /// What happened last, in words; [noticeIsError] says whether it went wrong.
  String? notice;
  bool noticeIsError = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      stored = await _baselines.get(requestId);
      enforce = (await _settings.get(requestId)).baseline.enforce;
    } catch (e) {
      _say('The baseline could not be read: ${SecretMasker.maskMessage('$e')}', error: true);
    }
    _compare();
    loaded = true;
    _notify();
  }

  void _compare() {
    final baseline = stored?.snapshot;
    report = baseline == null || response.truncated ? null : DriftDetector.compare(baseline, response);
  }

  /// Why this response cannot be recorded, or null when it can.
  String? get recordBlockedReason => response.truncated
      ? 'This response was cut off at the size limit, so a baseline made from it would describe only the part that arrived. '
          'Raise the limit in Settings and send again.'
      : null;

  bool get hasBaseline => stored != null;

  // --- recording and resetting ---------------------------------------------------

  /// Records this response as the baseline (replacing the one there is). A second response, when the stability probe
  /// ran, tells which values change by themselves, and what an earlier baseline already knew about stays known.
  Future<void> record() async {
    final blocked = recordBlockedReason;
    if (blocked != null) {
      _say(blocked, error: true);
      return;
    }
    await _run(() async {
      final snapshot = BaselineRecorder.record(response, stability: _stability(), volatile: stored?.snapshot.volatile ?? const {});
      await _baselines.save(requestId, snapshot);
      await _reload();
      _say('Baseline recorded: ${snapshot.summary}. It stays on this device.');
    });
  }

  /// Takes the baseline away, and with it "Enforce baseline in runs": there would be nothing to enforce.
  Future<void> reset() async {
    await _run(() async {
      await _baselines.delete(requestId);
      if (enforce) await _saveEnforce(false);
      await _reload();
      _say('Baseline removed.');
    });
  }

  // --- drift ---------------------------------------------------------------------

  /// Takes [change] over into the baseline: the response has it from now on.
  Future<void> accept(DriftChange change) => _accept([change]);

  Future<void> acceptAll() => _accept(report?.changes ?? const []);

  Future<void> _accept(List<DriftChange> changes) async {
    final baseline = stored?.snapshot;
    if (baseline == null || changes.isEmpty) return;
    await _run(() async {
      await _baselines.save(requestId, DriftAccept.apply(baseline, response, changes), note: stored?.note ?? '');
      await _reload();
      _say(changes.length == 1 ? 'Change accepted: the baseline now has it.' : '${changes.length} changes accepted: the baseline matches this response.');
    });
  }

  // --- runs and files ------------------------------------------------------------

  Future<void> setEnforce(bool value) async {
    if (value == enforce) return;
    await _run(() async {
      await _saveEnforce(value);
      enforce = value;
    });
  }

  Future<void> _saveEnforce(bool value) async {
    final current = await _settings.get(requestId);
    await _settings.save(requestId, current.withBaseline(BaselineSettings(enforce: value)));
    enforce = value;
  }

  /// Saves every baseline of this device as a JSON file for `postpilot run --baseline-file`.
  Future<void> exportAll() async {
    final export = _export;
    if (export == null) return;
    await _run(() async {
      final file = await export();
      if (file.entries.isEmpty) {
        _say('There are no baselines to export yet.', error: true);
        return;
      }
      final path = await _saveFile('postpilot-baselines.json', Uint8List.fromList(utf8.encode(file.encode())));
      if (path != null) {
        _say('Exported ${file.entries.length} ${file.entries.length == 1 ? 'baseline' : 'baselines'} to $path. '
            'Pass the file to the command line with --baseline-file.');
      }
    });
  }

  // --- plumbing ------------------------------------------------------------------

  Future<void> _reload() async {
    stored = await _baselines.get(requestId);
    enforce = (await _settings.get(requestId)).baseline.enforce;
    _compare();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    notice = null;
    _notify();
    try {
      await action();
    } catch (e) {
      _say('That did not work: ${SecretMasker.maskMessage('$e')}', error: true);
    } finally {
      busy = false;
      _notify();
    }
  }

  void _say(String text, {bool error = false}) {
    notice = text;
    noticeIsError = error;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
