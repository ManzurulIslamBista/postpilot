import 'dart:convert';
import '../../documentation/domain/services/secret_masker.dart';
import '../../scripting/domain/entities/assertion_entity.dart';

/// A request the model proposed from a description.
final class AiRequestSpec {
  final String name;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;

  const AiRequestSpec({required this.name, required this.method, required this.url, this.headers = const {}, this.body});
}

/// The prompts and the readers of the answers, kept apart from the network so
/// they can be tested and so the person can see exactly what would be sent.
abstract final class AiTasks {
  static const maxBodyChars = 12000;

  static const _persona = 'You are an API debugging assistant inside PostPilot, a Postman-like API client. '
      'Be concrete and brief. Answer in the language of the question. Never invent data that is not in the input.';

  // --- explain --------------------------------------------------------------------

  static const explainSystem = '$_persona '
      'The user shows one HTTP request and its response. Explain in plain words what the response means. '
      'If it is an error, give the most likely cause and the exact change to try, as a short numbered list. '
      'For Odoo errors name the model, field or access right involved. Keep it under 200 words.';

  /// What is sent to the model: every credential is masked first.
  static String explainInput({
    required String method,
    required String url,
    required int statusCode,
    required String statusText,
    Map<String, String> requestHeaders = const {},
    String? requestBody,
    Map<String, String> responseHeaders = const {},
    required String responseBody,
    String? question,
  }) {
    String headers(Map<String, String> h) => h.entries.map((e) => '${e.key}: ${SecretMasker.maskValue(e.key, e.value)}').join('\n');
    String clip(String s) => s.length <= maxBodyChars ? s : '${s.substring(0, maxBodyChars)}\n… (cut: ${s.length - maxBodyChars} more characters)';
    final b = StringBuffer()
      ..writeln('REQUEST')
      ..writeln('$method ${SecretMasker.maskUrl(url)}')
      ..writeln(headers(requestHeaders));
    if (requestBody != null && requestBody.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln(clip(SecretMasker.maskBody(requestBody)));
    }
    b
      ..writeln()
      ..writeln('RESPONSE')
      ..writeln('$statusCode $statusText')
      ..writeln(headers(responseHeaders))
      ..writeln()
      ..writeln(clip(SecretMasker.maskBody(responseBody)));
    if (question != null && question.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('QUESTION: ${question.trim()}');
    }
    return b.toString();
  }

  // --- tests ----------------------------------------------------------------------

  static const testsSystem = '$_persona '
      'Propose automated checks for the response. Reply with ONLY a JSON array, no prose, no code fence. '
      'Each item: {"type": one of ["statusEquals","statusIn2xx","bodyContains","jsonPathEquals","jsonPathExists","headerEquals","headerExists","responseTimeBelowMs"], '
      '"path": a JSON path like data.items[0].id or a header name (empty when not needed), "expected": the expected value as a string (empty when not needed)}. '
      'Prefer stable facts (status, required fields, types of ids) over volatile values (timestamps, random ids). At most 8 items.';

  static List<AssertionEntity> parseAssertions(String reply) {
    final json = _extractJson(reply);
    if (json is! List) return const [];
    final out = <AssertionEntity>[];
    for (final item in json.whereType<Map>()) {
      final name = '${item['type']}';
      final type = AssertionType.values.where((t) => t.name == name).firstOrNull;
      if (type == null || type == AssertionType.jsonSchema) continue;
      out.add(AssertionEntity(type: type, path: '${item['path'] ?? ''}', expected: '${item['expected'] ?? ''}'));
      if (out.length >= 8) break;
    }
    return out;
  }

  // --- request from a description -------------------------------------------------

  static const requestSystem = '$_persona '
      'Turn the description into ONE HTTP request. Reply with ONLY a JSON object, no prose, no code fence: '
      '{"name": short title, "method": GET|POST|PUT|PATCH|DELETE, "url": full URL (use {{baseUrl}} when the host is unknown), '
      '"headers": {"Name": "value"}, "body": JSON body as a string or null}. '
      'Use {{variables}} for secrets such as {{token}}; never invent a real credential. For Odoo 19+ use POST {{odooUrl}}/json/2/<model>/<method> '
      'with Authorization: bearer {{odooApiKey}} and named arguments in the JSON body.';

  static AiRequestSpec? parseRequest(String reply) {
    final json = _extractJson(reply);
    if (json is! Map) return null;
    final url = '${json['url'] ?? ''}'.trim();
    if (url.isEmpty) return null;
    final method = '${json['method'] ?? 'GET'}'.toUpperCase();
    if (!const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'}.contains(method)) return null;
    final headers = <String, String>{};
    final h = json['headers'];
    if (h is Map) {
      h.forEach((k, v) => headers['$k'] = '$v');
    }
    final body = json['body'];
    return AiRequestSpec(
      name: '${json['name'] ?? ''}'.trim().isEmpty ? '$method $url' : '${json['name']}'.trim(),
      method: method,
      url: url,
      headers: headers,
      body: body == null ? null : (body is String ? body : const JsonEncoder.withIndent('  ').convert(body)),
    );
  }

  /// The first JSON value in [reply], tolerating a code fence or a sentence around it.
  static Object? _extractJson(String reply) {
    var text = reply.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence[1]!.trim();
    try {
      return jsonDecode(text);
    } on FormatException {
      // Fall through to scanning for the first bracket.
    }
    final start = text.indexOf(RegExp(r'[\[{]'));
    if (start < 0) return null;
    final open = text[start];
    final close = open == '[' ? ']' : '}';
    final end = text.lastIndexOf(close);
    if (end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      return null;
    }
  }
}
