import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form is a `files` list (a text part has no file name: `(None, value)`), which also writes the boundary; a
  /// binary body is the open file.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()..writeln('import requests')..writeln();
    if (headers.isNotEmpty) {
      buffer.writeln('headers = {');
      for (final e in headers.entries) {
        buffer.writeln('    ${pythonString(e.key)}: ${pythonString(e.value)},');
      }
      buffer.writeln('}');
    }
    if (multipart != null) {
      buffer.writeln('files = [');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('    (${pythonString(name)}, (None, ${pythonString(value)})),');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              '    (${pythonString(name)}, (${pythonString(file.fileName)}, open(${pythonString(file.path)}, "rb"), '
              '${pythonString(file.contentType)})),',
            );
        }
      }
      buffer.writeln(']');
    } else {
      buffer.writeln('payload = open(${pythonString(binaryFileOf(spec)!.path)}, "rb")');
    }
    buffer.write('response = requests.request(${pythonString(spec.method)}, ${pythonString(spec.url)}');
    if (headers.isNotEmpty) buffer.write(', headers=headers');
    buffer
      ..write(multipart != null ? ', files=files' : ', data=payload')
      ..writeln(')')
      ..write('print(response.text)');
    return buffer.toString();
  }
}
