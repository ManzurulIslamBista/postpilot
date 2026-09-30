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
    final lines = ['http ${shellWord(spec.method)} ${shellQuote(spec.url)}'];
    for (final entry in spec.headers.entries) {
      lines.add(shellQuote(_headerItem(entry.key, entry.value)));
    }
    final body = bodyTextOf(spec);
    // `--raw=` rather than `--raw <body>`: argparse reads a body starting with
    // `--` (every multipart body does) as an unknown option.
    if (body != null) lines.add('--raw=${shellQuote(body)}');
    return shellLines(lines, indent: '  ');
  }

  // `Name:` unsets a header and `Name;` sends it empty. A backslash keeps
  // `:`, `=`, `@` and `;` from being read as request-item separators.
  String _headerItem(String name, String value) {
    final key = name.replaceAllMapped(RegExp(r'[:=@;]'), (m) => '\\${m[0]}');
    if (value.isEmpty) return '$key;';
    final escapeFirst = value.startsWith('@') || value.startsWith('=');
    return '$key:${escapeFirst ? r'\' : ''}$value';
  }
}
