import 'dart:convert';

enum DeviceKind {
  androidEmulator('Android emulator'),
  androidDevice('Android phone or tablet'),
  iosSimulator('iOS simulator');

  const DeviceKind(this.label);

  final String label;
}

/// What the tool reports about a device: only a [ready] one can be used.
enum DeviceState { ready, offline, unauthorized, noPermissions, other }

enum DeviceTransport {
  emulator('emulator'),
  usb('USB'),
  wifi('Wi-Fi'),
  simulator('simulator');

  const DeviceTransport(this.label);

  final String label;
}

/// A running emulator, simulator or attached phone, as `adb devices -l` or `simctl` listed it.
final class ConnectedDevice {
  /// The adb serial (`emulator-5554`, `ZD222LBHP4`, `192.168.1.20:5555`) or the simulator's UDID.
  final String id;

  /// The model or simulator name, readable (`moto g24 power`, `iPhone 15 Pro`).
  final String name;
  final DeviceKind kind;
  final DeviceState state;

  /// The state word as the tool printed it (`device`, `unauthorized`, `Booted`).
  final String stateText;
  final DeviceTransport transport;

  /// `Android 14`, `iOS 17.5`; null when not known (it needs a second adb call, which can fail).
  final String? osVersion;

  const ConnectedDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.state,
    required this.stateText,
    required this.transport,
    this.osVersion,
  });

  bool get isReady => state == DeviceState.ready;
  bool get isAndroid => kind != DeviceKind.iosSimulator;

  /// Why a device that is not [isReady] cannot be used, and what to do about it; null for a ready one.
  String? get problem => switch (state) {
        DeviceState.ready => null,
        DeviceState.offline => 'The device is offline. Unplug and replug the cable, or run "adb reconnect".',
        DeviceState.unauthorized => 'Unlock the phone and accept the "Allow USB debugging" prompt, then scan again.',
        DeviceState.noPermissions => 'This computer may not access the device (on Linux, check the udev rules for it).',
        DeviceState.other => 'The device is in the state "$stateText", not ready to run apps.',
      };

  ConnectedDevice copyWith({String? name, String? osVersion}) => ConnectedDevice(
        id: id,
        name: name ?? this.name,
        kind: kind,
        state: state,
        stateText: stateText,
        transport: transport,
        osVersion: osVersion ?? this.osVersion,
      );
}

/// What `adb devices -l` printed: the devices, and the lines that were neither a device nor a known status message (adb's own
/// error text, which is what to show when there is no device and a problem).
final class AdbParseResult {
  final List<ConnectedDevice> devices;
  final List<String> problems;
  const AdbParseResult(this.devices, this.problems);
}

/// Pure parsers for the output of `adb` and `xcrun simctl`, tested against captured output.
abstract final class DeviceParsers {
  static final _wifiSerial = RegExp(r'^(\d{1,3}(\.\d{1,3}){3}:\d+|adb-.+\._adb-tls-connect\._tcp\.?)$');

  /// The words adb prints after the serial.
  static const _knownStates = {'device', 'offline', 'unauthorized', 'recovery', 'sideload', 'bootloader', 'rescue', 'authorizing', 'connecting', 'host'};

