import 'package:path/path.dart' as p;
import 'connected_device.dart';

/// What a finished command printed.
final class CommandResult {
  /// -1 when the command could not be started or had to be stopped.
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// Why the program could not be started at all (not found, not executable).
  final String? startError;

  const CommandResult({this.exitCode = -1, this.stdout = '', this.stderr = '', this.timedOut = false, this.startError});

  bool get ok => exitCode == 0 && !timedOut && startError == null;

  /// Both streams, since adb prints its status messages on either.
  String get output => [stdout, stderr].where((s) => s.trim().isNotEmpty).join('\n');
}

/// Runs a program and never waits for it longer than [timeout]. The real one is `data/device_host_io.dart`; tests give a fake.
abstract interface class CommandRunner {
  Future<CommandResult> run(String executable, List<String> arguments, {Duration timeout = const Duration(seconds: 5)});
}

enum HostPlatform { windows, macos, linux, other }

/// Everything the detector needs from the machine it runs on, so the search for adb can be tested for a Windows machine on a
/// Mac and the scan can be tested without any program.
final class DeviceHost {
  final CommandRunner runner;
  final Map<String, String> environment;
  final bool Function(String path) fileExists;
  final HostPlatform platform;

  /// A desktop where programs can be run. False in a browser and on a phone.
  final bool isSupported;

  const DeviceHost({
    required this.runner,
    required this.environment,
    required this.fileExists,
    required this.platform,
    required this.isSupported,
  });

  /// An environment variable by name; Windows ignores the case (`Path` and `PATH` are the same variable).
  String? variable(String name) {
    final exact = environment[name];
    if (exact != null || platform != HostPlatform.windows) return exact;
    for (final e in environment.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
    }
    return null;
  }
}

/// Where adb may be: the SDK folders in `ANDROID_HOME` and `ANDROID_SDK_ROOT`, every folder on `PATH` (platform-tools is often
/// only there, for example `C:\platform-tools`), then the places Android Studio installs the SDK to.
abstract final class AdbLocator {
  static p.Context _context(DeviceHost host) => p.Context(style: host.platform == HostPlatform.windows ? p.Style.windows : p.Style.posix);

  static String _exe(DeviceHost host) => host.platform == HostPlatform.windows ? 'adb.exe' : 'adb';

  /// Every path adb is looked for at, best first.
  static List<String> candidates(DeviceHost host) {
    final ctx = _context(host);
    final exe = _exe(host);
    final found = <String>[];
    void add(String? dir, {bool sdk = false}) {
      final d = (dir ?? '').trim().replaceAll('"', '');
      if (d.isEmpty) return;
      final path = sdk ? ctx.join(d, 'platform-tools', exe) : ctx.join(d, exe);
      if (!found.contains(path)) found.add(path);
    }

    add(host.variable('ANDROID_HOME'), sdk: true);
    add(host.variable('ANDROID_SDK_ROOT'), sdk: true);
    final separator = host.platform == HostPlatform.windows ? ';' : ':';
    for (final dir in (host.variable('PATH') ?? '').split(separator)) {
      add(dir);
    }
    final home = host.variable(host.platform == HostPlatform.windows ? 'USERPROFILE' : 'HOME');
    switch (host.platform) {
      case HostPlatform.windows:
        final local = host.variable('LOCALAPPDATA') ?? (home == null ? null : ctx.join(home, 'AppData', 'Local'));
        if (local != null) add(ctx.join(local, 'Android', 'Sdk'), sdk: true);
      case HostPlatform.macos:
        if (home != null) add(ctx.join(home, 'Library', 'Android', 'sdk'), sdk: true);
      case HostPlatform.linux:
        if (home != null) {
          add(ctx.join(home, 'Android', 'Sdk'), sdk: true);
          add(ctx.join(home, 'Android', 'sdk'), sdk: true);
        }
      case HostPlatform.other:
        break;
    }
    return found;
  }

  /// The first candidate that exists, or null.
  static String? find(DeviceHost host) {
    for (final path in candidates(host)) {
      if (host.fileExists(path)) return path;
    }
    return null;
  }

  static String missingMessage(DeviceHost host) {
    final c = candidates(host);
    final where = c.isEmpty
        ? 'nowhere (no PATH, ANDROID_HOME or home folder is set)'
        : '${c.take(4).join(', ')}${c.length > 4 ? ' and ${c.length - 4} more' : ''}';
    return 'adb was not found, so Android devices cannot be listed. Install the Android SDK platform-tools and add their folder '
        'to PATH, or set ANDROID_HOME to the SDK folder. Looked in: $where.';
  }
}

/// What a scan found.
final class DeviceScanResult {
  final List<ConnectedDevice> devices;

  /// The adb that was used; null when none was found.
  final String? adbPath;

  /// Why Android devices could not be listed (adb missing, stuck or failing), null when adb answered.
  final String? adbProblem;

  /// Why iOS simulators could not be listed; null when they were, or when this is not a Mac.
  final String? simctlProblem;

  /// Whether iOS simulators were looked for at all (a Mac only).
  final bool scannedIos;

  const DeviceScanResult({
    this.devices = const [],
    this.adbPath,
    this.adbProblem,
    this.simctlProblem,
    this.scannedIos = false,
  });
}

/// What `adb reverse` did.
final class ReverseOutcome {
  final bool ok;

  /// The forward was not there before: undoing the change should remove it, and no other.
  final bool createdByUs;
  final String message;

  const ReverseOutcome({required this.ok, this.createdByUs = false, this.message = ''});
}

/// Finds the running emulators, simulators and phones with `adb devices -l` and `xcrun simctl list devices booted -j`, and
/// sets up `adb reverse`. Every command is stopped after [timeout], so a stuck adb server cannot freeze the screen.
final class DeviceDetector {
  static const timeout = Duration(seconds: 5);

