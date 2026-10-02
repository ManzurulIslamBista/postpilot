import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../documentation/domain/services/secret_masker.dart';
import 'reporters.dart';
import 'workspace_runner.dart';

/// Serves a PostPilot workspace to AI agents over the Model Context Protocol
/// (JSON-RPC 2.0, one message per line on stdin/stdout). The agent can list
/// the requests and run them with the workspace's environments and tests:
/// "run the Create order request on staging and tell me what failed".
///
/// Everything an agent reads is masked: credentials in URLs, headers and bodies
/// never leave the process.
final class McpServer {
  static const protocolVersion = '2024-11-05';

  final WorkspaceRunner runner;
  final RunOptions options;
  final Map<String, String> processVariables;

  McpServer(this.runner, this.options, this.processVariables);

  /// Reads requests from [input] until it closes.
  Future<void> serve(Stream<List<int>> input, IOSink output, IOSink log) async {
    log.writeln('PostPilot MCP server ready: ${runner.collectionNames.length} collections.');
    await for (final line in input.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final reply = await handleLine(line);
      if (reply != null) output.writeln(reply);
    }
  }

  /// One JSON-RPC message in, the reply (or null for a notification) out.
  Future<String?> handleLine(String line) async {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return jsonEncode({'jsonrpc': '2.0', 'id': null, 'error': {'code': -32700, 'message': 'Parse error'}});
    }
    if (message is! Map<String, dynamic>) {
      return jsonEncode({'jsonrpc': '2.0', 'id': null, 'error': {'code': -32600, 'message': 'Invalid request'}});
    }
    final id = message['id'];
    final method = message['method'];
    final params = message['params'] is Map<String, dynamic> ? message['params'] as Map<String, dynamic> : const <String, dynamic>{};
    if (id == null) return null; // a notification such as notifications/initialized

