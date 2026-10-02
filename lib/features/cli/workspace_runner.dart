// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or
// a CI job, where there is no UI and no database, only a workspace file.
import 'dart:convert';
import 'dart:typed_data';
import '../../core/enums/auth_type.dart';
import '../../core/utils/variable_resolver.dart';
import '../documentation/domain/services/secret_masker.dart';
import '../import_export/domain/services/backup_codec.dart';
import '../request_builder/domain/entities/api_response_entity.dart';
import '../request_builder/domain/services/request_spec_builder.dart';
import '../request_builder/domain/services/resolved_request_spec.dart';
import '../scripting/data/models/scripts_json_codec.dart';
import '../scripting/domain/entities/extractor_entity.dart';
import '../scripting/domain/entities/script_run_result.dart';
import '../scripting/domain/evaluator/assertion_evaluator.dart';
import '../scripting/domain/evaluator/extractor_value_resolver.dart';
import '../scripting/domain/evaluator/response_reader.dart';
import '../workplace/domain/services/secret_splitter.dart';

/// A request as it goes over the wire.
final class CliRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final List<int>? body;
  final Duration timeout;
  final bool verifySsl;
  const CliRequest({required this.method, required this.url, required this.headers, required this.body, required this.timeout, required this.verifySsl});
}

final class CliResponse {
  final int statusCode;
  final String statusMessage;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final Duration duration;
  const CliResponse({required this.statusCode, required this.statusMessage, required this.headers, required this.bodyBytes, required this.duration});
}

/// Sends one request. The terminal build uses `dart:io`; tests pass a fake.
typedef CliSend = Future<CliResponse> Function(CliRequest request);

final class RunOptions {
  final String? environment;

  /// `--var name=value`: beats every other source.
  final Map<String, String> variables;
  final String? collection;
  final String? folder;
  final bool bail;
  final Duration timeout;
  final bool verifySsl;
  final Duration delay;

  const RunOptions({
    this.environment,
    this.variables = const {},
    this.collection,
    this.folder,
    this.bail = false,
    this.timeout = const Duration(seconds: 30),
    this.verifySsl = true,
    this.delay = Duration.zero,
  });
}

/// What happened to one request.
final class RequestOutcome {
  final String collection;
  final String folder;
  final String name;
  final String method;

  /// Secret-masked, so a report can be shared.
  final String url;
  final int? status;
  final String? statusMessage;
  final Duration duration;
  final int sizeBytes;
  final String? error;

  /// Why it did not run (unsupported auth, unresolved variable...).
  final String? skipped;
  final ScriptRunResult scripts;
  final String? responseBody;
  final Map<String, String> responseHeaders;

  const RequestOutcome({
    required this.collection,
    required this.folder,
    required this.name,
    required this.method,
    required this.url,
    this.status,
    this.statusMessage,
    this.duration = Duration.zero,
    this.sizeBytes = 0,
    this.error,
    this.skipped,
    this.scripts = ScriptRunResult.empty,
    this.responseBody,
    this.responseHeaders = const {},
  });

  bool get isSuccess => status != null && status! >= 200 && status! < 300;

  /// A request with assertions passes on those alone; one without falls back to HTTP 2xx.
  /// A request that was skipped neither passes nor fails.
  bool get passed {
    if (skipped != null) return true;
    if (error != null || status == null) return false;
    return (scripts.assertions.isNotEmpty || isSuccess) && !scripts.hasFailures;
  }

  List<String> get failures => [
        ?error,
        if (error == null && scripts.assertions.isEmpty && !isSuccess && status != null) 'HTTP $status ${statusMessage ?? ''}'.trim(),
        for (final a in scripts.assertions.where((a) => !a.passed)) '${a.name} (got ${a.actual})',
        for (final e in scripts.extracted.where((e) => !e.ok)) 'variable ${e.key}: ${e.error}',
      ];
}

final class RunSummary {
  final List<RequestOutcome> outcomes;
  final Duration duration;
  const RunSummary(this.outcomes, this.duration);

  int get total => outcomes.length;
  int get skipped => outcomes.where((o) => o.skipped != null).length;
  int get failed => outcomes.where((o) => !o.passed).length;
  int get passed => total - failed - skipped;
  bool get ok => failed == 0;
}

