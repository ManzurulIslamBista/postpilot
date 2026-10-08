import 'dart:convert';
import 'dart:io';
import '../request_builder/domain/services/collection_run_options.dart';
import '../request_builder/domain/services/run_data_parser.dart';
import '../test_suggestions/domain/services/baseline_file.dart';
import 'dart_io_sender.dart';
import 'iterated_run.dart';
import 'markdown_reporter.dart';
import 'cli_proxy.dart';
import 'mcp_server.dart';
import 'production_lock.dart';
import 'reporters.dart';
import 'run_records_export.dart';
import 'workspace_runner.dart';

const cliVersion = '1.0.0';

const _usage = '''
PostPilot CLI: run a workspace's requests and tests from a terminal or CI.

Usage:
  postpilot run  <workspace.json> [options]    Send requests and check their tests
  postpilot list <workspace.json>              List environments, collections and requests
  postpilot mcp  <workspace.json> [options]    Serve the workspace to AI agents (Model Context Protocol, stdio)
  postpilot proxy [options]                    CORS proxy so the web version can call any API ("postpilot proxy --help")

Options for run and mcp:
  --env <name>          Environment whose variables are used
  --collection <name>   Only this collection
  --folder <path>       Only this folder (and its sub-folders)
  --request <name>      Only this request: its name, or Folder/Sub/Name (repeatable)
  --var <name=value>    Set a variable (repeatable); beats everything else
  --bail                Stop at the first failure
  --timeout <seconds>   Per-request timeout (default 30)
  --delay <ms>          Wait between requests
  --insecure            Do not verify TLS certificates
  --report <kind>       console (default), junit, json or markdown
  --out <file>          Write the junit/json/markdown report to a file
  --markdown-out <file> Also write a Markdown summary to this file (for an issue or a pull request comment)
  --iterations <n>      Repeat the whole run n times (1-1000)
  --data <file>         CSV (header row) or JSON (array of objects): one pass per row, {{column}} in a
                        request becomes that row's value; it replaces --iterations
  --records-dir <dir>   Write a run record (JSON) per collection into this folder; the app imports it with
                        "Import CLI run" in the collection's Run history
  --baseline-file <f>   Recorded response baselines ("Export baselines..." in the app's Response tools): a request
                        that turned on "Enforce baseline in runs" fails when its response drifted in a breaking
                        way, e.g. a field was removed or changed type
  --fail-on-skip       Fail the run when any request was skipped (for example OAuth 2.0 Authorization Code without a token)
  --no-color            Plain output

Requests run in the order the app shows them: folders and requests as arranged in
the sidebar, a folder's content right after it. --folder and --request only pick
from that order, they never change it.

Production lock: while the environment looks like production (a name with
prod, production, prd or live) or a request goes to a production host, requests
that change data (POST, PUT, PATCH, DELETE, an Odoo write, a GraphQL mutation)
are refused before anything is sent, with exit code 2. Reads still run.
  --allow-production    Send data-changing requests to production anyway
  --production-word <w> Another word that marks an environment as production (repeatable)
  --production-host <h> A host that is production under any environment name, for
                        example api.acme.com, *.acme.com or acme.com:8443 (repeatable)

Secrets: the shared workspace.json holds none of your secret values. If
workspace.local.json sits beside it, it is read too. In CI, pass secrets as
environment variables named POSTPILOT_VAR_<name> (for example POSTPILOT_VAR_odooApiKey).

OAuth 2.0: Client Credentials and Password requests get their token by themselves (a stored token that
is still valid is used as it is, a refresh token is used when there is one), also when it expires during
the run. Tokens renewed in a run are kept in memory only, never written back. Authorization Code needs
a person to sign in once in the app; without a token in the workspace it is skipped.
Re-login: a collection or folder set to "on 401/403 run request X" does so here too, once per request.

Flow (the Flow tab of a request, no script needed): Retry sends again on a network error or chosen statuses
(waiting longer each time, honouring Retry-After); Poll until repeats a request until a condition holds; Fetch
all pages follows a paged list to its end and gives one merged response. Each try is shown, e.g. "3 attempts",
"polled 5 times", "5 pages, 482 items". POST, PATCH and DELETE are only repeated when the request says so.
Run if skips a request (shown as skipped with the reason, never as failed) unless its condition holds: a variable,
the --env name, or how the previous request ended. A skipped request is not sent, so the production lock is not
asked about it, and --fail-on-skip does not count it. "Always run" requests (cleanups) still run after --bail
stopped the run, with their own Run if still applying.

GitHub Actions: when \$GITHUB_STEP_SUMMARY is set, a Markdown summary of the run (what broke, grouped by cause)
is appended to the job summary by itself, whatever --report says.

Exit code: 0 all passed, 1 a request or test failed (or nothing was verified:
every request was skipped, or --fail-on-skip and one was), 2 usage or file error,
a production lock refusal, a --request that matches nothing, or no request matched.
''';

