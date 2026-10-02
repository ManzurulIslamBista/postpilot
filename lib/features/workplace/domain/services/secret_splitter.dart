import 'dart:convert';
import '../../../git_sync/domain/services/secret_fields.dart';

/// A workspace document without its secrets, and the secrets by themselves.
final class SecretSplit {
  final Map<String, dynamic> publicDoc;

  /// Where each secret came from (see [SecretSplitter]) to its value.
  final Map<String, String> secrets;
  const SecretSplit(this.publicDoc, this.secrets);
}

/// Keeps passwords and tokens out of `workspace.json`, which is what gets
/// pushed to Git and shared with a team, by moving them to a file that stays
/// on this device (`workspace.local.json`).
///
/// Works on the decoded workspace document. A value is a secret when:
///  * it is an environment or global variable marked secret,
///  * it is a collection variable whose name looks like a credential
///    (`api_key`, `db_password`),
///  * it is a credential field of a collection's or request's auth
///    (`bearerToken`, `basicPassword`, `oauth2ClientSecret`...).
///
/// Secrets are addressed by names, not ids (ids change on every restore):
/// `env/<environment>/<variable>`, `global/<variable>`,
/// `cvar/<collection>/<variable>`, `cauth/<collection>/<field>` and
/// `rauth/<collection>/<request>/<field>`. Two siblings with the same name get
/// `#2`, `#3` so they stay apart.
abstract final class SecretSplitter {
  static const localFileVersion = 1;

  static SecretSplit split(Map<String, dynamic> doc) {
    final copy = _deepCopy(doc) as Map<String, dynamic>;
    final secrets = <String, String>{};
    _walk(copy, (key, value, blank) {
      if (value.isEmpty) return;
      secrets[key] = value;
      blank();
    });
    return SecretSplit(copy, secrets);
  }

  /// [doc] with each secret that is blank in it filled from [secrets]. A value
  /// that is already set (a teammate's shared default) is left alone.
  static Map<String, dynamic> merge(Map<String, dynamic> doc, Map<String, String> secrets) {
    if (secrets.isEmpty) return doc;
    final copy = _deepCopy(doc) as Map<String, dynamic>;
    _walk(copy, (key, value, _) {}, fill: secrets);
    return copy;
  }

  // --- the walk ---------------------------------------------------------------

  /// Visits every secret slot of [doc]. For each, [onSecret] gets its key, its
  /// current value and a function that blanks it. With [fill], a blank slot is
  /// set from the map instead.
  static void _walk(
    Map<String, dynamic> doc,
    void Function(String key, String value, void Function() blank) onSecret, {
    Map<String, String>? fill,
  }) {
    void slot(Map<String, dynamic> holder, String field, String key) {
      final current = holder[field];
      final blank = current == null || (current is String && current.isEmpty);
      if (fill != null) {
        final filled = fill[key];
        if (blank && filled != null && filled.isNotEmpty) holder[field] = filled;
        return;
      }
      if (current is String && current.isNotEmpty) {
        onSecret(key, current, () => holder[field] = '');
      }
    }

    String unique(Map<String, int> seen, String name) {
      final n = (seen[name] ?? 0) + 1;
      seen[name] = n;
      return n == 1 ? name : '$name#$n';
    }

    final envSeen = <String, int>{};
    for (final env in _maps(doc['environments'])) {
      final envName = unique(envSeen, '${env['name'] ?? ''}');
      final varSeen = <String, int>{};
      for (final v in _maps(env['variables'])) {
        final name = unique(varSeen, '${v['key'] ?? ''}');
        if (v['secret'] == true) slot(v, 'value', 'env/$envName/$name');
      }
    }
    final globalSeen = <String, int>{};
    for (final g in _maps(doc['globals'])) {
      final name = unique(globalSeen, '${g['key'] ?? ''}');
      if (g['secret'] == true) slot(g, 'value', 'global/$name');
    }
    final collectionSeen = <String, int>{};
    for (final c in _maps(doc['collections'])) {
      final cName = unique(collectionSeen, '${c['name'] ?? ''}');
      final cvarSeen = <String, int>{};
      for (final v in _maps(c['variables'])) {
        final name = unique(cvarSeen, '${v['key'] ?? ''}');
        if (SecretFields.looksSecretKey('${v['key'] ?? ''}')) slot(v, 'value', 'cvar/$cName/$name');
      }
      final cAuth = c['auth'];
      if (cAuth is Map<String, dynamic>) {
        for (final field in SecretFields.authKeys) {
          if (cAuth.containsKey(field)) slot(cAuth, field, 'cauth/$cName/$field');
        }
      }
      final reqSeen = <String, int>{};
      for (final r in _maps(c['requests'])) {
        final rName = unique(reqSeen, '${r['name'] ?? ''}');
        final rAuth = r['auth'];
        if (rAuth is Map<String, dynamic>) {
          for (final field in SecretFields.authKeys) {
            if (rAuth.containsKey(field)) slot(rAuth, field, 'rauth/$cName/$rName/$field');
          }
        }
      }
    }
  }

  static Iterable<Map<String, dynamic>> _maps(Object? list) =>
      list is List ? list.whereType<Map<String, dynamic>>() : const [];

  static Object? _deepCopy(Object? v) => switch (v) {
        Map<dynamic, dynamic>() => {for (final e in v.entries) '${e.key}': _deepCopy(e.value)},
        List<dynamic>() => [for (final e in v) _deepCopy(e)],
        _ => v,
      };

  // --- the local file -----------------------------------------------------------

  static String encodeLocal(Map<String, String> secrets) => const JsonEncoder.withIndent('  ').convert({
        'version': localFileVersion,
        'notice': 'Secrets of this workspace, kept on this device only. Do not share or commit this file.',
        'secrets': secrets,
      });

  /// An unreadable or missing file means no secrets, never an error: the
  /// workspace must still open.
  static Map<String, String> decodeLocal(String? text) {
    if (text == null || text.trim().isEmpty) return const {};
    try {
      final json = jsonDecode(text);
      final secrets = json is Map ? json['secrets'] : null;
      if (secrets is! Map) return const {};
      return {
        for (final e in secrets.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } on FormatException {
      return const {};
    }
  }
}
