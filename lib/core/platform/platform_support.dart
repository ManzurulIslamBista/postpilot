import 'package:flutter/foundation.dart' show kIsWeb;

/// Things PostPilot does on desktop (and mostly on mobile) that a browser cannot do. Every gate in the app asks here, so
/// the browser build says the same thing everywhere instead of each dialog finding its own words.
enum PlatformFeature {
  /// The mock server listens on a port of this computer.
  mockServer('browsers cannot open server sockets'),

  /// The traffic recorder is a local server the app under test calls.
  trafficRecorder('browsers cannot open server sockets');

  const PlatformFeature(this._why);

  final String _why;

  /// Whether this feature works here. [web] says whether the app runs in a browser; it is only passed in tests.
  bool isSupported({bool web = kIsWeb}) => !web;

  /// Why the feature cannot be used here, ready to show: null when it can be used.
  String? reason({bool web = kIsWeb}) => isSupported(web: web) ? null : 'Needs the desktop app: $_why';
}
