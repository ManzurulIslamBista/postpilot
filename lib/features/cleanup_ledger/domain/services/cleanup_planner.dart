// Pure Dart (no Flutter): the app and the command line plan a cleanup the same way.
import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../odoo/domain/services/odoo_json2.dart';
import '../../../odoo/domain/services/odoo_jsonrpc.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../entities/cleanup_entry.dart';
import '../entities/cleanup_settings.dart';
import 'cleanup_urls.dart';
import 'created_id_detector.dart';
import 'created_variables.dart';

/// One entry about to be put in the ledger: everything but its number.
final class CleanupDraft {
  final String requestName;
  final String? environment;
  final DateTime createdAt;
  final List<Object> ids;
  final CleanupPlan plan;
  final Map<String, String> variables;

  /// [CleanupState.pending], or [CleanupState.skipped] with a [reason] when nothing can be undone.
  final CleanupState state;
  final String? reason;

  const CleanupDraft({
    required this.requestName,
    required this.environment,
    required this.createdAt,
    required this.ids,
    required this.plan,
    required this.variables,
    this.state = CleanupState.pending,
    this.reason,
  });
}

/// Turns the answer to a create request into what the ledger keeps: the ids, the way to undo them and the variables the
/// undo is sent with. Pure: nothing is sent here.
abstract final class CleanupPlanner {
  /// The drafts for one send of [request]; none when the setting is off, the answer was not a success or it says that
  /// nothing was created (Odoo's `false`). A success from which no id can be read gives one skipped draft saying so,
  /// so the person finds out in the ledger rather than by looking for records that were never going to be deleted.
  static List<CleanupDraft> plan({
    required ApiRequestEntity request,
    required CleanupSettings settings,
    required int statusCode,
    required String responseBody,
    required String? environment,
    required DateTime now,
    Map<String, String> dataVariables = const {},
  }) {
    if (!settings.enabled || statusCode < 200 || statusCode >= 300) return const [];
    final path = settings.effectiveIdPath;
    if (path.isEmpty && CreatedIdDetector.saysNothingWasCreated(responseBody)) return const [];

    CleanupDraft skipped(String reason, {List<Object> ids = const [], CleanupUndo kind = CleanupUndo.auto}) => CleanupDraft(
          requestName: request.name,
          environment: environment,
          createdAt: now,
          ids: ids,
          plan: CleanupPlan(kind: kind, summary: 'Nothing to undo', collectionId: request.collectionId),
          variables: const {},
          state: CleanupState.skipped,
          reason: reason,
        );

    final Object? json = _decode(responseBody);
    final found = CreatedIdDetector.detect(json, idPath: path);
    if (found == null) {
      return [
        skipped(
          path.isEmpty
              ? 'No id found in the response (looked at ${CreatedIdDetector.objectPaths.join(', ')} and result). '
                  'Name where it is in the request\'s cleanup settings.'
              : 'Nothing at "$path" in the response.',
        ),
      ];
    }

    final kind = settings.undo == CleanupUndo.auto ? _autoKind(request, json) : settings.undo;
    if (kind == null) {
      return [
        skipped(
          'Automatic cleanup works for a POST that creates a record. Choose how this request is undone.',
          ids: found.values,
        ),
      ];
    }

    String? problem;
    final drafts = <CleanupDraft>[];
    CleanupDraft draft(CreatedIds ids, CleanupPlan plan) => CleanupDraft(
          requestName: request.name,
          environment: environment,
          createdAt: now,
          ids: ids.values,
          plan: plan,
          variables: {...dataVariables, ...CreatedVariables.build(ids, json)},
        );

    switch (kind) {
      case CleanupUndo.odooUnlink:
        final built = _odooUnlink(request, found);
        if (built.problem != null) {
          problem = built.problem;
        } else {
          drafts.add(draft(found, built.plan!));
        }
      case CleanupUndo.restDelete:
        // One DELETE per record: a REST API deletes one resource at a time.
        for (final id in found.values) {
          drafts.add(draft(CreatedIds([id], found.source), _restDelete(request, id)));
        }
      case CleanupUndo.request:
        final target = settings.request.trim();
        if (target.isEmpty) {
          problem = 'Choose the request that undoes this one (Settings > Clean up what this request creates).';
        } else {
          drafts.add(draft(found, _viaRequest(request, target, found)));
        }
      case CleanupUndo.auto:
        problem = 'Choose how this request is undone.';
    }
    if (problem != null) return [skipped(problem, ids: found.values, kind: kind)];
    return drafts;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// What "Automatic" does for [request]: an Odoo create is unlinked, any other POST gets a REST DELETE. Null when
  /// that cannot be told: a verb other than POST, or an Odoo JSON-RPC answer from a URL that is not `call_kw` (the
  /// legacy `/jsonrpc` endpoint), where a DELETE on the URL would hit something that is not a record.
  static CleanupUndo? _autoKind(ApiRequestEntity request, Object? json) {
    final odoo = CleanupUrls.odoo(request.url);
    if (odoo != null) return odoo.isCreate ? CleanupUndo.odooUnlink : null;
    if (request.method != HttpMethod.post) return null;
    if (json is Map && json.containsKey('jsonrpc')) return null;
    return CleanupUndo.restDelete;
  }

  static ({CleanupPlan? plan, String? problem}) _odooUnlink(ApiRequestEntity request, CreatedIds found) {
    final odoo = CleanupUrls.odoo(request.url);
    if (odoo == null || !odoo.isCreate) {
      return (
        plan: null,
        problem: 'This is not an Odoo create (…/json/2/<model>/create), so there is nothing to unlink with. '
            'Choose another way to undo it.',
      );
    }
    if (!found.areNumbers) return (plan: null, problem: 'Odoo ids are numbers, but the response named "${found.first}".');
    final ids = [for (final id in found.values) id as int];
    final call = OdooCall(model: odoo.model, method: 'unlink', ids: ids, context: _odooContext(request));
    final bodyText = odoo.jsonRpc ? OdooJsonRpc.bodyText(call) : call.bodyText;
    final undo = ApiRequestEntity(
      id: 0,
      collectionId: request.collectionId,
      folderId: request.folderId,
      name: 'Undo "${request.name}"',
      method: HttpMethod.post,
      url: odoo.urlFor('unlink'),
      headers: _headers(request),
      queryParams: _credentialParams(request),
      body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: bodyText),
      auth: request.auth,
    );
    return (
      plan: CleanupPlan(
        kind: CleanupUndo.odooUnlink,
        summary: 'Odoo unlink ${odoo.model} [${ids.join(', ')}]',
        collectionId: request.collectionId,
        request: undo,
      ),
      problem: null,
    );
  }

