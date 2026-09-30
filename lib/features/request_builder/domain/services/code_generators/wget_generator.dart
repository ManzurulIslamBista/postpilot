import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class WgetGenerator implements CodeGenerator {
  const WgetGenerator();

  @override
  String get id => 'wget';
  @override
  String get label => 'wget';

  @override
  String generate(ResolvedRequestSpec spec) {
    final lines = ['wget --quiet', '--method ${shellWord(spec.method)}'];
    for (final entry in spec.headers.entries) {
      lines.add('--header ${shellQuote('${entry.key}: ${entry.value}')}');
    }
    final body = bodyTextOf(spec);
    if (body != null) lines.add('--body-data ${shellQuote(body)}');
    lines
      ..add('--output-document -')
      ..add(shellQuote(spec.url));
    return shellLines(lines, indent: '  ');
  }
}
