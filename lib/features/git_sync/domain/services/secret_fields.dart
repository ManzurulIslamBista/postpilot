import '../entities/sync_doc.dart';
import 'secret_names.dart';
import 'secret_text.dart';

/// Which fields hold credentials and must not be committed unless the
/// user opted in (`GitLink.includeSecrets`).
///
/// A credential is blanked (not removed) wherever PostPilot can recognise one:
/// the `auth` map, secret-looking collection variables, and in requests the
/// values of `Authorization`/`Cookie`/API-key headers, secret query parameters
/// (also inside the URL), secret form and urlencoded fields, secret values of
/// raw (JSON, XML, SOAP, urlencoded text), GraphQL query and variables bodies,
/// the expected values of assertions on such headers and fields, and
/// unmistakable credentials in descriptions. Values that only reference
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
    'hmacSecret',
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
  /// A value that is only a `{{variable}}` reference is not a secret (the variable holds it) and stays, so a
  /// collection's `access-token: {{accessToken}}` survives a push and a pull.
  static Map<String, Object?> stripAuth(Map<String, Object?> auth) => {
        for (final e in auth.entries)
          if (!authKeys.contains(e.key) || (e.value is String && SecretNames.isTemplateOnly(e.value as String))) e.key: e.value,
      };

  /// [doc] without credentials: its `auth` map loses [authKeys], on the
  /// collection doc `variables` whose key [looksSecretKey] get an empty value,
  /// and on a request the credentials of its headers, query parameters, URL,
  /// body and assertions get one (see the class comment).
  /// Idempotent, so applying it to an already stripped doc changes nothing.
  static SyncDoc stripDoc(SyncDoc doc) {
    final data = {...doc.data};
    final description = data['description'];
    if (description is String) data['description'] = SecretText.blankNote(description);
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
    if (doc.kind == SyncKind.collection || doc.kind == SyncKind.folder) _stripDefaults(data, folder: doc.kind == SyncKind.folder);
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

  /// What a collection or folder passes down to its requests: the values of its secret headers, the
  /// expected values of its checks and, on a [folder], its secret variables (marked, or named like a
  /// credential). Its `auth` is stripped with every doc's, above.
  static void _stripDefaults(Map<String, Object?> data, {required bool folder}) {
    _blankItems(data, 'headers', SecretNames.isSecretHeader);
    final tests = data['tests'];
    if (tests is Map && tests['assertions'] is List) {
      data['tests'] = {
        ...tests,
        'assertions': [for (final assertion in tests['assertions'] as List) blankAssertion(assertion)],
      };
    }
    final variables = data['variables'];
    if (folder && variables is List) {
      data['variables'] = [
        for (final variable in variables)
          variable is Map && (variable['secret'] == true || (variable['key'] is String && looksSecretKey(variable['key'] as String)))
              ? _blankIfHasValue(variable)
              : variable,
      ];
    }
  }

  static Object? _blankIfHasValue(Map variable) =>
      variable.containsKey('value') ? (Map<String, Object?>.from(variable)..['value'] = '') : variable;

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
      for (final key in const ['rawText', 'graphqlQuery', 'graphqlVariables']) {
        final text = stripped[key];
        if (text is String) stripped[key] = SecretText.blankBody(text);
      }
      data['body'] = stripped;
    }
    final tests = data['tests'];
    if (tests is Map && tests['assertions'] is List) {
      data['tests'] = {
        ...tests,
        'assertions': [for (final assertion in tests['assertions'] as List) blankAssertion(assertion)],
      };
    }
    final settings = data['settings'];
    if (settings is Map && settings['flow'] is Map) {
      data['settings'] = {...settings, 'flow': _stripFlow(Map<String, Object?>.from(settings['flow'] as Map))};
    }
  }

  /// A request's flow settings without the credentials they could hold: what a poll-until condition expects
  /// (blanked like an assertion's expected value) and what a run-if compares a credential-named variable with.
  static Map<String, Object?> _stripFlow(Map<String, Object?> flow) {
    final poll = flow['poll'];
    if (poll is Map && poll['until'] is List) {
      flow['poll'] = {...poll, 'until': [for (final condition in poll['until'] as List) blankAssertion(condition)]};
    }
    final runIf = flow['runIf'];
    if (runIf is Map && runIf['all'] is List) {
      flow['runIf'] = {...runIf, 'all': [for (final condition in runIf['all'] as List) _blankCondition(condition)]};
    }
    return flow;
  }

  /// A run-if condition (`{kind, name, value}`) without the credential it compares a variable named like one with.
  static Object? _blankCondition(Object? condition) {
    if (condition is! Map) return condition;
    final name = condition['name'];
    final value = condition['value'];
    if (name is String && value is String && looksSecretKey(name) && SecretNames.hasLiteralSecret(value)) {
      return Map<String, Object?>.from(condition)..['value'] = '';
    }
    return condition;
  }

  /// [target] conditions (stripped) with the values [local] has for the same conditions put back: same kind and
  /// name, and the same text once [local] is blanked.
  static List<Object?> restoreConditions(List<Object?> target, List<Object?> local) {
    final unused = [for (final item in local) if (item is Map) item];
    return [
      for (final item in target)
        if (item is Map && item['value'] == '') _restoreCondition(item, unused) else item,
    ];
  }

  static Object? _restoreCondition(Map target, List<Map> unused) {
    for (final candidate in unused) {
      final original = candidate['value'];
      if (original is! String || original.isEmpty || candidate['kind'] != target['kind'] || candidate['name'] != target['name']) {
        continue;
      }
      // Only a value that blanking would have emptied is put back.
      final blanked = _blankCondition(candidate);
      if (blanked is! Map || blanked['value'] != '') continue;
      unused.remove(candidate);
      return Map<String, Object?>.from(target)..['value'] = original;
    }
    return target;
  }

  /// [assertion] (`{type, path, expected}`) without a credential it expects:
  /// the value of a secret header, of a secret JSON path, or credentials inside
  /// the text a body must contain.
  static Object? blankAssertion(Object? assertion) {
    if (assertion is! Map) return assertion;
    final expected = blankedExpected(assertion['type'], assertion['path'], assertion['expected']);
    if (expected == null || expected == assertion['expected']) return assertion;
    return Map<String, Object?>.from(assertion)..['expected'] = expected;
  }

  /// What an assertion expects once its credential is blanked, or null when
  /// [expected] is not a string or the assertion holds no credential kind.
  static String? blankedExpected(Object? type, Object? path, Object? expected) {
    if (expected is! String || expected.isEmpty) return null;
    final pathText = path is String ? path : '';
    switch (type) {
      case 'headerEquals':
        return SecretNames.isSecretHeader(pathText) && SecretNames.hasLiteralSecret(expected) ? '' : expected;
      case 'jsonPathEquals':
        return SecretNames.looksSecretKey(_lastPathName(pathText)) && SecretNames.hasLiteralSecret(expected)
            ? ''
            : expected;
      case 'bodyContains':
        return SecretText.blankSnippet(expected);
      default:
        return expected;
    }
  }

  /// [target] assertions (stripped) with the expected values [local] has for
  /// the same assertions put back: same type and path, and the same text once
  /// [local] is blanked.
  static List<Object?> restoreAssertions(List<Object?> target, List<Object?> local) {
    final unused = [for (final item in local) if (item is Map) item];
    return [
      for (final item in target)
        if (item is Map && item['expected'] is String)
          _restoreAssertion(item, unused)
        else
          item,
    ];
  }

  static Object? _restoreAssertion(Map target, List<Map> unused) {
    final expected = target['expected'] as String;
    for (final candidate in unused) {
      final original = candidate['expected'];
      if (original is! String ||
          original == expected ||
          candidate['type'] != target['type'] ||
          candidate['path'] != target['path']) {
        continue;
      }
      if (blankedExpected(candidate['type'], candidate['path'], original) != expected) continue;
      unused.remove(candidate);
      return Map<String, Object?>.from(target)..['expected'] = original;
    }
    return target;
  }

  /// The name a JSON path ends in: `data.items[0].password` is `password`.
  static String _lastPathName(String path) {
    final plain = path.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    return plain.substring(plain.lastIndexOf('.') + 1);
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
