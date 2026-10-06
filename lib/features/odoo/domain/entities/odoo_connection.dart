/// Which of Odoo's two external APIs a server is spoken to with.
enum OdooProtocol {
  /// Odoo 19 and later: `POST /json/2/<model>/<method>`, an API key as bearer token, named arguments.
  json2('json2', 'Odoo 19+ JSON-2 (API key)'),

  /// Odoo 18 and earlier: a session from `POST /web/session/authenticate` (database, login and password or API key),
  /// then `POST /web/dataset/call_kw/<model>/<method>` with the session cookie and positional arguments.
  jsonRpc('jsonrpc', 'Odoo ≤18 JSON-RPC (login + password/API key)');

  /// The value kept in the `odooProtocol` environment variable.
  final String id;
  final String label;
  const OdooProtocol(this.id, this.label);

  /// Anything but `jsonrpc` is the default, so an environment saved before the option existed keeps working.
  static OdooProtocol fromId(String? id) {
    final text = (id ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return text == 'jsonrpc' || text == 'rpc' ? jsonRpc : json2;
  }
}

/// Where an Odoo server is and how to authenticate to it.
final class OdooConnection {
  final String baseUrl;
  final String database;

  /// The API key with [OdooProtocol.json2]; the password (or an API key used as one) with [OdooProtocol.jsonRpc].
  final String apiKey;
  final OdooProtocol protocol;

  /// The user name of an [OdooProtocol.jsonRpc] login; unused with JSON-2, where the key names the user.
  final String login;

  const OdooConnection({
    required this.baseUrl,
    this.database = '',
    required this.apiKey,
    this.protocol = OdooProtocol.json2,
    this.login = '',
  });

  /// What an environment holds (`odooUrl`, `odooDb`, `odooApiKey` or `odooLogin` + `odooPassword`, `odooProtocol`),
  /// so every tool of Studio and the request tab talks to the server the active environment points at.
  factory OdooConnection.fromVariables(Map<String, String> variables) {
    final protocol = OdooProtocol.fromId(variables['odooProtocol']);
    final secret = protocol == OdooProtocol.jsonRpc
        ? (variables['odooPassword'] ?? variables['odooApiKey'] ?? '')
        : (variables['odooApiKey'] ?? '');
    return OdooConnection(
      baseUrl: variables['odooUrl'] ?? '',
      database: variables['odooDb'] ?? '',
      apiKey: secret,
      protocol: protocol,
      login: variables['odooLogin'] ?? '',
    );
  }

  OdooConnection copyWith({String? baseUrl, String? database, String? apiKey, OdooProtocol? protocol, String? login}) =>
      OdooConnection(
        baseUrl: baseUrl ?? this.baseUrl,
        database: database ?? this.database,
        apiKey: apiKey ?? this.apiKey,
        protocol: protocol ?? this.protocol,
        login: login ?? this.login,
      );

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      (protocol == OdooProtocol.json2 || login.trim().isNotEmpty);

  /// What is missing, in words for the person who has to type it; null when [isComplete].
  String? get missing {
    if (baseUrl.trim().isEmpty) return 'Enter the server URL first.';
    if (protocol == OdooProtocol.jsonRpc) {
      if (login.trim().isEmpty || apiKey.trim().isEmpty) return 'Enter the login and the password (or API key) first.';
      return null;
    }
    return apiKey.trim().isEmpty ? 'Enter the server URL and an API key first.' : null;
  }

  /// Without a scheme, `https://` is assumed; trailing slashes are dropped.
  /// This is also what is saved into an environment: the sender would
  /// otherwise assume `http://` for a bare host and send the API key unencrypted.
  String get normalizedUrl {
    var u = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.contains('://')) u = 'https://$u';
    return u;
  }

  /// Names one cached session or schema: the same server, database and user.
  String get identity => '${normalizedUrl.toLowerCase()}|${database.trim()}|${protocol == OdooProtocol.jsonRpc ? login.trim() : ''}';

  /// True when the API key would cross a network unencrypted: `http://` to a
  /// host that is neither this computer nor a private network.
  bool get sendsKeyUnencrypted {
    final u = normalizedUrl;
    if (!u.toLowerCase().startsWith('http://')) return false;
    final host = Uri.tryParse(u)?.host.toLowerCase() ?? '';
    return host.isNotEmpty && !isPrivateHost(host);
  }

  /// Loopback, private-range and intranet-style names, where plain `http://`
  /// does not leave the owner's own network.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) return true;
    if (h.contains(':')) return h == '::1' || h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd');
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(h);
    if (v4 != null) {
      final a = int.parse(v4[1]!);
      final b = int.parse(v4[2]!);
      return a == 10 || a == 127 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
    }
    return !h.contains('.');
  }
}
