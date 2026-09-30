import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/request_settings.dart';
import '../../domain/repositories/request_settings_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// Backs one request's Settings tab: its overrides of the global settings, and
/// the global settings alongside so the tab can show what "use global"
/// currently means.
///
/// Every edit is written at once rather than after a delay: the tab sits next
/// to the Send button, and a request sent right after an edit must see it.
final class RequestSettingsViewModel with ChangeNotifier {
  final RequestSettingsRepository _repository;
  final SettingsRepository _globalRepository;

  late final StreamSubscription<AppSettings> _globalSubscription;
  AppSettings _global;
  RequestSettings _overrides = RequestSettings.none;
  int? _requestId;
  Future<void> _lastSave = Future.value();
  bool _disposed = false;

  bool isLoading = false;

  /// Set when the last save failed; cleared by the next edit.
  String? saveError;

  RequestSettingsViewModel(this._repository, this._globalRepository) : _global = _globalRepository.current {
    _globalSubscription = _globalRepository.watch().listen((settings) {
      if (settings == _global) return;
      _global = settings;
      if (!_disposed) notifyListeners();
    });
  }

  RequestSettings get overrides => _overrides;
  AppSettings get global => _global;

  Future<void> load(int requestId) async {
    final savingPrevious = _lastSave;
    _requestId = requestId;
    _overrides = RequestSettings.none;
    isLoading = true;
    notifyListeners();
    await savingPrevious;

    RequestSettings loaded;
    try {
      loaded = await _repository.get(requestId);
    } catch (_) {
      loaded = RequestSettings.none;
    }
    if (_requestId != requestId || _disposed) return; // a newer load() superseded this one

    _overrides = loaded;
    isLoading = false;
    notifyListeners();
  }

  void setFollowRedirects(bool? value) => _update(_overrides.withFollowRedirects(value));

  void setVerifySsl(bool? value) => _update(_overrides.withVerifySsl(value));

  void setSendNoCacheHeader(bool? value) => _update(_overrides.withSendNoCacheHeader(value));

  /// Null follows the global timeout; 0 waits forever for this request.
  void setTimeoutSeconds(int? seconds) => _update(
        _overrides.withTimeoutSeconds(seconds == null ? null : math.min(math.max(seconds, 0), AppSettings.maxTimeoutSeconds)),
      );

  void clear() => _update(RequestSettings.none);

  /// Completes once every edit made so far has been written.
  Future<void> flush() => _lastSave;

  void _update(RequestSettings next) {
    final requestId = _requestId;
    if (next == _overrides || requestId == null) return;
    _overrides = next;
    saveError = null;
    _lastSave = _save(requestId, next);
    notifyListeners();
  }

  Future<void> _save(int requestId, RequestSettings overrides) async {
    try {
      await _repository.save(requestId, overrides);
    } catch (_) {
      saveError = "Couldn't save this request's settings";
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _globalSubscription.cancel();
    super.dispose();
  }
}
