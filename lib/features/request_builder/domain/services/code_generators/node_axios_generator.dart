import 'dart:convert';
import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form goes through the `form-data` package, whose headers carry the boundary; a binary body is a read stream.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()..writeln('const axios = require("axios");');
    if (multipart != null) buffer.writeln('const FormData = require("form-data");');
    buffer
      ..writeln('const fs = require("fs");')
      ..writeln();
    if (multipart != null) {
      buffer.writeln('const data = new FormData();');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('data.append(${jsString(name)}, ${jsString(value)});');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              'data.append(${jsString(name)}, fs.createReadStream(${jsString(file.path)}), '
              '{ filename: ${jsString(file.fileName)}, contentType: ${jsString(file.contentType)} });',
            );
        }
      }
      buffer.writeln();
    }
    buffer
      ..writeln('const config = {')
      ..writeln('  method: ${jsString(spec.method.toLowerCase())},')
      ..writeln('  url: ${jsString(spec.url)},');
    final entries = [
      if (multipart != null) '...data.getHeaders()',
      for (final e in headers.entries) '${jsString(e.key)}: ${jsString(e.value)}',
    ];
    if (entries.isNotEmpty) {
      buffer
        ..writeln('  headers: {')
        ..writeln(entries.map((e) => '    $e').join(',\n'))
        ..writeln('  },');
    }
    final file = binaryFileOf(spec);
    buffer
      ..writeln('  data: ${multipart != null ? 'data' : 'fs.createReadStream(${jsString(file!.path)})'},')
      ..writeln('  maxBodyLength: Infinity,')
      ..writeln('};')
      ..writeln()
      ..writeln('axios.request(config)')
      ..writeln('  .then((response) => console.log(response.data))')
      ..write('  .catch((error) => console.error(error));');
    return buffer.toString();
  }
}
