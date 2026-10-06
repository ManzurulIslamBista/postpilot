import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form is a `MultipartRequest` (package:http writes the boundary and the header; `MultipartFile.fromPath`
  /// streams the file from disk); a binary body is the bytes of the file.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer();
    if (multipart != null) {
      buffer
        ..writeln("import 'package:http/http.dart' as http;")
        ..writeln("import 'package:http_parser/http_parser.dart' show MediaType;");
    } else {
      buffer
        ..writeln("import 'dart:io';")
        ..writeln()
        ..writeln("import 'package:http/http.dart' as http;");
    }
    buffer
      ..writeln()
      ..writeln('void main() async {')
      ..writeln('  final uri = Uri.parse(${dartString(spec.url)});');
    if (multipart != null) {
      buffer.writeln('  final request = http.MultipartRequest(${dartString(spec.method)}, uri);');
    } else {
      buffer.writeln('  final request = http.Request(${dartString(spec.method)}, uri);');
    }
    if (headers.isNotEmpty) {
      buffer.writeln('  request.headers.addAll({');
      for (final e in headers.entries) {
        buffer.writeln('    ${dartString(e.key)}: ${dartString(e.value)},');
      }
      buffer.writeln('  });');
    }
    if (multipart != null) {
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('  request.fields[${dartString(name)}] = ${dartString(value)};');
          case UploadFilePart(:final name, :final file):
            final type = file.contentType.split(';').first.trim().split('/');
            buffer
              ..writeln('  request.files.add(await http.MultipartFile.fromPath(')
              ..writeln('    ${dartString(name)},')
              ..writeln('    ${dartString(file.path)},')
              ..writeln('    filename: ${dartString(file.fileName)},')
              ..writeln(
                '    contentType: MediaType(${dartString(type.first)}, ${dartString(type.length > 1 ? type[1] : '*')}),',
              )
              ..writeln('  ));');
        }
      }
    } else {
      buffer.writeln('  request.bodyBytes = await File(${dartString(binaryFileOf(spec)!.path)}).readAsBytes();');
    }
    buffer
      ..writeln('  final response = await http.Response.fromStream(await request.send());')
      ..writeln('  print(response.body);')
      ..write('}');
    return buffer.toString();
  }
}
