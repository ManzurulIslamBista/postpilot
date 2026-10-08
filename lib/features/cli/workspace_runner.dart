// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or
// a CI job, where there is no UI and no database, only a workspace file.
import 'dart:convert';
import 'dart:typed_data';
import '../../core/enums/auth_type.dart';
import '../../core/enums/body_type.dart';
import '../../core/network/upload_body.dart';
import '../../core/utils/variable_resolver.dart';
import '../auth_renewal/domain/repositories/oauth2_token_store.dart';
import '../auth_renewal/domain/services/oauth2_token_manager.dart';
import '../auth_renewal/domain/services/relogin_coordinator.dart';
import '../auth_renewal/domain/services/relogin_policy.dart';
import '../auth_renewal/domain/services/request_auth_override.dart';
import '../auth_renewal/domain/services/token_status.dart';
import '../defaults/domain/entities/inherited_defaults.dart';
import '../defaults/domain/services/defaults_resolver.dart';
import '../request_flow/domain/entities/flow_report.dart';
import '../request_flow/domain/entities/flow_settings.dart';
import '../request_flow/domain/entities/pagination_settings.dart';
import '../request_flow/domain/services/flow_executor.dart';
import '../request_flow/domain/services/run_if_evaluator.dart';
import '../documentation/domain/services/secret_masker.dart';
import '../import_export/domain/services/backup_codec.dart';
import '../import_export/domain/services/backup_order.dart';
import '../odoo/data/odoo_smart_resolver.dart';
import '../odoo/domain/services/odoo_jsonrpc.dart';
import '../odoo/domain/services/smart_references.dart';
import '../request_builder/domain/entities/api_request_entity.dart';
import '../request_builder/domain/entities/api_response_entity.dart';
import '../request_builder/domain/entities/request_auth.dart';
import '../request_builder/domain/services/digest_auth_challenge.dart';
import '../request_builder/domain/services/oauth2_token_service.dart';
import '../request_builder/domain/services/request_spec_builder.dart';
import '../request_builder/domain/services/resolved_request_spec.dart';
import '../matrix_run/domain/services/matrix_read_only.dart';
import '../safety/domain/services/production_detector.dart';
import '../scripting/data/models/scripts_json_codec.dart';
import '../scripting/domain/entities/assertion_result.dart';
import '../scripting/domain/entities/extractor_entity.dart';
import '../scripting/domain/entities/script_run_result.dart';
import '../scripting/domain/evaluator/assertion_evaluator.dart';
import '../scripting/domain/evaluator/extractor_value_resolver.dart';
import '../scripting/domain/evaluator/response_reader.dart';
import '../test_suggestions/domain/services/baseline_check.dart';
import '../test_suggestions/domain/services/baseline_file.dart';
import '../workplace/domain/services/secret_splitter.dart';
import 'cli_auth.dart';
import 'cli_cookies.dart';
import 'production_lock.dart';

