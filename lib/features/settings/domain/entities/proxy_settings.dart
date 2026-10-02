import '../../../../core/network/api_http_response.dart';
import 'settings_json.dart';

final class ProxySettings {
  static const defaultPort = 8080;

  final ProxyMode mode;
  final String host;
  final int port;
  final String username;
  final String password;

  /// Comma-separated hosts that skip a custom proxy, as typed.
  final String bypass;

  const ProxySettings({
    this.mode = ProxyMode.system,
    this.host = '',
    this.port = defaultPort,
    this.username = '',
    this.password = '',
    this.bypass = '',
  });

  factory ProxySettings.fromJson(Map<String, dynamic> json) => ProxySettings(
        mode: SettingsJson.enumOr(json['mode'], ProxyMode.values, ProxyMode.system),
        host: SettingsJson.stringOr(json['host'], ''),
        port: SettingsJson.intOr(json['port'], defaultPort, min: 1, max: 65535),
        username: SettingsJson.stringOr(json['username'], ''),
        password: SettingsJson.stringOr(json['password'], ''),
        bypass: SettingsJson.stringOr(json['bypass'], ''),
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'bypass': bypass,
      };

  ProxySettings copyWith({
    ProxyMode? mode,
    String? host,
    int? port,
    String? username,
    String? password,
    String? bypass,
  }) =>
      ProxySettings(
        mode: mode ?? this.mode,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        bypass: bypass ?? this.bypass,
      );

  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
  static final _pathStart = RegExp(r'[/?#]');
  static final _bracketedHost = RegExp(r'^(\[[^\]]*\])(?::(\d*))?$');
  static final _badHostCharacter = RegExp(r'[\s;,\\<>"@]');
  static final _bypassSeparator = RegExp(r'[,;\s]+');

  /// What the network layer needs. Only a custom proxy carries the rest of the
  /// fields (so a saved password never rides along while it is unused, and two
  /// requests in the same mode share one connection setup): a host pasted as a
  /// URL is taken apart (scheme, path, `user:password@` and `:port` — the
  /// pasted port beats the port field, pasted credentials only fill in for
  /// empty username and password fields), and the bypass text becomes a list
  /// of patterns.
  ProxyConfig toConfig() {
    if (mode != ProxyMode.custom) return ProxyConfig(mode: mode);
    final target = _parseHost();
    return ProxyConfig(
      mode: mode,
      host: target.host,
      port: target.port,
      username: target.username,
      password: target.password,
      bypass: [
        for (final entry in bypass.split(_bypassSeparator))
          if (entry.isNotEmpty) entry,
      ],
    );
  }

  ({String host, int port, String username, String password}) _parseHost() {
    var text = host.trim().replaceFirst(_scheme, '');
    final pathStart = text.indexOf(_pathStart);
    if (pathStart != -1) text = text.substring(0, pathStart);

    var user = username;
    var pass = password;
    final at = text.lastIndexOf('@');
    if (at != -1) {
      final userInfo = text.substring(0, at);
      text = text.substring(at + 1);
      if (username.isEmpty && password.isEmpty) {
        final colon = userInfo.indexOf(':');
        user = _percentDecoded(colon == -1 ? userInfo : userInfo.substring(0, colon));
        pass = colon == -1 ? '' : _percentDecoded(userInfo.substring(colon + 1));
      }
    }

    var hostName = text;
    var portNumber = port;
    final bracketed = _bracketedHost.firstMatch(text);
    if (bracketed != null) {
      hostName = bracketed.group(1)!;
      portNumber = _portOr(bracketed.group(2), portNumber);
    } else {
      // Exactly one colon is `host:port`; several are a bare IPv6 address.
      final colon = text.indexOf(':');
      if (colon != -1 && colon == text.lastIndexOf(':')) {
        final portText = text.substring(colon + 1);
        if (portText.isEmpty || _portOr(portText, 0) != 0) {
          hostName = text.substring(0, colon);
          portNumber = _portOr(portText, portNumber);
        }
      }
    }
    return (host: hostName, port: portNumber, username: user, password: pass);
  }

  static int _portOr(String? text, int fallback) {
    final parsed = int.tryParse(text ?? '');
    return parsed != null && parsed >= 1 && parsed <= 65535 ? parsed : fallback;
  }

  static String _percentDecoded(String text) {
    try {
      return Uri.decodeComponent(text);
    } catch (_) {
      return text;
    }
  }

  /// What is wrong with the custom proxy as it would be used, in words for the
  /// settings pane, or null. A blank host is not a problem: it is reported as
  /// "requests go direct" instead.
  String? get problem {
    if (mode != ProxyMode.custom) return null;
    final config = toConfig();
    if (config.host.isNotEmpty && (_badHostCharacter.hasMatch(config.host) || _hasStrayColon(config.host))) {
      return 'The host must be a bare host name or address such as proxy.example.com, '
          'with the port in the Port field.';
    }
    if (config.hasUnsendableCredentials) return ProxyConfig.unsendableCredentialsMessage;
    if (config.hasHalfCredentials) {
      return 'Fill in both the username and the password to authenticate with the proxy; '
          'with only one of them no credentials are sent.';
    }
    return null;
  }

  /// A colon left in a host that is neither bracketed nor a bare IPv6 address
  /// (`proxy:abc`): the text after it was not a port.
  static bool _hasStrayColon(String hostName) {
    if (hostName.startsWith('[')) return false;
    final colon = hostName.indexOf(':');
    return colon != -1 && colon == hostName.lastIndexOf(':');
  }

  /// The route the proxy fields amount to when it differs from what was typed
  /// (a pasted `http://user@proxy:3128/`), or null. Shown in the settings pane
  /// so a host that was taken apart is not a surprise.
  String? get routeNote {
    if (mode != ProxyMode.custom || host.trim().isEmpty || problem != null) return null;
    final config = toConfig();
    if (config.host == host.trim() && config.port == port) return null;
    return 'Requests go through ${config.host}:${config.port}.';
  }

  @override
  bool operator ==(Object other) =>
      other is ProxySettings &&
      other.mode == mode &&
      other.host == host &&
      other.port == port &&
      other.username == username &&
      other.password == password &&
      other.bypass == bypass;

  @override
  int get hashCode => Object.hash(mode, host, port, username, password, bypass);
}
