import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/entities/sync_doc.dart';
import '../../../git_sync/domain/services/secret_fields.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../../../git_sync/domain/services/secret_text.dart';

/// A workspace document without its secrets, and the secrets by themselves.
final class SecretSplit {
  final Map<String, dynamic> publicDoc;

  /// Where each secret came from (see [SecretSplitter]) to its value.
  final Map<String, String> secrets;

  /// What to call each secret in a message ("Dev › token"), by the same keys.
  final Map<String, String> labels;

  const SecretSplit(this.publicDoc, this.secrets, [this.labels = const {}]);
}

/// The content of `workspace.local.json`: the [secrets] of the workspace, and
/// the [unmatched] ones, which belong to nothing in the workspace as it is now
/// (a teammate renamed the environment or request they were for). Those are
/// kept so that renaming it back, or a later pull, brings them back.
final class LocalSecrets {
  final Map<String, String> secrets;
  final Map<String, String> unmatched;
  const LocalSecrets({this.secrets = const {}, this.unmatched = const {}});

  static const none = LocalSecrets();

  /// Every secret this file can offer; a current one wins over an unmatched one.
  Map<String, String> get all => {...unmatched, ...secrets};
}

/// Keeps passwords and tokens out of `workspace.json`, which is what gets
/// pushed to Git and shared with a team, by moving them to a file beside it
/// that is not pushed (`workspace.local.json`).
///
/// Works on the decoded workspace document. A value is a secret when:
///  * it is an environment or global variable marked secret,
///  * it is a collection variable whose name looks like a credential
///    (`api_key`, `db_password`),
///  * it is a credential field of a collection's or request's auth
///    (`bearerToken`, `basicPassword`, `oauth2ClientSecret`...),
///  * it is a request's `Authorization`/`Cookie`/API-key header, secret query
///    parameter (also inside the URL), secret form or urlencoded field, or a
///    secret value of its raw, GraphQL query or GraphQL variables body (JSON,
///    XML, SOAP, urlencoded text),
///  * it is a credential in a saved response example (its headers and body),
///    in what an assertion expects, or an unmistakable one in a description,
///  * it is in what a collection or a folder passes down to its requests: the
///    value of an `Authorization`/`Cookie`/API-key default header, a folder
///    variable marked secret (or named like a credential), a credential field
///    of a folder's auth, what a default check expects.
///
/// Each secret is addressed by a key. A collection or request that has a Git
/// `uid` is addressed by it (`@<uid>`), because a uid survives renames and
/// reordering; one without is addressed by its name, a request by its folders
/// and name (`Folder/Get user`), and two siblings with the same name get `#2`,
/// `#3`. The keys read `env/<environment>/<variable>`, `global/<variable>`,
/// `cvar/<collection>/<variable>`, `cauth/<collection>/<field>`,
/// `rauth/<collection>/<request>/<field>`, and `rurl`, `rhdr`, `rqry`, `rform`,
/// `renc`, `rbody`, `rtest`, `rexh`, `rexb`, `cdesc`, `fdesc`, `rdesc`, `cdhdr`, `cdtest` (the headers
/// and checks a collection passes down), `fdhdr`, `fvar`, `fauth`, `fdtest` (the same for a folder) and `gbase` (the
/// synced docs a linked collection keeps) for the other places. A file written before they existed still works: the old
/// names of a key are tried too.
abstract final class SecretSplitter {
  static const localFileVersion = 1;

  /// How many unmatched secrets a local file keeps: a rename that never comes
  /// back should not make it grow for ever.
  static const maxUnmatched = 200;

  static SecretSplit split(Map<String, dynamic> doc) {
    final copy = _deepCopy(doc) as Map<String, dynamic>;
    final secrets = <String, String>{};
    final labels = <String, String>{};
    for (final slot in _slots(copy)) {
      final value = slot.value;
      if (value == null || value.isEmpty) continue;
      final blanked = slot.blank(value);
      if (blanked == value) continue;
      secrets[slot.key] = value;
      labels[slot.key] = slot.label;
      slot.value = blanked;
    }
    return SecretSplit(copy, secrets, labels);
  }

