import '../services/odoo_error_parser.dart';

/// The answer to one call, whichever API it went through. For JSON-RPC the envelope is already taken off: [json] and
/// [body] hold the `result`, exactly what JSON-2 would have answered, so what reads them does not care.
final class OdooResult {
  final int status;
  final String body;

  /// The decoded body; `null` when it was not JSON.
  final Object? json;
  final OdooErrorInfo? error;
  final Duration duration;

  const OdooResult({required this.status, required this.body, required this.json, required this.error, required this.duration});

  /// A failure the app found by itself (a wrong password, a missing session cookie) rather than one the server
  /// reported, in the shape a server error has, so it is shown the same way.
  factory OdooResult.failure({
    required String title,
    required String message,
    String? hint,
    int status = 0,
    String exception = '',
    Duration duration = Duration.zero,
  }) =>
      OdooResult(
        status: status,
        body: '',
        json: null,
        error: OdooErrorInfo(exception: exception, title: title, message: message, hint: hint),
        duration: duration,
      );

  bool get ok => status >= 200 && status < 300 && error == null;

  /// Why the call failed, in one sentence: Odoo's own message when it sent one, otherwise what the answer was.
  /// [jsonRpc] picks which API the "not JSON" hint talks about.
  String failureText({bool jsonRpc = false}) {
    final message = error?.message ?? '';
    if (message.isNotEmpty) return message;
    if (json != null) return 'The server answered $status.';
    return 'The server answered $status. The body is not JSON: is this an Odoo '
        '${jsonRpc ? 'server with the JSON-RPC API (Odoo 18 and older)' : '19+ server with the JSON-2 API'}?';
  }
}

/// The databases a server offers, from `/web/database/list`. Many servers switch that listing off, so [problem]
/// says so and the person types the name instead.
final class OdooDatabases {
  final List<String> names;
  final String? problem;
  const OdooDatabases(this.names, {this.problem});
}
