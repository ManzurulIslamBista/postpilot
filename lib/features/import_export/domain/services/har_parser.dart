import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../entities/imported_collection.dart';
import 'imported_body_mapper.dart';

final class ParsedHar {
  final String name;
  final List<ImportedRequest> requests;

  /// Entries that can't be replayed: no URL, a non-http(s) scheme, a method the
  /// app doesn't send, or a browser's CORS preflight.
  final int skipped;
  const ParsedHar({required this.name, required this.requests, required this.skipped});
}

/// Parses a HAR 1.2 recording (browser dev tools "Save all as HAR") into one
/// request per `log.entries[].request`, named "METHOD /path".
///
/// The URL stays exactly as recorded, query string included. Headers the HTTP
/// client sets itself (`Host`, `Content-Length`, `Connection`, the
/// compression negotiation) and HTTP/2 pseudo-headers (`:authority`, ...) are
/// dropped — a stale `Content-Length` breaks the replay, and asking for
/// `br` gets a body the client can't decode. HTTP/2 splits `Cookie` into
/// one header per cookie, so those are merged back into one; the separate
/// `cookies` array is only a fallback when there is no `Cookie` header, never
/// added on top of it.
abstract final class HarParser {
  static const _transportHeaders = {'host', 'content-length', 'connection', 'accept-encoding', 'transfer-encoding', 'keep-alive'};

  static ParsedHar parse(String text) {
    final root = jsonDecode(text.replaceFirst('﻿', '').trim());
    final log = root is Map ? root['log'] : null;
    final entries = log is Map ? log['entries'] : null;
    if (entries is! List) throw const ImportException('no "log.entries" array found, so this is not a HAR file.');

    final requests = <ImportedRequest>[];
    var skipped = 0;
    for (final entry in entries) {
      final request = entry is Map ? _requestOf(entry['request']) : null;
      if (request == null) {
        skipped++;
      } else {
        requests.add(request);
      }
    }
    return ParsedHar(name: _collectionName(requests), requests: requests, skipped: skipped);
  }

  static String _collectionName(List<ImportedRequest> requests) {
    final host = requests.isEmpty ? null : Uri.tryParse(requests.first.url)?.host;
    return host == null || host.isEmpty ? 'HAR import' : 'HAR import - $host';
  }

  static ImportedRequest? _requestOf(dynamic raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    final method = '${raw['method'] ?? ''}'.toUpperCase();
    if (url is! String || !HttpMethod.values.any((m) => m.label == method)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;

    final recorded = _headerPairs(raw['headers']);
    final isPreflight =
        method == 'OPTIONS' && recorded.any((h) => h.$1.toLowerCase() == 'access-control-request-method');
    if (isPreflight) return null;

    final headers = _headersOf(recorded, raw['cookies']);
    final (body, contentType) = _bodyOf(raw['postData']);
    if (body.type == BodyType.formData) {
      // The recorded boundary belongs to the recorded body; the app writes a form of its own, with its own boundary.
      headers.removeWhere((h) => h.key.toLowerCase() == 'content-type' && h.value.toLowerCase().startsWith('multipart/'));
    }
    if (contentType != null && !ImportedBodyMapper.hasContentType(headers)) {
      headers.add(KeyValueItem(key: ImportedBodyMapper.contentTypeHeader, value: contentType));
    }
    return ImportedRequest(
      '$method ${uri.path.isEmpty ? '/' : uri.path}',
      method: HttpMethod.fromString(method),
      url: url,
      headers: headers,
      body: body,
    );
  }

  static List<(String, String)> _headerPairs(dynamic headers) => [
        if (headers is List)
          for (final h in headers)
            if (h is Map && h['name'] is String && (h['name'] as String).trim().isNotEmpty)
              ((h['name'] as String).trim(), '${h['value'] ?? ''}'),
      ];

  static List<KeyValueItem> _headersOf(List<(String, String)> recorded, dynamic cookiesArray) {
    final headers = <KeyValueItem>[];
    final cookies = <String>[];
    int? cookieAt;
    for (final (name, value) in recorded) {
      final lower = name.toLowerCase();
      if (name.startsWith(':') || _transportHeaders.contains(lower)) continue;
      if (lower == 'cookie') {
        cookieAt ??= headers.length;
        cookies.add(value);
      } else {
        headers.add(KeyValueItem(key: name, value: value));
      }
    }
    if (cookies.isEmpty && cookiesArray is List) {
      for (final c in cookiesArray) {
        if (c is Map && c['name'] is String) cookies.add('${c['name']}=${c['value'] ?? ''}');
      }
    }
    if (cookies.isNotEmpty) {
      headers.insert(cookieAt ?? headers.length, KeyValueItem(key: 'Cookie', value: cookies.join('; ')));
    }
    return headers;
  }

  static (RequestBody, String?) _bodyOf(dynamic raw) {
    if (raw is! Map) return (RequestBody.empty, null);
    final mime = '${raw['mimeType'] ?? ''}';
    final text = raw['text'] is String ? raw['text'] as String : '';
    final params = _paramsOf(raw['params']);
    final formParams = _paramsOf(raw['params'], files: true);
    if (mime.contains('x-www-form-urlencoded')) {
      return (RequestBody(type: BodyType.urlEncoded, urlEncodedFields: params.isNotEmpty ? params : _formFieldsOf(text)), null);
    }
    // Chrome records a multipart body only as text (params stay empty); that
    // text carries the boundary, so it replays faithfully as a raw body.
    if (mime.contains('multipart') && formParams.isNotEmpty) {
      return (RequestBody(type: BodyType.formData, formFields: formParams), null);
    }
    if (text.isEmpty) return (RequestBody.empty, null);
    if (mime.trim().isEmpty) {
      return (RequestBody(type: BodyType.raw, rawContentType: ImportedBodyMapper.sniffRawType(text), rawText: text), null);
    }
    return ImportedBodyMapper.raw(mime, text);
  }

  /// A part with a `fileName` is a file row (only for a multipart form, [files]): HAR records the name of the file
  /// and its type, not where it was on disk, so the path is that name and the file is chosen again. In a urlencoded
  /// body such a part means nothing and is left out.
  static List<KeyValueItem> _paramsOf(dynamic params, {bool files = false}) => [
        if (params is List)
          for (final p in params)
            if (p is Map && p['name'] is String && (p['name'] as String).isNotEmpty)
              if (p['fileName'] == null)
                KeyValueItem(key: p['name'] as String, value: '${p['value'] ?? ''}')
              else if (files)
                KeyValueItem(
                  key: p['name'] as String,
                  value: '${p['fileName']}',
                  kind: FormFieldKind.file,
                  contentType: p['contentType'] is String ? p['contentType'] as String : '',
                ),
      ];

  static List<KeyValueItem> _formFieldsOf(String text) => [
        for (final pair in text.split('&'))
          if (pair.isNotEmpty)
            KeyValueItem(
              key: _decodeComponent(pair.split('=').first),
              value: _decodeComponent(pair.contains('=') ? pair.substring(pair.indexOf('=') + 1) : ''),
            ),
      ];

  static String _decodeComponent(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } catch (_) {
      return text;
    }
  }
}