  /// [doc] with each secret that is blank in it filled from [secrets]. A value
  /// that is already set (a teammate's shared default) is left alone.
  static Map<String, dynamic> merge(Map<String, dynamic> doc, Map<String, String> secrets) {
    if (secrets.isEmpty) return doc;
    final copy = _deepCopy(doc) as Map<String, dynamic>;
    for (final slot in _slots(copy)) {
      final local = slot.localValue(secrets);
      if (local == null) continue;
      final current = slot.value ?? '';
      final restored = slot.restore(current, local);
      if (restored != current) slot.value = restored;
    }
    return copy;
  }

  /// The entries of [secrets] that belong to nothing in [doc]: no variable,
  /// header, field or request of that name is there any more.
  static Map<String, String> orphans(Map<String, dynamic> doc, Map<String, String> secrets) {
    if (secrets.isEmpty) return const {};
    final known = <String>{
      for (final slot in _slots(doc)) ...[slot.key, ...slot.legacyKeys],
    };
    return {
      for (final e in secrets.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };
  }

  /// What the local file should hold once [doc] (public, secrets blanked) and its
  /// [secrets] are written. Unmatched entries of [previous] stay, unless they have
  /// found their place in [doc] or [secrets]. With [keepOrphans], the entries of
  /// [previous]'s own secrets that [doc] has no place for join them: that is what
  /// happens when [doc] came from somebody else (a pull).
  static LocalSecrets retain({
    required Map<String, dynamic> doc,
    required Map<String, String> secrets,
    required LocalSecrets previous,
    bool keepOrphans = false,
  }) {
    final unmatched = <String, String>{
      ...orphans(doc, previous.unmatched),
      if (keepOrphans) ...orphans(doc, previous.secrets),
    }..removeWhere((key, _) => secrets.containsKey(key));
    return LocalSecrets(secrets: secrets, unmatched: capUnmatched(unmatched));
  }

  /// [unmatched] without its oldest entries once it is longer than [maxUnmatched].
  static Map<String, String> capUnmatched(Map<String, String> unmatched) {
    final overflow = unmatched.length - maxUnmatched;
    if (overflow <= 0) return unmatched;
    return {for (final e in unmatched.entries.skip(overflow)) e.key: e.value};
  }

  /// What a push of [doc] would publish in plain text, as "Collection › Request › Authorization header".
  /// With [keepLocal] the secrets are split off first, so only what the split
  /// cannot recognise remains; without it every secret is listed as well.
  static List<String> exposed(Map<String, dynamic> doc, {required bool keepLocal}) {
    final split = SecretSplitter.split(doc);
    return [
      if (!keepLocal) ...split.labels.values,
      for (final slot in _slots(split.publicDoc))
        if (slot.isExposed) slot.label,
    ];
  }

  // --- the places a secret can sit --------------------------------------------

  static List<_Slot> _slots(Map<String, dynamic> doc) {
    final slots = <_Slot>[];

    final envSeen = <String, int>{};
    for (final env in _maps(doc['environments'])) {
      final envName = '${env['name'] ?? ''}';
      final envKey = _unique(envSeen, envName);
      final varSeen = <String, int>{};
      for (final v in _maps(env['variables'])) {
        slots.add(_variable(v, 'env/$envKey/${_unique(varSeen, '${v['key'] ?? ''}')}', '$envName › ${v['key'] ?? ''}'));
      }
    }
    final globalSeen = <String, int>{};
    for (final g in _maps(doc['globals'])) {
      slots.add(_variable(g, 'global/${_unique(globalSeen, '${g['key'] ?? ''}')}', 'Globals › ${g['key'] ?? ''}'));
    }

    final collectionSeen = <String, int>{};
    for (final c in _maps(doc['collections'])) {
      _collection(c, _unique(collectionSeen, '${c['name'] ?? ''}'), slots);
    }
    return slots;
  }

  /// An environment or global variable: a secret when marked so. One that is
  /// not, but is named like a credential or holds a known token, is reported by
  /// [exposed].
  static _Slot _variable(Map<String, dynamic> variable, String key, String label) {
    final secret = variable['secret'] == true;
    final name = '${variable['key'] ?? ''}';
    return _Slot(
      variable,
      'value',
      key,
      label,
      blank: secret ? _blankAll : _keep,
      isExposedValue: secret ? null : (v) => _namedLikeSecret(name, v) || _looksExposed(v),
    );
  }

  static void _collection(Map<String, dynamic> c, String nameKey, List<_Slot> slots) {
    final name = '${c['name'] ?? ''}';
    final uid = _uid(c['uid']);
    final id = uid == null ? nameKey : '@$uid';
    final legacyId = uid == null ? null : nameKey;

    _Slot field(Map<String, dynamic> holder, String f, String kind, String rest, String label, {
      String Function(String)? blank,
      String Function(String, String)? restore,
      bool Function(String)? isExposedValue,
    }) => _Slot(
      holder,
      f,
      '$kind/$id$rest',
      label,
      legacyKeys: [if (legacyId != null) '$kind/$legacyId$rest'],
      blank: blank ?? _blankAll,
      restore: restore,
      isExposedValue: isExposedValue,
    );

    final varSeen = <String, int>{};
    for (final v in _maps(c['variables'])) {
      final key = '${v['key'] ?? ''}';
      slots.add(field(
        v,
        'value',
        'cvar',
        '/${_unique(varSeen, key)}',
        '$name › $key',
        blank: SecretNames.looksSecretKey(key) ? _blankLiteral : _keep,
        isExposedValue: (value) => _namedLikeSecret(key, value) || _looksExposed(value),
      ));
    }
    final auth = c['auth'];
    if (auth is Map<String, dynamic>) {
      for (final f in SecretFields.authKeys) {
        if (auth.containsKey(f)) slots.add(field(auth, f, 'cauth', '/$f', '$name › auth $f', blank: _blankLiteral));
      }
    }
    // What the collection passes down to its requests: an Authorization header or a token it carries is
    // a secret like the same value on a request.
    _defaultHeaders(c['headers'], slots, 'cdhdr/$id', [if (legacyId != null) 'cdhdr/$legacyId'], name);
    _defaultTests(c['tests'], slots, 'cdtest/$id', [if (legacyId != null) 'cdtest/$legacyId'], name);
    if (c['description'] is String) {
      slots.add(field(c, 'description', 'cdesc', '', '$name › description', blank: SecretText.blankNote, restore: SecretText.restoreNote, isExposedValue: _hasKnownToken));
    }

    final folderPaths = _folderPaths(c);
    final folderSeen = <String, int>{};
    for (final folder in _maps(c['folders'])) {
      if (folder['description'] is! String) continue;
      final path = folderPaths[folder['id']] ?? '${folder['name'] ?? ''}';
      slots.add(field(
        folder,
        'description',
        'fdesc',
        '/${_unique(folderSeen, path)}',
        '$name › $path › description',
        blank: SecretText.blankNote,
        restore: SecretText.restoreNote,
        isExposedValue: _hasKnownToken,
      ));
    }

    // What each folder passes down: headers, variables (a secret one is marked), auth and tests.
    // A folder is addressed by its Git uid when it has one, else by its path of names.
    final defaultsSeen = <String, int>{};
    for (final folder in _maps(c['folders'])) {
      final path = folderPaths[folder['id']] ?? '${folder['name'] ?? ''}';
      final pathKey = _unique(defaultsSeen, path);
      final folderUid = _uid(folder['uid']);
      final ref = folderUid == null ? pathKey : '@$folderUid';
      final byName = legacyId != null || folderUid != null;
      String base(String kind) => '$kind/$id/$ref';
      List<String> legacy(String kind) => [if (byName) '$kind/${legacyId ?? id}/$pathKey'];
      final where = '$name › $path';
      _defaultHeaders(folder['headers'], slots, base('fdhdr'), legacy('fdhdr'), where);
      _defaultVariables(folder['variables'], slots, base('fvar'), legacy('fvar'), where);
      _defaultAuth(folder['auth'], slots, base('fauth'), legacy('fauth'), where);
      _defaultTests(folder['tests'], slots, base('fdtest'), legacy('fdtest'), where);
    }

    // The Git link of a collection carries the docs as last synced. A collection that syncs its
    // secrets to its own repository would put them in this file too.
    final git = c['git'];
    if (git is Map<String, dynamic>) {
      for (final entry in _maps(git['base'])) {
        if (entry['doc'] is! String) continue;
        slots.add(_Slot(entry, 'doc', 'gbase/$id/${entry['uid'] ?? ''}', '$name › Git sync state', blank: _blankSyncDoc));
      }
    }

    final plainSeen = <String, int>{};
    final qualifiedSeen = <String, int>{};
    for (final r in _maps(c['requests'])) {
      final requestName = '${r['name'] ?? ''}';
      final folder = folderPaths[r['folderId']] ?? '';
      final requestUid = _uid(r['uid']);
      final nameId = _unique(plainSeen, requestName);
      final qualifiedId = _unique(qualifiedSeen, folder.isEmpty ? requestName : '$folder/$requestName');
      _request(
        r,
        key: '$id/${requestUid == null ? qualifiedId : '@$requestUid'}',
        legacyKey: legacyId == null && requestUid == null && qualifiedId == nameId ? null : '${legacyId ?? id}/$nameId',
        label: '$name › $requestName',
        slots: slots,
      );
    }
  }

  /// The headers of a collection's or folder's defaults: the value of a secret one (`Authorization`,
  /// `X-Api-Key`) is a secret, like on a request. [keyBase] addresses them; [legacyBases] are the same
  /// addresses by name, for a file written before the collection or folder had a uid.
  static void _defaultHeaders(Object? list, List<_Slot> slots, String keyBase, List<String> legacyBases, String label) {
    final seen = <String, int>{};
    for (final item in _maps(list)) {
      final name = '${item['key'] ?? ''}';
      final unique = _unique(seen, name);
      slots.add(_Slot(
        item,
        'value',
        '$keyBase/$unique',
        '$label › $name header',
        legacyKeys: [for (final base in legacyBases) '$base/$unique'],
        blank: SecretNames.isSecretHeader(name) ? _blankLiteral : _keep,
        isExposedValue: _looksExposed,
      ));
    }
  }

  /// The variables of a folder's defaults: one marked secret is blanked whole, one named like a
  /// credential (`api_key`) when it holds a literal, like a collection variable.
  static void _defaultVariables(Object? list, List<_Slot> slots, String keyBase, List<String> legacyBases, String label) {
    final seen = <String, int>{};
    for (final item in _maps(list)) {
      final name = '${item['key'] ?? ''}';
      final unique = _unique(seen, name);
      final secret = item['secret'] == true;
      slots.add(_Slot(
        item,
        'value',
        '$keyBase/$unique',
        '$label › $name',
        legacyKeys: [for (final base in legacyBases) '$base/$unique'],
        blank: secret ? _blankAll : (SecretNames.looksSecretKey(name) ? _blankLiteral : _keep),
        isExposedValue: secret ? null : (value) => _namedLikeSecret(name, value) || _looksExposed(value),
      ));
    }
  }

  /// The credential fields of the auth a folder passes down (the same fields a request's auth has).
  static void _defaultAuth(Object? auth, List<_Slot> slots, String keyBase, List<String> legacyBases, String label) {
    if (auth is! Map<String, dynamic>) return;
    for (final f in SecretFields.authKeys) {
      if (!auth.containsKey(f)) continue;
      slots.add(_Slot(
        auth,
        f,
        '$keyBase/$f',
        '$label › auth $f',
        legacyKeys: [for (final base in legacyBases) '$base/$f'],
        blank: _blankLiteral,
      ));
    }
  }

  /// What the checks of a collection's or folder's defaults expect: a credential there is shared like one on a request.
  static void _defaultTests(Object? tests, List<_Slot> slots, String keyBase, List<String> legacyBases, String label) {
    if (tests is! Map<String, dynamic>) return;
    final seen = <String, int>{};
    for (final assertion in _maps(tests['assertions'])) {
      if (assertion['expected'] is! String) continue;
      final type = assertion['type'];
      final path = assertion['path'];
      final unique = _unique(seen, '$type:${path ?? ''}');
      slots.add(_Slot(
        assertion,
        'expected',
        '$keyBase/$unique',
        '$label › test "${path is String && path.isNotEmpty ? path : type}"',
        legacyKeys: [for (final base in legacyBases) '$base/$unique'],
        blank: (v) => SecretFields.blankedExpected(type, path, v) ?? v,
        isExposedValue: _hasKnownToken,
      ));
    }
  }

  /// The places of one request. [key] identifies the request among all, [legacyKey]
  /// is what the earlier key format called it (only auth had a key then).
  static void _request(
    Map<String, dynamic> r, {
    required String key,
    required String? legacyKey,
    required String label,
    required List<_Slot> slots,
  }) {
    _Slot text(Map<String, dynamic> holder, String f, String kind, String rest, String what, {
      required String Function(String) blank,
      required String Function(String, String) restore,
      required bool Function(String) exposed,
    }) => _Slot(holder, f, '$kind/$key$rest', '$label › $what', blank: blank, restore: restore, isExposedValue: exposed);

    void items(Object? list, String kind, String what, bool Function(String name) isSecret) {
      final seen = <String, int>{};
      for (final item in _maps(list)) {
        final name = '${item['key'] ?? ''}';
        final secret = isSecret(name);
        slots.add(_Slot(
          item,
          'value',
          '$kind/$key/${_unique(seen, name)}',
          '$label › $name $what',
          blank: secret ? _blankLiteral : _keep,
          isExposedValue: _looksExposed,
        ));
      }
    }

    if (r['url'] is String) {
      slots.add(text(r, 'url', 'rurl', '', 'URL', blank: SecretText.blankUrl, restore: SecretText.restoreUrl, exposed: (v) => SecretMasker.maskUrl(v) != v));
    }
    items(r['headers'], 'rhdr', 'header', SecretNames.isSecretHeader);
    items(r['queryParams'], 'rqry', 'parameter', SecretNames.isSecretQuery);

    final body = r['body'];
    if (body is Map<String, dynamic>) {
      items(body['formFields'], 'rform', 'form field', SecretNames.looksSecretKey);
      items(body['urlEncodedFields'], 'renc', 'form field', SecretNames.looksSecretKey);
      for (final (field, what) in const [('rawText', 'body'), ('graphqlQuery', 'GraphQL query'), ('graphqlVariables', 'GraphQL variables')]) {
        if (body[field] is! String) continue;
        slots.add(text(body, field, 'rbody', '/$field', what, blank: SecretText.blankBody, restore: SecretText.restoreBody, exposed: _hasKnownToken));
      }
    }

    final auth = r['auth'];
    if (auth is Map<String, dynamic>) {
      for (final f in SecretFields.authKeys) {
        if (!auth.containsKey(f)) continue;
        slots.add(_Slot(
          auth,
          f,
          'rauth/$key/$f',
          '$label › auth $f',
          legacyKeys: [if (legacyKey != null) 'rauth/$legacyKey/$f'],
          blank: _blankLiteral,
        ));
      }
    }

    if (r['description'] is String) {
      slots.add(text(r, 'description', 'rdesc', '', 'description', blank: SecretText.blankNote, restore: SecretText.restoreNote, exposed: _hasKnownToken));
    }

    final scripts = r['scripts'];
    if (scripts is Map<String, dynamic>) {
      final seen = <String, int>{};
      for (final assertion in _maps(scripts['assertions'])) {
        if (assertion['expected'] is! String) continue;
        final type = assertion['type'];
        final path = assertion['path'];
        final id = _unique(seen, '$type:${path ?? ''}');
        slots.add(_Slot(
          assertion,
          'expected',
          'rtest/$key/$id',
          '$label › test "${path is String && path.isNotEmpty ? path : type}"',
          blank: (v) => SecretFields.blankedExpected(type, path, v) ?? v,
          isExposedValue: _hasKnownToken,
        ));
      }
    }

    final exampleSeen = <String, int>{};
    for (final example in _maps(r['examples'])) {
      final exampleName = '${example['name'] ?? ''}';
      final id = _unique(exampleSeen, exampleName);
      final headers = example['headers'];
      if (headers is Map<String, dynamic>) {
        for (final name in headers.keys.toList()) {
          if (headers[name] is! String) continue;
          final secret = SecretNames.isSecretHeader(name);
          slots.add(_Slot(
            headers,
            name,
            'rexh/$key/$id/$name',
            '$label › example "$exampleName" › $name header',
            blank: secret ? _blankLiteral : _keep,
            isExposedValue: _looksExposed,
          ));
        }
      }
      if (example['body'] is String) {
        slots.add(text(example, 'body', 'rexb', '/$id', 'example "$exampleName" body', blank: SecretText.blankSnippet, restore: SecretText.restoreSnippet, exposed: _hasKnownToken));
      }
    }
  }

  // --- how a value is blanked ----------------------------------------------------

  static String _blankAll(String value) => '';
  static String _blankLiteral(String value) => SecretNames.hasLiteralSecret(value) ? '' : value;
  static String _keep(String value) => value;

  /// The text of a synced doc without its credentials; the same text, byte for byte, when it has none.
  static String _blankSyncDoc(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return text;
      final doc = SyncDoc.fromJson(json);
      final stripped = SecretFields.stripDoc(doc);
      return stripped == doc ? text : stripped.canonicalText;
    } catch (_) {
      return text;
    }
  }

