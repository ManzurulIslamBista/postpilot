import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class JavaScriptFetchGenerator implements CodeGenerator {
  const JavaScriptFetchGenerator();

  @override
  String get id => 'javascript_fetch';
  @override
  String get label => 'JavaScript (fetch)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final headersLiteral = _headersLiteral(spec);
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('const response = await fetch(${jsString(spec.url)}, {')
      ..writeln('  method: ${jsString(spec.method)},');
    if (headersLiteral != null) buffer.writeln('  headers: $headersLiteral,');
    if (body != null) buffer.writeln('  body: ${jsString(body)},');
    buffer
      ..writeln('});')
      ..writeln('const data = await response.text();')
      ..write('console.log(data);');
    return buffer.toString();
  }

  String? _headersLiteral(ResolvedRequestSpec spec) {
    if (spec.headers.isEmpty) return null;
    final entries = spec.headers.entries.map((e) => '    ${jsString(e.key)}: ${jsString(e.value)}').join(',\n');
    return '{\n$entries\n  }';
  }

  /// A file is read with `node:fs` (Node 18+) and sent as a `Blob` part of a `FormData`, or as the body itself.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln('import { readFile } from "node:fs/promises";')
      ..writeln();
    if (multipart != null) {
      buffer.writeln('const form = new FormData();');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('form.append(${jsString(name)}, ${jsString(value)});');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              'form.append(${jsString(name)}, new Blob([await readFile(${jsString(file.path)})], '
              '{ type: ${jsString(file.contentType)} }), ${jsString(file.fileName)});',
            );
        }
      }
      buffer.writeln();
    }
    buffer
      ..writeln('const response = await fetch(${jsString(spec.url)}, {')
      ..writeln('  method: ${jsString(spec.method)},');
    if (headers.isNotEmpty) {
      final entries = headers.entries.map((e) => '    ${jsString(e.key)}: ${jsString(e.value)}').join(',\n');
      buffer.writeln('  headers: {\n$entries\n  },');
    }
    final file = binaryFileOf(spec);
    buffer
      ..writeln('  body: ${multipart != null ? 'form' : 'await readFile(${jsString(file!.path)})'},')
      ..writeln('});')
      ..writeln('const data = await response.text();')
      ..write('console.log(data);');
    return buffer.toString();
  }
}
