import 'dart:convert';
import 'dart:math';
import 'mock_http.dart';

/// Fills `{{...}}` placeholders in a saved example's body with values from the request that is being answered:
///
/// * `{{$guid}}`, `{{$timestamp}}` (Unix seconds), `{{$isoTimestamp}}`, `{{$randomInt}}`
/// * `{{path.id}}` for a path parameter, `{{query.page}}`, `{{header.x-tenant}}`
/// * `{{body.name}}` and `{{body.address.city}}` (`body.items.0.id` for a list) from a JSON request body
///
/// Anything else between double braces is left as it is, so an example that really contains `{{token}}` is served
/// unchanged. In a JSON body the substituted value is written as JSON: inside a string it is escaped, outside one a
/// string gets its quotes and a number stays a number (`{"id": {{path.id}}}` with `/users/42` gives `{"id": 42}`).
abstract final class MockTemplate {
  static final _placeholder = RegExp(r'\{\{\s*(\$[A-Za-z]+|(?:path|query|header)\.[^\s{}]+|body(?:\.[^\s{}]+)?)\s*\}\}');
  static const _dynamicNames = {r'$guid', r'$timestamp', r'$isoTimestamp', r'$randomInt'};
  static final _number = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?$');

  /// Whether [text] has anything to fill.
  static bool hasPlaceholders(String text) => text.contains('{{') && _placeholder.hasMatch(text);

  static String render(
    String text,
    MockRequest request, {
    Map<String, String> pathParams = const {},
    DateTime? now,
    String Function()? newGuid,
    Random? random,
  }) {
    if (!hasPlaceholders(text)) return text;
    final rng = random ?? Random();
    final clock = now ?? DateTime.now();
    final json = text.trimLeft().startsWith('{') || text.trimLeft().startsWith('[');
    final out = StringBuffer();
    var last = 0;
    var inString = false;
    for (final m in _placeholder.allMatches(text)) {
      final before = text.substring(last, m.start);
      out.write(before);
      if (json) inString = _endsInsideString(before, inString);
      last = m.end;
      final token = m[1]!;
      if (token.startsWith(r'$') && !_dynamicNames.contains(token)) {
        // Not one of ours: whatever the example holds is served as it is.
        out.write(m[0]);
        continue;
      }
      final (:found, :value) = _lookup(token, request, pathParams, clock, newGuid ?? () => guid(rng), rng);
      out.write(_write(value, found: found, json: json, inString: inString, fromText: !token.startsWith('body.') && !token.startsWith(r'$')));
    }
    out.write(text.substring(last));
    return out.toString();
  }

  /// A random version 4 UUID.
  static String guid(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes.sublist(from, to).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// Whether the text after [before] is inside a JSON string, [inString] being where [before] started.
  static bool _endsInsideString(String before, bool inString) {
    var inside = inString;
    for (var i = 0; i < before.length; i++) {
      final c = before[i];
      if (inside && c == r'\') {
        i++;
      } else if (c == '"') {
        inside = !inside;
      }
    }
    return inside;
  }

  static ({bool found, Object? value}) _lookup(
    String token,
    MockRequest request,
    Map<String, String> pathParams,
    DateTime now,
    String Function() newGuid,
    Random rng,
  ) {
    switch (token) {
      case r'$guid':
        return (found: true, value: newGuid());
      case r'$timestamp':
        return (found: true, value: now.millisecondsSinceEpoch ~/ 1000);
      case r'$isoTimestamp':
        return (found: true, value: now.toUtc().toIso8601String());
      case r'$randomInt':
        return (found: true, value: rng.nextInt(1000));
    }
    if (token.startsWith(r'$')) return (found: false, value: null);
    final dot = token.indexOf('.');
    final source = dot < 0 ? token : token.substring(0, dot);
    final name = dot < 0 ? '' : token.substring(dot + 1);
    switch (source) {
      case 'path':
        final v = pathParams[name];
        return (found: v != null, value: v);
      case 'query':
        final v = request.queryValue(name);
        return (found: v != null, value: v);
      case 'header':
        final v = request.header(name);
        return (found: v != null, value: v);
      case 'body':
        return _bodyValue(request.bodyJson, name);
    }
    return (found: false, value: null);
  }

  static ({bool found, Object? value}) _bodyValue(Object? json, String path) {
    if (path.isEmpty) return (found: json != null, value: json);
    Object? current = json;
    for (final part in path.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else if (current is List) {
        final i = int.tryParse(part);
        if (i == null || i < 0 || i >= current.length) return (found: false, value: null);
        current = current[i];
      } else {
        return (found: false, value: null);
      }
    }
    return (found: true, value: current);
  }

  static String _write(Object? value, {required bool found, required bool json, required bool inString, required bool fromText}) {
    if (!json) return !found || value == null ? '' : _plain(value);
    if (inString) return !found || value == null ? '' : _escape(_plain(value));
    if (!found || value == null) return 'null';
    // Text from the URL or a header is a number when it looks like one.
    if (fromText && value is String && _number.hasMatch(value)) return value;
    return jsonEncode(value);
  }

  static String _plain(Object value) => value is String ? value : (value is num || value is bool ? '$value' : jsonEncode(value));

  /// The inside of a JSON string literal for [text].
  static String _escape(String text) {
    final quoted = jsonEncode(text);
    return quoted.substring(1, quoted.length - 1);
  }
}
