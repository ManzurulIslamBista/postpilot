import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class DartHttpGenerator implements CodeGenerator {
  const DartHttpGenerator();

  @override
  String get id => 'dart_http';
  @override
  String get label => 'Dart (http)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final buffer = StringBuffer()
      ..writeln("import 'package:http/http.dart' as http;")
      ..writeln()
      ..writeln('void main() async {')
      ..writeln('  final uri = Uri.parse(${dartString(spec.url)});');

    final hasHeaders = spec.headers.isNotEmpty;
    if (hasHeaders) {
      buffer.writeln('  final headers = {');
      for (final e in spec.headers.entries) {
        buffer.writeln('    ${dartString(e.key)}: ${dartString(e.value)},');
      }
      buffer.writeln('  };');
    }

    final body = bodyTextOf(spec);
    final shortcut = _shortcutFor(spec.method, hasBody: body != null);
    if (shortcut != null) {
      final args = [
        'uri',
        if (hasHeaders) 'headers: headers',
        if (body != null) 'body: ${dartString(body)}',
      ].join(', ');
      buffer
        ..writeln('  final response = await http.$shortcut($args);')
        ..writeln('  print(response.body);');
    } else {
      buffer.writeln('  final request = http.Request(${dartString(spec.method)}, uri);');
      if (hasHeaders) buffer.writeln('  request.headers.addAll(headers);');
      if (body != null) buffer.writeln('  request.body = ${dartString(body)};');
      buffer
        ..writeln('  final response = await http.Response.fromStream(await request.send());')
        ..writeln('  print(response.body);');
    }
    buffer.write('}');
    return buffer.toString();
  }

  // package:http's get/head take no body, and it has no shortcut for other verbs.
  String? _shortcutFor(String method, {required bool hasBody}) => switch (method.toUpperCase()) {
        'GET' when !hasBody => 'get',
        'HEAD' when !hasBody => 'head',
        'POST' => 'post',
        'PUT' => 'put',
        'PATCH' => 'patch',
        'DELETE' => 'delete',
        _ => null,
      };
}
