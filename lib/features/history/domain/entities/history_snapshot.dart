import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../services/history_masker.dart';
import 'history_entry_entity.dart';

/// The request an entry was sent from, as it was saved: `{{variables}}` stay
/// templates (never today's values, never a secret that was resolved to send
/// it), and a literal credential is masked (see [HistoryMasker]).
///
/// Stored as JSON in `history_payloads.request_json`, together with the facts
/// about its origin and its answer that the list needs ([meta]).
final class HistoryRequestSnapshot {
  final HistoryEntryMeta meta;
  final HttpMethod method;

  /// As written, without the query parameters of [queryParams].
  final String url;
  final List<KeyValueItem> headers;
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;

  /// A raw or GraphQL body was longer than History keeps, so [body] is only its first part.
  final bool bodyTruncated;

  const HistoryRequestSnapshot({
    required this.meta,
    required this.method,
    required this.url,
    this.headers = const [],
    this.queryParams = const [],
    this.body = RequestBody.empty,
    this.auth = const RequestAuth(type: AuthType.none),
    this.bodyTruncated = false,
  });

  /// What is known of an entry that kept no snapshot: its method and URL.
  factory HistoryRequestSnapshot.bare(String method, String url) => HistoryRequestSnapshot(
        meta: const HistoryEntryMeta(),
        method: HttpMethod.fromString(method),
        url: url,
      );

  /// The snapshot of [request] as it is stored: masked, and with raw and GraphQL
  /// bodies cut to [maxBodyBytes]. [secretValues] are resolved secrets that must
  /// not survive in the text of the bodies (they never come from [request] itself,
  /// which holds templates).
  factory HistoryRequestSnapshot.capture(
    ApiRequestEntity request, {
    required HistoryEntryMeta meta,
    required int maxBodyBytes,
    List<String> secretValues = const [],
  }) {
    final raw = HistoryMasker.cappedText(request.body.rawText, maxBodyBytes, secretValues: secretValues);
    final query = HistoryMasker.cappedText(request.body.graphqlQuery, maxBodyBytes, secretValues: secretValues);
    final variables = HistoryMasker.cappedText(request.body.graphqlVariables, maxBodyBytes, secretValues: secretValues);
    return HistoryRequestSnapshot(
      meta: meta,
      method: request.method,
      url: HistoryMasker.url(request.url),
      headers: HistoryMasker.headers(request.headers),
      queryParams: HistoryMasker.queryParams(request.queryParams),
      body: RequestBody(
        type: request.body.type,
        rawContentType: request.body.rawContentType,
        rawText: raw.text,
        formFields: HistoryMasker.formFields(request.body.formFields),
        urlEncodedFields: HistoryMasker.formFields(request.body.urlEncodedFields),
        graphqlQuery: query.text,
        graphqlVariables: variables.text,
      ),
      auth: HistoryMasker.auth(request.auth),
      bodyTruncated: raw.truncated || query.truncated || variables.truncated,
    );
  }

  String get name => meta.requestName ?? '${method.label} $url';

  /// The URL with the enabled query parameters appended, the way History lists it.
  String get fullUrl {
    final query = queryParams.where((p) => p.enabled && p.key.isNotEmpty).map((p) => '${p.key}=${p.value}').join('&');
    if (query.isEmpty) return url;
    return '$url${url.contains('?') ? '&' : '?'}$query';
  }

  /// A credential was masked when this was recorded, so sending it as it is leaves that value empty.
  bool get hasMaskedValues {
    bool masked(String text) => text.contains(SecretMasker.mask);
    bool anyMasked(List<KeyValueItem> items) => items.any((i) => masked(i.value));
    return masked(url) ||
        anyMasked(headers) ||
        anyMasked(queryParams) ||
        anyMasked(body.formFields) ||
        anyMasked(body.urlEncodedFields) ||
        masked(body.rawText) ||
        masked(body.graphqlQuery) ||
        masked(body.graphqlVariables) ||
        masked(jsonEncode(auth.toJson()));
  }

