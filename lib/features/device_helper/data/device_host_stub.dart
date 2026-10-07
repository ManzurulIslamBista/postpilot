import '../domain/services/device_detector.dart';

final class _NoCommands implements CommandRunner {
  const _NoCommands();

  @override
  Future<CommandResult> run(String executable, List<String> arguments, {Duration timeout = const Duration(seconds: 5)}) async =>
      const CommandResult(startError: 'programs cannot be run here');
}

DeviceHost systemDeviceHost() => DeviceHost(
      runner: const _NoCommands(),
      environment: const {},
      fileExists: (_) => false,
      platform: HostPlatform.other,
      isSupported: false,
    );
