import 'dart:convert';

import '../../../../core/enums/auth_type.dart';
import '../../../defaults/domain/services/defaults_codec.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../domain/services/secret_fields.dart';
import '../../domain/services/secret_names.dart';
import '../../domain/services/secret_text.dart';

/// Canonical forms of the values that recur across doc kinds. Each function
/// takes what a doc may hold (absent, null, or the right JSON type) and returns
/// exactly what a database read produces, so equal states give equal docs no
/// matter who wrote them. A value of the wrong JSON type throws a [TypeError].
abstract final class DocValues {
  /// The description and tags of [data]. With [keepingSecretsOf] (the local,
  /// already canonical data) a description whose credentials were blanked gets
  /// them back, if nothing else in it changed.
  static Map<String, Object?> notes(Map<String, Object?> data, {Map<String, Object?>? keepingSecretsOf}) {
    var description = data['description'] as String? ?? '';
    final localDescription = keepingSecretsOf?['description'];
    if (localDescription is String) description = SecretText.restoreNote(description, localDescription);
    final tagList = tags(data['tags']);
    return {
      if (description.isNotEmpty) 'description': description,
      if (tagList.isNotEmpty) 'tags': tagList,
    };
  }

  /// Normalised and ordered like `EntityTagsDao` stores and returns tags, so a
  /// doc and a database read of the same tags agree.
  static List<String> tags(Object? value) {
    final seen = <String>{};
    final clean = <String>[];
    for (final raw in (value as List? ?? const [])) {
      final tag = (raw as String).trim();
      if (tag.isNotEmpty && seen.add(tag.toLowerCase())) clean.add(tag);
    }
    return clean..sort((a, b) {
      final byLower = a.toLowerCase().compareTo(b.toLowerCase());
      return byLower != 0 ? byLower : a.compareTo(b);
    });
  }

  /// Headers, parameters and form fields. With [keepingSecretsOf] (the local,
  /// already canonical list) and [isSecret], an item whose name [isSecret]
  /// accepts and whose value is empty keeps the local value of the same name,
  /// matching repeated names by occurrence.
  static List<Map<String, Object?>> keyValues(
    Object? value, {
    Object? keepingSecretsOf,
    bool Function(String name)? isSecret,
  }) {
    final items = [
      for (final item in (value as List? ?? const []))
        {
          'key': (item as Map)['key'] as String,
          'value': item['value'] as String? ?? '',
          'enabled': item['enabled'] as bool? ?? true,
          // A form-data file row is only the reference to its file (see KeyValueItem.toJson).
          if (item['kind'] == 'file') ..._fileKeys(item),
        },
    ];
    if (isSecret == null || keepingSecretsOf is! List) return items;
    return _keepLocalValues(items, keepingSecretsOf, isSecret);
  }

  /// A request URL. With [keepingSecretsOf] (the local URL) the blanked
  /// password and secret query values of the URL get their local values back.
  static String url(Object? value, {Object? keepingSecretsOf}) {
    final url = value as String? ?? '';
    return keepingSecretsOf is String ? SecretText.restoreUrl(url, keepingSecretsOf) : url;
  }

  /// A body text (raw body, GraphQL query or variables), [fallback] when
  /// absent. With [keepingSecretsOf] (the local text) blanked secret values
  /// get their local values back.
  static String jsonText(Object? value, {required String fallback, Object? keepingSecretsOf}) {
    final text = value as String? ?? fallback;
    return keepingSecretsOf is String ? SecretText.restoreBody(text, keepingSecretsOf) : text;
  }

  /// A request's assertions. With [keepingSecretsOf] (the local, already
  /// canonical list) blanked expected values get their local values back.
  static List<Object?> assertions(Object? value, {Object? keepingSecretsOf}) {
    final items = jsonList(value);
    return keepingSecretsOf is List ? SecretFields.restoreAssertions(items, keepingSecretsOf) : items;
  }

  /// What a file row adds to `{key, value, enabled}`: `kind`, and the name and type when they were set.
  static Map<String, Object?> _fileKeys(Map item) => {
        'kind': 'file',
        if (item['fileName'] is String && (item['fileName'] as String).isNotEmpty) 'fileName': item['fileName'],
        if (item['contentType'] is String && (item['contentType'] as String).isNotEmpty) 'contentType': item['contentType'],
      };

  static List<KeyValueItem> keyValueItems(Object? canonicalKeyValues) => [
        for (final item in canonicalKeyValues as List) KeyValueItem.tryFromJson(item)!,
      ];

