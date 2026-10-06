/// How a program on one device reaches a server running on this computer.
/// `localhost` means "this device" everywhere, which is exactly what trips up
/// mobile developers: on an Android emulator it is the emulator itself.
final class DeviceTarget {
  final String name;
  final String host;
  final String note;
  const DeviceTarget(this.name, this.host, this.note);
}

abstract final class DeviceTargets {
  /// Hosts that mean "this computer" in a URL written for desktop.
  static final _localHosts = RegExp(r'^(localhost|127\.0\.0\.1|0\.0\.0\.0|::1)$', caseSensitive: false);

  static List<DeviceTarget> forEmulators() => const [
        DeviceTarget('Android emulator', '10.0.2.2', "The emulator's alias for the computer it runs on."),
        DeviceTarget('Genymotion', '10.0.3.2', "Genymotion's alias for the host computer."),
        DeviceTarget('iOS simulator', 'localhost', 'The simulator shares the Mac network, so localhost works.'),
        DeviceTarget('Flutter web / desktop', 'localhost', 'Runs on this computer: localhost works.'),
      ];

  /// Why an `http://` address can still fail on a phone after it is reachable: both systems block
  /// plain http by default.
  static const cleartextNote = 'Plain http:// is blocked on phones by default. Android 9 and later: put '
      'android:usesCleartextTraffic="true" on <application> in AndroidManifest.xml (for debug builds), or limit it to this host '
      'with a network security config. iOS: set NSAppTransportSecurity > NSAllowsLocalNetworking to true in Info.plist; '
      'iOS 14 and later also asks the user to allow local network access.';

  /// Whether [url] is plain http, the case [cleartextNote] is about.
  static bool usesCleartext(String url) => Uri.tryParse(url.trim())?.scheme.toLowerCase() == 'http';

  /// `adb reverse` makes a USB-connected Android device's localhost point at this computer.
  static String adbReverse(int port) => 'adb reverse tcp:$port tcp:$port';

  /// Whether [url] points at this computer, so rewriting it makes sense.
  static bool isLocal(String url) {
    final uri = _parse(url);
    return uri != null && _localHosts.hasMatch(uri.host);
  }

  /// [url] with its host replaced by [host], keeping scheme, port, path and query.
  /// Returns null for a URL that is not absolute (a `{{variable}}` base, for instance).
  static String? rewrite(String url, String host) {
    final uri = _parse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.replace(host: host).toString();
  }

  /// Port in [url], or [fallback] when there is none.
  static int portOf(String url, {int fallback = 3000}) {
    final uri = _parse(url);
    if (uri == null || !uri.hasPort) return fallback;
    return uri.port;
  }

  static Uri? _parse(String url) {
    final t = url.trim();
    if (t.isEmpty || t.contains('{{')) return null;
    return Uri.tryParse(t.contains('://') ? t : 'http://$t');
  }
}
