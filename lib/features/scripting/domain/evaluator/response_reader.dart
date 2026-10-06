import 'dart:convert';
import '../../../../core/utils/exact_json.dart';
import '../../../../core/utils/set_cookie.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import 'json_path_resolver.dart';

/// Lazily-decoded view of a response shared by assertions and extractors:
/// body text, tolerant JSON parse, case-insensitive header lookup.
final class ResponseReader {
  final ApiResponseEntity response;

  /// [web] says which platform's numbers the JSON is read with; only tests
  /// pass it.
  ResponseReader(this.response, {this._web = ExactJson.isWeb});

  final bool _web;

  late final String bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
  late final ({bool valid, Object? value}) _json = _parseJson();

  /// The body with its integers outside the exact range of a `num` kept as
  /// [BigInt]; null when there are none. See [jsonPath].
  late final Object? _exactJson = _json.valid ? ExactJson.decodeIfLarge(bodyText, web: _web) : null;

  bool get isJson => _json.valid;

  /// Value at [path] in the JSON body; `null` when the body isn't JSON or
  /// the path doesn't resolve.
  ///
  /// An integer that a `num` cannot hold exactly (above 2^53 on the web, above
  /// 64 bits elsewhere) comes back as a [BigInt] when [path] ends on it, so an
  /// id such as `1234567890123456789` is extracted as written instead of rounded.
  /// An object or array result keeps plain numbers: schema checks and
  /// structural comparisons are written for those.
  Object? jsonPath(String path) {
    if (!_json.valid) return null;
    final exact = _exactJson;
    if (exact != null) {
      final value = JsonPathResolver.resolve(exact, path);
      if (value is BigInt) return value;
    }
    return JsonPathResolver.resolve(_json.value, path);
  }

  /// The value of header [name]. `Set-Cookie[sid]` names one cookie of the
  /// response and gives just its value, which the joined header cannot.
  String? header(String name) {
    final trimmed = name.trim();
    final cookie = _cookieSelector.firstMatch(trimmed);
    if (cookie != null) return SetCookies.valueOf(setCookies, cookie[1]!);
    final wanted = trimmed.toLowerCase();
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  static final _cookieSelector = RegExp(r'^set-cookie\s*\[(.+)\]$', caseSensitive: false);

  /// The cookies the response sets, one `name=value; attributes` line each.
  late final List<String> setCookies = response.setCookies.isNotEmpty
      ? response.setCookies
      : SetCookies.split(header('set-cookie') ?? '');

  ({bool valid, Object? value}) _parseJson() {
    try {
      return (valid: true, value: jsonDecode(bodyText));
    } on FormatException {
      return (valid: false, value: null);
    }
  }

  /// Scalars print bare (so `42` matches an expected "42"); containers as
  /// compact JSON. A whole-number double prints without `.0`: the VM decodes
  /// `100.0` as a double and would print `100.0`, while the web build prints `100`.
  static String stringify(Object? value) => switch (value) {
        null => 'null',
        String s => s,
        double d when d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15 => d.toInt().toString(),
        BigInt() || num() || bool() => value.toString(),
        _ => jsonEncode(value),
      };
}