  /// The request ready to be saved or sent. A masked value comes back empty:
  /// a send must never carry the mask itself as if it were the secret.
  ApiRequestEntity toRequest({required int id, required int collectionId, int? folderId, String? name}) {
    List<KeyValueItem> unmasked(List<KeyValueItem> items) => [for (final i in items) i.copyWith(value: _unmask(i.value))];
    final json = auth.toJson();
    for (final key in json.keys.toList()) {
      final value = json[key];
      if (value is String) json[key] = _unmask(value);
    }
    return ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: folderId,
      name: name ?? this.name,
      method: method,
      url: _unmask(url),
      headers: unmasked(headers),
      queryParams: unmasked(queryParams),
      body: RequestBody(
        type: body.type,
        rawContentType: body.rawContentType,
        rawText: _unmask(body.rawText),
        formFields: unmasked(body.formFields),
        urlEncodedFields: unmasked(body.urlEncodedFields),
        graphqlQuery: _unmask(body.graphqlQuery),
        graphqlVariables: _unmask(body.graphqlVariables),
      ),
      auth: RequestAuth.fromJson(json),
    );
  }

  static String _unmask(String text) => text.contains(SecretMasker.mask) ? text.replaceAll(SecretMasker.mask, '').trimRight() : text;

  // --- storage ---------------------------------------------------------------

  static const _version = 1;

  String encode() => jsonEncode({
        'v': _version,
        'meta': {
          'requestId': meta.requestId,
          'requestName': meta.requestName,
          'collectionId': meta.collectionId,
          'collectionName': meta.collectionName,
          'environmentName': meta.environmentName,
          'responseBytes': meta.responseBytes,
          'responseTruncated': meta.responseTruncated,
          'hasResponseBody': meta.hasResponseBody,
          'statusMessage': meta.statusMessage,
          'error': meta.error,
        },
        'request': {
          'method': method.name,
          'url': url,
          'headers': _rows(headers),
          'queryParams': _rows(queryParams),
          'body': {
            'type': body.type.name,
            'rawContentType': body.rawContentType.name,
            'rawText': body.rawText,
            'formFields': _rows(body.formFields),
            'urlEncodedFields': _rows(body.urlEncodedFields),
            'graphqlQuery': body.graphqlQuery,
            'graphqlVariables': body.graphqlVariables,
          },
          'auth': auth.toJson(),
          'bodyTruncated': bodyTruncated,
        },
      });

  /// Null when [json] holds no snapshot (an entry written before there was one, or damaged text).
  static HistoryRequestSnapshot? decode(String json) {
    try {
      final root = jsonDecode(json);
      if (root is! Map || root['request'] is! Map) return null;
      final request = Map<String, dynamic>.from(root['request'] as Map);
      final body = request['body'] is Map ? Map<String, dynamic>.from(request['body'] as Map) : <String, dynamic>{};
      return HistoryRequestSnapshot(
        meta: decodeMeta(root['meta']),
        method: HttpMethod.fromString(request['method'] as String?),
        url: request['url'] as String? ?? '',
        headers: _items(request['headers']),
        queryParams: _items(request['queryParams']),
        body: RequestBody(
          type: BodyType.values.firstWhere((t) => t.name == body['type'], orElse: () => BodyType.none),
          rawContentType:
              RawContentType.values.firstWhere((t) => t.name == body['rawContentType'], orElse: () => RawContentType.json),
          rawText: body['rawText'] as String? ?? '',
          formFields: _items(body['formFields']),
          urlEncodedFields: _items(body['urlEncodedFields']),
          graphqlQuery: body['graphqlQuery'] as String? ?? '',
          graphqlVariables: body['graphqlVariables'] as String? ?? '{}',
        ),
        auth: request['auth'] is Map
            ? RequestAuth.fromJson(Map<String, dynamic>.from(request['auth'] as Map))
            : const RequestAuth(type: AuthType.none),
        bodyTruncated: request['bodyTruncated'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Just the [HistoryEntryMeta] of stored [json]; null when there is none.
  static HistoryEntryMeta? decodeMetaOf(String json) {
    try {
      final root = jsonDecode(json);
      if (root is! Map || root['request'] is! Map) return null;
      return decodeMeta(root['meta']);
    } catch (_) {
      return null;
    }
  }

  static HistoryEntryMeta decodeMeta(Object? raw) {
    if (raw is! Map) return const HistoryEntryMeta();
    int? integer(String key) => raw[key] is int ? raw[key] as int : null;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    return HistoryEntryMeta(
      requestId: integer('requestId'),
      requestName: text('requestName'),
      collectionId: integer('collectionId'),
      collectionName: text('collectionName'),
      environmentName: text('environmentName'),
      responseBytes: integer('responseBytes'),
      responseTruncated: raw['responseTruncated'] == true,
      hasResponseBody: raw['hasResponseBody'] == true,
      statusMessage: text('statusMessage'),
      error: text('error'),
    );
  }

  static List<Map<String, Object?>> _rows(List<KeyValueItem> items) =>
      [for (final i in items) {'key': i.key, 'value': i.value, 'enabled': i.enabled}];

  static List<KeyValueItem> _items(Object? raw) => [
        if (raw is List)
          for (final row in raw)
            if (row is Map && row['key'] is String)
              KeyValueItem(key: row['key'] as String, value: row['value'] as String? ?? '', enabled: row['enabled'] != false),
      ];
}

/// An entry's request snapshot with the answer kept beside it (the `history_payloads` row, decoded).
final class HistoryDetail {
  final HistoryRequestSnapshot request;

  /// The response body as text, masked and cut to the limit; null for a binary or empty answer and for a failed send.
  final String? responseText;
  final String? responseContentType;

  /// [responseText] is only the first part of what arrived.
  final bool responseTruncated;

  const HistoryDetail({
    required this.request,
    this.responseText,
    this.responseContentType,
    this.responseTruncated = false,
  });

  bool get hasResponseBody => responseText != null && responseText!.isNotEmpty;
}
