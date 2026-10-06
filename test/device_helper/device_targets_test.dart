import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/device_helper/domain/services/device_targets.dart';

void main() {
  test('rewrites localhost URLs keeping port, path and query', () {
    expect(DeviceTargets.rewrite('http://localhost:3000/api/users?x=1', '10.0.2.2'), 'http://10.0.2.2:3000/api/users?x=1');
    expect(DeviceTargets.rewrite('https://127.0.0.1/a', '192.168.1.5'), 'https://192.168.1.5/a');
    expect(DeviceTargets.rewrite('localhost:8080/x', '10.0.2.2'), 'http://10.0.2.2:8080/x', reason: 'a missing scheme is assumed to be http');
  });

  test('refuses what cannot be rewritten', () {
    expect(DeviceTargets.rewrite('{{baseUrl}}/users', '10.0.2.2'), isNull);
    expect(DeviceTargets.rewrite('', '10.0.2.2'), isNull);
  });

  test('knows which hosts mean this computer', () {
    for (final u in ['http://localhost:3000', 'http://127.0.0.1', 'http://0.0.0.0:80', 'http://[::1]:3000']) {
      expect(DeviceTargets.isLocal(u), isTrue, reason: u);
    }
    expect(DeviceTargets.isLocal('https://api.example.com'), isFalse);
    expect(DeviceTargets.isLocal('{{baseUrl}}'), isFalse);
  });

  test('reads the port with a fallback, and builds the adb command', () {
    expect(DeviceTargets.portOf('http://localhost:8081/x'), 8081);
    expect(DeviceTargets.portOf('http://localhost/x', fallback: 3001), 3001);
    expect(DeviceTargets.adbReverse(3001), 'adb reverse tcp:3001 tcp:3001');
  });

  test('knows when an address is plain http, and the note names both platform settings', () {
    for (final u in ['http://192.168.1.5:3000', 'HTTP://10.0.2.2:8080/x', ' http://localhost ']) {
      expect(DeviceTargets.usesCleartext(u), isTrue, reason: u);
    }
    for (final u in ['https://192.168.1.5', '10.0.2.2:3000', '', '{{baseUrl}}']) {
      expect(DeviceTargets.usesCleartext(u), isFalse, reason: u);
    }
    expect(DeviceTargets.cleartextNote, contains('usesCleartextTraffic'));
    expect(DeviceTargets.cleartextNote, contains('network security config'));
    expect(DeviceTargets.cleartextNote, contains('NSAllowsLocalNetworking'));
    expect(DeviceTargets.cleartextNote, contains('Info.plist'));
  });

  test('lists the emulator aliases', () {
    final hosts = {for (final t in DeviceTargets.forEmulators()) t.name: t.host};
    expect(hosts['Android emulator'], '10.0.2.2');
    expect(hosts['Genymotion'], '10.0.3.2');
  });
}