  static CleanupPlan _restDelete(ApiRequestEntity request, Object id) {
    final url = CleanupUrls.restDelete(request.url, id);
    final undo = ApiRequestEntity(
      id: 0,
      collectionId: request.collectionId,
      folderId: request.folderId,
      name: 'Undo "${request.name}"',
      method: HttpMethod.delete,
      url: url,
      // A DELETE carries no body, so the type of the one the create sent would only mislead the server.
      headers: _headers(request, dropContentType: true),
      queryParams: _credentialParams(request),
      body: RequestBody.empty,
      auth: request.auth,
    );
    return CleanupPlan(
      kind: CleanupUndo.restDelete,
      summary: 'DELETE ${SecretMasker.maskUrl(url)}',
      collectionId: request.collectionId,
      request: undo,
    );
  }

  static CleanupPlan _viaRequest(ApiRequestEntity request, String target, CreatedIds found) {
    final many = found.values.length > 1;
    return CleanupPlan(
      kind: CleanupUndo.request,
      summary: 'Send "$target" with {{created.${many ? 'ids' : 'id'}}} = ${many ? found.values.join(', ') : found.first}',
      collectionId: request.collectionId,
      undoRequest: target,
    );
  }

  /// The headers of the creating request (the authorization, the database an Odoo server is asked for), as they were
  /// written: `{{variables}}` are resolved by the send of the undo, like any request.
  static List<KeyValueItem> _headers(ApiRequestEntity request, {bool dropContentType = false}) => [
        for (final h in request.headers)
          if (h.enabled &&
              h.key.trim().isNotEmpty &&
              h.key.toLowerCase() != 'content-length' &&
              !(dropContentType && h.key.toLowerCase() == 'content-type'))
            KeyValueItem(key: h.key, value: h.value),
      ];

