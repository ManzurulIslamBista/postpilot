import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../settings/domain/entities/request_settings.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../domain/entities/flow_settings.dart';
import '../../domain/entities/pagination_settings.dart';
import '../../domain/services/pagination_detector.dart';

/// Backs one request's Flow tab: its retry, poll until, run if and fetch-all-pages settings. They live in the same
/// row as the request's other settings, so every edit is written at once, on top of what the row holds now: a
/// request sent right after an edit must see it, and the other settings must not be overwritten.
final class RequestFlowViewModel with ChangeNotifier {
  final RequestSettingsRepository _repository;

  RequestSettings _settings = RequestSettings.none;
  int? _requestId;
  Future<void> _lastSave = Future.value();
  bool _disposed = false;

  bool isLoading = false;

  /// Set when the last save failed; cleared by the next edit.
  String? saveError;

  RequestFlowViewModel(this._repository);

  FlowSettings get flow => _settings.flow;
  PaginationSettings get pagination => _settings.pagination;

  Future<void> load(int requestId) async {
    final savingPrevious = _lastSave;
    _requestId = requestId;
    _settings = RequestSettings.none;
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

    _settings = loaded;
    isLoading = false;
    notifyListeners();
  }

  void setRetry(RetryPolicy value) => _update(_settings.withFlow(flow.copyWith(retry: value)));

  void setPoll(PollPolicy value) => _update(_settings.withFlow(flow.copyWith(poll: value)));

  void setRunIf(RunIfPolicy value) => _update(_settings.withFlow(flow.copyWith(runIf: value)));

  void setAlwaysRun(bool value) => _update(_settings.withFlow(flow.copyWith(alwaysRun: value)));

  void setRepeatUnsafe(bool value) => _update(_settings.withFlow(flow.copyWith(repeatUnsafe: value)));

  void setPagination(PaginationSettings value) => _update(_settings.withPagination(value));

  /// Takes what [PaginationDetector] found and turns Fetch all pages on with it. A read that goes over POST (an
  /// Odoo `search_read`) also ticks "repeating is safe": the person has just been shown that it only reads.
  void useDetection(PaginationDetection detection) => _update(
        _settings
            .withPagination(detection.settings.copyWith(enabled: true))
            .withFlow(detection.readOnlyPost ? flow.copyWith(repeatUnsafe: true) : flow),
      );

  /// Completes once every edit made so far has been written.
  Future<void> flush() => _lastSave;

  void _update(RequestSettings next) {
    final requestId = _requestId;
    if (next == _settings || requestId == null) return;
    _settings = next;
    saveError = null;
    _lastSave = _save(requestId, next);
    notifyListeners();
  }

  Future<void> _save(int requestId, RequestSettings settings) async {
    try {
      await _repository.save(requestId, settings);
    } catch (_) {
      saveError = "Couldn't save this request's flow settings";
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
