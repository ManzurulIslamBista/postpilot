import '../../../../core/enums/http_method.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../data/safety_prefs.dart';
import 'production_detector.dart';

/// Why a send needs confirming.
final class ProductionWarning {
  final String environmentName;
  final String description;
  const ProductionWarning(this.environmentName, this.description);
}

/// Checks a request about to leave the app: when the active environment looks
/// like production and the request changes data, the person is asked first.
final class ProductionGuard {
  final EnvironmentRepository _environments;
  final SafetyPrefs _prefs;

  const ProductionGuard(this._environments, this._prefs);

  Future<String?> _activeProductionName() async {
    if (!_prefs.confirmProductionWrites) return null;
    final active = await _environments.watchActive().first;
    if (active == null) return null;
    if (_prefs.isSilenced(active.name)) return null;
    return ProductionDetector.isProduction(active.name, extraWords: _prefs.extraWords) ? active.name : null;
  }

  /// `null` when the send may go ahead without asking.
  Future<ProductionWarning?> checkSend(HttpMethod method, String requestName) async {
    if (!ProductionDetector.changesData(method)) return null;
    final env = await _activeProductionName();
    if (env == null) return null;
    return ProductionWarning(env, '${method.label} "$requestName" changes data');
  }

  /// A collection run sends many requests; [writeCount] of them change data.
  Future<ProductionWarning?> checkRun(int writeCount, String collectionName) async {
    if (writeCount == 0) return null;
    final env = await _activeProductionName();
    if (env == null) return null;
    return ProductionWarning(env, 'Running "$collectionName" sends $writeCount data-changing request${writeCount == 1 ? '' : 's'}');
  }

  void silenceForSession(String environmentName) => _prefs.silenceForSession(environmentName);
}
