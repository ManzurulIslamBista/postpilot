import '../entities/sync_doc.dart';
import 'secret_names.dart';
import 'secret_text.dart';

/// Which fields hold credentials and must not be committed unless the
/// user opted in (`GitLink.includeSecrets`).
///
/// A credential is blanked (not removed) wherever PostPilot can recognise one:
/// the `auth` map, secret-looking collection variables, and in requests the
/// values of `Authorization`/`Cookie`/API-key headers, secret query parameters
/// (also inside the URL), secret form and urlencoded fields, and secret string
/// values of JSON raw and GraphQL-variables bodies. Values that only reference
/// `{{variables}}` hold no credential and are kept.
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

  /// Collection variables whose key looks like a credential get an empty
  /// value in committed files.
  static bool looksSecretKey(String key) => SecretNames.looksSecretKey(key);

  /// [auth] (a `RequestAuth.toJson()` map) without its credential keys.
  static Map<String, Object?> stripAuth(Map<String, Object?> auth) => {
        for (final e in auth.entries)
          if (!authKeys.contains(e.key)) e.key: e.value,
      };

  /// [doc] without credentials: its `auth` map loses [authKeys], on the
  /// collection doc `variables` whose key [looksSecretKey] get an empty value,
  /// and on a request the credentials of its headers, query parameters, URL
  /// and body get one (see the class comment).
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
    if (doc.kind == SyncKind.request) _stripRequest(data);
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

  static void _stripRequest(Map<String, Object?> data) {
    final url = data['url'];
    if (url is String) data['url'] = SecretText.blankUrl(url);
    _blankItems(data, 'headers', SecretNames.isSecretHeader);
    _blankItems(data, 'queryParams', SecretNames.isSecretQuery);
    final body = data['body'];
    if (body is Map) {
      final stripped = Map<String, Object?>.from(body);
      _blankItems(stripped, 'formFields', SecretNames.looksSecretKey);
      _blankItems(stripped, 'urlEncodedFields', SecretNames.looksSecretKey);
      for (final key in const ['rawText', 'graphqlVariables']) {
        final text = stripped[key];
        if (text is String) stripped[key] = SecretText.blankJson(text);
      }
      data['body'] = stripped;
    }
  }

  static void _blankItems(Map<String, Object?> data, String field, bool Function(String key) isSecret) {
    final items = data[field];
    if (items is List) data[field] = [for (final item in items) _blankItem(item, isSecret)];
  }

  static Object? _blankItem(Object? item, bool Function(String key) isSecret) {
    if (item is! Map) return item;
    final key = item['key'];
    final value = item['value'];
    if (key is String && value is String && isSecret(key) && SecretNames.hasLiteralSecret(value)) {
      return Map<String, Object?>.from(item)..['value'] = '';
    }
    return item;
  }

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