  static bool _hasKnownToken(String value) => SecretNames.knownTokens(value).isNotEmpty;

  /// A value, whatever its name, that is a known token or a URL that carries a password or secret parameter.
  static bool _looksExposed(String value) =>
      _hasKnownToken(value) || (value.contains('://') && SecretMasker.maskUrl(value) != value);

  /// A variable the user did not mark secret that is named like a credential.
  static bool _namedLikeSecret(String name, String value) =>
      SecretNames.looksSecretKey(name) && SecretNames.hasLiteralSecret(value);

  /// `Parent/Child` path of every folder of [collection], by folder id.
  static Map<Object?, String> _folderPaths(Map<String, dynamic> collection) {
    final folders = {for (final f in _maps(collection['folders'])) f['id']: f};
    String pathOf(Map<String, dynamic> folder) {
      final names = <String>[];
      Map<String, dynamic>? current = folder;
      for (var depth = 0; current != null && depth < 50; depth++) {
        names.insert(0, '${current['name'] ?? ''}');
        current = folders[current['parentId']];
      }
      return names.join('/');
    }

    return {for (final e in folders.entries) e.key: pathOf(e.value)};
  }

  static String? _uid(Object? value) => value is String && value.isNotEmpty ? value : null;

  static String _unique(Map<String, int> seen, String name) {
    final n = (seen[name] ?? 0) + 1;
    seen[name] = n;
    return n == 1 ? name : '$name#$n';
  }