final class RequestRef {
  final String collection;
  final String folder;
  final String name;
  final String method;
  final String url;
  const RequestRef(this.collection, this.folder, this.name, this.method, this.url);
}

/// Loads a workspace and runs its requests the way the app does: same variable
/// layers (CLI values, the chosen environment, the collection, globals), same
/// auth inheritance, same assertions and the same extractors that chain
/// requests together.
final class WorkspaceRunner {
  final BackupSnapshot snapshot;
  final CliSend send;
  final AssertionEvaluator _evaluator = const AssertionEvaluator();
  final RequestSpecBuilder _builder = const RequestSpecBuilder();

  WorkspaceRunner(this.snapshot, this.send);

  /// Reads a workspace document. [localSecrets] is the text of the
  /// `workspace.local.json` beside it, whose secrets fill the blanks of the shared file.
  factory WorkspaceRunner.parse(String workspaceJson, CliSend send, {String? localSecrets}) {
    var text = workspaceJson;
    final secrets = SecretSplitter.decodeLocal(localSecrets);
    if (secrets.isNotEmpty) {
      final merged = SecretSplitter.merge(jsonDecode(workspaceJson) as Map<String, dynamic>, secrets);
      text = jsonEncode(merged);
    }
    return WorkspaceRunner(BackupCodec.decode(text), send);
  }

  List<String> get environmentNames => [for (final e in snapshot.environments) e.name];
  List<String> get collectionNames => [for (final c in snapshot.collections) c.name];

  List<RequestRef> listRequests({String? collection}) => [
        for (final c in snapshot.collections)
          if (collection == null || c.name == collection)
            for (final r in c.requests) RequestRef(c.name, _folderPath(c, r.request.folderId), r.request.name, r.request.method.label, r.request.url),
      ];

  String _folderPath(BackupCollection c, int? folderId) {
    final names = <String>[];
    var current = folderId;
    var guard = 0;
    while (current != null && guard++ < 50) {
      final folder = c.folders.where((f) => f.id == current).firstOrNull;
      if (folder == null) break;
      names.insert(0, folder.name);
      current = folder.parentFolderId;
    }
    return names.join('/');
  }

  /// Runs every selected request in file order. [onResult] is called as each finishes.
  Future<RunSummary> run(RunOptions options, {void Function(RequestOutcome outcome)? onResult, Map<String, String> processVariables = const {}}) async {
    final clock = Stopwatch()..start();
    final state = RunState(snapshot, options, processVariables);
    final outcomes = <RequestOutcome>[];
    var stop = false;
    for (final collection in snapshot.collections) {
      if (stop) break;
      if (options.collection != null && collection.name != options.collection) continue;
      for (final item in collection.requests) {
        final folder = _folderPath(collection, item.request.folderId);
        if (options.folder != null && folder != options.folder && !folder.startsWith('${options.folder}/')) continue;
        final outcome = await runRequest(collection, item, state, options);
        outcomes.add(outcome);
        onResult?.call(outcome);
        if (options.bail && !outcome.passed) {
          stop = true;
          break;
        }
        if (options.delay > Duration.zero) await Future<void>.delayed(options.delay);
      }
    }
    return RunSummary(outcomes, clock.elapsed);
  }

