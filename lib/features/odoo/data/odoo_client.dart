import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../../settings/domain/services/tool_request_options.dart';
import '../domain/entities/odoo_connection.dart';
import '../domain/entities/odoo_result.dart';
import '../domain/services/odoo_json2.dart';
import 'odoo_schema_service.dart';
import 'odoo_transport.dart';

// Where they always were, for what already imports them from here.
export '../domain/entities/odoo_connection.dart';
export '../domain/entities/odoo_result.dart';

/// Calls an Odoo server, through its External JSON-2 API (Odoo 19 and later) or through the JSON-RPC session of
/// Odoo 18 and older, whichever [OdooConnection.protocol] says. Used by Odoo Studio to test a connection, list
/// models, read `fields_get`, run searches and look records up; the requests the user saves in a collection go
/// through the normal sender.
final class OdooClient {
  final Json2Transport _json2;
  final JsonRpcTransport _jsonRpc;

  /// The fields and models read so far, kept per server and database until [OdooSchemaService.clear] is asked for.
  late final OdooSchemaService schema = OdooSchemaService(call);

  /// [settings] are the app's timeout, proxy and certificate settings; without them a call is sent with the defaults.
  OdooClient(ApiClient api, {SettingsRepository? settings})
      : _json2 = Json2Transport(api, options: _optionsOf(settings)),
        _jsonRpc = JsonRpcTransport(api, options: _optionsOf(settings));

  // A saved Odoo request goes through the normal sender with these settings; a call from Studio must too,
  // or it fails behind a proxy where the saved request works.
  static ApiRequestOptions Function() _optionsOf(SettingsRepository? settings) =>
      () => ToolRequestOptions.resolve(settings, maxResponseBytes: 8 * 1024 * 1024);

  OdooTransport transportFor(OdooConnection connection) =>
      connection.protocol == OdooProtocol.jsonRpc ? _jsonRpc : _json2;

  Future<OdooResult> call(OdooConnection connection, OdooCall call) => transportFor(connection).call(connection, call);

  /// Tests the credentials (see [OdooTransport.connect]); with JSON-RPC this opens the session the next calls use.
  Future<OdooResult> connect(OdooConnection connection) => transportFor(connection).connect(connection);

  /// The databases a server lists, for the Connect tab's "Find databases".
  Future<OdooDatabases> databases(OdooConnection connection) => _jsonRpc.databases(connection);

  /// Closes the session kept for [connection] (a JSON-RPC login); the next call logs in again.
  void forgetSession(OdooConnection connection) => _jsonRpc.forget(connection);

  /// The user id of the open JSON-RPC session, which the error doctor uses to look at that user's groups.
  int? sessionUserId(OdooConnection connection) => _jsonRpc.sessionOf(connection)?.uid;
}
