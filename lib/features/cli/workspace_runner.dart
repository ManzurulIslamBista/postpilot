// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or
// a CI job, where there is no UI and no database, only a workspace file.
import 'dart:convert';
import 'dart:typed_data';
import '../../core/enums/auth_type.dart';
import '../../core/enums/body_type.dart';
import '../../core/utils/variable_resolver.dart';
import '../documentation/domain/services/secret_masker.dart';
import '../import_export/domain/services/backup_codec.dart';
import '../request_builder/domain/entities/api_request_entity.dart';
import '../request_builder/domain/entities/api_response_entity.dart';
import '../request_builder/domain/entities/request_auth.dart';
import '../request_builder/domain/services/digest_auth_challenge.dart';
import '../request_builder/domain/services/request_spec_builder.dart';
import '../request_builder/domain/services/resolved_request_spec.dart';
import '../safety/domain/services/production_detector.dart';
import '../scripting/data/models/scripts_json_codec.dart';
import '../scripting/domain/entities/assertion_result.dart';
import '../scripting/domain/entities/extractor_entity.dart';
import '../scripting/domain/entities/script_run_result.dart';
import '../scripting/domain/evaluator/assertion_evaluator.dart';
import '../scripting/domain/evaluator/extractor_value_resolver.dart';
import '../scripting/domain/evaluator/response_reader.dart';
import '../workplace/domain/services/secret_splitter.dart';
import 'production_lock.dart';

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

  /// `--var name=value`: beats every other source. Given by the person running the process, so trusted.
  final Map<String, String> variables;

  /// Variables an AI agent passed with a tool call. They beat everything else
  /// too, except that they may never change the scheme, host or port a request
  /// is sent to: see [WorkspaceRunner.runRequest].
  final Map<String, String> agentVariables;
  final String? collection;
  final String? folder;
  final bool bail;
  final Duration timeout;
  final bool verifySsl;
  final Duration delay;

  /// The production lock; on unless `--allow-production` was given.
  final ProductionLock production;

  /// `--fail-on-skip`: a skipped request makes the run fail.
  final bool failOnSkip;

  const RunOptions({
    this.environment,
    this.variables = const {},
    this.agentVariables = const {},
    this.collection,
    this.folder,
    this.bail = false,
    this.timeout = const Duration(seconds: 30),
    this.verifySsl = true,
    this.delay = Duration.zero,
    this.production = const ProductionLock(),
    this.failOnSkip = false,
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

  /// Why the production lock or the host pin refused to send it; [error] says the same.
  final String? blocked;
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
    this.blocked,
    this.scripts = ScriptRunResult.empty,
    this.responseBody,
    this.responseHeaders = const {},
  });

  bool get isSuccess => status != null && status! >= 200 && status! < 300;

  /// A request with assertions passes on those alone; one without falls back to HTTP 2xx.
  /// A request that was skipped neither passes nor fails (see [RunSummary.ok]: skipping alone never makes a run succeed).
  bool get passed {
    if (skipped != null) return true;
    if (error != null || status == null) return false;
    return (scripts.assertions.isNotEmpty || isSuccess) && !scripts.hasFailures;
  }

  /// What went wrong, in words an agent or a CI log may show: every text
  /// that can quote a URL or a response value goes through [SecretMasker].
  List<String> get failures => [
        if (error case final message?) SecretMasker.maskMessage(message),
        if (error == null && scripts.assertions.isEmpty && !isSuccess && status != null) 'HTTP $status ${statusMessage ?? ''}'.trim(),
        for (final a in scripts.assertions.where((a) => !a.passed)) failureText(a),
        for (final e in scripts.extracted.where((e) => !e.ok)) 'variable ${e.key}: ${SecretMasker.maskMessage('${e.error}')}',
      ];

  /// What the evaluator says every `actual` is when it is not a value of the response.
  static const _plainActuals = {
    'Missing',
    'Found in body',
    'Not found in body',
    'Matches',
    'No schema',
    'No text to search for',
    'Body is not valid JSON',
    'Enter a JSON path',
    'The schema is not valid JSON',
    'The schema must be a JSON object',
  };

  /// The value a failed check saw, masked: it is a piece of the response (a JSON
  /// value, a header) and may hold a credential. A check whose name says it
  /// looks at a secret (`access_token equals ...`, `Header Set-Cookie ...`)
  /// shows no value at all.
  static String shownActual(AssertionResult a) {
    if (_plainActuals.contains(a.actual)) return a.actual;
    if (SecretMasker.isSensitiveName(a.name)) return SecretMasker.mask;
    return SecretMasker.maskMessage(SecretMasker.maskBody(a.actual));
  }

  /// `Status equals 200 (got 500)`, masked.
  static String failureText(AssertionResult a) => '${SecretMasker.maskMessage(a.name)} (got ${shownActual(a)})';
}

