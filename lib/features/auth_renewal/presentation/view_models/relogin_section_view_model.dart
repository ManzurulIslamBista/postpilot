import 'package:flutter/foundation.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/usecases/send_request_usecase.dart';
import '../../domain/entities/relogin_config.dart';
import '../../domain/services/relogin_policy.dart';
import '../../domain/usecases/relogin_usecase.dart';

/// Behind the "Re-login on 401/403" section of the Auth tab: the requests of the collection the login
/// request can be picked from, and the "Test" button that runs the chosen one.
final class ReloginSectionViewModel with ChangeNotifier {
  final ReloginUseCase _relogin;
  final SendRequestUseCase _send;

  ReloginSectionViewModel(this._relogin, this._send);

  List<ReloginCandidate<RequestSummaryEntity>> candidates = const [];
  bool isLoading = false;
  bool isTesting = false;
  ReloginTestResult? testResult;
  bool _disposed = false;

  Future<void> load(int collectionId) async {
    isLoading = true;
    notifyListeners();
    try {
      candidates = await _relogin.candidates(collectionId);
    } catch (_) {
      candidates = const [];
    }
    isLoading = false;
    notifyListeners();
  }

  /// Sends the login request of [config] once, the way a re-login would (its extractors fill the token
  /// variable), and keeps what happened in [testResult].
  Future<void> test(int collectionId, ReloginConfig config) async {
    if (isTesting) return;
    isTesting = true;
    testResult = null;
    notifyListeners();
    try {
      testResult = await _relogin.test(collectionId, config, login: (request) => _send(request, reLogin: false));
    } catch (e) {
      testResult = ReloginTestResult(false, 'The login could not be run: $e');
    }
    isTesting = false;
    notifyListeners();
  }

  /// The request that is most likely the login: a name that says so, else the first one.
  ReloginCandidate<RequestSummaryEntity>? get likelyLogin {
    if (candidates.isEmpty) return null;
    final named = candidates.where((c) => RegExp(r'log.?in|sign.?in|auth|token', caseSensitive: false).hasMatch(c.name));
    return named.firstOrNull ?? candidates.first;
  }

  void clearResult() {
    if (testResult == null) return;
    testResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A request can outlive the section that asked for it, and notifying a disposed notifier asserts.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