  final DeviceHost host;
  const DeviceDetector(this.host);

  bool get isSupported => host.isSupported;

  /// Simulators are listed on a Mac only.
  bool get scansIos => host.platform == HostPlatform.macos;

  String? get adbPath => AdbLocator.find(host);

  Future<DeviceScanResult> scan() async {
    if (!host.isSupported) return const DeviceScanResult();
    final adb = _scanAdb();
    final ios = scansIos ? _scanSimulators() : Future<({List<ConnectedDevice> devices, String? problem})>.value((devices: const <ConnectedDevice>[], problem: null));
    final android = await adb;
    final simulators = await ios;
    return DeviceScanResult(
      devices: [...android.devices, ...simulators.devices],
      adbPath: android.adbPath,
      adbProblem: android.problem,
      simctlProblem: simulators.problem,
      scannedIos: scansIos,
    );
  }

  Future<({List<ConnectedDevice> devices, String? adbPath, String? problem})> _scanAdb() async {
    final adb = AdbLocator.find(host);
    if (adb == null) return (devices: const <ConnectedDevice>[], adbPath: null, problem: AdbLocator.missingMessage(host));
    final r = await host.runner.run(adb, ['devices', '-l'], timeout: timeout);
    if (r.startError != null) {
      return (devices: const <ConnectedDevice>[], adbPath: adb, problem: 'adb was found at $adb but could not be started: ${r.startError}');
    }
    if (r.timedOut) {
      return (
        devices: const <ConnectedDevice>[],
        adbPath: adb,
        problem: 'adb did not answer within ${timeout.inSeconds} seconds. Run "adb kill-server" in a terminal and scan again.',
      );
    }
    final parsed = DeviceParsers.parseAdbDevices(r.output);
    if (parsed.devices.isEmpty && (!r.ok || parsed.problems.isNotEmpty)) {
      final reason = parsed.problems.firstOrNull ?? _firstLine(r.stderr) ?? 'adb exited with code ${r.exitCode}';
      return (devices: const <ConnectedDevice>[], adbPath: adb, problem: 'adb reported: $reason');
    }
    final devices = await Future.wait([for (final d in parsed.devices) _enrich(adb, d)]);
    return (devices: devices, adbPath: adb, problem: null);
  }

  /// The Android version and, for an emulator, the AVD name: nice to have, so a failure leaves the device as it was.
  Future<ConnectedDevice> _enrich(String adb, ConnectedDevice device) async {
    if (!device.isReady) return device;
    final version = host.runner.run(adb, ['-s', device.id, 'shell', 'getprop', 'ro.build.version.release'], timeout: timeout);
    final avd = device.kind == DeviceKind.androidEmulator
        ? host.runner.run(adb, ['-s', device.id, 'emu', 'avd', 'name'], timeout: timeout)
        : Future.value(const CommandResult());
    final v = await version;
    final a = await avd;
    return device.copyWith(
      osVersion: v.ok ? DeviceParsers.parseAndroidVersion(v.stdout) : null,
      name: a.ok ? DeviceParsers.parseAvdName(a.stdout) : null,
    );
  }

  Future<({List<ConnectedDevice> devices, String? problem})> _scanSimulators() async {
    final r = await host.runner.run('xcrun', ['simctl', 'list', 'devices', 'booted', '-j'], timeout: timeout);
    if (r.startError != null) {
      return (devices: const <ConnectedDevice>[], problem: 'xcrun could not be started (${r.startError}). Install Xcode or its command line tools: xcode-select --install.');
    }
    if (r.timedOut) return (devices: const <ConnectedDevice>[], problem: 'xcrun simctl did not answer within ${timeout.inSeconds} seconds.');
    if (!r.ok) {
      return (devices: const <ConnectedDevice>[], problem: 'xcrun simctl failed: ${_firstLine(r.stderr) ?? 'exit code ${r.exitCode}'}');
    }
    try {
      return (devices: DeviceParsers.parseSimctlBooted(r.stdout), problem: null);
    } on FormatException catch (e) {
      return (devices: const <ConnectedDevice>[], problem: "Couldn't read the simulator list: ${e.message}");
    }
  }

  /// `adb -s [serial] reverse tcp:[port] tcp:[port]`: the device's localhost:[port] reaches this computer's.
  Future<ReverseOutcome> reverse(String serial, int port) async {
    final adb = AdbLocator.find(host);
    if (adb == null) return ReverseOutcome(ok: false, message: AdbLocator.missingMessage(host));
    final before = await host.runner.run(adb, ['-s', serial, 'reverse', '--list'], timeout: timeout);
    final existed = before.ok && DeviceParsers.parseReverseList(before.stdout).contains(port);
    final r = await host.runner.run(adb, ['-s', serial, 'reverse', 'tcp:$port', 'tcp:$port'], timeout: timeout);
    if (r.timedOut) return const ReverseOutcome(ok: false, message: 'adb did not answer in time. Run "adb kill-server" and try again.');
    if (!r.ok) {
      return ReverseOutcome(ok: false, message: 'adb reverse failed: ${r.startError ?? _firstLine(r.output) ?? 'exit code ${r.exitCode}'}');
    }
    return ReverseOutcome(ok: true, createdByUs: !existed, message: 'adb reverse tcp:$port tcp:$port is set up on $serial.');
  }

  /// Takes the forward for [port] away again; true when adb says it is gone.
  Future<bool> removeReverse(String serial, int port) async {
    final adb = AdbLocator.find(host);
    if (adb == null) return false;
    final r = await host.runner.run(adb, ['-s', serial, 'reverse', '--remove', 'tcp:$port'], timeout: timeout);
    return r.ok;
  }

  static String? _firstLine(String text) {
    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return null;
  }
}