  /// Runs one request by name (the first match), sharing [state] so extracted variables carry over.
  Future<RequestOutcome> runRequest(BackupCollection collection, BackupRequest item, RunState state, RunOptions options) async {
    final request = item.request;
    final folder = _folderPath(collection, request.folderId);
    RequestOutcome outcome({String? skipped, String? error, String? url}) => RequestOutcome(
          collection: collection.name,
          folder: folder,
          name: request.name,
          method: request.method.label,
          url: SecretMasker.maskUrl(url ?? request.url),
          skipped: skipped,
          error: error,
        );

    final inherited = collection.auth;
    final effective = request.auth.resolveInherited(inherited);
    if (effective.type == AuthType.digest || effective.type == AuthType.oauth2) {
      return outcome(skipped: '${effective.type.name} auth needs the app (a handshake or a browser); skipped');
    }

    final resolver = state.resolver(collection);
    final ResolvedRequestSpec spec;
    try {
      spec = _builder.build(request, resolver, inheritedAuth: inherited);
    } catch (e) {
      return outcome(error: 'Could not build the request: $e');
    }
    final unresolved = RegExp(r'\{\{([^{}]+)\}\}').firstMatch(spec.url);
    if (unresolved != null) {
      return outcome(error: 'The URL still contains {{${unresolved[1]}}}: pass --env or --var ${unresolved[1]}=...', url: spec.url);
    }

    final CliResponse response;
    try {
      response = await send(CliRequest(
        method: spec.method,
        url: spec.url,
        headers: spec.headers,
        body: spec.bodyBytes,
        timeout: options.timeout,
        verifySsl: options.verifySsl,
      ));
    } catch (e) {
      return outcome(error: '$e', url: spec.url);
    }

    final entity = ApiResponseEntity(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers,
      bodyBytes: Uint8List.fromList(response.bodyBytes),
      duration: response.duration,
    );
    final scripts = _runScripts(item, entity, resolver, state);
    final reader = ResponseReader(entity);
    return RequestOutcome(
      collection: collection.name,
      folder: folder,
      name: request.name,
      method: spec.method,
      url: SecretMasker.maskUrl(spec.url),
      status: response.statusCode,
      statusMessage: response.statusMessage,
      duration: response.duration,
      sizeBytes: response.bodyBytes.length,
      scripts: scripts,
      responseBody: reader.bodyText,
      responseHeaders: response.headers,
    );
  }

  ScriptRunResult _runScripts(BackupRequest item, ApiResponseEntity response, VariableResolver resolver, RunState state) {
    final scripts = item.scripts;
    if (scripts == null) return ScriptRunResult.empty;
    final assertions = _evaluator.evaluate(response, ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson), resolver);
    final reader = ResponseReader(response);
    final extracted = <ExtractionResult>[];
    for (final raw in ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson)) {
      final extractor = raw.copyWith(path: resolver.resolve(raw.path));
      final key = extractor.variableKey.trim();
      final configError = extractor.keyError ?? extractor.pathError;
      if (configError != null) {
        extracted.add(ExtractionResult(key: key, scope: extractor.scope, error: configError));
        continue;
      }
      final value = ExtractorValueResolver.resolve(reader, extractor);
      if (value == null) {
        extracted.add(ExtractionResult(key: key, scope: extractor.scope, error: 'Not found in response'));
        continue;
      }
      (extractor.scope == ExtractorScope.environment ? state.environment : state.globals)[key] = value;
      extracted.add(ExtractionResult(key: key, scope: extractor.scope, value: value));
    }
    return ScriptRunResult(assertions: assertions, extracted: extracted);
  }

  /// A fresh run state, for callers (the MCP server) that run requests one at a time.
  RunState newState(RunOptions options, {Map<String, String> processVariables = const {}}) => RunState(snapshot, options, processVariables);
}

/// Variables of a run: what was extracted lives here and is visible to the next request.
final class RunState {
  final Map<String, String> overrides;
  final Map<String, String> environment;
  final Map<String, String> globals;

  RunState._internal(this.overrides, this.environment, this.globals);

  factory RunState(BackupSnapshot snapshot, RunOptions options, Map<String, String> processVariables) {
    final env = <String, String>{};
    final named = options.environment;
    if (named != null) {
      final match = snapshot.environments.where((e) => e.name == named).firstOrNull;
      if (match == null) throw ArgumentError('There is no environment named "$named". Available: ${snapshot.environments.map((e) => e.name).join(', ')}');
      for (final v in match.variables) {
        if (v.enabled) env[v.key] = v.value;
      }
    }
    return RunState._internal(
      {...processVariables, ...options.variables},
      env,
      {for (final g in snapshot.globals) if (g.enabled) g.key: g.value},
    );
  }

  VariableResolver resolver(BackupCollection collection) => VariableResolver.layered([
        overrides,
        environment,
        {for (final v in collection.variables) if (v.enabled) v.key: v.value},
        globals,
      ]);
}
