import '../resolved_request_spec.dart';
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
}
