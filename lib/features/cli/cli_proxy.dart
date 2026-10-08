// `postpilot proxy`: the CORS proxy of the web version, started from a terminal. The engine is the same one the desktop app
// starts from its command palette (lib/features/cors_proxy); this file only reads the command line and prints.
import 'dart:async';
import 'dart:io';
import '../cors_proxy/data/cors_proxy_engine.dart';

const proxyUsage = '''
PostPilot CORS proxy: lets the web version of PostPilot call APIs that send no CORS headers.

Usage:
  postpilot proxy [options]

  --port <n>                 Port to listen on (default ${CorsProxyProtocol.defaultPort}, 0 picks a free one)
  --allow-origin <origin>    A web page that may use the proxy, besides http(s)://localhost:* and 127.0.0.1:*
                             (repeatable, or comma separated), e.g. https://app.example.com. A wildcard is refused.
  --token <t>                Use this token instead of a random one (8+ visible ASCII characters).
                             Also read from POSTPILOT_PROXY_TOKEN, which keeps it out of the process list.
  --allow-lan                Listen on every network interface, not only on this computer (see the warning it prints)
  --insecure                 Accept self-signed or expired TLS certificates of the servers it calls
  --help                     This text

The proxy listens on this computer only. The web app sends its real request to it with the address in an X-PostPilot-Url
header; the proxy forwards the call (no redirect is followed, a 60 second limit applies) and adds the CORS headers to the
answer. Every call but a browser preflight needs the X-PostPilot-Token header, so another web page cannot use it.
It prints METHOD host/path status time for each call, with secrets in the query masked; headers and bodies are never printed.
''';

/// The command line of `postpilot proxy`, parsed.
final class ProxyArgs {
  final CorsProxyConfig config;
  final bool help;

  const ProxyArgs(this.config, {this.help = false});

  /// Throws a [FormatException] whose message says what to fix.
  static ProxyArgs parse(List<String> args, {Map<String, String> environment = const {}}) {
    var port = CorsProxyProtocol.defaultPort;
    var lan = false;
    var insecure = false;
    String? token;
    final origins = <String>[];
    var next = 0;
    while (next < args.length) {
      var arg = args[next++];
      String? inline;
      final eq = arg.startsWith('--') ? arg.indexOf('=') : -1;
      if (eq > 0) {
        inline = arg.substring(eq + 1);
        arg = arg.substring(0, eq);
      }
      String value() {
        if (inline != null) return inline;
        if (next >= args.length) throw FormatException('$arg needs a value.');
        return args[next++];
      }

      switch (arg) {
        case '--help' || '-h':
          return ProxyArgs(CorsProxyConfig(token: CorsProxyToken.generate()), help: true);
        case '--port':
          final text = value();
          final n = int.tryParse(text);
          if (n == null || n < 0 || n > 65535) throw FormatException('--port needs a whole number from 0 to 65535, got "$text".');
          port = n;
        case '--allow-origin':
          final parsed = CorsProxyOrigins.parseList(value());
          final error = parsed.error;
          if (error != null) throw FormatException(error);
          for (final origin in parsed.origins) {
            if (!origins.contains(origin)) origins.add(origin);
          }
        case '--token':
          token = value();
        case '--allow-lan':
          lan = true;
        case '--insecure':
          insecure = true;
        default:
          throw FormatException('Unknown option $arg.');
      }
    }
    token ??= environment['POSTPILOT_PROXY_TOKEN'];
    if (token != null) {
      final problem = CorsProxyToken.problem(token);
      if (problem != null) throw FormatException(problem);
      if (lan) {
        final lanProblem = CorsProxyToken.lanProblem(token);
        if (lanProblem != null) throw FormatException(lanProblem);
      }
    }
    return ProxyArgs(CorsProxyConfig(
      token: token ?? CorsProxyToken.generate(),
      host: lan ? CorsProxyConfig.allInterfaces : CorsProxyConfig.loopbackHost,
      port: port,
      allowedOrigins: origins,
      insecure: insecure,
    ));
  }
}

/// Starts the proxy from command line [args] (what follows `postpilot proxy`), prints what to paste into the web app, then
/// prints each call until Ctrl+C ([until] replaces that, for a test). Returns the exit code: 0 stopped, 1 could not start,
/// 2 a mistake in the command line. [onStarted] sees the running engine once its address and token are printed.
Future<int> runProxyCommand(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? environment,
  Future<void>? until,
  void Function(CorsProxyEngine engine)? onStarted,
}) async {
  final sink = out ?? stdout;
  final errSink = err ?? stderr;
  final ProxyArgs parsed;
  try {
    parsed = ProxyArgs.parse(args, environment: environment ?? Platform.environment);
  } on FormatException catch (e) {
    errSink.writeln('${e.message}\n\n$proxyUsage');
    return 2;
  }
  if (parsed.help) {
    sink.write(proxyUsage);
    return 0;
  }

  final engine = CorsProxyEngine.create();
  try {
    await engine.start(parsed.config);
  } on StateError catch (e) {
    errSink.writeln(e.message);
    await engine.dispose();
    return 1;
  }
  final config = parsed.config;
  final port = engine.port!;
  sink.writeln('PostPilot CORS proxy is running.');
  if (config.listensOnAllInterfaces) {
    sink.writeln('');
    sink.writeln('!! WARNING: --allow-lan lets every device on your network use this proxy. !!');
    sink.writeln('Anyone who gets the token can send requests from this computer to any address it can reach, including your');
    sink.writeln('private network. Use it only on a network you trust, and keep the token secret.');
    sink.writeln('');
  }
  for (final url in await _addresses(config, port)) {
    sink.writeln('  URL:    $url');
  }
  sink.writeln('  Token:  ${config.token}');
  sink.writeln('  Pages allowed to use it: ${config.origins.describe()}');
  sink.writeln('');
  sink.writeln('In the PostPilot web app open Settings > CORS proxy, paste the URL and the token, switch the proxy on and press');
  sink.writeln('Test connection. Each call is listed below as METHOD host/path status time; headers and bodies are never printed.');
  sink.writeln('Press Ctrl+C to stop.');

  final subscription = engine.events.listen((e) {
    sink.writeln('${e.at.toIso8601String().substring(11, 19)}  ${e.line}');
  });
  onStarted?.call(engine);
  final stop = Completer<void>();
  final signals = <StreamSubscription<ProcessSignal>>[];
  if (until != null) {
    unawaited(until.then((_) {
      if (!stop.isCompleted) stop.complete();
    }));
  } else {
    void interrupted(ProcessSignal _) {
      if (!stop.isCompleted) stop.complete();
    }

    signals.add(ProcessSignal.sigint.watch().listen(interrupted));
    try {
      signals.add(ProcessSignal.sigterm.watch().listen(interrupted));
    } on SignalException {
      // Windows has no SIGTERM; Ctrl+C is enough there.
    }
  }
  await stop.future;
  for (final signal in signals) {
    await signal.cancel();
  }
  await subscription.cancel();
  await engine.dispose();
  return 0;
}

/// The addresses to paste into the web app: this computer's, and with --allow-lan the ones other devices use.
Future<List<String>> _addresses(CorsProxyConfig config, int port) async {
  if (!config.listensOnAllInterfaces) return ['http://localhost:$port'];
  final urls = ['http://localhost:$port'];
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) urls.add('http://${a.address}:$port');
      }
    }
  } catch (_) {
    // Only the local address is shown when the interfaces cannot be listed.
  }
  return urls;
}
