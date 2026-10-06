import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Parses a `WWW-Authenticate: Digest ...` challenge and computes the
/// `Authorization: Digest ...` response per RFC 7616 (which folds in the
/// older RFC 2617 MD5-only scheme as its default algorithm).
///
/// Supported: `MD5`, `SHA-256` and `SHA-512-256`, each with its `-sess`
/// variant, and the `auth` and `auth-int` qualities of protection. When a server
/// offers a list (`qop="auth,auth-int"`) the one sent back is `auth` if it is
/// among them: the response is computed for exactly one quality, and the header
/// names exactly that one.
final class DigestAuthChallenge {
  final String realm;
  final String nonce;
  final String? opaque;

  /// The `qop` directive as the server sent it: a list such as `auth,auth-int`.
  final String qop;

  /// Upper-case, `-SESS` suffix included.
  final String algorithm;

  /// Whether the server named an algorithm at all. Then the response says
  /// which one it used (RFC 7616 §3.4), and so it does for anything but MD5.
  final bool explicitAlgorithm;

  const DigestAuthChallenge({
    required this.realm,
    required this.nonce,
    this.qop = '',
    this.opaque,
    this.algorithm = 'MD5',
    this.explicitAlgorithm = false,
  });

  static const _supportedAlgorithms = {'MD5', 'SHA-256', 'SHA-512-256'};

  /// Returns null if [header] holds no Digest challenge this client can answer
  /// (it is Basic, there is no WWW-Authenticate header at all, the nonce is
  /// missing, or the algorithm or every quality of protection on offer is one
  /// it does not know). A header may carry several challenges, Basic ones
  /// included, as the server's choices in order of preference; the first
  /// Digest one that can be answered wins.
  static DigestAuthChallenge? parse(String? header) {
    if (header == null) return null;
    for (final directives in _digestChallenges(header)) {
      final nonce = directives['nonce'];
      if (nonce == null) continue;
      final algorithm = (directives['algorithm'] ?? 'MD5').toUpperCase();
      final base = algorithm.endsWith('-SESS') ? algorithm.substring(0, algorithm.length - 5) : algorithm;
      if (!_supportedAlgorithms.contains(base)) continue;
      final challenge = DigestAuthChallenge(
        realm: directives['realm'] ?? '',
        nonce: nonce,
        opaque: directives['opaque'],
        qop: directives['qop'] ?? '',
        algorithm: algorithm,
        explicitAlgorithm: directives.containsKey('algorithm'),
      );
      if (challenge.qop.isNotEmpty && challenge._offered.intersection(const {'auth', 'auth-int'}).isEmpty) continue;
      return challenge;
    }
    return null;
  }

  /// The directives of every `Digest` challenge in [header], in order. Reads
  /// quoted strings whole, so a comma or the word `Digest` inside a realm is
  /// not mistaken for the next directive or the next challenge.
  static List<Map<String, String>> _digestChallenges(String header) {
    final challenges = <Map<String, String>>[];
    Map<String, String>? current;
    final n = header.length;
    var i = 0;

    bool isBlank(String c) => c == ' ' || c == '\t' || c == '\r' || c == '\n';
    void skipBlanks() {
      while (i < n && isBlank(header[i])) {
        i++;
      }
    }

    while (true) {
      while (i < n && (header[i] == ',' || isBlank(header[i]))) {
        i++;
      }
      if (i >= n) break;
      final start = i;
      while (i < n && header[i] != '=' && header[i] != ',' && !isBlank(header[i])) {
        i++;
      }
      final word = header.substring(start, i);
      skipBlanks();
      if (i < n && header[i] == '=') {
        i++;
        skipBlanks();
        final value = StringBuffer();
        if (i < n && header[i] == '"') {
          i++;
          while (i < n && header[i] != '"') {
            if (header[i] == r'\' && i + 1 < n) i++;
            value.write(header[i]);
            i++;
          }
          i++; // the closing quote
        } else {
          while (i < n && header[i] != ',') {
            value.write(header[i]);
            i++;
          }
        }
        if (word.isNotEmpty) current?[word.toLowerCase()] = value.toString().trim();
      } else if (word.isNotEmpty) {
        // A bare word starts a challenge: its scheme.
        current = word.toLowerCase() == 'digest' ? <String, String>{} : null;
        if (current != null) challenges.add(current);
      }
    }
    return challenges;
  }

  Set<String> get _offered => {
        for (final q in qop.split(','))
          if (q.trim().isNotEmpty) q.trim().toLowerCase(),
      };

  /// `auth` when the server offers it, else `auth-int`; null when there is no
  /// `qop` at all (the RFC 2069 form, which has no `nc` and no `cnonce`).
  String? get selectedQop {
    final offered = _offered;
    if (offered.contains('auth')) return 'auth';
    if (offered.contains('auth-int')) return 'auth-int';
    return null;
  }

  bool get _isSess => algorithm.endsWith('-SESS');

  /// [cnonce] is injectable for testing against known RFC vectors; in
  /// production it's left null and a fresh random one is generated per call.
  /// [body] is the request body: only the `auth-int` quality covers it.
  String buildAuthorizationHeader({
    required String username,
    required String password,
    required String method,
    required String digestUri,
    List<int> body = const [],
    String? cnonce,
  }) {
    cnonce ??= _randomHex(16);
    const nc = '00000001';
    final qop = selectedQop;

    var ha1 = _hash('$username:$realm:$password');
    if (_isSess) ha1 = _hash('$ha1:$nonce:$cnonce');
    final ha2 = qop == 'auth-int' ? _hash('$method:$digestUri:${_hashBytes(body)}') : _hash('$method:$digestUri');
    final response = qop != null ? _hash('$ha1:$nonce:$nc:$cnonce:$qop:$ha2') : _hash('$ha1:$nonce:$ha2');

    final parts = {
      'username': username,
      'realm': realm,
      'nonce': nonce,
      'uri': digestUri,
      if (explicitAlgorithm || algorithm != 'MD5') 'algorithm': algorithm,
      'response': response,
      'opaque': ?opaque,
      'qop': ?qop,
      if (qop != null) 'nc': nc,
      // RFC 7616 §3.4.4: the session variants hash the cnonce in even without a qop.
      if (qop != null || _isSess) 'cnonce': cnonce,
    };

    const unquoted = {'nc', 'qop', 'algorithm'}; // tokens, not quoted-strings (RFC 2617 §3.2.2, RFC 7616 §3.4)
    final serialized = parts.entries.map((e) => unquoted.contains(e.key) ? '${e.key}=${e.value}' : '${e.key}="${_quote(e.value)}"');
    return 'Digest ${serialized.join(', ')}';
  }

  /// A quoted-string may hold a quote or a backslash only escaped (RFC 9110 §5.6.4).
  static String _quote(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  Hash get _hasher => switch (_isSess ? algorithm.substring(0, algorithm.length - 5) : algorithm) {
        'SHA-256' => sha256,
        'SHA-512-256' => sha512256,
        _ => md5,
      };

  String _hash(String input) => _hashBytes(utf8.encode(input));

  String _hashBytes(List<int> bytes) => _hasher.convert(bytes).toString();

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
