import 'dart:convert';
import '../../../../core/enums/http_method.dart';
import 'graphql_operations.dart';

/// What a request does to the server's data.
enum RequestEffect {
  /// Only looks: GET, an Odoo `search_read`, a GraphQL `query`.
  read,

  /// Creates or changes data.
  write,

  /// Removes data: DELETE, an Odoo `unlink`, a GraphQL `deleteUser` mutation.
  /// Never covered by "don't ask again".
  destructive;

  bool get changesData => this != read;
}

/// Decides which environments and hosts count as "production" and which
/// requests change data. Environments are recognised by name, because that is
/// how people label them: "Production", "Prod (EU)", "live", "acme-prod".
/// Pure Dart, shared by the app's production lock and the command line.
abstract final class ProductionDetector {
  static const builtInWords = {'prod', 'production', 'prd', 'live'};

  /// True when any word of [environmentName] is a production word, built in or in [extraWords].
  static bool isProduction(String environmentName, {Iterable<String> extraWords = const []}) {
    final words = environmentName
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final wanted = {...builtInWords, for (final w in extraWords) if (w.trim().isNotEmpty) w.trim().toLowerCase()};
    return words.any(wanted.contains);
  }

  /// Methods that change data on the server. By HTTP method alone: Odoo and
  /// GraphQL read over POST, so use [classify] when the URL and body are known.
  static bool changesData(HttpMethod method) =>
      method == HttpMethod.post || method == HttpMethod.put || method == HttpMethod.patch || method == HttpMethod.delete;

  /// What a request does, judged by its intent rather than its verb alone.
  /// GET, HEAD and OPTIONS read and DELETE removes; for POST the URL and body
  /// are looked at:
  ///  * Odoo (`/json/2/<model>/<method>`, `/web/dataset/call_kw/<model>/<method>`)
  ///    reads for `search_read`, `read`, `fields_get`... and removes for `unlink`;
  ///  * GraphQL (a JSON body with a `query`, or [graphqlQuery]) reads for
  ///    queries and subscriptions and writes for a mutation, which removes when
  ///    a root field is named like `deleteUser` or `removeItem`.
  /// Anything that cannot be proven to be a read (an unknown Odoo method, an
  /// unresolved `{{variable}}` where the method should be, a GraphQL document
  /// that does not parse) counts as a write. [body] and [url] may still hold
  /// `{{variables}}`.
  static RequestEffect classify(HttpMethod method, {String url = '', String? body, String? graphqlQuery}) {
    switch (method) {
      case HttpMethod.get:
      case HttpMethod.head:
      case HttpMethod.options:
        return RequestEffect.read;
      case HttpMethod.delete:
        return RequestEffect.destructive;
      case HttpMethod.put:
      case HttpMethod.patch:
        return RequestEffect.write;
      case HttpMethod.post:
        break;
    }
    final odoo = _odooMethod(url);
    if (odoo != null) return _odooEffect(odoo);
    final documents = _graphqlDocuments(graphqlQuery, body);
    if (documents != null) return _graphqlEffect(documents);
    return RequestEffect.write;
  }

  // --- Odoo ---

  static final _odooCall = RegExp(r'/(?:json/2|web/dataset/call_kw)/([^/?#\s]+)/([^/?#\s]+)', caseSensitive: false);

  /// Methods of an Odoo model that only read. Everything else counts as a write.
  static const _odooReadMethods = {
    'read',
    'search',
    'search_read',
    'search_count',
    'search_fetch',
    'fetch',
    'exists',
    'read_group',
    'web_read',
    'web_search_read',
    'web_read_group',
    'fields_get',
    'name_search',
    'name_get',
    'default_get',
    'get_metadata',
    'get_views',
    'get_view',
    'load_views',
    'fields_view_get',
    'check_access',
    'check_access_rights',
    'check_access_rule',
    'has_access',
    'has_group',
  };

  /// Whole words of an Odoo method name (`unlink`, `action_delete_all`) that make it a removal.
  static const _odooDestructiveWords = {'unlink', 'delete', 'remove', 'drop', 'destroy', 'purge', 'wipe', 'truncate', 'erase'};

  /// Inside a GraphQL root field (`deleteUser`, `removeFromCart`, `dropTable`) that makes a mutation a removal.
  static final _graphqlDestructive = RegExp(r'unlink|delete|remove|drop|destroy|purge|wipe|truncate|erase', caseSensitive: false);