final class RunSummary {
  final List<RequestOutcome> outcomes;
  final Duration duration;

  /// `--fail-on-skip`: a skipped request makes the run fail.
  final bool failOnSkip;
  const RunSummary(this.outcomes, this.duration, {this.failOnSkip = false});

  int get total => outcomes.length;
  int get skipped => outcomes.where((o) => o.skipped != null).length;
  int get failed => outcomes.where((o) => !o.passed).length;
  int get passed => total - failed - skipped;

  /// Nothing failed and something really ran and passed. A run in which every
  /// request was skipped verified nothing, so it is not ok; with [failOnSkip]
  /// a single skipped request is not ok either.
  bool get ok => failed == 0 && passed > 0 && !(failOnSkip && skipped > 0);

  /// Requests were selected but every one of them was skipped.
  bool get allSkipped => total > 0 && skipped == total;
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

  /// The requests [options] select (collection and folder filters), in file order.
  Iterable<(BackupCollection, BackupRequest)> _selected(RunOptions options) sync* {
    for (final collection in snapshot.collections) {
      if (options.collection != null && collection.name != options.collection) continue;
      for (final item in collection.requests) {
        final folder = _folderPath(collection, item.request.folderId);
        if (options.folder != null && folder != options.folder && !folder.startsWith('${options.folder}/')) continue;
        yield (collection, item);
      }
    }
  }

  /// Runs every selected request in file order. [onResult] is called as each finishes.
  /// The production lock is checked per request as it is sent; call
  /// [productionBlocks] first to refuse a whole run before anything leaves.
  Future<RunSummary> run(RunOptions options, {void Function(RequestOutcome outcome)? onResult, Map<String, String> processVariables = const {}}) async {
    final clock = Stopwatch()..start();
    final state = RunState(snapshot, options, processVariables);
    final outcomes = <RequestOutcome>[];
    for (final (collection, item) in _selected(options)) {
      final outcome = await runRequest(collection, item, state, options);
      outcomes.add(outcome);
      onResult?.call(outcome);
      if (options.bail && !outcome.passed) break;
      if (options.delay > Duration.zero) await Future<void>.delayed(options.delay);
    }
    return RunSummary(outcomes, clock.elapsed, failOnSkip: options.failOnSkip);
  }

  /// The selected requests the production lock would refuse, judged without
  /// sending anything; empty when `--allow-production` was given. Requests that
  /// are not sent at all (skipped for their auth) are not listed.
  List<ProductionBlock> productionBlocks(RunOptions options, {Map<String, String> processVariables = const {}}) {
    if (options.production.allow) return const [];
    final state = RunState(snapshot, options, processVariables);
    return [
      for (final (collection, item) in _selected(options))
        if (!_isSkippedForAuth(collection, item.request))
          ?_blockFor(collection, item, options, _preview(collection, item.request, state.resolver(collection, agent: options.agentVariables))),
    ];
  }

  bool _isSkippedForAuth(BackupCollection collection, ApiRequestEntity request) =>
      request.auth.resolveInherited(collection.auth).type == AuthType.oauth2;

  /// The wire form of a request for the lock to judge. The built request when it
  /// can be built, otherwise the URL and body resolved by hand.
  _Wire _preview(BackupCollection collection, ApiRequestEntity request, VariableResolver resolver) {
    try {
      final spec = _builder.build(request, resolver, inheritedAuth: collection.auth);
      return _Wire(spec.url, spec.bodyBytes == null ? null : utf8.decode(spec.bodyBytes!, allowMalformed: true));
    } catch (_) {
      final body = request.body;
      return body.type == BodyType.graphql
          ? _Wire(resolver.resolve(request.url), null, graphqlQuery: resolver.resolve(body.graphqlQuery))
          : _Wire(resolver.resolve(request.url), resolver.resolve(body.rawText));
    }
  }

