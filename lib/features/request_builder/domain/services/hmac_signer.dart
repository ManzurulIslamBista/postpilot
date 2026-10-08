import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../../../core/enums/auth_type.dart';

/// One request, signed: the signature, the exact bytes it covers and the headers to send.
final class HmacSignature {
  /// The HMAC of [payload], written as hex or base64.
  final String signature;

  /// The `{timestamp}` that went into the payload and the headers (empty when none was needed).
  final String timestamp;

  /// Exactly the bytes that were signed.
  final List<int> payload;

  /// The headers to add to the request: the signature header and, when one is set, the timestamp header.
  final Map<String, String> headers;

  const HmacSignature({required this.signature, required this.timestamp, required this.payload, required this.headers});

  /// [payload] as text, for showing it.
  String get payloadText => utf8.decode(payload, allowMalformed: true);
}

/// Signs a request the way webhook senders do (GitHub, Stripe, Shopify, Slack...): an HMAC over a payload
/// built from the request, written into a header. Nothing here is specific to one service: the payload and the
/// header value are templates, and [HmacPresets] holds the documented ones.
///
/// The payload template may use `{body}` (the body, byte for byte as it is sent; no body is the empty
/// string), `{timestamp}`, `{method}` (upper case), `{path}` (the path as sent, `/` for none), `{query}` (the
/// query string without `?`) and `{url}` (the whole URL). The header value template may use `{signature}` and
/// `{timestamp}`. Any other text, braces included, is taken as it is. The templates are read once from left to
/// right, so what a placeholder stands for is never read for placeholders again: a body that happens to hold
/// `{timestamp}` is signed as it is.
///
/// Every field is used verbatim: resolve `{{variables}}` before building the signer. The timestamp is given to
/// [sign], so the payload and the headers of one send always share the same one.
final class HmacSigner {
  final String secret;
  final HmacAlgorithm algorithm;
  final HmacEncoding encoding;
  final String payloadTemplate;

  /// The header that carries the signature; none is added while this is blank (the signature is still computed).
  final String headerName;

  /// A blank template stands for the signature alone.
  final String headerTemplate;

  /// The header that carries the timestamp on its own; none while blank.
  final String timestampHeader;

  const HmacSigner({
    required this.secret,
    this.algorithm = HmacAlgorithm.sha256,
    this.encoding = HmacEncoding.hex,
    this.payloadTemplate = '{body}',
    this.headerName = '',
    this.headerTemplate = '{signature}',
    this.timestampHeader = '',
  });

  static final _payloadToken = RegExp(r'\{(body|timestamp|method|path|query|url)\}');
  static final _headerToken = RegExp(r'\{(signature|timestamp)\}');

  /// The unix time of [now] in seconds, which is what a `{timestamp}` is unless a fixed one is set.
  static String unixSeconds(DateTime now) => (now.millisecondsSinceEpoch ~/ 1000).toString();

  /// Whether a `{timestamp}` is part of what this signer writes, so a send needs one.
  bool get usesTimestamp =>
      payloadTemplate.contains('{timestamp}') ||
      headerTemplate.contains('{timestamp}') ||
      timestampHeader.trim().isNotEmpty;

  Hash get _hash => switch (algorithm) {
        HmacAlgorithm.sha1 => sha1,
        HmacAlgorithm.sha256 => sha256,
        HmacAlgorithm.sha512 => sha512,
      };

  /// Signs a request of [method] to [uri] with [body] (the bytes that go on the wire; empty for none).
  HmacSignature sign({
    required String method,
    required Uri uri,
    required List<int> body,
    required String timestamp,
  }) {
    final payload = payloadOf(method: method, uri: uri, body: body, timestamp: timestamp);
    final digest = Hmac(_hash, utf8.encode(secret)).convert(payload).bytes;
    final signature = switch (encoding) {
      HmacEncoding.hex => _hex(digest),
      HmacEncoding.base64 => base64Encode(digest),
    };
    final template = headerTemplate.isEmpty ? '{signature}' : headerTemplate;
    final value = template.replaceAllMapped(_headerToken, (m) => m[1] == 'signature' ? signature : timestamp);
    final name = headerName.trim();
    final extra = timestampHeader.trim();
    return HmacSignature(
      signature: signature,
      timestamp: timestamp,
      payload: payload,
      headers: {
        if (name.isNotEmpty) name: value,
        if (extra.isNotEmpty) extra: timestamp,
      },
    );
  }

  /// The bytes the HMAC is computed over: the payload template with its placeholders filled in. The body is
  /// copied in as bytes, never decoded, so whatever the body holds is signed exactly.
  Uint8List payloadOf({
    required String method,
    required Uri uri,
    required List<int> body,
    required String timestamp,
  }) {
    final out = BytesBuilder();
    var cursor = 0;
    for (final match in _payloadToken.allMatches(payloadTemplate)) {
      out.add(utf8.encode(payloadTemplate.substring(cursor, match.start)));
      switch (match[1]) {
        case 'body':
          out.add(body);
        case 'timestamp':
          out.add(utf8.encode(timestamp));
        case 'method':
          out.add(utf8.encode(method.toUpperCase()));
        case 'path':
          out.add(utf8.encode(uri.path.isEmpty ? '/' : uri.path));
        case 'query':
          out.add(utf8.encode(uri.query));
        case 'url':
          out.add(utf8.encode(uri.toString()));
      }
      cursor = match.end;
    }
    out.add(utf8.encode(payloadTemplate.substring(cursor)));
    return out.takeBytes();
  }

  static String _hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
}