  /// Query parameters that carry a credential (`api_key`, `token`), in the query rows or written into the URL: the
  /// undo needs them to be let in. The others filter or page a list and mean nothing to a delete.
  static List<KeyValueItem> _credentialParams(ApiRequestEntity request) {
    final params = <KeyValueItem>[
      for (final p in request.queryParams)
        if (p.enabled && p.key.isNotEmpty && SecretMasker.isSensitiveName(p.key)) KeyValueItem(key: p.key, value: p.value),
    ];
    final at = request.url.indexOf('?');
    if (at != -1) {
      final query = request.url.substring(at + 1).split('#').first;
      for (final pair in query.split('&')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final key = pair.substring(0, eq);
        if (SecretMasker.isSensitiveName(key) && !params.any((p) => p.key == key)) {
          params.add(KeyValueItem(key: key, value: pair.substring(eq + 1)));
        }
      }
    }
    return params;
  }

  /// The `context` the create was sent with (the company, the language), so the unlink is made in the same one. Empty
  /// when the body is not plain JSON (a `{{variable}}` where a value should be, a form).
  static Map<String, Object?> _odooContext(ApiRequestEntity request) {
    if (request.body.type != BodyType.raw) return const {};
    try {
      final body = jsonDecode(request.body.rawText);
      if (body is! Map) return const {};
      final direct = body['context'];
      if (direct is Map) return direct.cast<String, Object?>();
      // call_kw (Odoo 18 and older): the context rides in the keyword arguments of the call.
      final params = body['params'];
      final kwargs = params is Map ? params['kwargs'] : null;
      final nested = kwargs is Map ? kwargs['context'] : null;
      return nested is Map ? nested.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// A one-click proposal for a request that creates records.
final class CleanupSuggestion {
  /// The settings that adopting it stores.
  final CleanupSettings settings;

  /// `Odoo create detected: delete with unlink`.
  final String title;

  const CleanupSuggestion(this.settings, this.title);
}

/// Notices a request that creates a record and proposes how to clean up after it.
abstract final class CleanupSuggester {
  /// Null for a request that does not look like a create, or when [current] already is the proposal. [lastBody] and
  /// [lastStatus] are the last response it got in this session, when it has one: a REST create is only recognised by
  /// its answer, an Odoo one by its URL.
  static CleanupSuggestion? suggest(ApiRequestEntity request, CleanupSettings current, {String? lastBody, int? lastStatus}) {
    if (request.method != HttpMethod.post) return null;
    final odoo = CleanupUrls.odoo(request.url);
    CleanupSuggestion? found;
    if (odoo != null) {
      if (odoo.isCreate) {
        found = const CleanupSuggestion(
          CleanupSettings(enabled: true, undo: CleanupUndo.odooUnlink),
          'Odoo create detected: delete with unlink',
        );
      }
    } else if (lastBody != null && lastStatus != null && lastStatus >= 200 && lastStatus < 300) {
      final ids = CreatedIdDetector.fromBody(lastBody);
      if (ids != null) {
        // A path is only written down when the id is not where it is looked for first.
        final path = ids.source == 'id' || ids.source == 'the result' ? '' : ids.source;
        found = CleanupSuggestion(
          CleanupSettings(enabled: true, undo: CleanupUndo.restDelete, idPath: path),
          'REST create detected (id in ${ids.source == 'the result' ? 'the result' : '`${ids.source}`'}): delete with DELETE <url>/{id}',
        );
      }
    }
    if (found == null) return null;
    // "Automatic" already does what the proposal says, so there is nothing left to offer.
    final same = current.enabled &&
        (current.undo == found.settings.undo || current.undo == CleanupUndo.auto) &&
        current.effectiveIdPath == found.settings.idPath;
    return same ? null : found;
  }
}
