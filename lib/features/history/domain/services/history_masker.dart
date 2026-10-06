import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_fields.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../response_tools/domain/services/resolved_secrets.dart';

/// Everything History stores passes through here first. A value that only
/// references a `{{variable}}` is kept (it is a reference, and keeping it is
/// what lets a request be sent again later); a literal credential becomes
/// [SecretMasker.mask]. It builds on the helpers the API docs and the Git sync
/// already use, so "what counts as a secret" has one answer in the app.
abstract final class HistoryMasker {
  /// A text is masked in a window this much longer than what is kept, then cut
  /// to size: a credential that straddles the cut is masked whole instead of
  /// being stored half.
  static const cutMargin = 4096;

  static final _numberPair = RegExp(r'("(?:[^"\\]|\\.)*")(\s*:\s*)(-?\d+(?:\.\d+)?)(?![\w.])');

  static String url(String url) {
    var masked = SecretMasker.maskUrl(url);
    // Names only SecretNames knows (a bare `key`, `sig`) are masked by it as well.
    masked = _maskQuery(masked);
    return masked;
  }

  static String _maskQuery(String url) {
    final question = url.indexOf('?');
    if (question == -1) return url;
    final hash = url.indexOf('#', question);
    final end = hash == -1 ? url.length : hash;
    final pairs = url.substring(question + 1, end).split('&').map((pair) {
      final equals = pair.indexOf('=');
      if (equals == -1) return pair;
      final name = _decode(pair.substring(0, equals));
      final value = pair.substring(equals + 1);
      return '${pair.substring(0, equals + 1)}${_named(name, value, SecretNames.isSecretQuery(name))}';
    }).join('&');
    return '${url.substring(0, question + 1)}$pairs${url.substring(end)}';
  }

  static List<KeyValueItem> headers(List<KeyValueItem> items) => [
        for (final item in items)
          item.copyWith(value: _named(item.key, item.value, SecretNames.isSecretHeader(item.key))),
      ];

  static List<KeyValueItem> queryParams(List<KeyValueItem> items) => [
        for (final item in items)
          item.copyWith(value: _named(item.key, item.value, SecretNames.isSecretQuery(item.key))),
      ];

  /// A file row holds the path of its file, not a value, so it is kept as it is.
  static List<KeyValueItem> formFields(List<KeyValueItem> items) => [
        for (final item in items)
          item.isFile ? item : item.copyWith(value: _named(item.key, item.value, SecretNames.looksSecretKey(item.key))),
      ];

  /// The auth with its credentials masked. The OAuth 2.0 tokens are blanked, not
  /// masked: the app fetched and cached them, so there is nothing to type back.
  static RequestAuth auth(RequestAuth auth) {
    final json = auth.toJson();
    for (final key in json.keys.toList()) {
      final value = json[key];
      if (value is! String || value.isEmpty) continue;
      if (key == 'oauth2AccessToken' || key == 'oauth2RefreshToken') {
        json[key] = '';
      } else if (SecretFields.authKeys.contains(key)) {
        json[key] = SecretNames.hasLiteralSecret(value) ? SecretMasker.mask : value;
      } else if (key == 'jwtPayload') {
        json[key] = text(value);
      } else {
        // Not a credential by name, but a token or `user:pass@` URL can sit in any field.
        json[key] = SecretMasker.maskValue('value', value);
      }
    }
    json['oauth2TokenExpiry'] = null;
    return RequestAuth.fromJson(json);
  }

  /// A request or response body of any format: credentials by the name they sit
  /// under, token shapes anywhere, and a bare number under a PIN or OTP name.
  static String text(String body) {
    if (body.isEmpty) return body;
    final masked = SecretMasker.maskBody(body);
    return masked.replaceAllMapped(_numberPair, (m) {
      final quoted = m[1]!;
      final name = quoted.substring(1, quoted.length - 1);
      return SecretNames.isNumericSecretKey(name) ? '$quoted${m[2]}"${SecretMasker.mask}"' : m[0]!;
    });
  }

  /// [body] masked and then cut to [maxBytes] of UTF-8, with whether anything was
  /// cut off. [secretValues] are resolved secrets to hide wherever they appear.
  static ({String text, bool truncated}) cappedText(String body, int maxBytes, {List<String> secretValues = const []}) {
    final windowCut = body.length > maxBytes + cutMargin;
    final window = windowCut ? body.substring(0, maxBytes + cutMargin) : body;
    final masked = text(ResolvedSecrets.mask(window, secretValues));
    final end = _cutIndex(masked, maxBytes);
    return (text: end == masked.length ? masked : masked.substring(0, end), truncated: windowCut || end < masked.length);
  }

  /// The longest prefix of [text] that is at most [maxBytes] long in UTF-8. A surrogate pair is
  /// never split: Flutter's text engine rejects a lone surrogate.
  static int _cutIndex(String text, int maxBytes) {
    var bytes = 0;
    var i = 0;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      final pair = unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length;
      final size = unit < 0x80
          ? 1
          : unit < 0x800
              ? 2
              : pair
                  ? 4
                  : 3;
      if (bytes + size > maxBytes) break;
      bytes += size;
      i += pair ? 2 : 1;
    }
    return i;
  }

  /// [value] under [name]: masked when the name says it is a credential
  /// ([secretName] is what `SecretNames` decides, [SecretMasker] decides too),
  /// or when the value itself is one. `Bearer`, `Basic` and the like stay.
  static String _named(String name, String value, bool secretName) {
    if (value.isEmpty || SecretNames.isTemplateOnly(value)) return value;
    final lookup = secretName && !SecretMasker.isSensitiveName(name) ? 'authorization' : name;
    return SecretMasker.maskValue(lookup, value);
  }

  static String _decode(String name) {
    try {
      return Uri.decodeQueryComponent(name);
    } catch (_) {
      return name;
    }
  }
}
