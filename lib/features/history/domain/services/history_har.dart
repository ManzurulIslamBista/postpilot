import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../entities/history_entry_entity.dart';
import '../entities/history_snapshot.dart';
import 'har_exporter.dart';

/// Turns History entries into [HarEntryInput]s.
///
/// [expand] fills in the `{{variables}}` of the stored request (the URL would
/// not be absolute otherwise); see `HistoryTemplateExpander` for how it keeps
/// secrets out. The authentication the request carried is written as the header
/// it would have produced, with the credential masked, so a colleague sees what kind
/// of auth the call used and PostPilot's HAR importer brings it back as a header.
abstract final class HistoryHar {
  static HarEntryInput inputFor(HistoryEntryEntity entry, HistoryDetail? detail, {String Function(String)? expand}) {
    String ex(String text) => expand == null ? text : expand(text);
    final snapshot = detail?.request ?? HistoryRequestSnapshot.bare(entry.method, entry.url);
    final auth = snapshot.auth;

    var url = ex(detail == null ? entry.url : snapshot.fullUrl);
    final headers = [
      for (final h in snapshot.headers)
        if (h.enabled && h.key.isNotEmpty) HarHeader(ex(h.key), ex(h.value)),
    ];
    bool has(String name) => headers.any((h) => h.name.toLowerCase() == name.toLowerCase());

    final apiKeyQuery = apiKeyQueryPair(auth, ex);
    if (apiKeyQuery != null) url = '$url${url.contains('?') ? '&' : '?'}$apiKeyQuery';
    final authHeader = authorizationHeader(auth, ex);
    if (authHeader != null && !has(authHeader.name)) headers.add(authHeader);

    final body = snapshot.body;
    String? bodyText;
    List<HarHeader>? params;
    String? mime;
    switch (body.type) {
      case BodyType.none:
        break;
      case BodyType.raw:
        if (body.rawText.isNotEmpty) {
          bodyText = ex(body.rawText);
          mime = body.rawContentType.mimeType;
        }
      case BodyType.graphql:
        bodyText = jsonEncode({'query': ex(body.graphqlQuery), 'variables': _variables(ex(body.graphqlVariables))});
        mime = 'application/json';
      case BodyType.urlEncoded:
        final fields = [for (final f in body.urlEncodedFields) if (f.enabled && f.key.isNotEmpty) f];
        if (fields.isNotEmpty) {
          bodyText = fields.map((f) => '${_formEncode(ex(f.key))}=${_formEncode(ex(f.value))}').join('&');
          mime = 'application/x-www-form-urlencoded';
        }
      case BodyType.formData:
        final fields = [for (final f in body.formFields) if (f.enabled && f.key.isNotEmpty) f];
        if (fields.isNotEmpty) {
          params = [for (final f in fields) HarHeader(ex(f.key), ex(f.value))];
          mime = 'multipart/form-data';
        }
    }
    final explicitType = headers.where((h) => h.name.toLowerCase() == 'content-type').firstOrNull;
    if (explicitType != null) {
      mime = explicitType.value.split(';').first.trim();
    } else if (mime != null && body.type != BodyType.formData) {
      // A multipart form is written without a header: its boundary is not known, and a header without one breaks a replay.
      headers.add(HarHeader('Content-Type', mime));
    }

    final contentType = detail?.responseContentType;
    final meta = snapshot.meta;
    final context = [
      if (meta.collectionName != null) meta.collectionName!,
      if (meta.requestName != null) meta.requestName!,
    ].join(' > ');
    return HarEntryInput(
      startedAt: entry.sentAt,
      durationMs: entry.durationMs,
      method: entry.method,
      url: url,
      requestHeaders: headers,
      requestMimeType: mime,
      requestBody: bodyText,
      requestParams: params,
      statusCode: entry.statusCode,
      statusText: meta.statusMessage ?? _reason(entry.statusCode),
      responseHeaders: [if (contentType != null && contentType.isNotEmpty) HarHeader('Content-Type', contentType)],
      responseMimeType: contentType?.split(';').first.trim(),
      responseText: detail?.hasResponseBody == true ? detail!.responseText : null,
      responseBytes: meta.responseBytes,
      responseTruncated: detail?.responseTruncated ?? false,
      error: meta.error,
      comment: [if (context.isNotEmpty) context, if (meta.environmentName != null) '(${meta.environmentName})'].join(' '),
    );
  }

  /// The header [auth] adds to a request, with the credential masked or left as the `{{variable}}` it
  /// references; null for types that add none and for an API key that goes in the query.
  static HarHeader? authorizationHeader(RequestAuth auth, String Function(String) ex) {
    const mask = SecretMasker.mask;
    return switch (auth.type) {
      AuthType.apiKey when auth.apiKeyLocation == ApiKeyLocation.header && auth.apiKeyName.isNotEmpty =>
        HarHeader(ex(auth.apiKeyName), ex(auth.apiKeyValue)),
      AuthType.bearer => HarHeader('Authorization', 'Bearer ${ex(auth.bearerToken)}'),
      AuthType.oauth2 => const HarHeader('Authorization', 'Bearer $mask'),
      AuthType.basic => const HarHeader('Authorization', 'Basic $mask'),
      AuthType.digest => const HarHeader('Authorization', 'Digest $mask'),
      AuthType.awsSignatureV4 => const HarHeader('Authorization', 'AWS4-HMAC-SHA256 $mask'),
      AuthType.jwtBearer => HarHeader('Authorization', '${auth.jwtHeaderPrefix} $mask'.trim()),
      AuthType.apiKey || AuthType.none || AuthType.inherit => null,
    };
  }

  /// `name=value` of an API key that is sent in the query string; null otherwise.
  static String? apiKeyQueryPair(RequestAuth auth, String Function(String) ex) =>
      auth.type == AuthType.apiKey && auth.apiKeyLocation == ApiKeyLocation.query && auth.apiKeyName.isNotEmpty
          ? '${ex(auth.apiKeyName)}=${ex(auth.apiKeyValue)}'
          : null;

  static Object? _variables(String text) {
    if (text.trim().isEmpty) return <String, Object?>{};
    try {
      return jsonDecode(text);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  /// Escapes only what would break `name=value&name=value`; `{{variables}}` stay readable.
  static String _formEncode(String text) => text
      .replaceAll('%', '%25')
      .replaceAll('&', '%26')
      .replaceAll('=', '%3D')
      .replaceAll('+', '%2B')
      .replaceAll('#', '%23')
      .replaceAll(' ', '+');

  static String _reason(int? status) => switch (status) {
        200 => 'OK',
        201 => 'Created',
        202 => 'Accepted',
        204 => 'No Content',
        301 => 'Moved Permanently',
        302 => 'Found',
        304 => 'Not Modified',
        400 => 'Bad Request',
        401 => 'Unauthorized',
        403 => 'Forbidden',
        404 => 'Not Found',
        405 => 'Method Not Allowed',
        409 => 'Conflict',
        415 => 'Unsupported Media Type',
        422 => 'Unprocessable Entity',
        429 => 'Too Many Requests',
        500 => 'Internal Server Error',
        502 => 'Bad Gateway',
        503 => 'Service Unavailable',
        504 => 'Gateway Timeout',
        _ => '',
      };
}