  static String enumName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback).name;

  static List<Object?> jsonList(Object? value) => List<Object?>.of(value as List? ?? const []);

  static Map<String, Object?> jsonMap(Object? value) => Map<String, Object?>.from(value as Map? ?? const {});

  /// A request's settings as the doc holds them. With [keepingSecretsOf] (the local, already canonical settings) the
  /// credentials of its flow that the target blanked (what a poll-until condition expects, what a run-if compares a
  /// credential-named variable with) get their local values back, like those of a request's assertions.
  static Map<String, Object?> requestSettings(Object? value, {Object? keepingSecretsOf}) {
    final settings = jsonMap(value);
    final flow = settings['flow'];
    final localFlow = keepingSecretsOf is Map ? keepingSecretsOf['flow'] : null;
    if (flow is! Map || localFlow is! Map) return settings;
    final restored = Map<String, Object?>.from(flow);
    final poll = flow['poll'];
    final localPoll = localFlow['poll'];
    if (poll is Map && localPoll is Map && poll['until'] is List && localPoll['until'] is List) {
      restored['poll'] = {
        ...poll,
        'until': SecretFields.restoreAssertions(List<Object?>.of(poll['until'] as List), List<Object?>.of(localPoll['until'] as List)),
      };
    }
    final runIf = flow['runIf'];
    final localRunIf = localFlow['runIf'];
    if (runIf is Map && localRunIf is Map && runIf['all'] is List && localRunIf['all'] is List) {
      restored['runIf'] = {
        ...runIf,
        'all': SecretFields.restoreConditions(List<Object?>.of(runIf['all'] as List), List<Object?>.of(localRunIf['all'] as List)),
      };
    }
    return {...settings, 'flow': restored};
  }

  /// A stored JSON column that no longer parses counts as empty, so one bad
  /// row cannot block syncing the whole collection.
  static List<Object?> decodeList(String? json) {
    try {
      final decoded = jsonDecode(json ?? '[]');
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  static Map<String, Object?> decodeMap(String? json) {
    try {
      final decoded = jsonDecode(json ?? '{}');
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Collection variables sorted by key, ties kept in their given order.
  /// With [keepingSecretsOf] (the local, already canonical variables) a
  /// secret-looking key with an empty value keeps the local value of the same
  /// key, matching repeated keys by occurrence.
  static List<Map<String, Object?>> variables(Object? value, {Object? keepingSecretsOf}) {
    final items = keyValues(value);
    final order = [for (var i = 0; i < items.length; i++) i]..sort((a, b) {
        final byKey = (items[a]['key'] as String).compareTo(items[b]['key'] as String);
        return byKey != 0 ? byKey : a.compareTo(b);
      });
    final sorted = [for (final i in order) items[i]];
    if (keepingSecretsOf is! List) return sorted;
    return _keepLocalValues(sorted, keepingSecretsOf, SecretFields.looksSecretKey);
  }

  /// [items] where an empty value under a name that [isSecret] takes the value
  /// [local] has for the same name (matched by occurrence).
  static List<Map<String, Object?>> _keepLocalValues(
    List<Map<String, Object?>> items,
    List<Object?> local,
    bool Function(String name) isSecret,
  ) {
    final localValues = <String, List<String>>{};
    for (final item in local) {
      (localValues[(item as Map)['key'] as String] ??= []).add(item['value'] as String);
    }
    final occurrences = <String, int>{};
    return [
      for (final item in items) _keepLocalValue(item, localValues, occurrences, isSecret),
    ];
  }

  static Map<String, Object?> _keepLocalValue(
    Map<String, Object?> item,
    Map<String, List<String>> localValues,
    Map<String, int> occurrences,
    bool Function(String name) isSecret,
  ) {
    final key = item['key'] as String;
    final nth = occurrences[key] ?? 0;
    occurrences[key] = nth + 1;
    if (item['value'] != '' || !isSecret(key)) return item;
    final local = localValues[key];
    if (local == null || nth >= local.length || local[nth].isEmpty) return item;
    return {...item, 'value': local[nth]};
  }

  /// A request's auth as `RequestAuth.toJson()` writes it. No auth at all is
  /// the request default, "inherit".
  static Map<String, Object?> requestAuth(Object? value, {Object? keepingSecretsOf}) =>
      _authMap(value == null ? const RequestAuth() : parseAuth(value), keepingSecretsOf);

  /// A collection's default auth, or null when none is set. "No auth" and no
  /// row at all mean the same to the app, so both are null, unless the auth carries a re-login setting
  /// ("on 401 run the login request"), which has to travel even when requests send no auth of their own.
  static Map<String, Object?>? collectionAuth(Object? value, {Object? keepingSecretsOf}) {
    if (value == null) return null;
    final auth = parseAuth(value);
    return auth.type == AuthType.none && auth.relogin == null ? null : _authMap(auth, keepingSecretsOf);
  }

  static RequestAuth parseAuth(Object value) => RequestAuth.fromJson(Map<String, dynamic>.from(value as Map));

  /// What a collection or folder passes down to its requests, as the keys its doc holds them under:
  /// `headers`, `tests` and, on a [folder], `variables` and `auth`; each present only when it holds
  /// something (a collection's own variables and auth have their own mappers). With [keepingSecretsOf]
  /// (the local, already canonical data) credentials the target left blank get their local values back.
  static Map<String, Object?> defaults(
    Map<String, Object?> data, {
    Map<String, Object?>? keepingSecretsOf,
    required bool folder,
  }) {
    final headers = keyValues(
      data['headers'],
      keepingSecretsOf: keepingSecretsOf?['headers'],
      isSecret: SecretNames.isSecretHeader,
    );
    final variables = folder
        ? folderVariables(data['variables'], keepingSecretsOf: keepingSecretsOf?['variables'])
        : const <Map<String, Object?>>[];
    final auth = folder ? folderAuth(data['auth'], keepingSecretsOf: keepingSecretsOf?['auth']) : null;
    final tests = defaultTests(data['tests'], keepingSecretsOf: keepingSecretsOf?['tests']);
    return {
      if (headers.isNotEmpty) 'headers': headers,
      if (variables.isNotEmpty) 'variables': variables,
      'auth': ?auth,
      'tests': ?tests,
    };
  }

  /// A folder's variables, sorted by key like a collection's (ties keep their order), `secret: true`
  /// only where it is marked. With [keepingSecretsOf] (the local, already canonical list) a secret one
  /// (marked, or named like a credential) whose value is empty keeps the local value of the same
  /// name, matching repeated names by occurrence.
  static List<Map<String, Object?>> folderVariables(Object? value, {Object? keepingSecretsOf}) {
    final items = [
      for (final item in (value as List? ?? const []))
        {
          'key': (item as Map)['key'] as String,
          'value': item['value'] as String? ?? '',
          if (item['secret'] == true) 'secret': true,
          'enabled': item['enabled'] as bool? ?? true,
        },
    ];
    final order = [for (var i = 0; i < items.length; i++) i]..sort((a, b) {
        final byKey = (items[a]['key'] as String).compareTo(items[b]['key'] as String);
        return byKey != 0 ? byKey : a.compareTo(b);
      });
    final sorted = [for (final i in order) items[i]];
    if (keepingSecretsOf is! List) return sorted;
    final marked = {
      for (final item in [...sorted, ...keepingSecretsOf.whereType<Map>()])
        if (item['secret'] == true) item['key'] as String,
    };
    return _keepLocalValues(sorted, keepingSecretsOf, (name) => marked.contains(name) || SecretFields.looksSecretKey(name));
  }

  /// A folder's auth, or null when it sets none (absent, empty, or "inherit"). "No Auth" is a setting
  /// on a folder (it switches off what is inherited), unlike on a collection, where it is the same as none.
  static Map<String, Object?>? folderAuth(Object? value, {Object? keepingSecretsOf}) {
    final auth = DefaultsCodec.authFromJson(value);
    return auth == null ? null : _authMap(auth, keepingSecretsOf);
  }

  /// The tests a collection or folder passes down (`{assertions, extractors}`), null when there are none.
  /// With [keepingSecretsOf] (the local, already canonical tests) blanked expected values get their
  /// local values back.
  static Map<String, Object?>? defaultTests(Object? value, {Object? keepingSecretsOf}) {
    final tests = value is Map ? value : const <String, Object?>{};
    final assertionList = assertions(
      tests['assertions'],
      keepingSecretsOf: keepingSecretsOf is Map ? keepingSecretsOf['assertions'] : null,
    );
    final extractorList = jsonList(tests['extractors']);
    if (assertionList.isEmpty && extractorList.isEmpty) return null;
    return {'assertions': assertionList, 'extractors': extractorList};
  }

  /// Credentials that the target leaves empty keep their local value.
  static Map<String, Object?> _authMap(RequestAuth auth, Object? local) {
    final map = Map<String, Object?>.from(auth.toJson());
    if (local is Map) {
      for (final key in SecretFields.authKeys) {
        if (_isBlank(map[key]) && !_isBlank(local[key])) map[key] = local[key];
      }
    }
    return map;
  }

  static bool _isBlank(Object? value) => value == null || value == '';
}
