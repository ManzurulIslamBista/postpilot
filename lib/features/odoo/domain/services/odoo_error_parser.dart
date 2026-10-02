import 'dart:convert';

/// What an Odoo error response means, in words a developer can act on.
final class OdooErrorInfo {
  /// `odoo.exceptions.AccessError`, `werkzeug.exceptions.Unauthorized`...
  final String exception;

  /// A short title: "Access denied", "Invalid API key", "Validation failed".
  final String title;

  /// Odoo's own message.
  final String message;

  /// What to check next; null when nothing specific applies.
  final String? hint;

  /// The last line of the Python traceback, where the actual failure is.
  final String? failingLine;

  /// The `file:line` frames inside Odoo and its addons, oldest first.
  final List<String> frames;

  const OdooErrorInfo({
    required this.exception,
    required this.title,
    required this.message,
    this.hint,
    this.failingLine,
    this.frames = const [],
  });
}

abstract final class OdooErrorParser {
  /// Reads [body] as an Odoo error. Returns `null` for anything else (a normal
  /// response, HTML, an error from another server), so callers can show the
  /// banner only when it is really Odoo speaking.
  static OdooErrorInfo? parse(String body, {int? statusCode}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;

    // Legacy JSON-RPC: {"error": {"message": "Odoo Server Error", "data": {...}}}
    Map? data;
    if (json['error'] is Map) {
      final error = json['error'] as Map;
      data = error['data'] is Map ? error['data'] as Map : null;
      if (data == null) return null;
    } else if (json['name'] is String && json.containsKey('message')) {
      // JSON-2: {"name": "...", "message": "...", "arguments": [...], "debug": "..."}
      data = json;
    } else {
      return null;
    }

    final exception = '${data['name'] ?? ''}';
    final message = '${data['message'] ?? (data['arguments'] is List && (data['arguments'] as List).isNotEmpty ? (data['arguments'] as List).first : '')}';
    final debug = data['debug'] is String ? data['debug'] as String : '';
    final (title, hint) = _explain(exception, message, statusCode);
    return OdooErrorInfo(
      exception: exception,
      title: title,
      message: message,
      hint: hint,
      failingLine: _lastLine(debug),
      frames: _frames(debug),
    );
  }

  static (String, String?) _explain(String exception, String message, int? status) {
    final short = exception.split('.').last;
    final unexpected = RegExp(r"unexpected keyword argument '(\w+)'").firstMatch(message);
    if (unexpected != null) {
      return (
        'Unknown parameter',
        'JSON-2 passes every argument by name, and this method has no parameter "${unexpected[1]}". '
            'Check the spelling against the method signature.'
      );
    }
    final missing = RegExp(r"missing \d+ required (?:positional )?arguments?: (.+)$").firstMatch(message);
    if (missing != null) {
      return ('Missing parameter', 'Add ${missing[1]} to the request body.');
    }
    switch (short) {
      case 'Unauthorized':
        return (
          'Invalid API key',
          'The key is wrong, expired or revoked. Create a new one in Odoo under Preferences > Account Security > New API Key, '
              'and put it in the odooApiKey variable.'
        );
      case 'Forbidden':
        return ('Not allowed', 'The key is valid but this user may not use this API or model.');
      case 'NotFound':
        return (
          'Model or method not found',
          'Check the model name (res.partner), the method name and that the module defining it is installed. '
              'The URL must be /json/2/<model>/<method>.'
        );
      case 'AccessError':
        return (
          'Access denied',
          'The API key\'s user has no right to do this. Check access rights (ir.model.access) and record rules for the model.'
        );
      case 'MissingError':
        return ('Record not found', 'A record in "ids" does not exist (it may have been deleted). Search again for current ids.');
      case 'ValidationError':
        return ('Validation failed', 'A constraint on the model rejected the data. Fix the values named in the message.');
      case 'UserError':
        return ('Rejected by a business rule', 'Odoo refused the operation. The message says what to change first.');
      case 'RedirectWarning':
        return ('Needs configuration', 'Odoo asks for a setting to be changed before this can work.');
      case 'IntegrityError':
        return (
          'Database constraint',
          'A required value is missing or a unique value is already used. Check the field named in the message.'
        );
      case 'KeyError':
        return ('Unknown model or field', 'Odoo does not know "$message". Check the spelling, and that the module is installed.');
    }
    if (message.contains('Invalid field') || message.contains('does not exist on model')) {
      return ('Unknown field', 'A field name in the request is not on this model. Run fields_get to list the real ones.');
    }
    if (status != null && status >= 500) return ('Server error', 'Odoo failed while running this call. The traceback shows where.');
    return (short.isEmpty ? 'Odoo error' : short, null);
  }

  static String? _lastLine(String debug) {
    final lines = debug.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.isEmpty ? null : lines.last;
  }

  static final _frame = RegExp(r'File "([^"]*(?:odoo|addons)[^"]*)", line (\d+), in (\w+)');

  static List<String> _frames(String debug) {
    final out = <String>[];
    for (final m in _frame.allMatches(debug)) {
      final path = m[1]!.replaceAll('\\', '/');
      final i = path.indexOf('/addons/');
      final short = i >= 0 ? path.substring(i + 1) : path.split('/').reversed.take(3).toList().reversed.join('/');
      out.add('$short:${m[2]} in ${m[3]}');
    }
    return out.length > 8 ? out.sublist(out.length - 8) : out;
  }
}
