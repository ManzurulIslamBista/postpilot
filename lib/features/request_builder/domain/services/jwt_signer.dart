import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../../core/enums/auth_type.dart';

/// Signs a JWT with an HMAC algorithm (HS256/384/512) — the symmetric-key
/// half of Postman's JWT Bearer auth. RS/ES/PS (asymmetric) algorithms need
/// real key-pair handling and are a separate, later addition.
final class JwtSigner {
  static String sign({required String secret, required JwtAlgorithm algorithm, required Map<String, dynamic> payload}) {
    final header = {'alg': algorithm.label, 'typ': 'JWT'};
    final headerSegment = _base64UrlEncode(utf8.encode(jsonEncode(header)));
    final payloadSegment = _base64UrlEncode(utf8.encode(jsonEncode(payload)));
    final signingInput = '$headerSegment.$payloadSegment';

    final hash = switch (algorithm) {
      JwtAlgorithm.hs256 => sha256,
      JwtAlgorithm.hs384 => sha384,
      JwtAlgorithm.hs512 => sha512,
    };
    final signature = Hmac(hash, utf8.encode(secret)).convert(utf8.encode(signingInput)).bytes;

    return '$signingInput.${_base64UrlEncode(signature)}';
  }

  static String _base64UrlEncode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
