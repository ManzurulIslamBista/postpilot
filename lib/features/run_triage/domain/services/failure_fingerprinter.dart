// Pure Dart.
import '../entities/run_record_doc.dart';

/// What kind of thing broke. Also the order ties are broken in: a person looks at a rejected login or a service
/// that is down before a changed field.
enum FailureKind { auth, network, config, blocked, http, assertion, extraction, other }

/// The cause of a failed request, normalised so that requests that failed for the same reason share one [key]:
/// the exact status code (401 and 403 are told apart, and are the "auth-looking" ones), the class of a network
/// error together with the host, an undefined variable by name, a failed check by its type and target. Values that
/// differ from request to request (the expected value, a number inside a path, an id) are left out.
final class FailureFingerprint {
  final String key;
  final FailureKind kind;

  /// A short name for the group: `HTTP 401 Unauthorized`, `Timeout talking to api.shop.test`.
  final String title;

  /// The status code of an HTTP failure.
  final int? status;

  /// The host of a network failure, when the message named it.
  final String? host;

  /// What a check looked at (`data.items[].id`, a header) or the variable that could not be saved.
  final String? target;

  /// The class of a network failure (`timeout`, `dns`, `refused`, `tls`, `dropped`) or the type of a check
  /// (`statusEquals`, `jsonPathEquals`...).
  final String? detail;

  const FailureFingerprint({
    required this.key,
    required this.kind,
    required this.title,
    this.status,
    this.host,
    this.target,
    this.detail,
  });
}

/// Works out the [FailureFingerprint] of a failed [RunResultEntry] from what a record keeps: the status, the error
/// text and the lines the checks wrote. Everything here reads text, so a record imported from the command line is
/// told apart exactly like one the app made.
abstract final class FailureFingerprinter {
  static const _reasons = {
    400: 'Bad Request',
    401: 'Unauthorized',
    403: 'Forbidden',
    404: 'Not Found',
    405: 'Method Not Allowed',
    408: 'Request Timeout',
    409: 'Conflict',
    410: 'Gone',
    415: 'Unsupported Media Type',
    422: 'Unprocessable Entity',
    429: 'Too Many Requests',
    500: 'Internal Server Error',
    501: 'Not Implemented',
    502: 'Bad Gateway',
    503: 'Service Unavailable',
    504: 'Gateway Timeout',
  };

  static FailureFingerprint of(RunResultEntry result) {
    final error = result.error;
    if (error != null && error.trim().isNotEmpty) return _fromError(error);
    final status = result.status;
    // The answer itself is the cause when it is not a success: a failing check on a 500 page is the 500's fault.
    if (status != null && (status < 200 || status >= 300)) return _fromStatus(status);
    for (final line in result.failures) {
      final found = _fromFailureLine(line);
      if (found != null) return found;
    }
    return const FailureFingerprint(key: 'other:unknown', kind: FailureKind.other, title: 'Failed without a message');
  }

  // --- status ---

  static FailureFingerprint _fromStatus(int status) {
    final reason = _reasons[status];
    final title = reason == null ? 'HTTP $status' : 'HTTP $status $reason';
    final kind = status == 401 || status == 403 ? FailureKind.auth : FailureKind.http;
    return FailureFingerprint(key: 'http:$status', kind: kind, title: title, status: status);
  }

  // --- errors (no answer came back, or the request was not sent) ---

  static final _token = RegExp(r'\{\{([^{}]+)\}\}');
  static final _hostPatterns = [
    RegExp(r'''Couldn't find the (?:server|proxy) "([^"]+)"'''),
    RegExp(r'connection to (\S+?) timed out'),
    RegExp(r'Could not connect to (\S+?) within'),
    RegExp(r'(?:server|proxy) at (\S+?)(?:\s|,|\.\s|$)'),
    RegExp(r'secure connection to (\S+?)(?:\s|,|:|\.\s|$)'),
    RegExp(r'^(\S+) can.t be reached'),
    RegExp(r"Failed host lookup: '([^']+)'"),
  ];
  static final _addressPort = RegExp(r'address = ([^,\s]+), port = (\d+)');
  static final _tls = RegExp(r'\b(?:tls|ssl)\b|handshake|certificate|secure connection');