/// A request as it goes over the wire.
final class CliRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final List<int>? body;
  final Duration timeout;
  final bool verifySsl;

  /// The files the request uploads, when it carries any: [body] is then null and the sender reads and streams them,
  /// so a large file is never held in memory.
  final UploadBody? upload;

  /// The folder a relative file path of [upload] is taken from: the folder of the workspace file.
  final String? baseDir;
  const CliRequest({required this.method, required this.url, required this.headers, required this.body, required this.timeout, required this.verifySsl, this.upload, this.baseDir});

  /// The same request with other [headers] (the cookie jar adds a `Cookie`). Every field is carried over: add a new
  /// field to this method as well as to the constructor.
  CliRequest withHeaders(Map<String, String> headers) =>
      CliRequest(method: method, url: url, headers: headers, body: body, timeout: timeout, verifySsl: verifySsl, upload: upload, baseDir: baseDir);
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

  /// `--request` (repeatable): only the requests with this name, or this `folder/path/name`. Together with
  /// [folder] a request must match both. They still run in the collection's order, not in the order given.
  final List<String> requests;
  final bool bail;
  final Duration timeout;
  final bool verifySsl;
  final Duration delay;

  /// The production lock; on unless `--allow-production` was given.
  final ProductionLock production;

  /// `--fail-on-skip`: a skipped request makes the run fail.
  final bool failOnSkip;

  /// Only GET, HEAD and OPTIONS requests are selected (`--matrix` without `--include-writes`).
  final bool readOnly;

  const RunOptions({
    this.environment,
    this.variables = const {},
    this.agentVariables = const {},
    this.collection,
    this.folder,
    this.requests = const [],
    this.bail = false,
    this.timeout = const Duration(seconds: 30),
    this.verifySsl = true,
    this.delay = Duration.zero,
    this.production = const ProductionLock(),
    this.failOnSkip = false,
    this.readOnly = false,
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

  /// What the run did about authentication around this request: a token renewed before it was sent, a
  /// re-login run and the request sent again. Never holds a token or a password.
  final List<String> notes;

  /// What retrying, polling and fetching pages did for this request; null when it had nothing to report.
  final FlowReport? flow;

  /// [skipped] is the request's own "Run if": left out on purpose, as opposed to one that could not run.
  /// `--fail-on-skip` is about the second kind.
  final bool skippedByRule;

  /// There was no answer because the network failed (as opposed to a request that could not be built or was
  /// refused): the kind of failure a retry is for.
  final bool networkFailure;

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
    this.notes = const [],
    this.flow,
    this.skippedByRule = false,
    this.networkFailure = false,
  });

  /// This outcome with [report] as what the flow around it did.
  RequestOutcome withFlow(FlowReport? report) => RequestOutcome(
        collection: collection,
        folder: folder,
        name: name,
        method: method,
        url: url,
        status: status,
        statusMessage: statusMessage,
        duration: duration,
        sizeBytes: sizeBytes,
        error: error,
        skipped: skipped,
        blocked: blocked,
        scripts: scripts,
        responseBody: responseBody,
        responseHeaders: responseHeaders,
        notes: notes,
        flow: report,
        skippedByRule: skippedByRule,
        networkFailure: networkFailure,
      );

  bool get isSuccess => status != null && status! >= 200 && status! < 300;

  /// A request with assertions passes on those alone; one without falls back to HTTP 2xx.
  /// A request that was skipped neither passes nor fails (see [RunSummary.ok]: skipping alone never makes a run succeed).
  /// A poll that never held and a page that failed fail it, whatever the responses were.
  bool get passed {
    if (skipped != null) return true;
    if (error != null || status == null) return false;
    if (flow?.failure != null) return false;
    return (scripts.assertions.isNotEmpty || isSuccess) && !scripts.hasFailures;
  }

  /// What went wrong, in words an agent or a CI log may show: every text
  /// that can quote a URL or a response value goes through [SecretMasker].
  List<String> get failures => [
        if (error case final message?) SecretMasker.maskMessage(message),
        if (flow?.failure case final message?) SecretMasker.maskMessage(message),
        if (error == null && scripts.assertions.isEmpty && !isSuccess && status != null) 'HTTP $status ${statusMessage ?? ''}'.trim(),
        for (final a in scripts.assertions.where((a) => !a.passed)) failureText(a),
        for (final e in scripts.extracted.where((e) => !e.ok))
          'variable ${e.key}: ${SecretMasker.maskMessage('${e.error}')}${_from(e.origin)}',
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
  /// A check inherited from a folder or the collection says where it was set.
  static String failureText(AssertionResult a) =>
      '${SecretMasker.maskMessage(a.name)} (got ${shownActual(a)})${_from(a.origin)}';

  static String _from(String? origin) => origin == null ? '' : ' (from ${SecretMasker.maskMessage(origin)})';
}

final class RunSummary {
  final List<RequestOutcome> outcomes;
  final Duration duration;

  /// `--fail-on-skip`: a skipped request makes the run fail.
  final bool failOnSkip;
  const RunSummary(this.outcomes, this.duration, {this.failOnSkip = false});

  int get total => outcomes.length;
  int get skipped => outcomes.where((o) => o.skipped != null).length;

  /// Requests left out by their own "Run if": on purpose, so `--fail-on-skip` does not count them.
  int get skippedByRule => outcomes.where((o) => o.skipped != null && o.skippedByRule).length;
  int get failed => outcomes.where((o) => !o.passed).length;
  int get passed => total - failed - skipped;

  /// Nothing failed and something really ran and passed. A run in which every
  /// request was skipped verified nothing, so it is not ok; with [failOnSkip]
  /// a single request that could not run (its OAuth 2.0 token needs the app) is not ok either.
  bool get ok => failed == 0 && passed > 0 && !(failOnSkip && skipped > skippedByRule);

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
  final DateTime Function() _now;

  /// The folder of the workspace file; a relative file path of an upload is taken from it.
  final String? baseDir;

  /// The recorded response baselines (`--baseline-file`), for the requests that enforce one.
  final BaselineFile baselines;

  /// OAuth 2.0 tokens renewed during the process, kept in memory only (a CI job has nowhere to save them).
  /// One manager per timeout and TLS choice, because the token requests go out with the run's own.
  final Map<(Duration, bool), OAuth2TokenManager> _tokenManagers = {};
  final ReloginCoordinator _relogin;

