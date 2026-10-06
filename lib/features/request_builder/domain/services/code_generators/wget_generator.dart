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
    for (final entry in snippetHeadersOf(spec).entries) {
      lines.add('--header ${shellQuote('${entry.key}: ${entry.value}')}');
    }
    final body = bodyTextOf(spec);
    if (body != null) lines.add('--body-data ${shellQuote(body)}');
    if (binaryFileOf(spec) case final file?) lines.add('--body-file ${shellQuote(file.path)}');
    lines
      ..add('--output-document -')
      ..add(shellQuote(spec.url));
    // wget has no multipart encoder: the file parts cannot be written, so the snippet says so instead of
    // sending a different request.
    final note = multipartOf(spec) == null
        ? ''
        : '# wget cannot send multipart/form-data with files: use the cURL snippet for this request.\n';
    return '$note${shellLines(lines, indent: '  ')}';
  }
}
