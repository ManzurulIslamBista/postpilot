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

  /// Returns the extra headers (Authorization, X-Amz-Date, and, if a session
  /// token is set, X-Amz-Security-Token) to add to the request.
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

    final signedHeaderMap = <String, String>{
      ...{for (final e in headers.entries) e.key.toLowerCase(): e.value.trim()},
      'host': uri.host,
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
    };

    final sortedHeaderNames = signedHeaderMap.keys.toList()..sort();
    final canonicalHeaders = sortedHeaderNames.map((k) => '$k:${signedHeaderMap[k]}\n').join();
    final signedHeaders = sortedHeaderNames.join(';');

    final canonicalRequest = [
      method.toUpperCase(),
      _canonicalUri(uri),
      _canonicalQuery(uri),
      canonicalHeaders,
      signedHeaders,
      sha256.convert(body).toString(),
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
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
      'Authorization': authorization,
    };
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

  String _canonicalUri(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return path.split('/').map(_uriEncode).join('/');
  }

  String _canonicalQuery(Uri uri) {
    final params = <String, String>{};
    uri.queryParametersAll.forEach((key, values) {
      for (final v in values) {
        params[_uriEncode(key)] = _uriEncode(v);
      }
    });
    final sortedKeys = params.keys.toList()..sort();
    return sortedKeys.map((k) => '$k=${params[k]}').join('&');
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
