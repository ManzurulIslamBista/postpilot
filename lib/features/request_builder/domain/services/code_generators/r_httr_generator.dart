import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class RHttrGenerator implements CodeGenerator {
  const RHttrGenerator();

  @override
  String get id => 'r_httr';
  @override
  String get label => 'R (httr)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final body = bodyTextOf(spec);
    final args = <String>[
      rString(spec.method),
      'url = ${rString(spec.url)}',
      if (spec.headers.isNotEmpty)
        'add_headers(\n${spec.headers.entries.map((e) => '    ${rString(e.key)} = ${rString(e.value)}').join(',\n')}\n  )',
      if (body != null) 'body = ${rString(body)}',
    ];
    return [
      'library(httr)',
      '',
      'response <- VERB(',
      args.map((a) => '  $a').join(',\n'),
      ')',
      '',
      'cat(content(response, "text", encoding = "UTF-8"), "\\n")',
    ].join('\n');
  }

  /// A form is a list with `upload_file` parts, `encode = "multipart"` (httr writes the boundary and the header; it
  /// sends the file under its own name, so a changed name is noted); a binary body is `upload_file` alone.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final renamed = <String>[];
    final String body;
    if (multipart != null) {
      final parts = <String>[];
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            parts.add('    ${rString(name)} = ${rString(value)}');
          case UploadFilePart(:final name, :final file):
            parts.add('    ${rString(name)} = upload_file(${rString(file.path)}, type = ${rString(file.contentType)})');
            if (hasCustomFileName(file)) renamed.add(name);
        }
      }
      body = 'body = list(\n${parts.join(',\n')}\n  )';
    } else {
      final file = binaryFileOf(spec)!;
      body = 'body = upload_file(${rString(file.path)}, type = ${rString(file.contentType)})';
    }
    final args = <String>[
      rString(spec.method),
      'url = ${rString(spec.url)}',
      if (headers.isNotEmpty)
        'add_headers(\n${headers.entries.map((e) => '    ${rString(e.key)} = ${rString(e.value)}').join(',\n')}\n  )',
      body,
      if (multipart != null) 'encode = "multipart"',
    ];
    return [
      'library(httr)',
      '',
      if (renamed.isNotEmpty)
        '# httr sends a file under its own name: the name of ${renamed.map((n) => '"$n"').join(', ')} cannot be set.',
      'response <- VERB(',
      args.map((a) => '  $a').join(',\n'),
      ')',
      '',
      'cat(content(response, "text", encoding = "UTF-8"), "\\n")',
    ].join('\n');
  }
}