  static FailureFingerprint _fromError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('production lock')) {
      return const FailureFingerprint(
        key: 'blocked:production-lock',
        kind: FailureKind.blocked,
        title: 'Refused by the production lock',
      );
    }
    // The app says "{{x}} (used in the URL) is not defined", the command line "The URL still contains {{x}}".
    if (lower.contains('not defined') || lower.contains('still contains {{')) {
      final names = {for (final m in _token.allMatches(error)) m[1]!.trim()}.toList()..sort();
      if (names.isNotEmpty) {
        return FailureFingerprint(
          key: 'config:variable:${names.join('+')}',
          kind: FailureKind.config,
          title: names.length == 1
              ? 'Undefined variable {{${names.single}}}'
              : 'Undefined variables ${names.map((n) => '{{$n}}').join(', ')}',
          target: names.join(', '),
        );
      }
    }
    if (lower.contains('could not build the request')) {
      return const FailureFingerprint(key: 'config:build', kind: FailureKind.config, title: 'Request could not be built');
    }
    if (lower.contains('the request was not sent') && (lower.contains('token') || lower.contains('oauth'))) {
      return const FailureFingerprint(key: 'auth:renewal', kind: FailureKind.auth, title: 'Token could not be renewed');
    }
    final host = _hostIn(error);
    FailureFingerprint network(String detail, String what) => FailureFingerprint(
          key: 'network:$detail:${host ?? ''}',
          kind: FailureKind.network,
          title: host == null ? what : '$what ($host)',
          host: host,
          detail: detail,
        );
    if (_has(lower, const ['timed out', 'did not answer within', 'took too long', 'timeout', 'could not connect to'])) {
      return network('timeout', 'Timeout');
    }
    if (_has(lower, const ["couldn't find the", 'failed host lookup', 'no such host', 'name or service not known'])) {
      return network('dns', 'Host not found');
    }
    if (_has(lower, const ['refused the connection', 'connection refused', "can't reach", "can't be reached", 'cannot reach', "couldn't reach", 'unreachable'])) {
      return network('refused', 'Connection refused');
    }
    if (_tls.hasMatch(lower)) return network('tls', 'TLS problem');
    if (_has(lower, const ['closed the connection', 'dropped the connection', 'connection reset', 'closed before the whole'])) {
      return network('dropped', 'Connection dropped');
    }
    final first = error.trim().split(RegExp(r'[\r\n]+')).first.trim();
    return FailureFingerprint(key: 'error:${_normalise(first)}', kind: FailureKind.other, title: _clip(first, 90));
  }

  static String? _hostIn(String text) {
    for (final pattern in _hostPatterns) {
      final m = pattern.firstMatch(text);
      if (m != null) return m[1]!.toLowerCase();
    }
    final address = _addressPort.firstMatch(text);
    return address == null ? null : '${address[1]}:${address[2]}'.toLowerCase();
  }

  // --- the lines a check or a variable save wrote ---

  static final _origin = RegExp(r'\s*\(from [^)]*\)\s*$');
  static final _got = RegExp(r'\s*\(got .*\)\s*$');
  static final _statusEquals = RegExp(r'^Status equals ');
  static final _bodyContains = RegExp(r'^Body contains ');
  static final _headerEquals = RegExp(r'^Header (\S+) equals ');
  static final _headerExists = RegExp(r'^Header (\S+) exists$');
  static final _responseTime = RegExp(r'^Response time below ');
  static final _schemaAt = RegExp(r'^(.+) matches the JSON Schema$');
  static final _pathEquals = RegExp(r'^(\S+) equals ');
  static final _pathExists = RegExp(r'^(\S+) exists$');
  static final _saveFailure = RegExp(r'^variable ([^:\s]+): ');
  static final _index = RegExp(r'\[\d+\]');

  static FailureFingerprint? _fromFailureLine(String line) {
    var text = line.trim();
    if (text.startsWith('The response was cut off')) return null;
    text = text.replaceFirst(_origin, '').replaceFirst(_got, '').trim();

    FailureFingerprint check(String type, String target, String title) => FailureFingerprint(
          key: 'assert:$type:$target',
          kind: FailureKind.assertion,
          title: title,
          target: target,
          detail: type,
        );

    final save = _saveFailure.firstMatch(text);
    if (save != null) {
      final name = save[1]!;
      return FailureFingerprint(
        key: 'extract:$name',
        kind: FailureKind.extraction,
        title: 'Could not save {{$name}}',
        target: name,
      );
    }
    if (_statusEquals.hasMatch(text)) return check('statusEquals', 'status', 'Unexpected status code');
    if (text == 'Status is 2xx') return check('statusIn2xx', 'status', 'Status is not 2xx');
    if (_bodyContains.hasMatch(text)) return check('bodyContains', 'body', 'Body misses expected text');
    final headerEq = _headerEquals.firstMatch(text);
    if (headerEq != null) {
      final h = headerEq[1]!.toLowerCase();
      return check('headerEquals', h, 'Wrong header $h');
    }
    final headerEx = _headerExists.firstMatch(text);
    if (headerEx != null) {
      final h = headerEx[1]!.toLowerCase();
      return check('headerExists', h, 'Missing header $h');
    }
    if (_responseTime.hasMatch(text)) return check('responseTimeBelowMs', 'response time', 'Response too slow');
    if (text == 'Body matches the JSON Schema') return check('jsonSchema', 'body', 'Response does not match the schema');
    final schema = _schemaAt.firstMatch(text);
    if (schema != null) return check('jsonSchema', _path(schema[1]), 'Response does not match the schema');
    final pathEq = _pathEquals.firstMatch(text);
    if (pathEq != null) {
      final path = _path(pathEq[1]);
      return check('jsonPathEquals', path, 'Wrong value at $path');
    }
    final pathEx = _pathExists.firstMatch(text);
    if (pathEx != null) {
      final path = _path(pathEx[1]);
      return check('jsonPathExists', path, 'Missing field $path');
    }
    // An HTTP line the command line wrote for a failed status is the status; anything else is a message of its own.
    if (text.isEmpty) return null;
    return FailureFingerprint(key: 'other:${_normalise(text)}', kind: FailureKind.other, title: _clip(text, 90));
  }

  /// `data.items[3].id` and `data.items[0].id` are one target.
  static String _path(String? path) => (path ?? '').replaceAll(_index, '[]');

  // --- helpers ---

  static bool _has(String lower, List<String> needles) => needles.any(lower.contains);

  /// What a free-text message keeps when its numbers, quoted values and identifiers are taken out, so two failures
  /// that differ only by an id share a key.
  static String _normalise(String text) {
    final lower = text
        .toLowerCase()
        .replaceAll(RegExp(r'"[^"]*"|\x27[^\x27]*\x27'), '"_"')
        .replaceAll(RegExp(r'[0-9a-f]{8,}'), '#')
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return lower.length <= 80 ? lower : lower.substring(0, 80);
  }

  static String _clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max - 1)}…';
}
