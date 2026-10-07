import 'dart:convert';
import '../../../git_sync/domain/services/secret_fields.dart';
import '../../../git_sync/domain/services/secret_names.dart';

/// A pull must never erase a credential this device already has.
///
/// The repository's `workspace.json` carries credentials blank by design (they live in each device's
/// `workspace.local.json`), and a file pushed by an older version also lost `{{token}}` references that were
/// never stored locally. Replacing the database with such a file blanked, for example, a collection's
/// `access-token: {{accessToken}}` header, and every request after the login came back 401.
///
/// [keep] returns [incoming] with each credential that is blank (or missing) in it filled from the same place
/// in [current], the data the device has now: auth credentials of collections and requests, and secret
/// variables of environments, globals and collections. A value the pulled file does set always wins, and
/// nothing is filled into an auth of another type.
abstract final class CredentialKeeper {
  static Map<String, dynamic> keep(Map<String, dynamic> incoming, Map<String, dynamic> current) {
    final copy = jsonDecode(jsonEncode(incoming)) as Map<String, dynamic>;
    _variables(copy['globals'], current['globals']);
    _matched(copy['environments'], current['environments'], (e) => '${e['name']}', (into, from) {
      _variables(into['variables'], from['variables']);
    });
    _matched(copy['collections'], current['collections'], (c) => '${c['uid'] ?? c['name']}', (into, from) {
      _auth(into['auth'], from['auth']);
      _variables(into['variables'], from['variables']);
      _matched(into['requests'], from['requests'], (r) => '${r['name']}|${r['method']}|${r['url']}', (req, old) {
        _auth(req['auth'], old['auth']);
      });
    });
    return copy;
  }

  /// Runs [fill] for each map of [into] that has a partner in [from] under the same [keyOf]; the first
  /// partner of a key is used once per key, so two requests with one name do not share credentials.
  static void _matched(
    Object? into,
    Object? from,
    String Function(Map<String, dynamic>) keyOf,
    void Function(Map<String, dynamic> into, Map<String, dynamic> from) fill,
  ) {
    if (into is! List || from is! List) return;
    final partners = <String, List<Map<String, dynamic>>>{};
    for (final item in from) {
      if (item is Map<String, dynamic>) partners.putIfAbsent(keyOf(item), () => []).add(item);
    }
    for (final item in into) {
      if (item is! Map<String, dynamic>) continue;
      final list = partners[keyOf(item)];
      if (list == null || list.isEmpty) continue;
      fill(item, list.removeAt(0));
    }
  }

  static void _auth(Object? into, Object? from) {
    if (into is! Map<String, dynamic> || from is! Map) return;
    if (into['type'] != from['type']) return;
    for (final key in SecretFields.authKeys) {
      final have = from[key];
      final now = into[key];
      if (have is String && have.isNotEmpty && (now is! String || now.isEmpty)) into[key] = have;
    }
  }

  static void _variables(Object? into, Object? from) {
    if (into is! List || from is! List) return;
    final have = <String, Map>{};
    for (final v in from) {
      if (v is Map && '${v['value'] ?? ''}'.isNotEmpty) have.putIfAbsent('${v['key']}', () => v);
    }
    for (final v in into) {
      if (v is! Map<String, dynamic>) continue;
      if ('${v['value'] ?? ''}'.isNotEmpty) continue;
      final old = have['${v['key']}'];
      if (old == null) continue;
      final secret = v['secret'] == true || old['secret'] == true || SecretNames.looksSecretKey('${v['key']}');
      if (secret) v['value'] = old['value'];
    }
  }
}
