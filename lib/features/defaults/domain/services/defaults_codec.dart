import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/entities/extractor_entity.dart';
import '../entities/default_variable.dart';
import '../entities/level_defaults.dart';

/// How the defaults of a collection or folder are written down. Two shapes of
/// the same data, both pure Dart (the CLI reads them too):
///
///  * **Columns** of `folder_defaults` and `collection_defaults`: text holding JSON.
///    `headers_json` is `{"v":1,"items":[{"key","value","enabled"}]}`, `variables_json`
///    the same with a `secret` flag on each item, `auth_json` the auth as
///    `RequestAuth.toJson()` writes it (`{}` while the folder sets none) and
///    `scripts_json` `{"v":1,"assertions":[...],"extractors":[...]}`.
///  * **Documents** (a workspace file, a Git doc): the keys `headers`, `variables`,
///    `auth` and `tests` (`{assertions, extractors}`) on the collection's or folder's
///    map, each present only when it holds something.
///
/// Reading is forgiving, because it runs on the send path and a damaged value must
/// not turn into a failed request: a column that is empty, `[]`, `{}` or not valid
/// JSON is an empty level, and an item of the wrong shape is skipped. A bare list
/// (what the columns default to) reads like `{"items": [...]}`. `v` is written so
/// a later format can be told apart; a newer one is read as far as it matches.
abstract final class DefaultsCodec {
  static const version = 1;

  // --- columns ------------------------------------------------------------------

  static String encodeHeaders(List<KeyValueItem> headers) =>
      jsonEncode({'v': version, 'items': headersToJson(headers)});

  static List<KeyValueItem> decodeHeaders(String? json) => headersFromJson(_items(_parse(json)));

  static String encodeVariables(List<DefaultVariable> variables) =>
      jsonEncode({'v': version, 'items': variablesToJson(variables)});

  static List<DefaultVariable> decodeVariables(String? json) => variablesFromJson(_items(_parse(json)));

  /// `{}` when [auth] is null (the folder sets none). An auth of type "inherit" is no auth either.
  static String encodeAuth(RequestAuth? auth) => jsonEncode(authToJson(auth) ?? const <String, Object?>{});

  static RequestAuth? decodeAuth(String? json) => authFromJson(_parse(json));

  static String encodeScripts(List<AssertionEntity> assertions, List<ExtractorEntity> extractors) => jsonEncode({
        'v': version,
        'assertions': ScriptsJsonCodec.assertionsToJson(assertions),
        'extractors': ScriptsJsonCodec.extractorsToJson(extractors),
      });

  static ({List<AssertionEntity> assertions, List<ExtractorEntity> extractors}) decodeScripts(String? json) {
    final map = _parse(json);
    final tests = map is Map ? map : const <String, Object?>{};
    return (
      assertions: ScriptsJsonCodec.assertionsFromJson(tests['assertions']),
      extractors: ScriptsJsonCodec.extractorsFromJson(tests['extractors']),
    );
  }

  // --- list forms (shared by the columns and the documents) ---------------------

  static List<Map<String, Object?>> headersToJson(List<KeyValueItem> headers) => [
        for (final h in headers) {'key': h.key, 'value': h.value, 'enabled': h.enabled},
      ];

  static List<KeyValueItem> headersFromJson(Object? list) => [
        for (final e in _maps(list))
          if (e['key'] is String)
            KeyValueItem(key: e['key'] as String, value: _text(e['value']), enabled: e['enabled'] != false),
      ];

  /// `secret` is written only when it is set, so a plain variable stays as small as a header.
  static List<Map<String, Object?>> variablesToJson(List<DefaultVariable> variables) => [
        for (final v in variables)
          {'key': v.key, 'value': v.value, if (v.isSecret) 'secret': true, 'enabled': v.enabled},
      ];

  static List<DefaultVariable> variablesFromJson(Object? list) => [
        for (final e in _maps(list))
          if (e['key'] is String)
            DefaultVariable(
              key: e['key'] as String,
              value: _text(e['value']),
              isSecret: e['secret'] == true,
              enabled: e['enabled'] != false,
            ),
      ];

  /// Null (nothing to write) for no auth and for "inherit".
  static Map<String, Object?>? authToJson(RequestAuth? auth) =>
      auth == null || auth.type == AuthType.inherit ? null : auth.toJson();

  /// Null for an empty map, anything that is not a map, a map whose `type` is not an auth type
  /// (a damaged value then inherits instead of quietly switching authentication off), and a type of
  /// "inherit".
  static RequestAuth? authFromJson(Object? value) {
    if (value is! Map || value.isEmpty) return null;
    if (!AuthType.values.any((t) => t.name == value['type'])) return null;
    final auth = RequestAuth.fromJson(Map<String, dynamic>.from(value));
    return auth.type == AuthType.inherit ? null : auth;
  }

  // --- documents ----------------------------------------------------------------

  /// What [defaults] adds to a collection's or folder's document. A collection's own `variables`
  /// and `auth` are written by their own mappers, so they are left out with [includeVariablesAndAuth] off.
  static Map<String, Object?> toDoc(LevelDefaults defaults, {bool includeVariablesAndAuth = true}) {
    final auth = includeVariablesAndAuth ? authToJson(defaults.auth) : null;
    return {
      if (defaults.headers.isNotEmpty) 'headers': headersToJson(defaults.headers),
      if (includeVariablesAndAuth && defaults.variables.isNotEmpty) 'variables': variablesToJson(defaults.variables),
      'auth': ?auth,
      if (defaults.hasTests)
        'tests': {
          'assertions': ScriptsJsonCodec.assertionsToJson(defaults.assertions),
          'extractors': ScriptsJsonCodec.extractorsToJson(defaults.extractors),
        },
    };
  }

  /// The levels [toDoc] wrote, from [doc] (a collection's or folder's map). Keys that are absent
  /// are empty. The collection's own `variables` are not read, they are not defaults of this codec.
  static LevelDefaults fromDoc(Map<String, Object?> doc, {bool includeVariablesAndAuth = true}) {
    final tests = doc['tests'];
    final testMap = tests is Map ? tests : const <String, Object?>{};
    return LevelDefaults(
      headers: headersFromJson(doc['headers']),
      variables: includeVariablesAndAuth ? variablesFromJson(doc['variables']) : const [],
      auth: includeVariablesAndAuth ? authFromJson(doc['auth']) : null,
      assertions: ScriptsJsonCodec.assertionsFromJson(testMap['assertions']),
      extractors: ScriptsJsonCodec.extractorsFromJson(testMap['extractors']),
    );
  }

  // --- helpers ------------------------------------------------------------------

  static Object? _parse(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }

  /// The list of a column: `{"items": [...]}`, or the bare list the column defaults to.
  static Object? _items(Object? decoded) => decoded is Map ? decoded['items'] : decoded;

  static Iterable<Map<String, dynamic>> _maps(Object? list) =>
      list is List ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)) : const [];

  static String _text(Object? value) => value == null ? '' : '$value';
}
