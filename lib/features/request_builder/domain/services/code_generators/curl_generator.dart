import '../../../../../core/network/upload_body.dart';
import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'curl_form.dart';
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
    for (final entry in snippetHeadersOf(spec).entries) {
      lines.add('--header ${_quote(_headerLine(entry.key, entry.value))}');
    }
    final body = bodyTextOf(spec);
    if (body != null) lines.add('--data-raw ${_quote(body)}');
    lines.addAll(_uploadOptions(spec));
    return shellLines(lines);
  }

  /// A file goes by its path: `--form 'name=@path;type=...'` for a form part, `--data-binary '@path'` for the body.
  /// A text part is written with `--form-string`, so a value that starts with `@` or `<` is not taken for a file.
  List<String> _uploadOptions(ResolvedRequestSpec spec) => [
        for (final part in multipartOf(spec)?.parts ?? const <UploadPart>[])
          switch (part) {
            UploadTextPart(:final name, :final value) => '--form-string ${_quote('$name=$value')}',
            UploadFilePart(:final name, :final file) => '--form ${_quote('$name=${curlFileFormValue(
                  file.path,
                  contentType: file.contentType,
                  fileName: hasCustomFileName(file) ? file.fileName : null,
                )}')}',
          },
        if (binaryFileOf(spec) case final file?) '--data-binary ${_quote('@${file.path}')}',
      ];

  String _quote(String value) => shellQuote(value, ansiC: ansiC);

  // `Name:` would remove the header; curl sends an empty one for `Name;`.
  String _headerLine(String name, String value) => value.isEmpty ? '$name;' : '$name: $value';
}