  static Iterable<Map<String, dynamic>> _maps(Object? list) =>
      list is List ? list.whereType<Map<String, dynamic>>() : const [];

  static Object? _deepCopy(Object? v) => switch (v) {
        Map<dynamic, dynamic>() => {for (final e in v.entries) '${e.key}': _deepCopy(e.value)},
        List<dynamic>() => [for (final e in v) _deepCopy(e)],
        _ => v,
      };

  // --- the local file -----------------------------------------------------------

  static String encodeLocal(Map<String, String> secrets, {Map<String, String> unmatched = const {}}) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': localFileVersion,
        'notice': 'Secret values of this workspace. They are kept in this file, beside workspace.json, instead of in '
            'workspace.json, which is what gets pushed to Git. Do not share or commit this file.',
        'secrets': secrets,
        if (unmatched.isNotEmpty) 'unmatched': unmatched,
      });

  /// An unreadable or missing file means no secrets, never an error: the
  /// workspace must still open.
  static Map<String, String> decodeLocal(String? text) => decodeLocalFile(text).secrets;

  static LocalSecrets decodeLocalFile(String? text) {
    if (text == null || text.trim().isEmpty) return LocalSecrets.none;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return LocalSecrets.none;
      return LocalSecrets(secrets: _strings(json['secrets']), unmatched: _strings(json['unmatched']));
    } on FormatException {
      return LocalSecrets.none;
    }
  }

  static Map<String, String> _strings(Object? map) => map is! Map
      ? const {}
      : {
          for (final e in map.entries)
            if (e.value is String) '${e.key}': e.value as String,
        };
}