  /// Retries, polls and page fetches of the requests that have them; replaceable so a test can run their waits instantly.
  final FlowExecutor _flowExecutor;

  /// Odoo's `{{xmlid:...}}` / `{{ref:...}}` tokens are looked up on the server a request goes to; one resolver per
  /// timeout and TLS choice (the lookups go out with the run's own), each keeping its answers for the process.
  final Map<(Duration, bool), SmartReferenceResolver> _smartResolvers = {};

  /// [send] is wrapped in an in-memory cookie jar: a request that logs in (an Odoo 18 `/web/session/authenticate`)
  /// is followed by requests that carry its session cookie, as in the app.
  WorkspaceRunner(this.snapshot, CliSend send, {DateTime Function()? now, this.baseDir, FlowExecutor? flowExecutor, this.baselines = BaselineFile.empty})
      : send = CliCookieJar().wrap(send),
        _now = now ?? DateTime.now,
        _relogin = ReloginCoordinator(now: now),
        _flowExecutor = flowExecutor ?? FlowExecutor();

  /// Reads a workspace document. [localSecrets] is the text of the
  /// `workspace.local.json` beside it, whose secrets fill the blanks of the shared file.
  factory WorkspaceRunner.parse(String workspaceJson, CliSend send, {String? localSecrets, DateTime Function()? now, String? baseDir, FlowExecutor? flowExecutor, BaselineFile baselines = BaselineFile.empty}) {
    var text = workspaceJson;
    final secrets = SecretSplitter.decodeLocal(localSecrets);
    if (secrets.isNotEmpty) {
      final merged = SecretSplitter.merge(jsonDecode(workspaceJson) as Map<String, dynamic>, secrets);
      text = jsonEncode(merged);
    }
    return WorkspaceRunner(BackupCodec.decode(text), send, now: now, baseDir: baseDir, flowExecutor: flowExecutor, baselines: baselines);
  }

  List<String> get environmentNames => [for (final e in snapshot.environments) e.name];
  List<String> get collectionNames => [for (final c in snapshot.collections) c.name];

