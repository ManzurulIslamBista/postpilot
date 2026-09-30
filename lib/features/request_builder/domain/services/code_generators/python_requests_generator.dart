import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class PythonRequestsGenerator implements CodeGenerator {
  const PythonRequestsGenerator();

  @override
  String get id => 'python_requests';
  @override
  String get label => 'Python (requests)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final buffer = StringBuffer()..writeln('import requests')..writeln();
    if (spec.headers.isNotEmpty) {
      buffer.writeln('headers = {');
      for (final e in spec.headers.entries) {
        buffer.writeln('    ${pythonString(e.key)}: ${pythonString(e.value)},');
      }
      buffer.writeln('}');
    }
    final body = bodyTextOf(spec);
    if (body != null) {
      // requests would send a str body as Latin-1 and fail on other characters.
      final encode = body.runes.any((r) => r > 0x7F) ? ".encode('utf-8')" : '';
      buffer.writeln('payload = ${pythonString(body)}$encode');
    }
    buffer.write('response = requests.request(${pythonString(spec.method)}, ${pythonString(spec.url)}');
    if (spec.headers.isNotEmpty) buffer.write(', headers=headers');
    if (body != null) buffer.write(', data=payload');
    buffer
      ..writeln(')')
      ..write('print(response.text)');
    return buffer.toString();
  }
}
