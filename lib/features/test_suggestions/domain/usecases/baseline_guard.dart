import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../scripting/domain/entities/assertion_result.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../repositories/request_baseline_repository.dart';
import '../services/baseline_check.dart';

/// Holds a request to its recorded baseline when a run asks for it: the collection runner calls it after each
/// send, and a request that turned on "Enforce baseline in runs" gets one more result row,
/// `Baseline: N breaking changes`.
final class BaselineGuard {
  final RequestBaselineRepository _baselines;
  final RequestSettingsRepository _settings;

  const BaselineGuard(this._baselines, this._settings);

  /// The row for [response] of [requestId], or null when the request does not enforce a baseline.
  Future<AssertionResult?> rowFor(int requestId, ApiResponseEntity response) async {
    try {
      final settings = await _settings.get(requestId);
      if (!settings.baseline.enforce) return null;
      final stored = await _baselines.get(requestId);
      return BaselineCheck.evaluate(stored?.snapshot, response);
    } catch (e) {
      // Enforcement was asked for, so a check that could not run must not pass quietly.
      return AssertionResult(
        name: 'Baseline: could not be checked',
        passed: false,
        actual: SecretMasker.maskMessage('$e'),
      );
    }
  }
}