  /// The requests in the order a run sends them (the collection's canonical order, the sidebar's).
  List<RequestRef> listRequests({String? collection}) => [
        for (final c in snapshot.collections)
          if (collection == null || c.name == collection)
            for (final r in c.orderedRequests) RequestRef(c.name, _folderPath(c, r.request.folderId), r.request.name, r.request.method.label, r.request.url),
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

  /// The requests [options] select (collection, folder and request filters), in the collection's canonical order:
  /// depth-first, folders and requests interleaved by their position, the same order the app's runner uses.
  Iterable<(BackupCollection, BackupRequest)> _selected(RunOptions options) sync* {
    for (final collection in snapshot.collections) {
      if (options.collection != null && collection.name != options.collection) continue;
      for (final item in collection.orderedRequests) {
        final folder = _folderPath(collection, item.request.folderId);
        if (options.folder != null && folder != options.folder && !folder.startsWith('${options.folder}/')) continue;
        if (options.requests.isNotEmpty && !options.requests.any((s) => _matchesRequest(s, folder, item.request.name))) continue;
        if (options.readOnly && !MatrixReadOnly.allows(item.request.method)) continue;
        yield (collection, item);
      }
    }
  }

  /// A `--request` selector names a request alone (`Login`) or with its folder (`Auth/Login`).
  static bool _matchesRequest(String selector, String folder, String name) =>
      selector == name || selector == (folder.isEmpty ? name : '$folder/$name');

  /// The `--request` selectors of [options] that match no request of the selected collections and folder, so a typo
  /// stops the run before anything is sent instead of quietly running less than was asked for.
  List<String> unmatchedRequestSelectors(RunOptions options) {
    final unfiltered = RunOptions(collection: options.collection, folder: options.folder);
    final candidates = [
      for (final (collection, item) in _selected(unfiltered)) (_folderPath(collection, item.request.folderId), item.request.name),
    ];
    return [
      for (final selector in options.requests)
        if (!candidates.any((c) => _matchesRequest(selector, c.$1, c.$2))) selector,
    ];
  }

  /// Runs every selected request in the collection's canonical order. [onResult] is called as each finishes.
  /// The production lock is checked per request as it is sent; call
  /// [productionBlocks] first to refuse a whole run before anything leaves.
  ///
  /// A request's "Run if" is judged just before it would be sent: when it does not hold the request is reported as
  /// skipped (with the reason) and nothing is sent, so the production lock is not asked either. Skipped is not
  /// failed: it does not trigger `--bail`. After `--bail` has ended the run, the requests marked "always run" are still
  /// sent (cleanups), each with its own "Run if" still applying; the rest are not reported.
  Future<RunSummary> run(RunOptions options, {void Function(RequestOutcome outcome)? onResult, Map<String, String> processVariables = const {}}) async {
    final clock = Stopwatch()..start();
    final state = RunState(snapshot, options, processVariables);
    final outcomes = <RequestOutcome>[];
    final pass = FlowRunPass();
    for (final (collection, item) in _selected(options)) {
      final flow = item.settings?.flow ?? FlowSettings.none;
      if (pass.stopped && !flow.alwaysRun) continue;
      final skippedByRule = _skippedByRunIf(collection, item, state, options, pass);
      final outcome = skippedByRule ?? await runRequest(collection, item, state, options);
      outcomes.add(outcome);
      onResult?.call(outcome);
      // Only a request that was really sent counts as "the previous one".
      if (outcome.skipped == null) pass.sent(item.request.name, passed: outcome.passed);
      if (options.bail && !outcome.passed) pass.stopped = true;
      if (!pass.stopped && skippedByRule == null && options.delay > Duration.zero) await Future<void>.delayed(options.delay);
    }
    return RunSummary(outcomes, clock.elapsed, failOnSkip: options.failOnSkip);
  }

  /// The outcome to report instead of sending [item] when its "Run if" does not hold; null when it does (or has none).
  RequestOutcome? _skippedByRunIf(BackupCollection collection, BackupRequest item, RunState state, RunOptions options, FlowRunPass pass) {
    final policy = item.settings?.flow.runIf ?? const RunIfPolicy();
    if (!policy.isActive) return null;
    final decision = RunIfEvaluator.evaluate(
      policy,
      RunIfContext(
        resolver: state.resolver(collection, agent: options.agentVariables, folderId: item.request.folderId),
        environmentName: options.environment,
        previous: pass.previous,
      ),
    );
    if (decision.run) return null;
    return RequestOutcome(
      collection: collection.name,
      folder: _folderPath(collection, item.request.folderId),
      name: item.request.name,
      method: item.request.method.label,
      url: SecretMasker.maskUrl(item.request.url),
      skipped: decision.reason,
      skippedByRule: true,
    );
  }

  /// The selected requests the production lock would refuse, judged without
  /// sending anything; empty when `--allow-production` was given. Requests that
  /// are not sent at all (skipped for their auth, or because their "Run if" says they only run in another
  /// environment) are not listed.
  List<ProductionBlock> productionBlocks(RunOptions options, {Map<String, String> processVariables = const {}}) {
    if (options.production.allow) return const [];
    final state = RunState(snapshot, options, processVariables);
    return [
      for (final (collection, item) in _selected(options))
        if (!_isSkippedForAuth(collection, item.request) &&
            !RunIfEvaluator.surelySkippedIn(item.settings?.flow.runIf ?? const RunIfPolicy(), options.environment))
          ?_blockFor(
            collection,
            item,
            options,
            _preview(collection, item.request, state.resolver(collection, agent: options.agentVariables, folderId: item.request.folderId)),
          ),
    ];
  }

  /// What a request inherits from its collection and folders: the same rules, from the same
  /// levels, as the app (see `DefaultsResolver`), so a request is built identically in both.
  InheritedDefaults _inherited(BackupCollection collection, int? folderId) =>
      DefaultsResolver.resolve(collection.defaultsTree.chainFor(folderId));

  /// An OAuth 2.0 request that cannot get a token without a person (Authorization Code with no usable token,
  /// no token URL): it is left out of the run, and the lock does not judge what is not sent.
  bool _isSkippedForAuth(BackupCollection collection, ApiRequestEntity request) =>
      _oauthBlocker(request.auth.resolveInherited(_inherited(collection, request.folderId).auth)) != null;

  /// Why [auth], when it is OAuth 2.0, cannot be used by a process nobody signs in for; null when it can.
  String? _oauthBlocker(RequestAuth? auth) =>
      auth == null || auth.type != AuthType.oauth2 ? null : OAuth2Readiness.whyNotUnattended(auth, _now());

  /// The wire form of a request for the lock to judge. The built request when it
  /// can be built, otherwise the URL and body resolved by hand.
  _Wire _preview(BackupCollection collection, ApiRequestEntity request, VariableResolver resolver) {
    try {
      final inherited = _inherited(collection, request.folderId);
      final spec = _builder.build(request, resolver, inheritedAuth: inherited.auth, inheritedHeaders: inherited.headerRows);
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
    final trusted = state.resolver(collection, folderId: request.folderId).resolve(request.url);
    final actual = state.resolver(collection, agent: agent, folderId: request.folderId).resolve(request.url);
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
  /// A request that comes back 401/403 is sent once more after the login request its collection or folder
  /// names has run, unless [allowRelogin] is off (it is for that retry and for the login request itself);
  /// [priorNotes] are what was said about that first attempt.
  Future<RequestOutcome> runRequest(
    BackupCollection collection,
    BackupRequest item,
    RunState state,
    RunOptions options, {
    bool allowRelogin = true,
    List<String> priorNotes = const [],
    bool runScripts = true,
  }) async {
    // Retry, poll until and fetch all pages: each try is this same method again, without them and without the tests,
    // which run once on the answer that comes out.
    final flowed = await _runFlowed(collection, item, state, options, allowRelogin: allowRelogin, priorNotes: priorNotes);
    if (flowed != null) return flowed;
    final request = item.request;
    final folder = _folderPath(collection, request.folderId);
    final notes = <String>[...priorNotes];
    RequestOutcome outcome({String? skipped, String? error, String? url, String? blocked, bool network = false}) => RequestOutcome(
          collection: collection.name,
          folder: folder,
          name: request.name,
          method: request.method.label,
          url: SecretMasker.maskUrl(url ?? request.url),
          skipped: skipped,
          error: error == null ? null : SecretMasker.maskMessage(error),
          blocked: blocked == null ? null : SecretMasker.maskMessage(blocked),
          notes: notes,
          networkFailure: network,
        );

    // The auth, headers, variables and tests the request inherits from its folders and collection.
    final inherited = _inherited(collection, request.folderId);
    final effective = request.auth.resolveInherited(inherited.auth);
    if (_oauthBlocker(effective) case final why?) return outcome(skipped: 'oauth2 auth needs the app: $why');

    final override = _hostOverride(request, state, collection, options);
    if (override != null) return outcome(error: override, blocked: override);

    var resolver = state.resolver(collection, agent: options.agentVariables, folderId: request.folderId);
    ResolvedRequestSpec spec;
    try {
      spec = _builder.build(request, resolver, inheritedAuth: inherited.auth, inheritedHeaders: inherited.headerRows);
    } catch (e) {
      return outcome(error: 'Could not build the request: $e');
    }
    // A smart reference ({{xmlid:...}}, {{ref:...}}) in the URL is looked up below, it is not a missing variable.
    final unresolved = _unresolvedToken.allMatches(spec.url).where((m) => !SmartReferences.isSmartKey(m[1]!)).firstOrNull;
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

    // Odoo smart references: looked up on the server the request goes to, only now that nothing has refused the
    // request. One that cannot be resolved stops it; the literal token is never sent.
    final pendingReferences = SmartReferences.pendingKeys(
      _builder.undefinedVariables(request, resolver, inheritedAuth: inherited.auth, inheritedHeaders: inherited.headerRows),
    );
    if (pendingReferences.isNotEmpty) {
      try {
        final values = await _smartReferencesFor(options).resolve(
          SmartReferenceContext(url: spec.url, headers: spec.headers, variable: resolver.lookup),
          pendingReferences,
        );
        resolver = VariableResolver.layered([values, ...resolver.scopes], resolver.dynamicVariables);
        spec = _builder.build(request, resolver, inheritedAuth: inherited.auth, inheritedHeaders: inherited.headerRows);
      } on SmartReferenceException catch (e) {
        return outcome(error: '${e.message} The request was not sent.', url: spec.url);
      }
    }

    // OAuth 2.0: the token is checked, and renewed, only now that nothing has refused the request, so a refused
    // request costs no token request. The token request resolves its `{{variables}}` without the ones an agent
    // passed: those must never decide where a client secret is sent.
    if (effective.type == AuthType.oauth2) {
      try {
        final renewal = await _tokensFor(options).ensureFresh(
          effective,
          owner: CliAuthOwners.of(
            ownsAuth: request.auth.type != AuthType.inherit,
            collection: collection.name,
            requestPath: folder.isEmpty ? request.name : '$folder/${request.name}',
            origin: inherited.authOrigin,
          ),
          resolver: state.resolver(collection, folderId: request.folderId),
        );
        if (renewal.note case final note?) notes.add(note);
        if (renewal.refreshTokenRotated) notes.add(_rotatedRefreshToken);
        if (renewal.replacesAuth) {
          final (buildRequest, buildInherited) = RequestAuthOverride.apply(request, inherited.auth, renewal.auth);
          spec = _builder.build(buildRequest, resolver, inheritedAuth: buildInherited, inheritedHeaders: inherited.headerRows);
        }
      } on OAuth2RenewalException catch (e) {
        return outcome(error: '${e.message} The request was not sent.', url: spec.url);
      }
    }

    final sentAt = _now();
    CliResponse response;
    try {
      response = await send(_wireRequest(spec, spec.headers, options));
      if (effective.type == AuthType.digest && response.statusCode == 401) {
        response = await _retryWithDigest(effective, resolver, spec, response, options);
      }
    } catch (e) {
      return outcome(error: '$e', url: spec.url, network: true);
    }

    // A rejected request: log in again and send it once more. The retry is what is reported, so the tests and
    // variable saves of the first, rejected answer never run.
    if (allowRelogin) {
      final retried = await _reloginAndRetry(collection, item, inherited, _expiredAs401(response), sentAt, state, options, notes);
      if (retried != null) return retried;
    }

    final entity = ApiResponseEntity(
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers,
      bodyBytes: Uint8List.fromList(response.bodyBytes),
      duration: response.duration,
    );
    final scripts = runScripts
        ? _withBaseline(collection, item, entity, _runScripts(item, inherited, entity, resolver, state))
        : ScriptRunResult.empty;
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
      notes: notes,
    );
  }

  /// [runRequest] for a request that has retry, poll until or fetch all pages (see `FlowExecutor`); null when it has
  /// none of them, and the caller sends it plainly. Every try is [runRequest] again with no flow settings and no tests
  /// of its own (the production lock, the OAuth token and the re-login all apply to each try as they do to a plain
  /// send); the tests and variable saves run once, on the response that comes out: the last one, or the pages merged.
  Future<RequestOutcome?> _runFlowed(
    BackupCollection collection,
    BackupRequest item,
    RunState state,
    RunOptions options, {
    required bool allowRelogin,
    required List<String> priorNotes,
  }) async {
    final settings = item.settings;
    final flow = settings?.flow ?? FlowSettings.none;
    final pagination = settings?.pagination ?? PaginationSettings.none;
    if (settings == null || !FlowExecutor.changesSending(flow, pagination)) return null;

    final request = item.request;
    final plain = settings.withFlow(FlowSettings.none).withPagination(PaginationSettings.none);
    final notes = <String>[];
    RequestOutcome? first;
    RequestOutcome? last;

    Future<FlowExchange> exchange(ApiRequestEntity entity) async {
      final outcome = await runRequest(
        collection,
        BackupRequest(request: entity, scripts: item.scripts, examples: item.examples, settings: plain, notes: item.notes, uid: item.uid),
        state,
        options,
        allowRelogin: allowRelogin,
        priorNotes: priorNotes,
        runScripts: false,
      );
      first ??= outcome;
      last = outcome;
      notes.addAll(outcome.notes.where((note) => !notes.contains(note)));
      if (outcome.status != null) return FlowResponded(_responseOf(outcome));
      // Only a network failure is worth trying again. A request that was refused, cannot be built or needs the app
      // would fail the same way every time, so it ends the flow with its own outcome.
      if (outcome.networkFailure) {
        final text = outcome.error ?? 'The request failed';
        return FlowFailed(text, SecretMasker.maskMessage(text));
      }
      throw _FlowEnded(outcome);
    }

    final FlowOutcome result;
    try {
      result = await _flowExecutor.execute(
        request: request,
        flow: flow,
        pagination: pagination,
        send: exchange,
        context: FlowContext(
          resolver: () async => state.resolver(collection, agent: options.agentVariables, folderId: request.folderId),
        ),
      );
    } on _FlowEnded catch (ended) {
      return ended.outcome;
    }

    final report = result.report.isNoteworthy ? result.report : null;
    final response = result.response;
    // The network failed on the last try: that try's outcome stands, with what the tries before it did.
    if (response == null) return last!.withFlow(report);

    final resolver = state.resolver(collection, agent: options.agentVariables, folderId: request.folderId);
    final scripts = _withBaseline(
      collection,
      item,
      response,
      _runScripts(item, _inherited(collection, request.folderId), response, resolver, state),
    );
    return RequestOutcome(
      collection: collection.name,
      folder: first!.folder,
      name: request.name,
      method: first!.method,
      url: first!.url,
      status: response.statusCode,
      statusMessage: response.statusMessage,
      duration: response.duration,
      sizeBytes: response.bodyBytes.length,
      scripts: scripts,
      responseBody: ResponseReader(response).bodyText,
      responseHeaders: response.headers,
      notes: notes,
      flow: report,
    );
  }

  /// What came back in [outcome], as the response the flow looks at.
  ApiResponseEntity _responseOf(RequestOutcome outcome) => ApiResponseEntity(
        statusCode: outcome.status!,
        statusMessage: outcome.statusMessage ?? '',
        headers: outcome.responseHeaders,
        bodyBytes: Uint8List.fromList(utf8.encode(outcome.responseBody ?? '')),
        duration: outcome.duration,
      );

  static const _rotatedRefreshToken =
      'The server issued a new refresh token and the command line cannot save it, so the refresh '
      'token in the workspace file no longer works: sign in once in the app again before the next run.';

  SmartReferenceResolver _smartReferencesFor(RunOptions options) => _smartResolvers.putIfAbsent(
        (options.timeout, options.verifySsl),
        () => OdooSmartReferenceResolver(CliApiClient(send, timeout: options.timeout, verifySsl: options.verifySsl)),
      );

  /// Odoo 18 and older answer an expired session with 200 and an error in the body. For the re-login that is a 401
  /// (its notes then say 401): the answer itself is never changed, only what the re-login sees.
  static CliResponse _expiredAs401(CliResponse response) {
    if (response.statusCode >= 400 || !OdooSessionExpiry.isExpiredBytes(response.bodyBytes)) return response;
    return CliResponse(statusCode: 401, statusMessage: response.statusMessage, headers: response.headers, bodyBytes: response.bodyBytes, duration: response.duration);
  }

  OAuth2TokenManager _tokensFor(RunOptions options) => _tokenManagers.putIfAbsent(
        (options.timeout, options.verifySsl),
        () => OAuth2TokenManager(
          OAuth2TokenService(CliApiClient(send, timeout: options.timeout, verifySsl: options.verifySsl), now: _now),
          const MemoryOAuth2TokenStore(),
          now: _now,
        ),
      );

  /// "On 401/403 run the login request, then retry once". Null when no re-login applies or it did not work
  /// ([notes] then says why, and the rejected answer stands); otherwise the outcome of the retry. The login
  /// request and the retry both run with `allowRelogin` off: one retry per request, never a chain, and a
  /// login that is rejected does not start another login.
  Future<RequestOutcome?> _reloginAndRetry(
    BackupCollection collection,
    BackupRequest item,
    InheritedDefaults inherited,
    CliResponse response,
    DateTime sentAt,
    RunState state,
    RunOptions options,
    List<String> notes,
  ) async {
    final config = ReloginPolicy.configIn(inherited.chain);
    if (config == null || !config.triggersOn(response.statusCode)) return null;

    final candidates = [
      for (final r in collection.orderedRequests)
        ReloginCandidate<BackupRequest>(
          folderPath: _folderPath(collection, r.request.folderId),
          name: r.request.name,
          method: r.request.method,
          value: r,
        ),
    ];
    final ReloginCandidate<BackupRequest> target;
    switch (ReloginPolicy.find(config.request, candidates)) {
      case ReloginNotFound():
        notes.add(ReloginPolicy.notFoundNote(config.request));
        return null;
      case ReloginAmbiguous(:final count):
        notes.add(ReloginPolicy.ambiguousNote(config.request, count));
        return null;
      case ReloginFound(:final candidate):
        target = candidate;
    }
    if (identical(target.value, item)) return null; // the login request itself was rejected
    if (ReloginPolicy.methodProblem(target.method) case final problem?) {
      notes.add(ReloginPolicy.methodNote(config.request, problem));
      return null;
    }

    final key = '${collection.name}|${config.request}';
    final login = await _relogin.run(key, sentAt, () async {
      final answered = await runRequest(collection, target.value, state, options, allowRelogin: false);
      return _loginResult(answered);
    });
    if (!login.ok) {
      final why = login.failure ?? 'it failed';
      notes.add(login.skipped ? ReloginPolicy.skippedNote(config.request, why) : ReloginPolicy.failedNote(config.request, why));
      return null;
    }
    final retried = await runRequest(
      collection,
      item,
      state,
      options,
      allowRelogin: false,
      priorNotes: [...notes, ReloginPolicy.retriedNote(config.request, response.statusCode)],
    );
    final again = retried.status;
    if (again != null && config.triggersOn(again)) {
      _relogin.markIneffective(key, 'the request was rejected again (HTTP $again) after the last re-login');
    }
    return retried;
  }

  /// A login worked when it was sent, answered 2xx and saved every variable its extractors name: a login
  /// that answers 200 but saves no token would only repeat the stale one.
  ReloginLogin _loginResult(RequestOutcome login) {
    if (login.blocked != null) return const ReloginLogin.failed('the production lock refused it');
    if (login.skipped != null) return ReloginLogin.failed('it was skipped (${login.skipped})');
    if (login.error != null) {
      final first = login.error!.split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'it failed').trim();
      return ReloginLogin.failed(first.length <= 160 ? first : '${first.substring(0, 160)}…');
    }
    if (!login.isSuccess) return ReloginLogin.failed('it answered HTTP ${login.status}');
    final unsaved = login.scripts.extracted.where((e) => !e.ok).firstOrNull;
    if (unsaved != null) {
      return ReloginLogin.failed('it did not save {{${unsaved.key}}}: ${SecretMasker.maskMessage('${unsaved.error}')}');
    }
    return const ReloginLogin.ok();
  }

  CliRequest _wireRequest(ResolvedRequestSpec spec, Map<String, String> headers, RunOptions options) => CliRequest(
        method: spec.method,
        url: spec.url,
        headers: headers,
        body: spec.bodyBytes,
        timeout: options.timeout,
        verifySsl: options.verifySsl,
        upload: spec.upload,
        baseDir: baseDir,
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

  /// The tests of the collection and of the folders above the request run first, outermost level first, then
  /// the request's own (the order the app runs them in); each result of an inherited one says where it comes from.
  ScriptRunResult _runScripts(
    BackupRequest item,
    InheritedDefaults inherited,
    ApiResponseEntity response,
    VariableResolver resolver,
    RunState state,
  ) {
    final scripts = item.scripts;
    if (scripts == null && inherited.tests.isEmpty) return ScriptRunResult.empty;
    final assertions = <AssertionResult>[
      for (final level in inherited.tests)
        for (final result in _evaluator.evaluate(response, level.assertions, resolver)) result.fromOrigin(level.origin.label),
      if (scripts != null) ..._evaluator.evaluate(response, ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson), resolver),
    ];
    final reader = ResponseReader(response);

    ExtractionResult extract(ExtractorEntity raw) {
      final extractor = raw.copyWith(path: resolver.resolve(raw.path));
      final key = extractor.variableKey.trim();
      final configError = extractor.keyError ?? extractor.pathError;
      if (configError != null) return ExtractionResult(key: key, scope: extractor.scope, error: configError);
      final value = ExtractorValueResolver.resolve(reader, extractor);
      if (value == null) return ExtractionResult(key: key, scope: extractor.scope, error: 'Not found in response');
      (extractor.scope == ExtractorScope.environment ? state.environment : state.globals)[key] = value;
      return ExtractionResult(key: key, scope: extractor.scope, value: value);
    }

    final extracted = <ExtractionResult>[
      for (final level in inherited.tests)
        for (final extractor in level.extractors) extract(extractor).fromOrigin(level.origin.label),
      if (scripts != null)
        for (final extractor in ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson)) extract(extractor),
    ];
    return ScriptRunResult(assertions: assertions, extracted: extracted);
  }

