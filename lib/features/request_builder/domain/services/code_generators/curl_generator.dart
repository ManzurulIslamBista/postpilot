import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class CurlGenerator implements CodeGenerator {
  /// With [ansiC] a body, header or url holding CR, tab or other control
  /// characters is written as a bash/zsh `$'...'` string. That is what to
  /// paste into a terminal, where raw CRs are lost, but the app's own cURL
  /// importer (which reads back exported scripts) cannot parse `$'...'`, so
  /// the default keeps them raw inside plain single quotes.
  const CurlGenerator({this.ansiC = false});

  final bool ansiC;

  @override
  String get id => 'curl';
  @override
  String get label => 'cURL';

  @override
  String generate(ResolvedRequestSpec spec) {
    final lines = ['curl --location --request ${shellWord(spec.method)} ${_quote(spec.url)}'];
    for (final entry in spec.headers.entries) {
      lines.add('--header ${_quote(_headerLine(entry.key, entry.value))}');
    }
    final body = bodyTextOf(spec);
    if (body != null) lines.add('--data-raw ${_quote(body)}');
    return shellLines(lines);
  }

  String _quote(String value) => shellQuote(value, ansiC: ansiC);

  // `Name:` would remove the header; curl sends an empty one for `Name;`.
  String _headerLine(String name, String value) => value.isEmpty ? '$name;' : '$name: $value';
}
