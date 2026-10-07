// Device detection without a device: the parsers against captured adb / simctl output, the search for adb on a Windows, a Mac
// and a Linux machine, and the scan with a scripted runner (timeouts, errors, unauthorized phones, simulators).
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/device_helper/domain/services/connected_device.dart';
import 'package:postpilot/features/device_helper/domain/services/device_detector.dart';
import 'package:postpilot/features/device_helper/domain/services/device_url_planner.dart';

/// The line the moto g24 power really printed.
const _realLine = 'ZD222LBHP4             device product:fogorow_gpq model:moto_g24_power device:fogorow transport_id:1';

const _multi = 'List of devices attached\r\n'
    'emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa transport_id:1\r\n'
    'ZD222LBHP4             device product:fogorow_gpq model:moto_g24_power device:fogorow transport_id:2\r\n'
    '192.168.1.20:5555      device product:oriole model:Pixel_6 device:oriole transport_id:3\r\n'
    'adb-R5CT123ABC-xYzAbC._adb-tls-connect._tcp device product:beyond1 model:SM_G973F device:beyond1 transport_id:4\r\n'
    '0123456789ABCDEF       unauthorized usb:1-1 transport_id:5\r\n'
    'R58M1234XYZ            offline usb:3-2 transport_id:6\r\n'
    'ABCD1234               no permissions (user in plugdev group; are your udev rules wrong?); see [http://developer.android.com/tools/device.html] usb:1-4 transport_id:7\r\n'
    '\r\n';

const _simctl = '''
{
  "devices" : {
    "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
      {"dataPath":"/x","logPath":"/y","udid":"A1B2C3D4-0000-1111-2222-333344445555","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro","state":"Booted","name":"iPhone 15 Pro"},
      {"udid":"B1B2C3D4-0000-1111-2222-333344445555","isAvailable":true,"state":"Booted","name":"iPad Air (5th generation)"}
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-10-5" : [
      {"udid":"C1B2C3D4-0000-1111-2222-333344445555","state":"Booted","name":"Apple Watch Series 9 (45mm)"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-16-4" : []
  }
}
''';

final class _FakeRunner implements CommandRunner {
  final Map<String, CommandResult> responses;
  final List<String> calls = [];
  _FakeRunner(this.responses);

  @override
  Future<CommandResult> run(String executable, List<String> arguments, {Duration timeout = const Duration(seconds: 5)}) async {
    final key = '${executable.split(RegExp(r'[\\/]')).last} ${arguments.join(' ')}';
    calls.add(key);
    return responses[key] ?? CommandResult(exitCode: 1, stderr: 'unexpected call: $key');
  }
}

CommandResult _ok(String stdout) => CommandResult(exitCode: 0, stdout: stdout);

DeviceHost _host(
  HostPlatform platform,
  CommandRunner runner, {
  Map<String, String> env = const {},
  Set<String> files = const {},
  bool supported = true,
}) =>
    DeviceHost(runner: runner, environment: env, fileExists: files.contains, platform: platform, isSupported: supported);

const _winAdb = r'C:\platform-tools\adb.exe';

