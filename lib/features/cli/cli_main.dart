import 'dart:convert';
import 'dart:io';
import 'dart_io_sender.dart';
import 'mcp_server.dart';
import 'reporters.dart';
import 'workspace_runner.dart';

const cliVersion = '1.0.0';

const _usage = '''
PostPilot CLI: run a workspace's requests and tests from a terminal or CI.

Usage:
  postpilot run  <workspace.json> [options]    Send requests and check their tests
  postpilot list <workspace.json>              List environments, collections and requests
  postpilot mcp  <workspace.json> [options]    Serve the workspace to AI agents (Model Context Protocol, stdio)

Options for run and mcp:
  --env <name>          Environment whose variables are used
  --collection <name>   Only this collection
  --folder <path>       Only this folder (and its sub-folders)
  --var <name=value>    Set a variable (repeatable); beats everything else
  --bail                Stop at the first failure
  --timeout <seconds>   Per-request timeout (default 30)
  --delay <ms>          Wait between requests
  --insecure            Do not verify TLS certificates
  --report <kind>       console (default), junit or json
  --out <file>          Write the junit/json report to a file
  --no-color            Plain output

Secrets: the shared workspace.json holds none of your secret values. If
workspace.local.json sits beside it, it is read too. In CI, pass secrets as
environment variables named POSTPILOT_VAR_<name> (for example POSTPILOT_VAR_odooApiKey).

Exit code: 0 all passed, 1 a request or test failed, 2 usage or file error.
''';

/// Parses the command line and runs it. Returns the process exit code.
Future<int> runCli(List<String> args, {CliSend? sender, IOSink? out, IOSink? err, Map<String, String>? environment}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final env = environment ?? Platform.environment;

  if (args.isEmpty || args.first == '--help' || args.first == '-h' || args.first == 'help') {
    stdoutSink.write(_usage);
    return args.isEmpty ? 2 : 0;
  }
  if (args.first == '--version' || args.first == '-v') {
    stdoutSink.writeln('postpilot $cliVersion');
    return 0;
  }

  final command = args.first;
  if (!const {'run', 'list', 'mcp'}.contains(command)) {
    stderrSink.writeln('Unknown command "$command".\n');
    stderrSink.write(_usage);
    return 2;
  }

  final parsed = _Args.parse(args.skip(1).toList());
  if (parsed.error != null) {
    stderrSink.writeln(parsed.error);
    return 2;
  }
  final path = parsed.positional.firstOrNull;
  if (path == null) {
    stderrSink.writeln('Give the workspace file: postpilot $command <workspace.json>');
    return 2;
  }
  final file = File(path);
  if (!file.existsSync()) {
    stderrSink.writeln('File not found: $path');
    return 2;
  }

  final WorkspaceRunner runner;
  try {
    final localFile = File('${file.parent.path}${Platform.pathSeparator}workspace.local.json');
    runner = WorkspaceRunner.parse(
      file.readAsStringSync(),
      sender ?? sendWithDartIo,
      localSecrets: localFile.existsSync() ? localFile.readAsStringSync() : null,
    );
  } catch (e) {
    stderrSink.writeln('"$path" is not a PostPilot workspace: $e');
    return 2;
  }

  final processVariables = {
    for (final e in env.entries)
      if (e.key.startsWith('POSTPILOT_VAR_')) e.key.substring('POSTPILOT_VAR_'.length): e.value,
  };

  if (command == 'list') {
    stdoutSink.writeln('Environments: ${runner.environmentNames.isEmpty ? '(none)' : runner.environmentNames.join(', ')}');
    for (final r in runner.listRequests()) {
      stdoutSink.writeln('${r.collection}${r.folder.isEmpty ? '' : ' / ${r.folder}'}  ${r.method.padRight(6)} ${r.name}');
    }
    return 0;
  }

  final options = RunOptions(
    environment: parsed.options['env'],
    variables: parsed.variables,
    collection: parsed.options['collection'],
    folder: parsed.options['folder'],
    bail: parsed.flags.contains('bail'),
    timeout: Duration(seconds: int.tryParse(parsed.options['timeout'] ?? '') ?? 30),
    delay: Duration(milliseconds: int.tryParse(parsed.options['delay'] ?? '') ?? 0),
    verifySsl: !parsed.flags.contains('insecure'),
  );

  if (command == 'mcp') {
    try {
      await McpServer(runner, options, processVariables).serve(stdin, stdoutSink, stderrSink);
      return 0;
    } on ArgumentError catch (e) {
      stderrSink.writeln(e.message);
      return 2;
    }
  }

  final report = parsed.options['report'] ?? 'console';
  if (!const {'console', 'junit', 'json'}.contains(report)) {
    stderrSink.writeln('Unknown report "$report". Use console, junit or json.');
    return 2;
  }
  final color = !parsed.flags.contains('no-color') && stdoutSink == stdout && stdout.hasTerminal;
  final live = report == 'console' || parsed.options['out'] != null;
  try {
    final summary = await runner.run(
      options,
      processVariables: processVariables,
      onResult: live ? (o) => stdoutSink.writeln(RunReporters.line(o, color: color)) : null,
    );
    final text = switch (report) {
      'junit' => RunReporters.junit(summary),
      'json' => RunReporters.json(summary),
      _ => RunReporters.console(summary, color: color),
    };
    final target = parsed.options['out'];
    if (report == 'console') {
      stdoutSink.write(text);
    } else if (target != null) {
      File(target).writeAsStringSync(text);
      stdoutSink.write(RunReporters.console(summary, color: color));
      stdoutSink.writeln('Report written to $target');
    } else {
      stdoutSink.write(text);
    }
    if (summary.total == 0) {
      stderrSink.writeln('Nothing ran: no request matched${options.collection == null ? '' : ' collection "${options.collection}"'}.');
      return 2;
    }
    return summary.ok ? 0 : 1;
  } on ArgumentError catch (e) {
    stderrSink.writeln(e.message);
    return 2;
  }
}

final class _Args {
  final List<String> positional = [];
  final Map<String, String> options = {};
  final Map<String, String> variables = {};
  final Set<String> flags = {};
  String? error;

  static const _valued = {'env', 'collection', 'folder', 'timeout', 'delay', 'report', 'out'};
  static const _boolean = {'bail', 'insecure', 'no-color'};

  static _Args parse(List<String> args) {
    final result = _Args();
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (!a.startsWith('--')) {
        result.positional.add(a);
        continue;
      }
      final eq = a.indexOf('=');
      final name = eq < 0 ? a.substring(2) : a.substring(2, eq);
      if (_boolean.contains(name)) {
        result.flags.add(name);
        continue;
      }
      if (name != 'var' && !_valued.contains(name)) {
        result.error = 'Unknown option --$name.';
        return result;
      }
      final String value;
      if (eq >= 0) {
        value = a.substring(eq + 1);
      } else if (i + 1 < args.length) {
        value = args[++i];
      } else {
        result.error = 'Option --$name needs a value.';
        return result;
      }
      if (name == 'var') {
        final split = value.indexOf('=');
        if (split <= 0) {
          result.error = '--var needs name=value, got "$value".';
          return result;
        }
        result.variables[value.substring(0, split)] = value.substring(split + 1);
      } else {
        result.options[name] = value;
      }
    }
    return result;
  }
}

/// The report as a JSON-encodable list, for the MCP server and tests.
List<Map<String, Object?>> outcomesAsJson(RunSummary s) => (jsonDecode(RunReporters.json(s)) as Map<String, dynamic>)['requests'].cast<Map<String, Object?>>();
