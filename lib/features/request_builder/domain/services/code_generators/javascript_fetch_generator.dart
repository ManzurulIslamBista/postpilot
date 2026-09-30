import '../resolved_request_spec.dart';
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
}