  /// A request that turned on "Enforce baseline in runs" gets one more row, `Baseline: N breaking changes`, judged
  /// against its entry in the baseline file: the same check the app's runner makes (see `BaselineCheck`).
  ScriptRunResult _withBaseline(BackupCollection collection, BackupRequest item, ApiResponseEntity response, ScriptRunResult scripts) {
    if (!(item.settings?.baseline.enforce ?? false)) return scripts;
    final request = item.request;
    final recorded = baselines.find(
      collection: collection.name,
      folder: _folderPath(collection, request.folderId),
      name: request.name,
      method: request.method.label,
    );
    final row = BaselineCheck.evaluate(
      recorded,
      response,
      missingHint: baselines.entries.isEmpty
          ? 'No baseline file was given: export baselines from the app (Response tools > Suggest tests > Baseline) and pass --baseline-file <file>.'
          : 'The baseline file has no entry for this request: export the baselines again from the app after recording one.',
    );
    return ScriptRunResult(assertions: [...scripts.assertions, row], extracted: scripts.extracted);
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
  /// brings its own (or none). The variables of the request's folders ([folderId]) sit between the
  /// environment and the collection's, the innermost folder first, as in the app.
  VariableResolver resolver(BackupCollection collection, {Map<String, String> agent = const {}, int? folderId}) =>
      VariableResolver.layered([
        if (agent.isNotEmpty) agent,
        overrides,
        environment,
        ...DefaultsResolver.resolve(collection.defaultsTree.chainFor(folderId)).variableScopes,
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

/// Ends a flow with the outcome of the try that cannot be repeated (refused, not buildable, needs the app).
final class _FlowEnded implements Exception {
  final RequestOutcome outcome;
  const _FlowEnded(this.outcome);
}
