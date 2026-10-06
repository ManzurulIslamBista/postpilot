import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../../settings/domain/services/tool_request_options.dart';
import '../domain/services/odoo_error_parser.dart';
import '../domain/services/odoo_json2.dart';

/// Where an Odoo server is and how to authenticate to it.
final class OdooConnection {
  final String baseUrl;
  final String database;
  final String apiKey;

  const OdooConnection({required this.baseUrl, this.database = '', required this.apiKey});

  bool get isComplete => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// Without a scheme, `https://` is assumed; trailing slashes are dropped.
  /// This is also what is saved into an environment: the sender would
  /// otherwise assume `http://` for a bare host and send the API key unencrypted.
  String get normalizedUrl {
    var u = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.contains('://')) u = 'https://$u';
    return u;
  }

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

final class OdooResult {
  final int status;
  final String body;

  /// The decoded body; `null` when it was not JSON.
  final Object? json;
  final OdooErrorInfo? error;
  final Duration duration;

  const OdooResult({required this.status, required this.body, required this.json, required this.error, required this.duration});

  bool get ok => status >= 200 && status < 300 && error == null;
}

/// Calls an Odoo server through its External JSON-2 API. Used by Odoo Studio
/// to test a connection, list models, read `fields_get` and run searches;
/// the requests the user saves in a collection go through the normal sender.
final class OdooClient {
  final ApiClient _api;

  /// The app's timeout, proxy and certificate settings; without them a call is sent with the defaults.
  final SettingsRepository? _settings;

  const OdooClient(this._api, {this._settings});

  Future<OdooResult> call(OdooConnection connection, OdooCall call) async {
    final response = await _api.send(
      ApiRequestSpec(
        method: 'POST',
        url: '${connection.normalizedUrl}${call.path}',
        headers: OdooJson2.headers(apiKey: connection.apiKey.trim(), database: connection.database.trim()),
        body: utf8.encode(jsonEncode(call.body)),
        // A saved Odoo request goes through the normal sender with these settings; a call from Studio must too,
        // or it fails behind a proxy where the saved request works.
        options: ToolRequestOptions.resolve(_settings, maxResponseBytes: 8 * 1024 * 1024),
      ),
    );
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // An HTML error page from a proxy, for instance.
    }
    return OdooResult(
      status: response.statusCode,
      body: text,
      json: json,
      error: OdooErrorParser.parse(text, statusCode: response.statusCode),
      duration: response.duration,
    );
  }
}
