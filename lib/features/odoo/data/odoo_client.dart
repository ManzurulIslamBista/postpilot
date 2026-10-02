import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
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
  String get normalizedUrl {
    var u = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.contains('://')) u = 'https://$u';
    return u;
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
  const OdooClient(this._api);

  Future<OdooResult> call(OdooConnection connection, OdooCall call) async {
    final response = await _api.send(
      ApiRequestSpec(
        method: 'POST',
        url: '${connection.normalizedUrl}${call.path}',
        headers: OdooJson2.headers(apiKey: connection.apiKey.trim(), database: connection.database.trim()),
        body: utf8.encode(jsonEncode(call.body)),
        options: const ApiRequestOptions(maxResponseBytes: 8 * 1024 * 1024),
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