/// One value of a workspace document that can hold a secret: where it is, the
/// key it is stored under, how it is blanked and how it is put back.
final class _Slot {
  final Map<String, dynamic> _holder;
  final String _field;

  /// What the local file calls it, then what it called it before (see [SecretSplitter]).
  final String key;
  final List<String> legacyKeys;
  final String label;

  /// [value] without its secret; the same text when it holds none.
  final String Function(String value) blank;
  final String Function(String target, String local)? _restore;

  /// Whether [value], in a document that is about to be pushed, still looks like a secret.
  final bool Function(String value)? isExposedValue;

  _Slot(
    this._holder,
    this._field,
    this.key,
    this.label, {
    this.legacyKeys = const [],
    this.blank = SecretSplitter._blankAll,
    this._restore,
    this.isExposedValue,
  });

  String? get value {
    final v = _holder[_field];
    return v is String ? v : null;
  }

  set value(String v) => _holder[_field] = v;

  bool get isExposed {
    final v = value;
    return v != null && v.isNotEmpty && (isExposedValue?.call(v) ?? false);
  }

  /// What [secrets] holds for this slot, if anything.
  String? localValue(Map<String, String> secrets) {
    for (final k in [key, ...legacyKeys]) {
      final v = secrets[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// [target] (what the shared file holds) with [local] put back, but never over
  /// a value somebody has set.
  String restore(String target, String local) =>
      _restore?.call(target, local) ?? (blank(local) == target ? local : target);
}
