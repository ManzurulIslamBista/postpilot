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
  static final _bypassSeparator = RegExp(r'[,;\s]+');

  /// What the network layer needs. Only a custom proxy carries the rest of the
  /// fields (so a saved password never rides along while it is unused, and two
  /// requests in the same mode share one connection setup): a host pasted as a
  /// URL loses its scheme and trailing slash, and the bypass text becomes a
  /// list of patterns.
  ProxyConfig toConfig() => mode != ProxyMode.custom
      ? ProxyConfig(mode: mode)
      : ProxyConfig(
          mode: mode,
          host: host.trim().replaceFirst(_scheme, '').replaceFirst(RegExp(r'/+$'), ''),
          port: port,
          username: username,
          password: password,
          bypass: [
            for (final entry in bypass.split(_bypassSeparator))
              if (entry.isNotEmpty) entry,
          ],
        );

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
