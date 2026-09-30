import 'dart:convert';

import '../../../../core/enums/auth_type.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../domain/services/secret_fields.dart';

/// Canonical forms of the values that recur across doc kinds. Each function
/// takes what a doc may hold (absent, null, or the right JSON type) and returns
/// exactly what a database read produces, so equal states give equal docs no
/// matter who wrote them. A value of the wrong JSON type throws a [TypeError].
abstract final class DocValues {
  static Map<String, Object?> notes(Map<String, Object?> data) {
    final description = data['description'] as String? ?? '';
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

  static List<Map<String, Object?>> keyValues(Object? value) => [
        for (final item in (value as List? ?? const []))
          {
            'key': (item as Map)['key'] as String,
            'value': item['value'] as String? ?? '',
            'enabled': item['enabled'] as bool? ?? true,
          },
      ];

  static List<KeyValueItem> keyValueItems(Object? canonicalKeyValues) => [
        for (final item in canonicalKeyValues as List)
          KeyValueItem(key: item['key'] as String, value: item['value'] as String, enabled: item['enabled'] as bool),
      ];

  static String enumName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback).name;

  static List<Object?> jsonList(Object? value) => List<Object?>.of(value as List? ?? const []);

  static Map<String, Object?> jsonMap(Object? value) => Map<String, Object?>.from(value as Map? ?? const {});

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

    final localValues = <String, List<String>>{};
    for (final variable in keepingSecretsOf) {
      (localValues[variable['key'] as String] ??= []).add(variable['value'] as String);
    }
    final occurrences = <String, int>{};
    return [
      for (final variable in sorted) _keepLocalValue(variable, localValues, occurrences),
    ];
  }

  static Map<String, Object?> _keepLocalValue(
    Map<String, Object?> variable,
    Map<String, List<String>> localValues,
    Map<String, int> occurrences,
  ) {
    final key = variable['key'] as String;
    final nth = occurrences[key] ?? 0;
    occurrences[key] = nth + 1;
    if (variable['value'] != '' || !SecretFields.looksSecretKey(key)) return variable;
    final local = localValues[key];
    if (local == null || nth >= local.length || local[nth].isEmpty) return variable;
    return {...variable, 'value': local[nth]};
  }

  /// A request's auth as `RequestAuth.toJson()` writes it. No auth at all is
  /// the request default, "inherit".
  static Map<String, Object?> requestAuth(Object? value, {Object? keepingSecretsOf}) =>
      _authMap(value == null ? const RequestAuth() : parseAuth(value), keepingSecretsOf);

  /// A collection's default auth, or null when none is set. "No auth" and no
  /// row at all mean the same to the app, so both are null.
  static Map<String, Object?>? collectionAuth(Object? value, {Object? keepingSecretsOf}) {
    if (value == null) return null;
    final auth = parseAuth(value);
    return auth.type == AuthType.none ? null : _authMap(auth, keepingSecretsOf);
  }

  static RequestAuth parseAuth(Object value) => RequestAuth.fromJson(Map<String, dynamic>.from(value as Map));

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