    Object result;
    try {
      result = switch (method) {
        'initialize' => {
            'protocolVersion': params['protocolVersion'] ?? protocolVersion,
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'postpilot', 'version': '1.0.0'},
          },
        'ping' => <String, Object?>{},
        'tools/list' => {'tools': _tools},
        'tools/call' => await _call('${params['name']}', params['arguments'] is Map<String, dynamic> ? params['arguments'] as Map<String, dynamic> : const {}),
        _ => throw _MethodNotFound('$method'),
      };
    } on _MethodNotFound catch (e) {
      return jsonEncode({'jsonrpc': '2.0', 'id': id, 'error': {'code': -32601, 'message': 'Method not found: ${e.method}'}});
    }
    return jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  static final _tools = [
    {
      'name': 'list_requests',
      'description': 'List the requests in the workspace: collection, folder, name, method and URL (credentials masked).',
      'inputSchema': {
        'type': 'object',
        'properties': {'collection': {'type': 'string', 'description': 'Only this collection'}},
      },
    },
    {
      'name': 'list_environments',
      'description': 'List the environments (Dev, Staging, Production...) a request can be run in.',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'run_request',
      'description': 'Send one request by name and return its status, timing, response body and test results. '
          'Variables extracted by earlier calls in this session stay available.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'request': {'type': 'string', 'description': 'Request name'},
          'collection': {'type': 'string', 'description': 'Collection name (needed when two collections share a request name)'},
          'environment': {'type': 'string', 'description': 'Environment name; defaults to the one the server started with'},
          'variables': {'type': 'object', 'description': 'Variables to set for this call', 'additionalProperties': {'type': 'string'}},
        },
        'required': ['request'],
      },
    },
    {
      'name': 'run_collection',
      'description': 'Run every request of a collection in order and return a pass/fail summary with each failure.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'collection': {'type': 'string'},
          'folder': {'type': 'string'},
          'environment': {'type': 'string'},
          'bail': {'type': 'boolean', 'description': 'Stop at the first failure'},
        },
        'required': ['collection'],
      },
    },
  ];

  RunState? _session;

  Future<Map<String, Object?>> _call(String name, Map<String, dynamic> args) async {
    try {
      return _text(await _run(name, args));
    } on ArgumentError catch (e) {
      return _text('Error: ${e.message}', isError: true);
    } catch (e) {
      return _text('Error: $e', isError: true);
    }
  }

  Future<String> _run(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'list_requests':
        final refs = runner.listRequests(collection: args['collection'] as String?);
        return const JsonEncoder.withIndent('  ').convert([
          for (final r in refs) {'collection': r.collection, 'folder': r.folder, 'name': r.name, 'method': r.method, 'url': SecretMasker.maskUrl(r.url)},
        ]);
      case 'list_environments':
        return const JsonEncoder.withIndent('  ').convert({'environments': runner.environmentNames, 'default': options.environment});
      case 'run_request':
        final wanted = '${args['request']}';
        final collection = args['collection'] as String?;
        final matches = [
          for (final c in runner.snapshot.collections)
            if (collection == null || c.name == collection)
              for (final r in c.requests)
                if (r.request.name == wanted) (c, r),
        ];
        if (matches.isEmpty) throw ArgumentError('No request named "$wanted"${collection == null ? '' : ' in "$collection"'}. Use list_requests.');
        if (matches.length > 1) throw ArgumentError('"$wanted" exists in ${matches.map((m) => m.$1.name).toSet().join(', ')}: pass the collection.');
        final callOptions = _optionsFor(args);
        final state = _session != null && callOptions.environment == options.environment ? _session! : runner.newState(callOptions, processVariables: processVariables);
        if (callOptions.environment == options.environment) _session = state;
        final outcome = await runner.runRequest(matches.single.$1, matches.single.$2, state, callOptions);
        return _describe(outcome);
      case 'run_collection':
        final callOptions = _optionsFor(args, collection: '${args['collection']}', folder: args['folder'] as String?, bail: args['bail'] == true);
        final summary = await runner.run(callOptions, processVariables: processVariables);
        if (summary.total == 0) throw ArgumentError('No request ran: check the collection name.');
        final failed = [for (final o in summary.outcomes) if (!o.passed) {'request': o.name, 'status': o.status, 'failures': o.failures}];
        return const JsonEncoder.withIndent('  ').convert({
          'ok': summary.ok,
          'total': summary.total,
          'passed': summary.passed,
          'failed': summary.failed,
          'skipped': summary.skipped,
          'failures': failed,
          'report': RunReporters.console(summary).trim(),
        });
      default:
        throw ArgumentError('Unknown tool "$name".');
    }
  }

  RunOptions _optionsFor(Map<String, dynamic> args, {String? collection, String? folder, bool bail = false}) => RunOptions(
        environment: args['environment'] as String? ?? options.environment,
        variables: {
          ...options.variables,
          if (args['variables'] is Map) for (final e in (args['variables'] as Map).entries) '${e.key}': '${e.value}',
        },
        collection: collection,
        folder: folder,
        bail: bail,
        timeout: options.timeout,
        verifySsl: options.verifySsl,
        delay: options.delay,
      );

  String _describe(RequestOutcome o) {
    String clip(String s) => s.length <= 20000 ? s : '${s.substring(0, 20000)}\n… (${s.length - 20000} more characters)';
    return const JsonEncoder.withIndent('  ').convert({
      'request': '${o.method} ${o.url}',
      if (o.skipped != null) 'skipped': o.skipped,
      if (o.error != null) 'error': o.error,
      if (o.status != null) 'status': '${o.status} ${o.statusMessage ?? ''}'.trim(),
      'durationMs': o.duration.inMilliseconds,
      'passed': o.passed,
      if (o.failures.isNotEmpty) 'failures': o.failures,
      if (o.scripts.assertions.isNotEmpty) 'tests': [for (final a in o.scripts.assertions) '${a.passed ? 'PASS' : 'FAIL'} ${a.name}${a.passed ? '' : ' (got ${a.actual})'}'],
      if (o.scripts.extracted.isNotEmpty) 'savedVariables': [for (final e in o.scripts.extracted) '${e.key}${e.ok ? '' : ': ${e.error}'}'],
      'responseHeaders': {for (final e in o.responseHeaders.entries) e.key: SecretMasker.maskValue(e.key, e.value)},
      if (o.responseBody != null) 'responseBody': clip(SecretMasker.maskBody(o.responseBody!)),
    });
  }

  Map<String, Object?> _text(String text, {bool isError = false}) => {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': isError,
      };
}

final class _MethodNotFound implements Exception {
  final String method;
  const _MethodNotFound(this.method);
}
