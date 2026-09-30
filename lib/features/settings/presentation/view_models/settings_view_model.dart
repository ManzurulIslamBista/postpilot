import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import '../../../../core/network/api_http_response.dart' show ProxyMode;
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// Backs the settings dialog and the app's theme. Every change shows at once
/// and is saved [saveDelay] after the last one, so typing into a field does
/// not write on every keystroke; [flush] saves without waiting.
final class SettingsViewModel with ChangeNotifier {
  final SettingsRepository _repository;
  final Duration saveDelay;

  late final StreamSubscription<AppSettings> _subscription;
  AppSettings _settings;
  Timer? _timer;
  bool _hasUnsavedChanges = false;
  bool _disposed = false;

  /// Set when the last save failed; cleared by the next change.
  String? saveError;

  SettingsViewModel(this._repository, {this.saveDelay = const Duration(milliseconds: 400)})
      : _settings = _repository.current {
    _subscription = _repository.watch().listen(_onStored);
  }

  AppSettings get settings => _settings;

  ThemeMode get themeMode => switch (_settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  void setThemeMode(AppThemeMode mode) => _update(_settings.copyWith(themeMode: mode));

  void setRequestTimeoutSeconds(int seconds) =>
      _update(_settings.copyWith(requestTimeoutSeconds: _within(seconds, 0, AppSettings.maxTimeoutSeconds)));

  void setFollowRedirects(bool value) => _update(_settings.copyWith(followRedirects: value));

  void setMaxRedirects(int count) =>
      _update(_settings.copyWith(maxRedirects: _within(count, 1, AppSettings.maxRedirectsLimit)));

  void setVerifySsl(bool value) => _update(_settings.copyWith(verifySsl: value));

  void setSendNoCacheHeader(bool value) => _update(_settings.copyWith(sendNoCacheHeader: value));

  void setTrimKeysAndValues(bool value) => _update(_settings.copyWith(trimKeysAndValues: value));

  void setMaxResponseSizeMb(int megabytes) => _update(
        _settings.copyWith(maxResponseSizeMb: _within(megabytes, 0, AppSettings.maxResponseSizeMbLimit)),
      );

  void setProxyMode(ProxyMode mode) => _update(_settings.copyWith(proxy: _settings.proxy.copyWith(mode: mode)));

  void setProxyHost(String host) => _update(_settings.copyWith(proxy: _settings.proxy.copyWith(host: host)));

  void setProxyPort(int port) =>
      _update(_settings.copyWith(proxy: _settings.proxy.copyWith(port: _within(port, 1, 65535))));

  void setProxyUsername(String username) =>
      _update(_settings.copyWith(proxy: _settings.proxy.copyWith(username: username)));

  void setProxyPassword(String password) =>
      _update(_settings.copyWith(proxy: _settings.proxy.copyWith(password: password)));

  void setProxyBypass(String bypass) => _update(_settings.copyWith(proxy: _settings.proxy.copyWith(bypass: bypass)));

  /// Saves any change still waiting out the delay.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_hasUnsavedChanges) return;
    _hasUnsavedChanges = false;
    try {
      await _repository.save(_settings);
    } catch (_) {
      _failed();
    }
  }

  Future<void> reset() async {
    _timer?.cancel();
    _timer = null;
    _hasUnsavedChanges = false;
    _settings = const AppSettings();
    saveError = null;
    notifyListeners();
    try {
      await _repository.reset();
    } catch (_) {
      _failed();
    }
  }

  void _update(AppSettings next) {
    if (next == _settings) return;
    _settings = next;
    _hasUnsavedChanges = true;
    saveError = null;
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(flush()));
    notifyListeners();
  }

  /// Settings that changed underneath this view model (the startup load
  /// arriving late, a restore) are adopted, unless an edit of its own is
  /// still waiting to be saved — that edit is newer. Its own saves come back
  /// here equal to what it already holds.
  void _onStored(AppSettings stored) {
    if (_hasUnsavedChanges || stored == _settings) return;
    _settings = stored;
    notifyListeners();
  }

  void _failed() {
    saveError = "Couldn't save your settings";
    if (!_disposed) notifyListeners();
  }

  int _within(int value, int min, int max) => math.min(math.max(value, min), max);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _subscription.cancel();
    if (_hasUnsavedChanges) unawaited(_repository.save(_settings).catchError((Object _) {}));
    super.dispose();
  }
}