/// Parses the command line and runs it. Returns the process exit code.
Future<int> runCli(
  List<String> args, {
  CliSend? sender,
  IOSink? out,
  IOSink? err,
  Map<String, String>? environment,
  DateTime Function()? now,
}) async {
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
  // The CORS proxy of the web version: its own options, nothing to do with a workspace file.
  if (command == 'proxy') {
    return runProxyCommand(args.skip(1).toList(), out: stdoutSink, err: stderrSink, environment: env);
  }
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

  var baselines = BaselineFile.empty;
  final baselinePath = parsed.options['baseline-file'];
  if (baselinePath != null) {
    final baselineFile = File(baselinePath);
    if (!baselineFile.existsSync()) {
      stderrSink.writeln('Baseline file not found: $baselinePath');
      return 2;
    }
    try {
      baselines = BaselineFile.parse(baselineFile.readAsStringSync());
    } on FormatException catch (e) {
      stderrSink.writeln('"$baselinePath": ${e.message}');
      return 2;
    }
  }

  final WorkspaceRunner runner;
  try {
    final localFile = File('${file.parent.path}${Platform.pathSeparator}workspace.local.json');
    runner = WorkspaceRunner.parse(
      file.readAsStringSync(),
      sender ?? sendWithDartIo,
      localSecrets: localFile.existsSync() ? localFile.readAsStringSync() : null,
      // A file a request uploads is found from the folder of the workspace file when its path is relative.
      baseDir: file.absolute.parent.path,
      baselines: baselines,
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

  // One RunOptions per pass: a data row's columns go on top of --var, as the data row is the top scope in the app.
  RunOptions optionsFor(Map<String, String> row) => RunOptions(
    environment: parsed.options['env'],
    variables: {...parsed.variables, ...row},
    collection: parsed.options['collection'],
    folder: parsed.options['folder'],
    requests: parsed.lists['request'] ?? const [],
    bail: parsed.flags.contains('bail'),
    timeout: Duration(seconds: int.tryParse(parsed.options['timeout'] ?? '') ?? 30),
    delay: Duration(milliseconds: int.tryParse(parsed.options['delay'] ?? '') ?? 0),
    verifySsl: !parsed.flags.contains('insecure'),
    production: ProductionLock(
      allow: parsed.flags.contains('allow-production'),
      extraWords: parsed.lists['production-word'] ?? const [],
      hosts: parsed.lists['production-host'] ?? const [],
    ),
    failOnSkip: parsed.flags.contains('fail-on-skip'),
  );
  final options = optionsFor(const {});

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
  if (!const {'console', 'junit', 'json', 'markdown'}.contains(report)) {
    stderrSink.writeln('Unknown report "$report". Use console, junit, json or markdown.');
    return 2;
  }
  // --iterations and --data repeat the run; they are checked before anything is sent.
  final repeat = _Repeat.read(parsed.options['iterations'], parsed.options['data']);
  if (repeat.error != null) {
    stderrSink.writeln(repeat.error);
    return 2;
  }
  if (repeat.note != null) stderrSink.writeln(repeat.note);
  final color = !parsed.flags.contains('no-color') && stdoutSink == stdout && stdout.hasTerminal;
  final live = report == 'console' || parsed.options['out'] != null;
  final unmatched = runner.unmatchedRequestSelectors(options);
  if (unmatched.isNotEmpty) {
    stderrSink.writeln(
      'No request matches ${unmatched.map((s) => '"$s"').join(', ')}. '
      'Use the request name, or Folder/Sub-folder/Name; "postpilot list $path" shows what is there.',
    );
    return 2;
  }
  try {
    // The production lock refuses the whole run up front: sending half of a
    // collection to production and then stopping is worse than sending none.
    // A data row can change a URL, so the lock looks at every pass; a request refused in several is listed once.
    final blocks = <ProductionBlock>[];
    final listed = <String>{};
    for (final row in repeat.rows.isEmpty ? const [<String, String>{}] : repeat.rows) {
      for (final block in runner.productionBlocks(optionsFor(row), processVariables: processVariables)) {
        if (listed.add(block.line)) blocks.add(block);
      }
    }
    if (blocks.isNotEmpty) {
      stderrSink.writeln(ProductionBlock.describe(
        blocks,
        howToAllow: 'Pass --allow-production to send them anyway, or select only read-only requests with --collection or --folder.',
      ));
      return 2;
    }
    final startedAt = (now ?? DateTime.now)().toUtc();
    final run = await runIterated(
      runner,
      optionsFor: optionsFor,
      processVariables: processVariables,
      data: repeat.rows,
      iterations: repeat.iterations,
      bail: options.bail,
      delay: options.delay,
      failOnSkip: options.failOnSkip,
      onPass: live && repeat.passes > 1 ? (pass, total) => stdoutSink.writeln('── Pass $pass of $total ──') : null,
      onResult: live ? (o, pass) => stdoutSink.writeln(RunReporters.line(o, color: color, iteration: repeat.passes > 1 ? pass : null)) : null,
    );
    final summary = run.combined;
    // A plain run reports exactly as before; only a repeated one names the pass of each request.
    final passes = run.repeated ? run.iterations : null;
    final text = switch (report) {
      'junit' => RunReporters.junit(summary, iterations: passes),
      'json' => RunReporters.json(summary, iterations: passes),
      'markdown' => MarkdownReporter.summary(summary, iterations: passes, environment: options.environment ?? '', collection: options.collection ?? ''),
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
    _writeExtras(
      parsed: parsed,
      env: env,
      run: run,
      options: options,
      markdown: report == 'markdown' ? text : null,
      startedAt: startedAt,
      stderrSink: stderrSink,
      stdoutSink: stdoutSink,
    );
    if (summary.total == 0) {
      stderrSink.writeln('Nothing ran: no request matched${options.collection == null ? '' : ' collection "${options.collection}"'}.');
      return 2;
    }
    if (summary.allSkipped) {
      stderrSink.writeln('Nothing was verified: all ${summary.total} selected request${summary.total == 1 ? ' was' : 's were'} skipped, so no request was sent or checked.');
    } else if (options.failOnSkip && summary.skipped > summary.skippedByRule && summary.failed == 0) {
      // A request left out by its own Run if is not counted: that was asked for.
      final unplanned = summary.skipped - summary.skippedByRule;
      stderrSink.writeln('--fail-on-skip: $unplanned request${unplanned == 1 ? ' was' : 's were'} skipped.');
    }
    return summary.ok ? 0 : 1;
  } on ArgumentError catch (e) {
    stderrSink.writeln(e.message);
    return 2;
  }
}

/// `--iterations` and `--data`: how many passes the run makes and what each is fed, checked before anything is sent.
final class _Repeat {
  final int iterations;
  final List<Map<String, String>> rows;
  final String? error;

  /// Said on stderr but not an error (`--iterations` given together with `--data`).
  final String? note;

  const _Repeat(this.iterations, this.rows, {this.note}) : error = null;
  const _Repeat.failed(String this.error)
      : iterations = 1,
        rows = const [],
        note = null;

  /// How many passes will run: one per data row, else the iteration count.
  int get passes => rows.isEmpty ? iterations : rows.length;

  static _Repeat read(String? iterationsText, String? dataPath) {
    var iterations = 1;
    if (iterationsText != null) {
      final n = int.tryParse(iterationsText.trim());
      if (n == null || n < 1 || n > CollectionRunOptions.maxIterations) {
        return _Repeat.failed('--iterations needs a whole number from 1 to ${CollectionRunOptions.maxIterations}, got "$iterationsText".');
      }
      iterations = n;
    }
    if (dataPath == null) return _Repeat(iterations, const []);
    final file = File(dataPath);
    if (!file.existsSync()) return _Repeat.failed('Data file not found: $dataPath');
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (e) {
      return _Repeat.failed('Could not read the data file "$dataPath": ${e.message}');
    } on FormatException {
      return _Repeat.failed('The data file "$dataPath" is not UTF-8 text. Save it as a UTF-8 CSV or JSON file.');
    }
    final data = const RunDataParser().parse(text);
    if (data.error != null) return _Repeat.failed('The data file "$dataPath" cannot be used: ${data.error}');
    if (data.rows.isEmpty) return _Repeat.failed('The data file "$dataPath" has no rows. It needs a header row and at least one row of data (CSV), or a JSON array of objects.');
    return _Repeat(
      data.rows.length,
      data.rows,
      note: iterationsText == null ? null : '--iterations is ignored: the data file has ${data.rows.length} rows, one pass each.',
    );
  }
}

/// What a run leaves besides its report: the Markdown file (`--markdown-out`), the job summary of GitHub Actions and
/// the run records (`--records-dir`). One that cannot be written is said on stderr and never changes the exit code,
/// which is about the requests.
void _writeExtras({
  required _Args parsed,
  required Map<String, String> env,
  required IteratedRun run,
  required RunOptions options,
  required String? markdown,
  required DateTime startedAt,
  required IOSink stderrSink,
  required IOSink stdoutSink,
}) {
  final summary = run.combined;
  final passes = run.repeated ? run.iterations : null;
  String markdownText() => markdown ??= MarkdownReporter.summary(
        summary,
        iterations: passes,
        environment: options.environment ?? '',
        collection: options.collection ?? '',
      );

  void tryWrite(String what, String target, void Function() write) {
    try {
      write();
    } on FileSystemException catch (e) {
      stderrSink.writeln('Could not write $what to "$target": ${e.message}');
    }
  }

  final markdownOut = parsed.options['markdown-out'];
  if (markdownOut != null) {
    tryWrite('the Markdown summary', markdownOut, () {
      File(markdownOut).writeAsStringSync(markdownText());
      stdoutSink.writeln('Markdown summary written to $markdownOut');
    });
  }
  // GitHub Actions: the job summary is a file the steps append to.
  final stepSummary = env['GITHUB_STEP_SUMMARY'];
  if (stepSummary != null && stepSummary.isNotEmpty) {
    tryWrite('the job summary', stepSummary, () => File(stepSummary).writeAsStringSync('${markdownText()}\n', mode: FileMode.append));
  }
  final recordsDir = parsed.options['records-dir'];
  if (recordsDir != null) {
    tryWrite('the run records', recordsDir, () {
      final docs = CliRunRecords.build(run, environment: options.environment ?? '', startedAt: startedAt, bail: options.bail);
      for (final path in CliRunRecords.write(recordsDir, docs)) {
        stdoutSink.writeln('Run record written to $path');
      }
    });
  }
}

final class _Args {
  final List<String> positional = [];
  final Map<String, String> options = {};
  final Map<String, String> variables = {};

  /// Options that may be given more than once (`--production-host a --production-host b`, `--request A --request B`).
  final Map<String, List<String>> lists = {};
  final Set<String> flags = {};
  String? error;

  static const _valued = {
    'env',
    'collection',
    'folder',
    'timeout',
    'delay',
    'report',
    'out',
    'markdown-out',
    'iterations',
    'data',
    'records-dir',
    'baseline-file',
  };
  static const _repeatable = {'production-word', 'production-host', 'request'};
  static const _boolean = {'bail', 'insecure', 'no-color', 'allow-production', 'fail-on-skip'};

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
      if (name != 'var' && !_valued.contains(name) && !_repeatable.contains(name)) {
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
      } else if (_repeatable.contains(name)) {
        result.lists.putIfAbsent(name, () => []).add(value);
      } else {
        result.options[name] = value;
      }
    }
    return result;
  }
}

/// The report as a JSON-encodable list, for the MCP server and tests.
List<Map<String, Object?>> outcomesAsJson(RunSummary s) => (jsonDecode(RunReporters.json(s)) as Map<String, dynamic>)['requests'].cast<Map<String, Object?>>();
