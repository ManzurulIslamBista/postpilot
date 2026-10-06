import 'dart:convert';
import '../../../../core/errors/app_exception.dart';
import '../../../git_sync/domain/services/secret_names.dart';

/// One entry of a Postman environment or globals file.
final class PostmanEnvironmentVariable {
  final String key;
  final String value;
  final bool enabled;
  final bool isSecret;
  const PostmanEnvironmentVariable({required this.key, required this.value, required this.enabled, required this.isSecret});
}

final class ParsedPostmanEnvironment {
  /// The environment's name; a globals file has none of its own.
  final String name;

  /// A `*_globals.json` / `*.postman_globals.json` file: its variables are global ones, not an environment.
  final bool isGlobals;
  final List<PostmanEnvironmentVariable> variables;

  /// Entries that could not be imported (no key, or a key already used earlier in the file), with why.
  final List<String> skipped;

  const ParsedPostmanEnvironment({
    required this.name,
    required this.isGlobals,
    required this.variables,
    this.skipped = const [],
  });
}

/// Parses an exported Postman environment (`{"name": ..., "values": [{key, value, enabled, type}]}`) or
/// globals file (the same shape with `_postman_variable_scope: "globals"`).
///
/// `type: "secret"` marks a secret, and so does a name that looks like one
/// (`token`, `api_key`, `client_secret` ...), because an export routinely holds
/// a credential in a plain variable. A disabled value is imported disabled, so
/// nothing is lost and nothing is silently switched on.
abstract final class PostmanEnvironmentParser {
  static ParsedPostmanEnvironment parse(String json) {
    final Object? root = jsonDecode(json.replaceFirst('﻿', '').trim());
    if (root is! Map || root['values'] is! List) {
      throw const ImportException('this JSON is not a Postman environment (expected an object with a "values" list).');
    }
    final name = root['name'];
    final variables = <PostmanEnvironmentVariable>[];
    final skipped = <String>[];
    final seen = <String>{};
    final values = root['values'] as List;
    for (var i = 0; i < values.length; i++) {
      final entry = values[i];
      final key = entry is Map ? entry['key'] : null;
      if (entry is! Map || key is! String || key.trim().isEmpty) {
        skipped.add('Entry ${i + 1} has no variable name, so it was not imported.');
        continue;
      }
      if (!seen.add(key)) {
        skipped.add('Variable "$key" appears more than once; only its first value was imported.');
        continue;
      }
      variables.add(
        PostmanEnvironmentVariable(
          key: key,
          value: _text(entry['value']),
          enabled: entry['enabled'] != false,
          isSecret: entry['type'] == 'secret' || SecretNames.looksSecretKey(key),
        ),
      );
    }
    return ParsedPostmanEnvironment(
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'Imported environment',
      isGlobals: root['_postman_variable_scope'] == 'globals',
      variables: variables,
      skipped: skipped,
    );
  }

  /// A value is text in the export, but a hand-edited file may hold a number or boolean.
  static String _text(Object? value) => switch (value) {
    null => '',
    String() => value,
    _ => jsonEncode(value),
  };
}
