import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/history_dao.dart';
import '../../../../core/database/daos/history_payloads_dao.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_fields.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/services/response_body/body_decoder.dart';
import '../../../response_tools/domain/services/resolved_secrets.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/entities/history_snapshot.dart';
import '../../domain/repositories/history_store.dart';
import '../../domain/services/history_masker.dart';
import '../../domain/services/history_policy.dart';
import '../../domain/services/history_search.dart';

/// Keeps the newest sends (the history settings decide how many and for how
/// long) with, when the settings allow, the request each was sent from and a
/// masked, size-capped copy of the response text.
///
/// The summary row is `history_entries`; the details are the `history_payloads`
/// row with the same id, which goes with it when the entry is pruned.
final class HistoryRepositoryImpl implements HistoryStore {
  final HistoryDao _dao;
  final HistoryPolicy _policy;
  final HistoryContextSource? _context;

  HistoryRepositoryImpl(this._dao, {this._policy = const FixedHistoryPolicy(), this._context});

  HistoryPayloadsDao get _payloads => _dao.attachedDatabase.historyPayloadsDao;

  bool _oldHeadersForgotten = false;

  /// Meta of each entry on the list, read from its payload once: the list is re-read after every send and the
  /// payloads are far larger than their summaries. A null value is an entry that has no payload.
  final Map<int, HistoryEntryMeta?> _meta = {};

  /// More than any retention setting allows, so the list shows everything that is kept.
  static const _listCap = 10000;

  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => _dao.watchRecent().map(
        (rows) => rows
            .map((r) => HistoryEntryEntity(
                  id: r.id,
                  method: r.method,
                  url: r.url,
                  statusCode: r.statusCode,
                  durationMs: r.durationMs,
                  sentAt: r.sentAt,
                ))
            .toList(),
      );

  @override
  Stream<List<HistoryEntryEntity>> watchAll() => _dao.watchRecent(limit: _listCap).asyncMap(_withMeta);

  Future<List<HistoryEntryEntity>> _withMeta(List<HistoryListRow> rows) async {
    final unknown = [for (final r in rows) if (!_meta.containsKey(r.id)) r.id];
    if (unknown.isNotEmpty) {
      final stored = await _payloads.requestJsonFor(unknown);
      for (final id in unknown) {
        final json = stored[id];
        _meta[id] = json == null ? null : HistoryRequestSnapshot.decodeMetaOf(json);
      }
    }
    final live = {for (final r in rows) r.id};
    _meta.removeWhere((id, _) => !live.contains(id));
    return [
      for (final r in rows)
        HistoryEntryEntity(
          id: r.id,
          method: r.method,
          url: r.url,
          statusCode: r.statusCode,
          durationMs: r.durationMs,
          sentAt: r.sentAt,
          meta: _meta[r.id],
        ),
    ];
  }

  /// [responseHeaders] is accepted for the sake of the interface but not
  /// stored: nothing reads it, and it holds `Set-Cookie` and token headers.
  /// The table is trimmed to the history settings on every write.
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {
    await _forgetOldHeaders();
    await _write(method, url, statusCode, durationMs, null, await _limits());
  }

  @override
  Future<void> recordCapture({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required HistoryCapture capture,
  }) async {
    await _forgetOldHeaders();
    final limits = await _limits();
    _Payload? payload;
    if (limits.keepBodies) {
      try {
        payload = await _payloadOf(method, url, statusCode, capture, limits);
      } catch (error) {
        // The details are a convenience; the entry itself must still be recorded. Only the type is logged:
        // the text of an error can quote the request.
        debugPrint('PostPilot: the request details could not be kept in History (${error.runtimeType}).');
      }
    }
    await _write(method, url, statusCode, durationMs, payload, limits);
  }