  /// The method of an Odoo call URL, lower-cased; `''` when it is not known yet (a `{{variable}}`); `null` when [url] is no Odoo call.
  static String? _odooMethod(String url) {
    final match = _odooCall.firstMatch(url);
    if (match == null) return null;
    var method = match[2]!;
    try {
      method = Uri.decodeComponent(method);
    } catch (_) {
      return ''; // a bad percent escape (Uri throws an ArgumentError or a FormatException): unknown, so a write
    }
    method = method.toLowerCase();
    return method.contains('{') ? '' : method;
  }

  static RequestEffect _odooEffect(String method) {
    if (_odooReadMethods.contains(method)) return RequestEffect.read;
    if (method.split('_').any(_odooDestructiveWords.contains)) return RequestEffect.destructive;
    return RequestEffect.write;
  }

  // --- GraphQL ---

  /// The GraphQL documents a request carries, or `null` when it is not GraphQL.
  static List<String>? _graphqlDocuments(String? graphqlQuery, String? body) {
    if (graphqlQuery != null && graphqlQuery.trim().isNotEmpty) return [graphqlQuery];
    final text = body?.trim() ?? '';
    if (text.isEmpty) return null;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // Not JSON: a raw `application/graphql` body is the document itself.
      final raw = GraphqlOperations.parse(text);
      return raw == null ? null : [text];
    }
    final entries = json is List ? json : [json];
    final documents = [
      for (final entry in entries)
        if (entry is Map && entry['query'] is String) entry['query'] as String,
    ];
    return documents.isEmpty ? null : documents;
  }

  static RequestEffect _graphqlEffect(List<String> documents) {
    var effect = RequestEffect.read;
    for (final document in documents) {
      final operations = GraphqlOperations.parse(document);
      if (operations == null) return RequestEffect.write;
      for (final operation in operations) {
        if (!operation.isMutation) continue;
        if (operation.rootFields.any(_graphqlDestructive.hasMatch)) return RequestEffect.destructive;
        effect = RequestEffect.write;
      }
    }
    return effect;
  }

  // --- hosts ---

  /// True when the host of [url] is one of [hosts], whichever environment is
  /// active. An entry matches its own host and every subdomain of it (`acme.com`
  /// covers `api.acme.com`; a leading `*.` or `.` means the same), ignoring
  /// case and a trailing dot. An entry written with a port (`acme.com:8443`)
  /// only matches that port, the scheme's default counting when the URL has
  /// none. An entry may also be pasted as a whole URL. A [url] whose host is
  /// not known yet (`{{baseUrl}}` unresolved) never matches.
  static bool isProductionHost(String url, Iterable<String> hosts) {
    final uri = _parseUrl(url);
    if (uri == null) return false;
    final host = _normaliseHost(uri.host);
    for (final raw in hosts) {
      final entry = _parseHostEntry(raw);
      if (entry == null) continue;
      if (host != entry.host && !host.endsWith('.${entry.host}')) continue;
      if (entry.port == null || entry.port == uri.port) return true;
    }
    return false;
  }

  /// The host of [url] in lower case, without port or user info; `null` when it has none.
  static String? hostOf(String url) {
    final uri = _parseUrl(url);
    return uri == null ? null : _normaliseHost(uri.host);
  }

  static final _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  static Uri? _parseUrl(String url) {
    final text = url.trim();
    if (text.isEmpty) return null;
    // Like the request builder: a URL typed without a scheme is http.
    final uri = Uri.tryParse(_hasScheme.hasMatch(text) ? text : 'http://$text');
    // A `{{variable}}` left in the host means the host is not known yet (Dart percent-encodes the braces).
    return uri == null || uri.host.isEmpty || uri.host.contains('{') || uri.host.contains('%') ? null : uri;
  }

  static String _normaliseHost(String host) {
    final lower = host.toLowerCase();
    return lower.endsWith('.') ? lower.substring(0, lower.length - 1) : lower;
  }

  static ({String host, int? port})? _parseHostEntry(String raw) {
    var text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    text = text.replaceFirst(_hasScheme, '');
    text = text.split(RegExp(r'[/?#]')).first;
    text = text.substring(text.lastIndexOf('@') + 1);
    text = text.replaceFirst(RegExp(r'^\*?\.'), '');
    final match = RegExp(r'^(\[[^\]]+\]|[^:\[\]]+)(?::(\d{1,5}))?$').firstMatch(text);
    if (match == null) return null;
    var host = match[1]!;
    if (host.startsWith('[')) host = host.substring(1, host.length - 1);
    host = _normaliseHost(host);
    if (host.isEmpty) return null;
    return (host: host, port: match[2] == null ? null : int.parse(match[2]!));
  }
}
