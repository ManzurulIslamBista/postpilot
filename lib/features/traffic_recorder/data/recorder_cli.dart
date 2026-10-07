// A command line entry for the recorder engine, so it can run without the app (a phone test, a CI job, a quick look):
//
//   dart run lib/features/traffic_recorder/data/recorder_cli.dart --upstream https://api.example.com --port 8099 --lan
//
// Nothing here needs Flutter: the engine, its models and the masking helpers are plain Dart. Every finished call is printed
// as one line (query secrets masked) until Ctrl+C.
import 'dart:async';
import 'dart:io';
import '../../device_helper/data/network_info.dart';
import '../domain/services/lan_addresses.dart';
import '../domain/services/recorder_connect.dart';
import '../domain/services/traffic_masking.dart';
import 'recorder_engine.dart';

/// The command line of [runRecorderCli], parsed.
final class RecorderCliArgs {
  final RecorderConfig config;
  final bool help;

  const RecorderCliArgs(this.config, {this.help = false});

  static const usage = '''
PostPilot traffic recorder: a reverse proxy that records the calls an app makes.

  --upstream <url>   the real server (required), e.g. https://api.example.com
  --port <n>         port to listen on (default 8099, 0 picks a free one)
  --host <address>   address to listen on (default 127.0.0.1)
  --lan              listen on every interface (0.0.0.0) so a phone on the same Wi-Fi can connect
  --insecure         accept a self-signed or expired certificate from the upstream
  --no-rewrite       do not rewrite Host, Origin and Referer
  --keep-brotli      do not ask the upstream for gzip instead of brotli
  --system-proxy     reach the upstream through HTTP_PROXY / HTTPS_PROXY
  --timeout <s>      seconds the upstream may stay silent (default 60)
  --max-body <kb>    kilobytes of each body to keep (default 512)
  --help             this text
''';

  /// Throws a [FormatException] whose message says what to fix.
  static RecorderCliArgs parse(List<String> args) {
    String? upstream;
    var port = 8099;
    var host = RecorderConfig.loopbackHost;
    var insecure = false;
    var rewrite = true;
    var readable = true;
    var systemProxy = false;
    var timeout = 60;
    var maxBodyKb = RecorderConfig.defaultMaxBodyBytes ~/ 1024;
    var next = 0;
    while (next < args.length) {
      final arg = args[next++];
      String value() {
        if (next >= args.length) throw FormatException('$arg needs a value.');
        return args[next++];
      }

      int number() => int.tryParse(value()) ?? (throw FormatException('$arg needs a whole number.'));

      switch (arg) {
        case '--help' || '-h':
          return RecorderCliArgs(RecorderConfig(upstream: Uri.parse('http://localhost')), help: true);
        case '--upstream':
          upstream = value();
        case '--port':
          port = number();
        case '--host':
          host = value();
        case '--lan':
          host = RecorderConfig.allInterfaces;
        case '--insecure':
          insecure = true;
        case '--no-rewrite':
          rewrite = false;
        case '--keep-brotli':
          readable = false;
        case '--system-proxy':
          systemProxy = true;
        case '--timeout':
          timeout = number();
        case '--max-body':
          maxBodyKb = number();
        default:
          throw FormatException('Unknown option $arg.');
      }
    }
    final problem = RecorderConfig.upstreamProblem(upstream ?? '');
    if (problem != null) throw FormatException(problem);
    return RecorderCliArgs(RecorderConfig(
      upstream: RecorderConfig.parseUpstream(upstream!)!,
      host: host,
      port: port,
      allowSelfSigned: insecure,
      rewriteHostHeaders: rewrite,
      keepResponsesReadable: readable,
      useSystemProxy: systemProxy,
      timeout: Duration(seconds: timeout),
      maxBodyBytes: maxBodyKb * 1024,
    ));
  }
}

/// Starts a recorder from command line [args], prints what to give the app, then prints each call until Ctrl+C. Returns the
/// exit code.
Future<int> runRecorderCli(List<String> args, {StringSink? out}) async {
  final sink = out ?? stdout;
  final RecorderCliArgs parsed;
  try {
    parsed = RecorderCliArgs.parse(args);
  } on FormatException catch (e) {
    sink.writeln('${e.message}\n\n${RecorderCliArgs.usage}');
    return 64;
  }
  if (parsed.help) {
    sink.writeln(RecorderCliArgs.usage);
    return 0;
  }

  final engine = RecorderEngine.create();
  try {
    await engine.start(parsed.config);
  } on StateError catch (e) {
    sink.writeln(e.message);
    return 1;
  }
  final port = engine.port!;
  final List<LocalAddress> lan = parsed.config.listensOnAllInterfaces ? await RecorderAddresses.lookup() : const <LocalAddress>[];
  sink.writeln('Recording ${parsed.config.upstream} on port $port. Point the app at one of these:');
  for (final option in RecorderConnect.options(port: port, allowOtherDevices: parsed.config.listensOnAllInterfaces, addresses: lan)) {
    if (!option.available || option.url.isEmpty) continue;
    sink.writeln('  ${option.label}: ${option.url}${option.command == null ? '' : '   (first run: ${option.command})'}');
  }
  sink.writeln('Plain http:// must be allowed by the app on a phone. Press Ctrl+C to stop.');

  final subscription = engine.exchanges.listen((e) {
    final ms = e.duration.inMilliseconds;
    final note = e.error == null ? '' : '  [${e.error}]';
    sink.writeln('${e.startedAt.toIso8601String().substring(11, 19)}  ${e.method.padRight(6)} ${e.status}  ${ms.toString().padLeft(5)} ms  '
        '${TrafficMasking.url(e.path)}$note');
  });
  final stop = Completer<void>();
  final signal = ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  await stop.future;
  await signal.cancel();
  await subscription.cancel();
  await engine.dispose();
  return 0;
}

Future<void> main(List<String> args) async => exit(await runRecorderCli(args));
