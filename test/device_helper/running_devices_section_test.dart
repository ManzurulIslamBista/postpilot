// "Use for <environment>" in the device helper: devices found by a scripted adb, the exact change shown before it is made,
// adb reverse set up for a phone, the variable rewritten, and Undo putting both back.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/device_helper/domain/services/device_detector.dart';
import 'package:postpilot/features/device_helper/presentation/running_devices_section.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/environments/presentation/view_models/environments_view_model.dart';

/// Environments that live in memory and tell their watchers about every change.
final class _Environments implements EnvironmentRepository {
  final environments = [const EnvironmentEntity(id: 1, name: 'Dev', isActive: true)];
  final variables = [
    const EnvironmentVariableEntity(id: 2, environmentId: 1, key: 'baseUrl', value: 'http://10.0.2.2:3000', isSecret: false, enabled: true),
    const EnvironmentVariableEntity(id: 3, environmentId: 1, key: 'api_key', value: 'secret-value', isSecret: true, enabled: true),
    const EnvironmentVariableEntity(id: 4, environmentId: 1, key: 'timeoutMs', value: '5000', isSecret: false, enabled: true),
  ];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<EnvironmentEntity>> watchAll() async* {
    yield [...environments];
  }

  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) async* {
    List<EnvironmentVariableEntity> mine() => [for (final v in variables) if (v.environmentId == environmentId) v];
    yield mine();
    await for (final _ in _changes.stream) {
      yield mine();
    }
  }

  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) async {
    final at = variables.indexWhere((v) => v.id == variable.id);
    if (at >= 0) {
      variables[at] = variable;
    } else {
      variables.add(variable);
    }
    _changes.add(null);
  }

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(environments.first);
  @override
  Future<int> create(String name) async => throw UnimplementedError();
  @override
  Future<void> rename(int id, String name) async {}
  @override
  Future<void> setActive(int id) async {}
  @override
  Future<void> clearActive() async {}
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> deleteVariable(int id) async {}
  @override
  Future<Map<String, String>> getActiveVariables() async => {};
}

final class _Globals implements GlobalVariableRepository {
  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(const []);
  @override
  Future<void> upsert(GlobalVariableEntity variable) async {}
  @override
  Future<void> delete(int id) async {}
  @override
  Future<Map<String, String>> getEnabledMap() async => {};
}

final class _Runner implements CommandRunner {
  final Map<String, CommandResult> responses;
  final calls = <String>[];
  _Runner(this.responses);

  @override
  Future<CommandResult> run(String executable, List<String> arguments, {Duration timeout = const Duration(seconds: 5)}) async {
    final key = '${executable.split(RegExp(r'[\\/]')).last} ${arguments.join(' ')}';
    calls.add(key);
    return responses[key] ?? const CommandResult(exitCode: 1, stderr: 'unexpected');
  }
}

const _adb = r'C:\platform-tools\adb.exe';

const _devices = 'List of devices attached\r\n'
    'ZD222LBHP4             device product:fogorow_gpq model:moto_g24_power device:fogorow transport_id:1\r\n'
    '0123456789ABCDEF       unauthorized usb:1-1 transport_id:2\r\n'
    '\r\n';

DeviceDetector _detector(_Runner runner, {bool supported = true}) => DeviceDetector(DeviceHost(
      runner: runner,
      environment: const {'PATH': r'C:\platform-tools'},
      fileExists: (p) => p == _adb,
      platform: HostPlatform.windows,
      isSupported: supported,
    ));

_Runner _scripted() => _Runner({
      'adb.exe devices -l': const CommandResult(exitCode: 0, stdout: _devices),
      'adb.exe -s ZD222LBHP4 shell getprop ro.build.version.release': const CommandResult(exitCode: 0, stdout: '14\r\n'),
      'adb.exe -s ZD222LBHP4 reverse --list': const CommandResult(exitCode: 0),
      'adb.exe -s ZD222LBHP4 reverse tcp:3000 tcp:3000': const CommandResult(exitCode: 0, stdout: '3000\r\n'),
      'adb.exe -s ZD222LBHP4 reverse --remove tcp:3000': const CommandResult(exitCode: 0),
    });

