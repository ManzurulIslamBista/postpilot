import '../../../../../core/network/upload_body.dart';
import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class HttpieGenerator implements CodeGenerator {
  const HttpieGenerator();

  @override
  String get id => 'httpie';
  @override
  String get label => 'HTTPie';

  @override
  String generate(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final lines = ['http ${multipart == null ? '' : '--multipart '}${shellWord(spec.method)} ${shellQuote(spec.url)}'];
    for (final entry in snippetHeadersOf(spec).entries) {
      lines.add(shellQuote(_headerItem(entry.key, entry.value)));
    }
    final body = bodyTextOf(spec);
    // `--raw=` rather than `--raw <body>`: argparse reads a body starting with
    // `--` (every multipart body does) as an unknown option.
    if (body != null) lines.add('--raw=${shellQuote(body)}');

    final renamed = <String>[];
    for (final part in multipart?.parts ?? const <UploadPart>[]) {
      switch (part) {
        case UploadTextPart(:final name, :final value):
          lines.add(shellQuote('${_itemName(name)}=$value'));
        case UploadFilePart(:final name, :final file):
          lines.add(shellQuote('${_itemName(name)}@${file.path};type=${file.contentType}'));
          if (hasCustomFileName(file)) renamed.add(name);
      }
    }
    // The body of a binary request is the file on standard input.
    if (binaryFileOf(spec) case final file?) lines.add('< ${shellQuote(file.path)}');
    final note = renamed.isEmpty
        ? ''
        : '# HTTPie sends a file under its own name: the name of ${renamed.map((n) => '"$n"').join(', ')} cannot be set.\n';
    return '$note${shellLines(lines, indent: '  ')}';
  }

  /// A backslash keeps `=`, `@`, `:` and `;` in a field name from being read as a request-item separator.
  String _itemName(String name) => name.replaceAllMapped(RegExp(r'[:=@;\\]'), (m) => '\\${m[0]}');

  // `Name:` unsets a header and `Name;` sends it empty. A backslash keeps
  // `:`, `=`, `@` and `;` from being read as request-item separators.
  String _headerItem(String name, String value) {
    final key = name.replaceAllMapped(RegExp(r'[:=@;]'), (m) => '\\${m[0]}');
    if (value.isEmpty) return '$key;';
    final escapeFirst = value.startsWith('@') || value.startsWith('=');
    return '$key:${escapeFirst ? r'\' : ''}$value';
  }
}
