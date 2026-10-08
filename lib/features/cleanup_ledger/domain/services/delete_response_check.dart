// Pure Dart (no Flutter): the app and the command line judge the answer to a delete the same way.
import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';

/// Whether the answer to an undo request means the record is gone.
abstract final class DeleteResponseCheck {
  static const _longest = 64 * 1024;

  /// Why the answer is not a delete that worked; null when it is. A 2xx counts, except for an Odoo 18 answer, which says
  /// 200 whatever happened and puts the error in the body. The reason names the status and, when the server explained
  /// itself, its own sentence (masked, one line).
  static String? failureOf({required int statusCode, String statusMessage = '', required String body}) {
    final message = _messageOf(body);
    if (statusCode < 200 || statusCode >= 300) {
      final status = 'HTTP $statusCode${statusMessage.isEmpty ? '' : ' $statusMessage'}';
      return message == null ? status : '$status: $message';
    }
    if (body.length < _longest && body.contains('"error"')) {
      try {
        final json = jsonDecode(body);
        if (json is Map && json['jsonrpc'] != null && json['error'] != null) return message ?? 'The server answered with an error.';
      } on FormatException {
        // not JSON: a success
      }
    }
    return null;
  }

  /// The server's own explanation, from an Odoo error (`message`, or `error.data.message`) or a REST one
  /// (`message`, `error`, `detail`).
  static String? _messageOf(String body) {
    if (body.isEmpty || body.length > _longest) return null;
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final error = json['error'];
      final data = error is Map ? error['data'] : null;
      // Odoo's JSON-RPC puts the useful sentence in error.data.message; error.message is only "Odoo Server Error".
      final candidates = [
        json['message'],
        if (data is Map) data['message'],
        if (error is Map) error['message'] else error,
        json['detail'],
      ];
      for (final c in candidates) {
        if (c is String && c.trim().isNotEmpty) {
          final line = c.trim().split(RegExp(r'[\r\n]+')).first;
          return SecretMasker.maskMessage(line.length > 160 ? '${line.substring(0, 160)}…' : line);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
