import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/services/device_detector.dart';

/// Runs a program without a shell and gives up on it after the timeout.
final class _ProcessRunner implements CommandRunner {
  const _ProcessRunner();

  @override
  Future<CommandResult> run(String executable, List<String> arguments, {Duration timeout = const Duration(seconds: 5)}) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments).timeout(timeout);
    } on TimeoutException {
      return const CommandResult(timedOut: true);
    } on ProcessException catch (e) {
      return CommandResult(startError: e.message.isEmpty ? '$executable could not be started' : e.message);
    } on Object catch (e) {
      return CommandResult(startError: '$e');
    }
    try {
      // Nothing here reads input; a program that waits for it must see the end of it instead of waiting forever.
      await process.stdin.close();
    } on Object {
      // The program may already have exited.
    }
    final out = StringBuffer();
    final err = StringBuffer();
    const decoder = Utf8Decoder(allowMalformed: true);
    final outDone = process.stdout.transform(decoder).forEach(out.write).catchError((Object _) {});
    final errDone = process.stderr.transform(decoder).forEach(err.write).catchError((Object _) {});
    try {
      final code = await process.exitCode.timeout(timeout);
      // adb starts its server on the first call and the server may keep the pipes open: wait for them only briefly.
      await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 1), onTimeout: () => const <void>[]);
      return CommandResult(exitCode: code, stdout: out.toString(), stderr: err.toString());
    } on TimeoutException {
      process.kill();
      return CommandResult(stdout: out.toString(), stderr: err.toString(), timedOut: true);
    }
  }
}

DeviceHost systemDeviceHost() {
  final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  return DeviceHost(
    runner: const _ProcessRunner(),
    environment: Platform.environment,
    fileExists: (path) => File(path).existsSync(),
    platform: Platform.isWindows
        ? HostPlatform.windows
        : Platform.isMacOS
            ? HostPlatform.macos
            : Platform.isLinux
                ? HostPlatform.linux
                : HostPlatform.other,
    isSupported: desktop,
  );
}
