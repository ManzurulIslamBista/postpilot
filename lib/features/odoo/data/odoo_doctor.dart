// Pure Dart (no Flutter).
import '../../environments/domain/repositories/environment_repository.dart';
import '../domain/services/odoo_error_parser.dart';
import 'odoo_client.dart';
import 'odoo_error_doctor.dart';

/// What the doctor found, and on which server it looked.
final class OdooDoctorAnswer {
  final OdooDoctorReport report;

  /// The server asked (the active environment's), without credentials, so a person can see which one answered.
  final String server;
  const OdooDoctorAnswer(this.report, this.server);
}

/// The error doctor for the app: it asks the server of the active environment, as the user of that environment, and
/// for a JSON-RPC session also names the user whose groups to look at. Read-only (see [OdooErrorDoctor]).
final class OdooDoctor {
  final EnvironmentRepository _environments;
  final OdooClient _client;
  final OdooErrorDoctor _doctor;

  OdooDoctor(this._environments, this._client) : _doctor = OdooErrorDoctor(_client.call, _client.schema);

  Future<OdooDoctorAnswer> diagnose(OdooErrorInfo info, {String? model}) async {
    final connection = OdooConnection.fromVariables(await _environments.getActiveVariables());
    final report = await _doctor.investigate(connection, info, userId: _client.sessionUserId(connection), model: model);
    return OdooDoctorAnswer(report, connection.normalizedUrl);
  }
}