  Future<void> _write(
    String method,
    String url,
    int? statusCode,
    int? durationMs,
    _Payload? payload,
    HistoryLimits limits,
  ) =>
      _dao.attachedDatabase.transaction(() async {
        final id = await _dao.record(
          HistoryEntriesCompanion.insert(
            method: method,
            // A literal secret typed into the URL is masked here as it is in the snapshot.
            url: HistoryMasker.url(url),
            requestId: Value(payload?.requestId),
            statusCode: Value(statusCode),
            durationMs: Value(durationMs),
          ),
          keep: limits.maxEntries,
        );
        if (payload != null) {
          await _payloads.upsert(HistoryPayloadsCompanion.insert(
            historyId: Value(id),
            requestJson: Value(payload.requestJson),
            responseText: Value(payload.responseText),
            responseContentType: Value(payload.responseContentType),
            responseTruncated: Value(payload.responseTruncated),
            searchText: Value(payload.searchText),
          ));
        }
        await _pruneByAge(limits);
      });

  Future<void> _pruneByAge(HistoryLimits limits) async {
    final days = limits.retentionDays;
    if (days == null || days <= 0) return;
    final now = DateTime.now();
    await _dao.pruneOlderThan(DateTime(now.year, now.month, now.day - days));
  }

  Future<HistoryLimits> _limits() async {
    try {
      return await _policy.limits();
    } catch (_) {
      return const HistoryLimits();
    }
  }

  Future<_Payload> _payloadOf(
    String method,
    String url,
    int? statusCode,
    HistoryCapture capture,
    HistoryLimits limits,
  ) async {
    final request = capture.request;
    final context = await _contextOf(request);
    final secrets = _secretValues(capture, context);
    final response = _responseText(capture, limits, secrets);
    final error = capture.error == null ? null : _firstChars(SecretMasker.maskMessage(capture.error!), 300);
    final meta = HistoryEntryMeta(
      requestId: request.id > 0 ? request.id : null,
      requestName: _firstChars(request.name, 120),
      collectionId: request.collectionId > 0 ? request.collectionId : null,
      collectionName: context.collectionName == null ? null : _firstChars(context.collectionName!, 80),
      environmentName: context.environmentName == null ? null : _firstChars(context.environmentName!, 80),
      responseBytes: error == null ? capture.responseBytes.length : null,
      responseTruncated: response?.truncated ?? capture.responseTruncated,
      hasResponseBody: response != null && response.text.isNotEmpty,
      statusMessage: capture.statusMessage.isEmpty ? null : _firstChars(capture.statusMessage, 80),
      error: error,
    );
    final snapshot = HistoryRequestSnapshot.capture(
      request,
      meta: meta,
      maxBodyBytes: limits.maxBodyBytes,
      secretValues: secrets,
    );
    return _Payload(
      requestId: meta.requestId,
      requestJson: snapshot.encode(),
      responseText: response?.text,
      responseContentType: capture.responseContentType == null ? null : _firstChars(capture.responseContentType!, 200),
      responseTruncated: meta.responseTruncated,
      searchText: HistorySearch.searchText(
        method: method,
        url: snapshot.fullUrl,
        requestName: meta.requestName,
        collectionName: meta.collectionName,
        environmentName: meta.environmentName,
        statusCode: statusCode,
        statusMessage: meta.statusMessage,
        requestBody: _requestBodyText(snapshot.body),
        responseBody: response?.text,
        error: error,
      ),
    );
  }

  Future<HistoryContext> _contextOf(ApiRequestEntity request) async {
    try {
      return await _context?.of(request) ?? const HistoryContext();
    } catch (_) {
      return const HistoryContext();
    }
  }

