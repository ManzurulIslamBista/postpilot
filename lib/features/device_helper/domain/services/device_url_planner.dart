import 'connected_device.dart';

/// The change "Use for `<environment>`" would make to one variable, worked out before anything is touched so it can be shown.
final class DeviceUrlPlan {
  final ConnectedDevice device;

  /// The variable's value now.
  final String before;

  /// The value after the change; null when it cannot be worked out ([error] says why).
  final String? after;

  /// The host that [after] points at.
  final String? host;

  /// Set when `adb reverse tcp:N tcp:N` must be run on the device first, so that its `localhost:N` reaches this computer.
  final int? reversePort;
  final String? error;

  /// Things to know before accepting the change.
  final List<String> notes;

  const DeviceUrlPlan({
    required this.device,
    required this.before,
    this.after,
    this.host,
    this.reversePort,
    this.error,
    this.notes = const [],
  });

  bool get ok => error == null && after != null;

  /// The value is already right: nothing to write.
  bool get isUnchanged => ok && after == before;

  /// The command that sets up the forward, for display.
  String? get reverseCommand => reversePort == null ? null : 'adb -s ${device.id} reverse tcp:$reversePort tcp:$reversePort';
}

/// Which host a URL must have to reach the server on this computer from a given device:
/// Android emulator `10.0.2.2`; a phone `localhost` through `adb reverse`, or this computer's LAN address when reverse is not
/// wanted; iOS simulator `localhost`.
abstract final class DeviceUrlPlanner {
  static DeviceUrlPlan plan(ConnectedDevice device, String url, {bool useReverse = true, String? lanIp}) {
    DeviceUrlPlan fail(String message) => DeviceUrlPlan(device: device, before: url, error: message);

    final t = url.trim();
    if (t.isEmpty) return fail('The variable is empty. Give it an address such as http://localhost:3000 first.');
    if (t.contains('{{')) return fail('That value is built from another {{variable}}. Change that variable instead.');
    final uri = _parse(t);
    if (uri == null || uri.host.isEmpty) return fail('"$t" is not an address with a host, so there is no host to change.');
    if (!device.isReady) return fail(device.problem ?? 'The device is not ready.');

    String host;
    int? reversePort;
    final notes = <String>[];
    switch (device.kind) {
      case DeviceKind.androidEmulator:
        host = '10.0.2.2';
        notes.add('10.0.2.2 is the emulator\'s alias for this computer.');
      case DeviceKind.iosSimulator:
        host = 'localhost';
        notes.add('The simulator shares this Mac\'s network, so localhost works.');
      case DeviceKind.androidDevice:
        if (useReverse) {
          final port = uri.hasPort ? uri.port : _defaultPort(uri.scheme);
          if (port <= 0) return fail('"$t" has no port, so adb reverse does not know which one to forward. Add one such as :3000.');
          host = 'localhost';
          reversePort = port;
          notes.add('adb reverse makes the phone\'s localhost:$port reach this computer\'s port $port over the cable. It lasts until the phone is unplugged or adb restarts.');
        } else {
          if (lanIp == null || lanIp.isEmpty) {
            return fail('No network address of this computer was found. Connect to Wi-Fi or Ethernet, or use adb reverse.');
          }
          host = lanIp;
          notes.add('The server must listen on all interfaces ("Allow other devices" in the mock server) and the firewall must allow the port.');
        }
    }
    if (!isDevelopmentHost(uri.host)) {
      notes.add('"${uri.host}" is not an address on this computer. After the change the app talks to this computer instead of that server.');
    }
    return DeviceUrlPlan(
      device: device,
      before: url,
      after: rewriteHost(url, host),
      host: host,
      reversePort: reversePort,
      notes: notes,
    );
  }

  /// Whether [value] is an address a device could be pointed at: `http://localhost:3000/api` or, without a scheme, something that
  /// is clearly a host (`localhost`, `10.0.2.2:3000`, `api.example.com`). `5000` or `abc` are not.
  static bool looksLikeAddress(String value) {
    final t = value.trim();
    if (t.isEmpty || t.contains('{{') || t.contains(RegExp(r'\s'))) return false;
    final uri = _parse(t);
    if (uri == null || uri.host.isEmpty) return false;
    if (t.contains('://')) return true;
    if (uri.host == 'localhost' || uri.hasPort) return true;
    // Digits and dots are an address only as a whole IPv4 one: a version such as 1.2.3 is not.
    if (RegExp(r'^[0-9.]+$').hasMatch(uri.host)) return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host);
    return RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(uri.host);
  }

  /// [url] with its host replaced, keeping scheme, port, path, query and fragment. An address without a scheme
  /// (`localhost:3000/api`) stays without one. Null when there is no host to replace.
  static String? rewriteHost(String url, String host) {
    final t = url.trim();
    final hasScheme = t.contains('://');
    final uri = _parse(t);
    if (uri == null || uri.host.isEmpty) return null;
    final out = uri.replace(host: host).toString();
    return hasScheme ? out : out.substring('http://'.length);
  }

  /// Hosts that mean "this computer" or one of the addresses used to reach it: localhost, loopback, the emulator aliases and the
  /// private network ranges.
  static bool isDevelopmentHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h == '0.0.0.0' || h == '10.0.2.2' || h == '10.0.3.2' || h.endsWith('.local')) return true;
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(h);
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  static int _defaultPort(String scheme) => switch (scheme.toLowerCase()) {
        'http' || 'ws' => 80,
        'https' || 'wss' => 443,
        _ => 0,
      };

  static Uri? _parse(String t) => Uri.tryParse(t.contains('://') ? t : 'http://$t');
}
