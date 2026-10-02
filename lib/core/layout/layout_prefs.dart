import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the response panel sits relative to the request editor.
enum ResponseLayout { right, bottom }

/// Window-layout choices the user makes by dragging or toggling: sidebar
/// width/collapse, the request/response split and its orientation. Kept in
/// local preferences (per device: a phone and a desktop want different
/// layouts), not synced with the account.
///
/// Dragging updates the in-memory value on every frame; [commit] writes it
/// once the drag ends, so a drag is not a stream of disk writes.
class LayoutPrefs extends ChangeNotifier {
  static const sidebarMin = 220.0;
  static const sidebarMax = 480.0;
  static const sidebarDefault = 288.0;
  static const fractionMin = 0.25;
  static const fractionMax = 0.75;

  static const _kSidebarWidth = 'layout.sidebarWidth';
  static const _kSidebarCollapsed = 'layout.sidebarCollapsed';
  static const _kResponseLayout = 'layout.responseLayout';
  static const _kRequestFraction = 'layout.requestFraction';

  SharedPreferences? _prefs;
  double _sidebarWidth = sidebarDefault;
  bool _sidebarCollapsed = false;
  ResponseLayout _responseLayout = ResponseLayout.right;
  double _requestFraction = 0.5;

  double get sidebarWidth => _sidebarWidth;
  bool get sidebarCollapsed => _sidebarCollapsed;
  ResponseLayout get responseLayout => _responseLayout;

  /// Share of the available space the request editor takes (0..1).
  double get requestFraction => _requestFraction;

  /// Reads the stored values. Never throws: a device without working storage
  /// just keeps the defaults for this run.
  Future<void> load() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _sidebarWidth = (prefs.getDouble(_kSidebarWidth) ?? sidebarDefault).clamp(sidebarMin, sidebarMax);
      _sidebarCollapsed = prefs.getBool(_kSidebarCollapsed) ?? false;
      _responseLayout =
          prefs.getString(_kResponseLayout) == ResponseLayout.bottom.name ? ResponseLayout.bottom : ResponseLayout.right;
      _requestFraction = (prefs.getDouble(_kRequestFraction) ?? 0.5).clamp(fractionMin, fractionMax);
      notifyListeners();
    } catch (_) {
      _prefs = null;
    }
  }

  void setSidebarWidth(double width) {
    final next = width.clamp(sidebarMin, sidebarMax);
    if (next == _sidebarWidth) return;
    _sidebarWidth = next;
    notifyListeners();
  }

  void resetSidebarWidth() {
    _sidebarWidth = sidebarDefault;
    notifyListeners();
    commit();
  }

  void toggleSidebar() {
    _sidebarCollapsed = !_sidebarCollapsed;
    notifyListeners();
    commit();
  }

  void setRequestFraction(double fraction) {
    final next = fraction.clamp(fractionMin, fractionMax);
    if (next == _requestFraction) return;
    _requestFraction = next;
    notifyListeners();
  }

  void resetRequestFraction() {
    _requestFraction = 0.5;
    notifyListeners();
    commit();
  }

  void setResponseLayout(ResponseLayout layout) {
    if (layout == _responseLayout) return;
    _responseLayout = layout;
    notifyListeners();
    commit();
  }

  void toggleResponseLayout() =>
      setResponseLayout(_responseLayout == ResponseLayout.right ? ResponseLayout.bottom : ResponseLayout.right);

  /// Persists the current values; call when a drag ends.
  Future<void> commit() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setDouble(_kSidebarWidth, _sidebarWidth);
      await prefs.setBool(_kSidebarCollapsed, _sidebarCollapsed);
      await prefs.setString(_kResponseLayout, _responseLayout.name);
      await prefs.setDouble(_kRequestFraction, _requestFraction);
    } catch (_) {
      // Layout is a convenience; failing to remember it must not surface.
    }
  }
}