  /// Output of `adb devices -l`:
  ///
  /// ```
  /// List of devices attached
  /// ZD222LBHP4   device product:fogorow_gpq model:moto_g24_power device:fogorow transport_id:1
  /// ```
  ///
  /// Lines adb prints while it starts its server (`* daemon ...`), the header and blank lines are skipped. A line that is
  /// none of these (`error: ...`, `adb: failed to ...`) is returned in [AdbParseResult.problems].
  static AdbParseResult parseAdbDevices(String output) {
    final devices = <ConnectedDevice>[];
    final problems = <String>[];
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('*') || line.startsWith('List of devices') || line.startsWith('adb server')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        problems.add(line);
        continue;
      }
      final serial = parts[0];
      final word = parts[1];
      final noPermissions = word == 'no' && parts.length > 2 && parts[2].startsWith('permissions');
      if (!noPermissions && !_knownStates.contains(word)) {
        problems.add(line);
        continue;
      }
      final attributes = <String, String>{};
      for (final p in parts.skip(2)) {
        final at = p.indexOf(':');
        if (at > 0) attributes[p.substring(0, at)] = p.substring(at + 1);
      }
      final state = noPermissions
          ? DeviceState.noPermissions
          : switch (word) {
              'device' => DeviceState.ready,
              'offline' => DeviceState.offline,
              'unauthorized' => DeviceState.unauthorized,
              _ => DeviceState.other,
            };
      final emulator = serial.startsWith('emulator-');
      final model = attributes['model'] ?? attributes['device'] ?? attributes['product'];
      devices.add(ConnectedDevice(
        id: serial,
        name: model == null || model.isEmpty ? (emulator ? 'Android emulator' : serial) : model.replaceAll('_', ' '),
        kind: emulator ? DeviceKind.androidEmulator : DeviceKind.androidDevice,
        state: state,
        stateText: noPermissions ? 'no permissions' : word,
        transport: emulator ? DeviceTransport.emulator : (_wifiSerial.hasMatch(serial) ? DeviceTransport.wifi : DeviceTransport.usb),
      ));
    }
    return AdbParseResult(devices, problems);
  }

  /// Output of `adb shell getprop ro.build.version.release` (`14`), as `Android 14`; null for anything else.
  static String? parseAndroidVersion(String output) {
    final v = output.trim().split(RegExp(r'\s+')).first;
    return RegExp(r'^\d+(\.\d+)*$').hasMatch(v) ? 'Android $v' : null;
  }

  /// Output of `adb -s <serial> emu avd name` (`Pixel_7_API_34` then `OK`): the AVD name, readable.
  static String? parseAvdName(String output) {
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line == 'OK' || line.startsWith('KO')) return null;
      return line.replaceAll('_', ' ');
    }
    return null;
  }

  /// Output of `adb reverse --list`: the device-side ports that are forwarded (`host-19 tcp:3000 tcp:3000`).
  static List<int> parseReverseList(String output) {
    final ports = <int>[];
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final m = RegExp(r'\btcp:(\d+)\s+tcp:\d+').firstMatch(line);
      if (m != null) ports.add(int.parse(m.group(1)!));
    }
    return ports;
  }

  /// Output of `xcrun simctl list devices booted -j`. Only iOS runtimes are kept (a watch or a TV is no place to run a Flutter
  /// app against localhost). Throws a [FormatException] for text that is not that JSON.
  static List<ConnectedDevice> parseSimctlBooted(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('simctl did not print JSON: ${e.message}');
    }
    final groups = decoded is Map ? decoded['devices'] : null;
    if (groups is! Map) throw const FormatException('simctl output has no "devices" object');
    final devices = <ConnectedDevice>[];
    for (final entry in groups.entries) {
      final runtime = RegExp(r'SimRuntime\.([A-Za-z]+)-(\d+(?:-\d+)*)$').firstMatch('${entry.key}');
      if (runtime == null || runtime.group(1) != 'iOS') continue;
      final list = entry.value;
      if (list is! List) continue;
      for (final d in list) {
        if (d is! Map) continue;
        final udid = d['udid'];
        final name = d['name'];
        if (udid is! String || name is! String) continue;
        final state = '${d['state'] ?? ''}';
        devices.add(ConnectedDevice(
          id: udid,
          name: name,
          kind: DeviceKind.iosSimulator,
          state: state == 'Booted' ? DeviceState.ready : DeviceState.other,
          stateText: state,
          transport: DeviceTransport.simulator,
          osVersion: 'iOS ${runtime.group(2)!.replaceAll('-', '.')}',
        ));
      }
    }
    return devices;
  }
}
