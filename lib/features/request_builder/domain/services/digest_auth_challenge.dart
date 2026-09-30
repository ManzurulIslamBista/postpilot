import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Parses a `WWW-Authenticate: Digest ...` challenge and computes the
/// `Authorization: Digest ...` response per RFC 7616 (which folds in the
/// older RFC 2617 MD5-only scheme as its default algorithm).
final class DigestAuthChallenge {
  final String realm;
  final String nonce;
  final String? opaque;
  final String qop;
  final String algorithm;

  const DigestAuthChallenge({
    required this.realm,
    required this.nonce,
    this.qop = '',
    this.opaque,
    this.algorithm = 'MD5',
  });

  /// Returns null if [header] isn't a Digest challenge (e.g. it's Basic, or
  /// there's no WWW-Authenticate header at all).
  static DigestAuthChallenge? parse(String? header) {
    if (header == null || !header.trimLeft().toUpperCase().startsWith('DIGEST')) return null;

    final directives = <String, String>{};
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))').allMatches(header)) {
      directives[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? '';
    }

    final nonce = directives['nonce'];
    if (nonce == null) return null;

    return DigestAuthChallenge(
      realm: directives['realm'] ?? '',
      nonce: nonce,
      opaque: directives['opaque'],
      qop: directives['qop'] ?? '',
      algorithm: (directives['algorithm'] ?? 'MD5').toUpperCase(),
    );
  }

  /// [cnonce] is injectable for testing against known RFC vectors; in
  /// production it's left null and a fresh random one is generated per call.
  String buildAuthorizationHeader({
    required String username,
    required String password,
    required String method,
    required String digestUri,
    String? cnonce,
  }) {
    cnonce ??= _randomHex(16);
    const nc = '00000001';
    final usesQop = qop.isNotEmpty;

    final ha1 = _hash('$username:$realm:$password');
    final ha2 = _hash('$method:$digestUri');
    final response = usesQop ? _hash('$ha1:$nonce:$nc:$cnonce:$qop:$ha2') : _hash('$ha1:$nonce:$ha2');

    final parts = {
      'username': username,
      'realm': realm,
      'nonce': nonce,
      'uri': digestUri,
      'response': response,
      'opaque': ?opaque,
      if (usesQop) 'qop': qop,
      if (usesQop) 'nc': nc,
      if (usesQop) 'cnonce': cnonce,
    };

    const unquoted = {'nc', 'qop'}; // RFC 2617 §3.2.2: nc and qop are tokens, not quoted-strings
    final serialized = parts.entries.map((e) => unquoted.contains(e.key) ? '${e.key}=${e.value}' : '${e.key}="${e.value}"');
    return 'Digest ${serialized.join(', ')}';
  }

  String _hash(String input) {
    final bytes = utf8.encode(input);
    final digest = algorithm.contains('256') ? sha256.convert(bytes) : md5.convert(bytes);
    return digest.toString();
  }

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