void main() {
  late _Environments repository;
  late EnvironmentsViewModel environments;

  setUp(() {
    repository = _Environments();
    environments = EnvironmentsViewModel(repository, _Globals());
  });

  tearDown(() => environments.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> show(WidgetTester tester, DeviceDetector detector, {bool autoScan = true, String? lanIp = '192.168.1.20', Size size = const Size(1000, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // A new key: showing a second detector must start a second scan, not reuse the state of the first.
          child: RunningDevicesSection(key: UniqueKey(), detector: detector, environments: environments, lanIp: lanIp, autoScan: autoScan),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('lists what adb found, with the model, the transport and the Android version, and why a phone cannot be used yet', (tester) async {
    final runner = _scripted();
    await show(tester, _detector(runner));
    expect(find.text('moto g24 power'), findsOneWidget);
    expect(find.text('Android phone or tablet  ·  USB  ·  Android 14  ·  ZD222LBHP4'), findsOneWidget);
    expect(find.byKey(const ValueKey('device-0123456789ABCDEF')), findsOneWidget);
    expect(find.textContaining('Allow USB debugging'), findsOneWidget);
    expect(find.text('adb: $_adb'), findsOneWidget);
    expect(find.text('iOS simulators are listed on a Mac only.'), findsOneWidget);
    // The environment and its address variable are shown, secrets and numbers are not offered.
    expect(find.text('Now: http://10.0.2.2:3000'), findsOneWidget);
    final buttons = find.widgetWithText(FilledButton, 'Use for Dev');
    expect(buttons, findsNWidgets(2));
    expect(tester.widget<FilledButton>(buttons.at(0)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(buttons.at(1)).onPressed, isNull, reason: 'unauthorized');
  });

  testWidgets('Use for Dev shows the exact change and the adb reverse command, then sets both up, and Undo puts both back', (tester) async {
    final runner = _scripted();
    await show(tester, _detector(runner));

    await tester.tap(find.widgetWithText(FilledButton, 'Use for Dev').first);
    await settle(tester);
    expect(find.text('Use moto g24 power for Dev'), findsOneWidget);
    expect(find.text('http://10.0.2.2:3000'), findsOneWidget, reason: 'now');
    expect(find.text('http://localhost:3000'), findsOneWidget, reason: 'after');
    expect(find.byKey(const ValueKey('reverse-command')), findsOneWidget);
    expect(find.text('adb -s ZD222LBHP4 reverse tcp:3000 tcp:3000'), findsOneWidget);
    expect(runner.calls.where((c) => c.contains('reverse')), isEmpty, reason: 'nothing happens before Apply');
    expect(repository.variables.first.value, 'http://10.0.2.2:3000');

    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(runner.calls, contains('adb.exe -s ZD222LBHP4 reverse tcp:3000 tcp:3000'));
    expect(repository.variables.first.value, 'http://localhost:3000');
    expect(repository.variables.first.key, 'baseUrl');
    expect(repository.variables[1].value, 'secret-value', reason: 'nothing else was touched');
    expect(find.text('Changed baseUrl in Dev'), findsOneWidget);
    expect(find.text('http://10.0.2.2:3000  ->  http://localhost:3000'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(repository.variables.first.value, 'http://10.0.2.2:3000');
    expect(runner.calls, contains('adb.exe -s ZD222LBHP4 reverse --remove tcp:3000'));
    expect(find.byKey(const ValueKey('device-applied')), findsNothing);
    expect(find.textContaining('adb reverse for port 3000 was removed'), findsOneWidget);
  });

  testWidgets('Cancel changes nothing; a forward that was already there is not removed by Undo', (tester) async {
    final runner = _scripted();
    runner.responses['adb.exe -s ZD222LBHP4 reverse --list'] = const CommandResult(exitCode: 0, stdout: 'host-19 tcp:3000 tcp:3000\r\n');
    await show(tester, _detector(runner));

    await tester.tap(find.widgetWithText(FilledButton, 'Use for Dev').first);
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(repository.variables.first.value, 'http://10.0.2.2:3000');
    expect(runner.calls.where((c) => c.contains('reverse')), isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Use for Dev').first);
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(repository.variables.first.value, 'http://10.0.2.2:3000');
    expect(runner.calls.where((c) => c.contains('--remove')), isEmpty, reason: 'the forward was not ours');
  });

  testWidgets('a failing adb reverse changes nothing and says so', (tester) async {
    final runner = _scripted();
    runner.responses['adb.exe -s ZD222LBHP4 reverse tcp:3000 tcp:3000'] = const CommandResult(exitCode: 1, stderr: 'adb.exe: error: closed\r\n');
    await show(tester, _detector(runner));
    await tester.tap(find.widgetWithText(FilledButton, 'Use for Dev').first);
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(find.byKey(const ValueKey('device-error')), findsOneWidget);
    expect(find.textContaining('adb reverse failed: adb.exe: error: closed Nothing was changed.'), findsOneWidget);
    expect(repository.variables.first.value, 'http://10.0.2.2:3000');
    expect(find.byKey(const ValueKey('device-applied')), findsNothing);
  });

  testWidgets('without adb reverse a phone gets this computer\'s LAN address', (tester) async {
    final runner = _scripted();
    await show(tester, _detector(runner));
    await tester.tap(find.text('Use adb reverse for phones (the address becomes localhost)'));
    await settle(tester);
    expect(find.textContaining('192.168.1.20'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Use for Dev').first);
    await settle(tester);
    expect(find.text('http://192.168.1.20:3000'), findsOneWidget);
    expect(find.byKey(const ValueKey('reverse-command')), findsNothing);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(repository.variables.first.value, 'http://192.168.1.20:3000');
    expect(runner.calls.where((c) => c.contains('reverse')), isEmpty);
  });

  testWidgets('adb missing, stuck, or no device: each says what to do', (tester) async {
    await show(tester, DeviceDetector(DeviceHost(
      runner: _scripted(),
      environment: const {'PATH': r'C:\Windows'},
      fileExists: (_) => false,
      platform: HostPlatform.windows,
      isSupported: true,
    )));
    expect(find.byKey(const ValueKey('adb-problem')), findsOneWidget);
    expect(find.textContaining('adb was not found'), findsOneWidget);

    await show(tester, _detector(_Runner({'adb.exe devices -l': const CommandResult(exitCode: 0, stdout: 'List of devices attached\r\n\r\n')})));
    expect(find.byKey(const ValueKey('no-devices')), findsOneWidget);
    expect(find.byKey(const ValueKey('adb-problem')), findsNothing);
  });

  testWidgets('nothing runs until asked when there is no auto scan, and the button scans', (tester) async {
    final runner = _scripted();
    await show(tester, _detector(runner), autoScan: false);
    expect(runner.calls, isEmpty);
    expect(find.text('Scan for devices'), findsOneWidget);
    await tester.tap(find.text('Scan for devices'));
    await settle(tester);
    expect(find.text('moto g24 power'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });

  testWidgets('a browser gets an honest note instead of the section', (tester) async {
    final runner = _scripted();
    await show(tester, _detector(runner, supported: false));
    expect(find.textContaining('needs the desktop app'), findsOneWidget);
    expect(find.text('Scan for devices'), findsNothing);
    expect(runner.calls, isEmpty);
  });

  testWidgets('fits a phone screen', (tester) async {
    await show(tester, _detector(_scripted()), size: const Size(380, 800));
    expect(find.text('moto g24 power'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