  ProductionBlock? _blockFor(BackupCollection collection, BackupRequest item, RunOptions options, _Wire wire) {
    final request = item.request;
    final effect = ProductionDetector.classify(request.method, url: wire.url, body: wire.body, graphqlQuery: wire.graphqlQuery);
    if (!effect.changesData) return null;
    final reason = options.production.reason(options.environment, wire.url);
    if (reason == null) return null;
    return ProductionBlock(
      collection: collection.name,
      folder: _folderPath(collection, request.folderId),
      name: request.name,
      method: request.method.label,
      effect: effect,
      reason: reason,
    );
  }

  static final _unresolvedToken = RegExp(r'\{\{([^{}]+)\}\}');

  /// `scheme://authority` of [url] as written, `http://` assumed like the
  /// request builder does; what a variable must not be able to change.
  static String _origin(String url) {
    final text = url.trim();
    final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text) ? text : 'http://$text';
    final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*)').firstMatch(withScheme);
    return match?[1] ?? withScheme;
  }

  /// `scheme://host:port` without credentials, for a message.
  static String _originForMessage(String origin) {
    final at = origin.lastIndexOf('@');
    if (at < 0) return origin;
    return '${origin.substring(0, origin.indexOf('://') + 3)}${origin.substring(at + 1)}';
  }

  /// A message when the variables an agent passed decide where [request] goes;
  /// `null` when its scheme, host and port come from the workspace alone.
  ///
  /// The agent's values sit above every other source, so an injected
  /// instruction ("set baseUrl to https://evil.example") would otherwise send the
  /// workspace's Bearer token or API key to a stranger. The URL is resolved
  /// twice, with and without the agent's variables, and the two must agree on
  /// the origin, whichever variable (or chain of variables) builds it. A host
  /// that only an agent variable could fill in is refused too.
  String? _hostOverride(ApiRequestEntity request, RunState state, BackupCollection collection, RunOptions options) {
    final agent = options.agentVariables;
    if (agent.isEmpty) return null;
    final trusted = state.resolver(collection).resolve(request.url);
    final actual = state.resolver(collection, agent: agent).resolve(request.url);
    final trustedOrigin = _origin(trusted);
    final mentioned = [
      for (final m in _unresolvedToken.allMatches(request.url))
        if (agent.containsKey(m[1])) m[1]!,
    ];
    final names = (mentioned.isEmpty ? agent.keys.toList() : mentioned).join(', ');
    const rule = 'Only the workspace, the chosen environment or the --var options of the person running PostPilot decide where a request is sent, '
        'so credentials cannot be redirected by a variable an agent passes.';
    final open = _unresolvedToken.firstMatch(trustedOrigin);
    if (open != null) {
      return 'Refused: the host of "${request.name}" comes from {{${open[1]}}}, which the workspace does not define, '
          'and variables passed by an agent cannot fill it in. $rule Choose an environment that defines it, or ask the operator to start the server with --var ${open[1]}=...';
    }
    final actualOrigin = _origin(actual);
    if (actualOrigin.toLowerCase() == trustedOrigin.toLowerCase()) return null;
    return 'Refused: the variable(s) passed ($names) change where "${request.name}" is sent '
        '(${_originForMessage(trustedOrigin)} would become ${_originForMessage(actualOrigin)}). $rule';
  }

  /// Runs one request by name (the first match), sharing [state] so extracted variables carry over.
  Future<RequestOutcome> runRequest(BackupCollection collection, BackupRequest item, RunState state, RunOptions options) async {
    final request = item.request;
    final folder = _folderPath(collection, request.folderId);
    RequestOutcome outcome({String? skipped, String? error, String? url, String? blocked}) => RequestOutcome(
          collection: collection.name,
          folder: folder,
          name: request.name,
          method: request.method.label,
          url: SecretMasker.maskUrl(url ?? request.url),
          skipped: skipped,
          error: error == null ? null : SecretMasker.maskMessage(error),
          blocked: blocked == null ? null : SecretMasker.maskMessage(blocked),
        );

    final inherited = collection.auth;
    final effective = request.auth.resolveInherited(inherited);
    if (effective.type == AuthType.oauth2) {
      return outcome(skipped: 'oauth2 auth needs the app (it gets its token through a browser or a token request); skipped');
    }

    final override = _hostOverride(request, state, collection, options);
    if (override != null) return outcome(error: override, blocked: override);

    final resolver = state.resolver(collection, agent: options.agentVariables);
    final ResolvedRequestSpec spec;
    try {
      spec = _builder.build(request, resolver, inheritedAuth: inherited);
    } catch (e) {
      return outcome(error: 'Could not build the request: $e');
    }
    final unresolved = _unresolvedToken.firstMatch(spec.url);
    if (unresolved != null) {
      return outcome(error: 'The URL still contains {{${unresolved[1]}}}: pass --env or --var ${unresolved[1]}=...', url: spec.url);
    }

    if (!options.production.allow) {
      final bodyText = spec.bodyBytes == null ? null : utf8.decode(spec.bodyBytes!, allowMalformed: true);
      final block = _blockFor(collection, item, options, _Wire(spec.url, bodyText));
      if (block != null) {
        final message = 'Refused by the production lock: ${block.line}. This request changes data; read-only requests still run. '
            'Only the person who starts PostPilot can allow it, with --allow-production.';
        return outcome(error: message, blocked: message, url: spec.url);
      }
    }

    CliResponse response;
    try {
      response = await send(_wireRequest(spec, spec.headers, options));
      if (effective.type == AuthType.digest && response.statusCode == 401) {
        response = await _retryWithDigest(effective, resolver, spec, response, options);
      }
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

  CliRequest _wireRequest(ResolvedRequestSpec spec, Map<String, String> headers, RunOptions options) => CliRequest(
        method: spec.method,
        url: spec.url,
        headers: headers,
        body: spec.bodyBytes,
        timeout: options.timeout,
        verifySsl: options.verifySsl,
      );

  /// Digest auth is a handshake: the first answer is a 401 with a challenge, and
  /// the request is sent again signed for it. The challenge is read and answered
  /// by the same [DigestAuthChallenge] the app uses. Without a usable challenge
  /// the 401 stands.
  Future<CliResponse> _retryWithDigest(RequestAuth auth, VariableResolver resolver, ResolvedRequestSpec spec, CliResponse challengeResponse, RunOptions options) async {
    final header = challengeResponse.headers.entries.where((e) => e.key.toLowerCase() == 'www-authenticate').firstOrNull?.value;
    final challenge = DigestAuthChallenge.parse(header);
    if (challenge == null) return challengeResponse;
    final authorization = challenge.buildAuthorizationHeader(
      username: resolver.resolve(auth.basicUsername),
      password: resolver.resolve(auth.basicPassword),
      method: spec.method,
      digestUri: _digestRequestUri(spec.url),
    );
    return send(_wireRequest(spec, {...spec.headers, 'Authorization': authorization}, options));
  }

  /// The Request-URI the Digest `uri` covers (RFC 7616 3.4): path plus query, as on the request line.
  /// The same rule as `digestRequestUri` in `SendRequestUseCase`, which sits beside the app's HTTP client and history and is not pulled into this entry point.
  static String _digestRequestUri(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
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

  /// [agent] are the variables an agent passed with this one call. They go on top
  /// of everything, and belong to the call, not to the state: the next call
  /// brings its own (or none).
  VariableResolver resolver(BackupCollection collection, {Map<String, String> agent = const {}}) => VariableResolver.layered([
        if (agent.isNotEmpty) agent,
        overrides,
        environment,
        {for (final v in collection.variables) if (v.enabled) v.key: v.value},
        globals,
      ]);
}

/// A request as the production lock judges it: where it goes and what it carries.
final class _Wire {
  final String url;
  final String? body;
  final String? graphqlQuery;
  const _Wire(this.url, this.body, {this.graphqlQuery});
}