  /// The resolved credentials of this send, which must not survive in anything stored: a server can echo them
  /// back in a body. The variables that are secret by name or by the user's flag, those named in a secret place of the
  /// request (an `Authorization` header or an auth field may reference a variable that is called anything), and the
  /// literal credentials of the request's auth and the collection's.
  List<String> _secretValues(HistoryCapture capture, HistoryContext context) {
    final values = <String>{};
    void add(String value) {
      if (value.length >= _minSecretLength && !value.contains('{{')) values.add(value);
    }

    final resolver = capture.resolver;
    if (resolver != null) {
      ResolvedSecrets.valuesOf(resolver, flaggedKeys: context.flaggedSecretKeys).forEach(add);
      final secretTexts = <String>[
        for (final h in capture.request.headers)
          if (SecretNames.isSecretHeader(h.key)) h.value,
        for (final p in capture.request.queryParams)
          if (SecretNames.isSecretQuery(p.key)) p.value,
        for (final entry in capture.request.auth.toJson().entries)
          if (SecretFields.authKeys.contains(entry.key) && entry.value is String) entry.value as String,
      ];
      for (final text in secretTexts) {
        add(resolver.resolve(text));
      }
    }
    for (final entry in capture.request.auth.toJson().entries) {
      final value = entry.value;
      if (SecretFields.authKeys.contains(entry.key) && value is String && SecretNames.hasLiteralSecret(value)) add(value);
    }
    context.secretValues.forEach(add);
    return values.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  static const _minSecretLength = 6;

  static final _textualMimeType = RegExp(r'^text/|json|xml|javascript|ecmascript|yaml|urlencoded|graphql|csv');

  /// The response as masked text, cut to the limit; null for an empty body and for binary content.
  ({String text, bool truncated})? _responseText(HistoryCapture capture, HistoryLimits limits, List<String> secrets) {
    final bytes = capture.responseBytes;
    if (bytes.isEmpty) return null;
    final contentType = capture.responseContentType;
    final mimeType = contentType == null ? '' : contentType.split(';').first.trim().toLowerCase();
    if (mimeType.isNotEmpty && !_textualMimeType.hasMatch(mimeType)) return null;
    final window = limits.maxBodyBytes + HistoryMasker.cutMargin;
    final windowCut = bytes.length > window;
    final decoded = decodeResponseBody(
      Uint8List.fromList(windowCut ? bytes.sublist(0, window) : bytes),
      mimeType: mimeType,
      charset: charsetOfContentType(contentType),
      truncated: windowCut || capture.responseTruncated,
    );
    if (decoded == null) return null;
    final capped = HistoryMasker.cappedText(decoded, limits.maxBodyBytes, secretValues: secrets);
    return (text: capped.text, truncated: capped.truncated || windowCut || capture.responseTruncated);
  }

  /// What of the request body the search can find: the raw text, the GraphQL query, or the form's `name=value` pairs.
  String _requestBodyText(RequestBody body) {
    String pairs(Iterable<({String key, String value})> rows) => rows.map((r) => '${r.key}=${r.value}').join('&');
    return [
      body.rawText,
      body.graphqlQuery,
      pairs(body.formFields.where((f) => f.enabled).map((f) => (key: f.key, value: f.value))),
      pairs(body.urlEncodedFields.where((f) => f.enabled).map((f) => (key: f.key, value: f.value))),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  static String _firstChars(String text, int max) => text.length <= max ? text : text.substring(0, max);

  @override
  Future<Set<int>> searchStored(String query) async {
    final needle = HistorySearch.normalise(query);
    if (needle.isEmpty) return const {};
    return (await _payloads.idsMatching(needle)).toSet();
  }

  @override
  Future<HistoryDetail?> detailOf(int historyId) async {
    final row = await _payloads.findByHistory(historyId);
    if (row == null) return null;
    final request = HistoryRequestSnapshot.decode(row.requestJson);
    if (request == null) return null;
    return HistoryDetail(
      request: request,
      responseText: row.responseText,
      responseContentType: row.responseContentType,
      responseTruncated: row.responseTruncated,
    );
  }

  @override
  Future<void> applyRetention() async {
    final limits = await _limits();
    await _dao.attachedDatabase.transaction(() async {
      await _dao.prune(keep: limits.maxEntries);
      await _pruneByAge(limits);
    });
  }

  /// Once per run: rows written by older versions still carry their headers.
  Future<void> _forgetOldHeaders() async {
    if (_oldHeadersForgotten) return;
    try {
      await _dao.forgetStoredHeaders();
      _oldHeadersForgotten = true;
    } catch (_) {
      // Tidying must never stop a send from being recorded; tried again next time.
    }
  }

  @override
  Future<void> clear() => _dao.attachedDatabase.transaction(() async {
        // The foreign key would take the payloads along; this does not depend on it being enforced.
        await _payloads.deleteAll();
        await _dao.clear();
      });
}

/// What is written beside an entry.
final class _Payload {
  final int? requestId;
  final String requestJson;
  final String? responseText;
  final String? responseContentType;
  final bool responseTruncated;
  final String searchText;

  const _Payload({
    required this.requestId,
    required this.requestJson,
    required this.responseText,
    required this.responseContentType,
    required this.responseTruncated,
    required this.searchText,
  });
}