void main() {
  group('adb devices -l', () {
    test('the real moto g24 power line', () {
      final r = DeviceParsers.parseAdbDevices('List of devices attached\n$_realLine\n\n');
      expect(r.problems, isEmpty);
      final d = r.devices.single;
      expect(d.id, 'ZD222LBHP4');
      expect(d.name, 'moto g24 power');
      expect(d.kind, DeviceKind.androidDevice);
      expect(d.transport, DeviceTransport.usb);
      expect(d.state, DeviceState.ready);
      expect(d.isReady, isTrue);
      expect(d.problem, isNull);
    });

    test('several devices: emulator, USB, Wi-Fi by address and by mDNS name, unauthorized, offline, no permissions (CRLF)', () {
      final r = DeviceParsers.parseAdbDevices(_multi);
      expect(r.problems, isEmpty);
      expect(r.devices.map((d) => d.id), [
        'emulator-5554', 'ZD222LBHP4', '192.168.1.20:5555', 'adb-R5CT123ABC-xYzAbC._adb-tls-connect._tcp', '0123456789ABCDEF', 'R58M1234XYZ', 'ABCD1234',
      ]);
      expect(r.devices.map((d) => d.name), ['sdk gphone64 x86 64', 'moto g24 power', 'Pixel 6', 'SM G973F', '0123456789ABCDEF', 'R58M1234XYZ', 'ABCD1234']);
      expect(r.devices.map((d) => d.kind), [
        DeviceKind.androidEmulator,
        DeviceKind.androidDevice,
        DeviceKind.androidDevice,
        DeviceKind.androidDevice,
        DeviceKind.androidDevice,
        DeviceKind.androidDevice,
        DeviceKind.androidDevice,
      ]);
      expect(r.devices.map((d) => d.transport), [
        DeviceTransport.emulator, DeviceTransport.usb, DeviceTransport.wifi, DeviceTransport.wifi, DeviceTransport.usb, DeviceTransport.usb, DeviceTransport.usb,
      ]);
      expect(r.devices.map((d) => d.state), [
        DeviceState.ready, DeviceState.ready, DeviceState.ready, DeviceState.ready, DeviceState.unauthorized, DeviceState.offline, DeviceState.noPermissions,
      ]);
      expect(r.devices[6].stateText, 'no permissions');
      expect(r.devices[4].problem, contains('USB debugging'));
      expect(r.devices[5].problem, contains('offline'));
      expect(r.devices.where((d) => d.isReady), hasLength(4));
    });

    test('daemon start-up lines and the version notice are skipped; an empty list is empty', () {
      final started = DeviceParsers.parseAdbDevices(
        '* daemon not running; starting now at tcp:5037\n* daemon started successfully\n'
        "adb server version (41) doesn't match this client (40); killing...\n"
        'List of devices attached\n$_realLine\n',
      );
      expect(started.devices.map((d) => d.id), ['ZD222LBHP4']);
      expect(started.problems, isEmpty);

      final empty = DeviceParsers.parseAdbDevices('List of devices attached\n\n');
      expect(empty.devices, isEmpty);
      expect(empty.problems, isEmpty);
      expect(DeviceParsers.parseAdbDevices('').devices, isEmpty);
    });

    test('adb error text is a problem, never a device', () {
      final r = DeviceParsers.parseAdbDevices(
        'adb: failed to check server version: cannot connect to daemon\n'
        'error: no devices/emulators found\n'
        'error: more than one device/emulator\n',
      );
      expect(r.devices, isEmpty);
      expect(r.problems, [
        'adb: failed to check server version: cannot connect to daemon',
        'error: no devices/emulators found',
        'error: more than one device/emulator',
      ]);
    });

    test('an offline emulator with no attributes still gets a name', () {
      final d = DeviceParsers.parseAdbDevices('List of devices attached\nemulator-5556\toffline\n').devices.single;
      expect(d.name, 'Android emulator');
      expect(d.state, DeviceState.offline);
      expect(d.kind, DeviceKind.androidEmulator);
    });

    test('Android version, AVD name and the reverse list', () {
      expect(DeviceParsers.parseAndroidVersion('14\r\n'), 'Android 14');
      expect(DeviceParsers.parseAndroidVersion('8.1.0\n'), 'Android 8.1.0');
      expect(DeviceParsers.parseAndroidVersion('error: closed\n'), isNull);
      expect(DeviceParsers.parseAndroidVersion(''), isNull);
      expect(DeviceParsers.parseAvdName('Pixel_7_API_34\r\nOK\r\n'), 'Pixel 7 API 34');
      expect(DeviceParsers.parseAvdName('KO: unknown command\r\n'), isNull);
      expect(DeviceParsers.parseAvdName('OK\n'), isNull);
      expect(DeviceParsers.parseReverseList('host-19 tcp:3000 tcp:3000\nhost-19 tcp:8081 tcp:9090\n'), [3000, 8081]);
      expect(DeviceParsers.parseReverseList(''), isEmpty);
    });
  });

  group('xcrun simctl list devices booted -j', () {
    test('iOS simulators with their runtime; other platforms and empty runtimes are left out', () {
      final devices = DeviceParsers.parseSimctlBooted(_simctl);
      expect(devices.map((d) => d.name), ['iPhone 15 Pro', 'iPad Air (5th generation)']);
      expect(devices.first.id, 'A1B2C3D4-0000-1111-2222-333344445555');
      expect(devices.first.osVersion, 'iOS 17.5');
      expect(devices.first.kind, DeviceKind.iosSimulator);
      expect(devices.first.transport, DeviceTransport.simulator);
      expect(devices.first.isReady, isTrue);
    });

    test('nothing booted, and output that is not simctl JSON', () {
      expect(DeviceParsers.parseSimctlBooted('{"devices":{}}'), isEmpty);
      expect(() => DeviceParsers.parseSimctlBooted('xcrun: error: unable to find utility "simctl"'), throwsFormatException);
      expect(() => DeviceParsers.parseSimctlBooted('[]'), throwsFormatException);
    });
  });

  group('finding adb', () {
    test('on PATH, where C:\\platform-tools is and the default SDK folder is not', () {
      final host = _host(
        HostPlatform.windows,
        _FakeRunner({}),
        env: {'Path': r'C:\Windows\System32;"C:\platform-tools";C:\Program Files\Git\cmd', 'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
        files: {_winAdb},
      );
      expect(AdbLocator.find(host), _winAdb);
      expect(AdbLocator.candidates(host), [
        r'C:\Windows\System32\adb.exe',
        r'C:\platform-tools\adb.exe',
        r'C:\Program Files\Git\cmd\adb.exe',
        r'C:\Users\me\AppData\Local\Android\Sdk\platform-tools\adb.exe',
      ]);
    });

    test('ANDROID_HOME and ANDROID_SDK_ROOT come before PATH', () {
      final host = _host(
        HostPlatform.windows,
        _FakeRunner({}),
        env: {'ANDROID_SDK_ROOT': r'C:\Sdk2', 'ANDROID_HOME': r'C:\Sdk', 'PATH': r'C:\platform-tools'},
        files: {_winAdb, r'C:\Sdk\platform-tools\adb.exe', r'C:\Sdk2\platform-tools\adb.exe'},
      );
      expect(AdbLocator.candidates(host).take(3), [r'C:\Sdk\platform-tools\adb.exe', r'C:\Sdk2\platform-tools\adb.exe', _winAdb]);
      expect(AdbLocator.find(host), r'C:\Sdk\platform-tools\adb.exe');
    });

    test('default SDK folders on a Mac and on Linux, without PATH', () {
      final mac = _host(HostPlatform.macos, _FakeRunner({}), env: {'HOME': '/Users/me'}, files: {'/Users/me/Library/Android/sdk/platform-tools/adb'});
      expect(AdbLocator.find(mac), '/Users/me/Library/Android/sdk/platform-tools/adb');
      final linux = _host(HostPlatform.linux, _FakeRunner({}), env: {'HOME': '/home/me', 'PATH': '/usr/bin:/bin'}, files: {'/home/me/Android/Sdk/platform-tools/adb'});
      expect(AdbLocator.find(linux), '/home/me/Android/Sdk/platform-tools/adb');
      expect(AdbLocator.candidates(linux).first, '/usr/bin/adb');
    });

    test('nothing found: null, and a message that says where it looked and what to do', () {
      final host = _host(HostPlatform.windows, _FakeRunner({}), env: {'PATH': r'C:\Windows'});
      expect(AdbLocator.find(host), isNull);
      final message = AdbLocator.missingMessage(host);
      expect(message, contains('adb was not found'));
      expect(message, contains('ANDROID_HOME'));
      expect(message, contains(r'C:\Windows\adb.exe'));
      expect(AdbLocator.missingMessage(_host(HostPlatform.other, _FakeRunner({}))), contains('nowhere'));
    });
  });

  group('scan', () {
    DeviceHost windows(_FakeRunner runner) => _host(HostPlatform.windows, runner, env: {'PATH': r'C:\platform-tools'}, files: {_winAdb});

    test('lists the devices, adds the Android version and the AVD name, and leaves a phone that is not ready alone', () async {
      final runner = _FakeRunner({
        'adb.exe devices -l': _ok(_multi),
        'adb.exe -s emulator-5554 shell getprop ro.build.version.release': _ok('15\r\n'),
        'adb.exe -s emulator-5554 emu avd name': _ok('Pixel_7_API_35\r\nOK\r\n'),
        'adb.exe -s ZD222LBHP4 shell getprop ro.build.version.release': _ok('14\r\n'),
        'adb.exe -s 192.168.1.20:5555 shell getprop ro.build.version.release': const CommandResult(exitCode: 1, stderr: 'error: closed'),
        'adb.exe -s adb-R5CT123ABC-xYzAbC._adb-tls-connect._tcp shell getprop ro.build.version.release': _ok('13\n'),
      });
      final result = await DeviceDetector(windows(runner)).scan();
      expect(result.adbProblem, isNull);
      expect(result.adbPath, _winAdb);
      expect(result.scannedIos, isFalse);
      expect(result.devices, hasLength(7));
      expect(result.devices[0].name, 'Pixel 7 API 35');
      expect(result.devices[0].osVersion, 'Android 15');
      expect(result.devices[1].osVersion, 'Android 14');
      expect(result.devices[1].name, 'moto g24 power');
      expect(result.devices[2].osVersion, isNull, reason: 'the version is nice to have: a failure keeps the device');
      expect(result.devices[3].osVersion, 'Android 13');
      expect(runner.calls.where((c) => c.contains('0123456789ABCDEF') || c.contains('R58M1234XYZ') || c.contains('ABCD1234')), isEmpty,
          reason: 'devices that are not ready are not asked anything');
      expect(runner.calls.any((c) => c.startsWith('xcrun')), isFalse, reason: 'simulators are listed on a Mac only');
    });

    test('adb not installed: a clear message and no program is run', () async {
      final runner = _FakeRunner({});
      final result = await DeviceDetector(_host(HostPlatform.windows, runner, env: {'PATH': r'C:\Windows'})).scan();
      expect(result.devices, isEmpty);
      expect(result.adbPath, isNull);
      expect(result.adbProblem, contains('adb was not found'));
      expect(runner.calls, isEmpty);
    });

    test('adb that does not answer in time, cannot be started, or fails', () async {
      final slow = await DeviceDetector(windows(_FakeRunner({'adb.exe devices -l': const CommandResult(timedOut: true)}))).scan();
      expect(slow.adbProblem, contains('did not answer within 5 seconds'));
      expect(slow.adbProblem, contains('adb kill-server'));

      final broken = await DeviceDetector(windows(_FakeRunner({'adb.exe devices -l': const CommandResult(startError: 'Access is denied')}))).scan();
      expect(broken.adbProblem, contains('could not be started: Access is denied'));

      final failing = await DeviceDetector(windows(_FakeRunner({
        'adb.exe devices -l': const CommandResult(exitCode: 1, stderr: 'adb: failed to check server version: cannot connect to daemon\r\n'),
      }))).scan();
      expect(failing.devices, isEmpty);
      expect(failing.adbProblem, 'adb reported: adb: failed to check server version: cannot connect to daemon');

      final silent = await DeviceDetector(windows(_FakeRunner({'adb.exe devices -l': const CommandResult(exitCode: 2)}))).scan();
      expect(silent.adbProblem, 'adb reported: adb exited with code 2');
    });

    test('an empty list is not a problem', () async {
      final result = await DeviceDetector(windows(_FakeRunner({'adb.exe devices -l': _ok('List of devices attached\n\n')}))).scan();
      expect(result.devices, isEmpty);
      expect(result.adbProblem, isNull);
    });

    test('on a Mac the booted simulators are listed too, and a simctl failure is its own message', () async {
      final runner = _FakeRunner({
        'adb devices -l': _ok('List of devices attached\n$_realLine\n'),
        'adb -s ZD222LBHP4 shell getprop ro.build.version.release': _ok('14\n'),
        'xcrun simctl list devices booted -j': _ok(_simctl),
      });
      final both = await DeviceDetector(_host(HostPlatform.macos, runner, env: {'PATH': '/opt/platform-tools'}, files: {'/opt/platform-tools/adb'})).scan();
      expect(both.scannedIos, isTrue);
      expect(both.devices.map((d) => d.name), ['moto g24 power', 'iPhone 15 Pro', 'iPad Air (5th generation)']);

      final failing = await DeviceDetector(_host(
        HostPlatform.macos,
        _FakeRunner({
          'adb devices -l': _ok('List of devices attached\n\n'),
          'xcrun simctl list devices booted -j': const CommandResult(exitCode: 72, stderr: 'xcrun: error: unable to find utility "simctl", not a developer tool or in PATH\n'),
        }),
        env: {'PATH': '/opt/platform-tools'},
        files: {'/opt/platform-tools/adb'},
      )).scan();
      expect(failing.simctlProblem, 'xcrun simctl failed: xcrun: error: unable to find utility "simctl", not a developer tool or in PATH');
      expect(failing.adbProblem, isNull);

      final garbled = await DeviceDetector(_host(
        HostPlatform.macos,
        _FakeRunner({
          'adb devices -l': _ok('List of devices attached\n\n'),
          'xcrun simctl list devices booted -j': _ok('not json'),
        }),
        env: {'PATH': '/opt/platform-tools'},
        files: {'/opt/platform-tools/adb'},
      )).scan();
      expect(garbled.simctlProblem, contains("Couldn't read the simulator list"));
    });

    test('a host that cannot run programs (a browser) scans nothing', () async {
      final runner = _FakeRunner({});
      final detector = DeviceDetector(_host(HostPlatform.other, runner, supported: false));
      expect(detector.isSupported, isFalse);
      final result = await detector.scan();
      expect(result.devices, isEmpty);
      expect(runner.calls, isEmpty);
    });
  });

  group('adb reverse', () {
    DeviceDetector detector(Map<String, CommandResult> responses) => DeviceDetector(
          _host(HostPlatform.windows, _FakeRunner(responses), env: {'PATH': r'C:\platform-tools'}, files: {_winAdb}),
        );

    test('sets the forward up and says it was new', () async {
      final runner = _FakeRunner({
        'adb.exe -s ZD222LBHP4 reverse --list': _ok(''),
        'adb.exe -s ZD222LBHP4 reverse tcp:3000 tcp:3000': _ok('3000\n'),
      });
      final d = DeviceDetector(_host(HostPlatform.windows, runner, env: {'PATH': r'C:\platform-tools'}, files: {_winAdb}));
      final r = await d.reverse('ZD222LBHP4', 3000);
      expect(r.ok, isTrue);
      expect(r.createdByUs, isTrue);
      expect(runner.calls, ['adb.exe -s ZD222LBHP4 reverse --list', 'adb.exe -s ZD222LBHP4 reverse tcp:3000 tcp:3000']);
    });

    test('a forward that was there already is not ours to remove', () async {
      final r = await detector({
        'adb.exe -s S reverse --list': _ok('host-19 tcp:3000 tcp:3000\n'),
        'adb.exe -s S reverse tcp:3000 tcp:3000': _ok('3000\n'),
      }).reverse('S', 3000);
      expect(r.ok, isTrue);
      expect(r.createdByUs, isFalse);
    });

    test('failures come back as readable messages', () async {
      final failed = await detector({
        'adb.exe -s S reverse --list': _ok(''),
        'adb.exe -s S reverse tcp:3000 tcp:3000': const CommandResult(exitCode: 1, stderr: 'adb.exe: error: device unauthorized.\n'),
      }).reverse('S', 3000);
      expect(failed.ok, isFalse);
      expect(failed.message, 'adb reverse failed: adb.exe: error: device unauthorized.');
      final timedOut = await detector({
        'adb.exe -s S reverse --list': _ok(''),
        'adb.exe -s S reverse tcp:3000 tcp:3000': const CommandResult(timedOut: true),
      }).reverse('S', 3000);
      expect(timedOut.ok, isFalse);
      expect(timedOut.message, contains('did not answer'));
      final missing = await DeviceDetector(_host(HostPlatform.windows, _FakeRunner({}), env: {'PATH': r'C:\Windows'})).reverse('S', 3000);
      expect(missing.ok, isFalse);
      expect(missing.message, contains('adb was not found'));
    });

    test('removes one forward, and only that one', () async {
      final runner = _FakeRunner({'adb.exe -s S reverse --remove tcp:3000': _ok('')});
      final d = DeviceDetector(_host(HostPlatform.windows, runner, env: {'PATH': r'C:\platform-tools'}, files: {_winAdb}));
      expect(await d.removeReverse('S', 3000), isTrue);
      expect(runner.calls, ['adb.exe -s S reverse --remove tcp:3000']);
      expect(await detector({}).removeReverse('S', 3000), isFalse, reason: 'adb said no');
    });
  });

  group('Use for <environment>: which host each device gets', () {
    ConnectedDevice device(DeviceKind kind, {DeviceState state = DeviceState.ready, DeviceTransport transport = DeviceTransport.usb}) => ConnectedDevice(
          id: 'ZD222LBHP4',
          name: 'moto g24 power',
          kind: kind,
          state: state,
          stateText: state == DeviceState.ready ? 'device' : state.name,
          transport: transport,
        );
    final emulator = device(DeviceKind.androidEmulator, transport: DeviceTransport.emulator);
    final phone = device(DeviceKind.androidDevice);
    final simulator = device(DeviceKind.iosSimulator, transport: DeviceTransport.simulator);

    test('Android emulator: 10.0.2.2, scheme, port, path, query and fragment kept', () {
      final p = DeviceUrlPlanner.plan(emulator, 'http://localhost:3000/api/v1?x=1&y=2#top');
      expect(p.ok, isTrue);
      expect(p.after, 'http://10.0.2.2:3000/api/v1?x=1&y=2#top');
      expect(p.host, '10.0.2.2');
      expect(p.reversePort, isNull);
      expect(p.reverseCommand, isNull);
      expect(p.isUnchanged, isFalse);
    });

    test('phone with adb reverse: localhost, and the command that makes it work', () {
      final p = DeviceUrlPlanner.plan(phone, 'http://10.0.2.2:3000/api');
      expect(p.after, 'http://localhost:3000/api');
      expect(p.reversePort, 3000);
      expect(p.reverseCommand, 'adb -s ZD222LBHP4 reverse tcp:3000 tcp:3000');
      expect(DeviceUrlPlanner.plan(phone, 'http://localhost:3000/api').isUnchanged, isTrue);
      expect(DeviceUrlPlanner.plan(phone, 'https://127.0.0.1/api').reversePort, 443, reason: 'no port in the URL: the scheme\'s own');
      expect(DeviceUrlPlanner.plan(phone, 'ws://localhost/socket').reversePort, 80);
    });

    test('phone without adb reverse: this computer\'s LAN address, or an error when there is none', () {
      final p = DeviceUrlPlanner.plan(phone, 'http://localhost:3000/api', useReverse: false, lanIp: '192.168.1.20');
      expect(p.after, 'http://192.168.1.20:3000/api');
      expect(p.reversePort, isNull);
      expect(p.notes.any((n) => n.contains('Allow other devices')), isTrue);
      final none = DeviceUrlPlanner.plan(phone, 'http://localhost:3000/api', useReverse: false);
      expect(none.ok, isFalse);
      expect(none.error, contains('No network address'));
    });

    test('iOS simulator: localhost', () {
      expect(DeviceUrlPlanner.plan(simulator, 'http://10.0.2.2:8080/x').after, 'http://localhost:8080/x');
      expect(DeviceUrlPlanner.plan(simulator, 'http://localhost:8080/x').isUnchanged, isTrue);
    });

    test('an address without a scheme stays without one; IPv6 hosts are replaced', () {
      expect(DeviceUrlPlanner.plan(emulator, 'localhost:3000/api').after, '10.0.2.2:3000/api');
      expect(DeviceUrlPlanner.plan(emulator, 'http://[::1]:3000/x').after, 'http://10.0.2.2:3000/x');
      expect(DeviceUrlPlanner.rewriteHost('nonsense', 'x'), 'x');
      expect(DeviceUrlPlanner.rewriteHost('', 'x'), isNull);
    });

    test('which values are addresses a device could be pointed at', () {
      for (final v in ['http://localhost:3000', 'https://api.example.com/v1', 'localhost', 'localhost:3000/api', '10.0.2.2:3000', 'api.example.com', 'ws://[::1]:8080', '192.168.1.5']) {
        expect(DeviceUrlPlanner.looksLikeAddress(v), isTrue, reason: v);
      }
      for (final v in ['5000', 'abc', '', 'true', '{{host}}:3000', 'hello world', 'Bearer token', 'http://', '12345', '1.2.3']) {
        expect(DeviceUrlPlanner.looksLikeAddress(v), isFalse, reason: v);
      }
    });

    test('values that cannot be changed say why', () {
      expect(DeviceUrlPlanner.plan(emulator, '{{host}}:3000').error, contains('{{variable}}'));
      expect(DeviceUrlPlanner.plan(emulator, '  ').error, contains('empty'));
      expect(DeviceUrlPlanner.plan(emulator, 'http://').error, contains('no host'));
      expect(DeviceUrlPlanner.plan(phone, 'myapp://localhost').error, contains('no port'));
      final locked = device(DeviceKind.androidDevice, state: DeviceState.unauthorized);
      expect(DeviceUrlPlanner.plan(locked, 'http://localhost:3000').error, contains('USB debugging'));
    });

    test('a host that is not this computer is called out', () {
      final p = DeviceUrlPlanner.plan(emulator, 'https://api.example.com/v1');
      expect(p.ok, isTrue);
      expect(p.after, 'https://10.0.2.2/v1');
      expect(p.notes.any((n) => n.contains('"api.example.com" is not an address on this computer')), isTrue);
      expect(DeviceUrlPlanner.plan(emulator, 'http://localhost:3000').notes.any((n) => n.contains('is not an address')), isFalse);
    });

    test('which hosts count as this computer', () {
      for (final h in ['localhost', '127.0.0.1', '::1', '0.0.0.0', '10.0.2.2', '10.0.3.2', '192.168.0.5', '172.16.0.1', '172.31.255.1', '10.1.2.3', 'mac.local']) {
        expect(DeviceUrlPlanner.isDevelopmentHost(h), isTrue, reason: h);
      }
      for (final h in ['8.8.8.8', '172.32.0.1', '172.15.0.1', 'api.example.com', '192.169.0.1']) {
        expect(DeviceUrlPlanner.isDevelopmentHost(h), isFalse, reason: h);
      }
    });
  });
}
