import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Implements AWS Signature Version 4, following the algorithm exactly as
/// specified at https://docs.aws.amazon.com/general/latest/gr/sigv4-signing-process.html
/// — the canonicalization rules here are load-bearing: a subtly wrong sort
/// order or encoding produces a signature AWS silently rejects.
final class AwsSigV4Signer {
  final String accessKey;
  final String secretKey;
  final String region;
  final String service;
  final String sessionToken;

  const AwsSigV4Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.service,
    this.sessionToken = '',
  });

  /// Amazon S3 differs from every other service in two ways: it wants the
  /// payload hash sent (and signed) as an `x-amz-content-sha256` header, and
  /// it takes the path URI-encoded once where the others take it twice.
  bool get _isS3 => const {'s3', 's3-object-lambda', 's3express'}.contains(service.trim().toLowerCase());

  /// Returns the extra headers (Authorization, X-Amz-Date, for S3 also
  /// X-Amz-Content-Sha256, and, if a session token is set,
  /// X-Amz-Security-Token) to add to the request.
  Map<String, String> sign({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int> body,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now().toUtc());
    final amzDate = _amzDate(timestamp);
    final dateStamp = amzDate.substring(0, 8);

    final canonical = canonicalRequest(method: method, uri: uri, headers: headers, body: body, amzDate: amzDate);
    final signedHeaders = canonical.signedHeaders;

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonical.request)).toString(),
    ].join('\n');

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    final authorization = 'AWS4-HMAC-SHA256 '
        'Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    return {
      'X-Amz-Date': amzDate,
      if (sessionToken.isNotEmpty) 'X-Amz-Security-Token': sessionToken,
      // A header the request already carries is signed as it is; adding it again would send it twice.
      if (_isS3 && _headerValue(headers, 'x-amz-content-sha256') == null) 'X-Amz-Content-Sha256': _payloadHash(headers, body),
      'Authorization': authorization,
    };
  }

  String? _headerValue(Map<String, String> headers, String lowerName) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerName && entry.value.trim().isNotEmpty) return entry.value.trim();
    }
    return null;
  }

  /// What the last line of the canonical request holds: the hash of the body,
  /// except that S3 takes the value of the request's own `x-amz-content-sha256`
  /// header when it has one (`UNSIGNED-PAYLOAD`, say).
  String _payloadHash(Map<String, String> headers, List<int> body) =>
      (_isS3 ? _headerValue(headers, 'x-amz-content-sha256') : null) ?? sha256.convert(body).toString();

  /// Step 1 of the signing process, and the `SignedHeaders` list it names.
  /// Public so the canonical form can be checked against AWS's documented
  /// examples.
  ({String request, String signedHeaders}) canonicalRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int> body,
    required String amzDate,
  }) {
    final payloadHash = _payloadHash(headers, body);
    final signedHeaderMap = <String, String>{
      ...{for (final e in headers.entries) e.key.toLowerCase(): _canonicalValue(e.value)},
      'host': _hostHeader(uri),
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
      if (_isS3) 'x-amz-content-sha256': payloadHash,
    };

    final sortedHeaderNames = signedHeaderMap.keys.toList()..sort();
    final canonicalHeaders = sortedHeaderNames.map((k) => '$k:${signedHeaderMap[k]}\n').join();
    final signedHeaders = sortedHeaderNames.join(';');

    final request = [
      method.toUpperCase(),
      _canonicalUri(uri),
      _canonicalQuery(uri),
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    return (request: request, signedHeaders: signedHeaders);
  }

  /// Trimmed, with each run of spaces folded into one, as the canonical form wants.
  String _canonicalValue(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The `Host` header `dart:io` sends: the port is part of it unless it is
  /// the scheme's default, and the signature must cover it exactly as sent
  /// (LocalStack on :4566 or MinIO on :9000 reject anything else).
  String _hostHeader(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final defaultPort = uri.scheme == 'https' ? 443 : 80;
    return uri.hasPort && uri.port != defaultPort ? '$host:${uri.port}' : host;
  }

  List<int> _deriveSigningKey(String dateStamp) {
    List<int> hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secretKey'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, service);
    return hmac(kService, 'aws4_request');
  }

  String _amzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// Each path segment, taken back to what the user meant (the path of a `Uri`
  /// is percent-encoded however the URL was typed), is encoded once for S3 and
  /// twice for every other service, which is what the service itself does with
  /// the path it receives.
  String _canonicalUri(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return path.split('/').map((segment) {
      final once = _uriEncode(_decode(segment));
      return _isS3 ? once : _uriEncode(once);
    }).join('/');
  }

  String _decode(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } on FormatException {
      return segment; // a stray `%`: signed as written
    }
  }

  String _canonicalQuery(Uri uri) {
    // A name may repeat (`tag=a&tag=b`) and every occurrence is sent, so every
    // one is signed: sorted by encoded name, then by encoded value.
    final params = <(String, String)>[
      for (final entry in uri.queryParametersAll.entries)
        for (final value in entry.value) (_uriEncode(entry.key), _uriEncode(value)),
    ]..sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    return params.map((p) => '${p.$1}=${p.$2}').join('&');
  }

  /// RFC 3986 percent-encoding as AWS requires it: unreserved characters
  /// (A-Z a-z 0-9 - _ . ~) are left alone, everything else is %XX-encoded
  /// with uppercase hex digits — `Uri.encodeComponent` alone doesn't match
  /// this (it under-encodes a few characters AWS wants encoded).
  String _uriEncode(String input) {
    const unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final bytes = utf8.encode(input);
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final char = String.fromCharCode(byte);
      if (unreserved.contains(char)) {
        buffer.write(char);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }
}

/// Just so callers building a body-hash outside this class stay consistent.
String sha256Hex(List<int> bytes) => sha256.convert(bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toString();
