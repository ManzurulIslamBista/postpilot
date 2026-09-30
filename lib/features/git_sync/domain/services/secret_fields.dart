import '../entities/sync_doc.dart';

/// Which fields hold credentials and must not be committed unless the
/// user opted in (`GitLink.includeSecrets`).
abstract final class SecretFields {
  /// Keys of `RequestAuth.toJson()` that carry credentials or live tokens.
  static const authKeys = {
    'apiKeyValue',
    'bearerToken',
    'basicPassword',
    'awsSecretKey',
    'awsSessionToken',
    'jwtSecret',
    'oauth2ClientSecret',
    'oauth2Password',
    'oauth2AccessToken',
    'oauth2RefreshToken',
    'oauth2TokenExpiry',
  };

  static final _secretKeyName = RegExp(
    r'(token|secret|password|passwd|pwd|api[_-]?key|apikey|private[_-]?key|credential)',
    caseSensitive: false,
  );

  /// Collection variables whose key looks like a credential get an empty
  /// value in committed files.
  static bool looksSecretKey(String key) => _secretKeyName.hasMatch(key);

  /// [auth] (a `RequestAuth.toJson()` map) without its credential keys.
  static Map<String, Object?> stripAuth(Map<String, Object?> auth) => {
        for (final e in auth.entries)
          if (!authKeys.contains(e.key)) e.key: e.value,
      };

  /// [doc] without credentials: its `auth` map loses [authKeys] and, on the
  /// collection doc, `variables` whose key [looksSecretKey] get an empty value.
  /// Idempotent, so applying it to an already stripped doc changes nothing.
  static SyncDoc stripDoc(SyncDoc doc) {
    final data = {...doc.data};
    final auth = data['auth'];
    if (auth is Map) data['auth'] = stripAuth(Map<String, Object?>.from(auth));
    final variables = data['variables'];
    if (doc.kind == SyncKind.collection) {
      if (variables is List) {
        data['variables'] = [for (final variable in variables) _blankIfSecret(variable)];
      } else if (variables is Map) {
        data['variables'] = {
          for (final e in variables.entries)
            '${e.key}': looksSecretKey('${e.key}') ? _blankValue(e.value) : e.value,
        };
      }
    }
    return SyncDoc(
      uid: doc.uid,
      kind: doc.kind,
      parentUid: doc.parentUid,
      name: doc.name,
      order: doc.order,
      data: data,
    );
  }

  static SyncSnapshot stripSnapshot(SyncSnapshot snapshot) =>
      SyncSnapshot({for (final e in snapshot.docs.entries) e.key: stripDoc(e.value)});

  /// What a link syncs: the snapshot as is with `includeSecrets`, otherwise
  /// without credentials.
  static SyncSnapshot applyPolicy(SyncSnapshot snapshot, {required bool includeSecrets}) =>
      includeSecrets ? snapshot : stripSnapshot(snapshot);

  static Object? _blankIfSecret(Object? variable) {
    if (variable is! Map) return variable;
    final key = variable['key'];
    if (key is String && looksSecretKey(key) && variable.containsKey('value')) {
      return Map<String, Object?>.from(variable)..['value'] = '';
    }
    return variable;
  }

  static Object? _blankValue(Object? entry) => switch (entry) {
        String() => '',
        Map() when entry.containsKey('value') => Map<String, Object?>.from(entry)..['value'] = '',
        _ => entry,
      };
}
