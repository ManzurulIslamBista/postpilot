import 'dart:convert';
import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class NodeAxiosGenerator implements CodeGenerator {
  const NodeAxiosGenerator();

  @override
  String get id => 'nodejs_axios';
  @override
  String get label => 'Node.js (axios)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('const axios = require("axios");')
      ..writeln()
      ..writeln('const config = {')
      ..writeln('  method: ${jsString(spec.method.toLowerCase())},')
      ..writeln('  url: ${jsString(spec.url)},');
    if (spec.headers.isNotEmpty) {
      final entries = spec.headers.entries.map((e) => '    ${jsString(e.key)}: ${jsString(e.value)}');
      buffer
        ..writeln('  headers: {')
        ..writeln(entries.join(',\n'))
        ..writeln('  },');
    }
    if (body != null) {
      buffer.writeln('  data: ${jsString(body)},');
      if (_axiosWouldRewrite(spec, body)) buffer.writeln('  transformRequest: [(data) => data],');
    }
    buffer
      ..writeln('};')
      ..writeln()
      ..writeln('axios.request(config)')
      ..writeln('  .then((response) => console.log(response.data))')
      ..write('  .catch((error) => console.error(error));');
    return buffer.toString();
  }

  // Under a JSON Content-Type axios JSON-encodes a string body that is not
  // itself valid JSON (wrapping it in quotes), so it would send other bytes.
  bool _axiosWouldRewrite(ResolvedRequestSpec spec, String body) {
    final contentType = headerValueOf(spec, 'content-type');
    if (contentType == null || !contentType.contains('application/json')) return false;
    try {
      jsonDecode(body);
      return false;
    } on FormatException {
      return true;
    }
  }
}
