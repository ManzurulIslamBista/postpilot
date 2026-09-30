import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class PhpCurlGenerator implements CodeGenerator {
  const PhpCurlGenerator();

  @override
  String get id => 'php_curl';
  @override
  String get label => 'PHP (cURL)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('<?php')
      ..writeln()
      ..writeln(r'$curl = curl_init();')
      ..writeln()
      ..writeln(r'curl_setopt_array($curl, [')
      ..writeln('    CURLOPT_URL => ${phpString(spec.url)},')
      ..writeln('    CURLOPT_RETURNTRANSFER => true,');
    // A custom HEAD verb would leave curl waiting for a body that never comes.
    if (spec.method.toUpperCase() == 'HEAD') {
      buffer.writeln('    CURLOPT_NOBODY => true,');
    } else {
      buffer.writeln('    CURLOPT_CUSTOMREQUEST => ${phpString(spec.method)},');
    }
    if (spec.headers.isNotEmpty) {
      buffer.writeln('    CURLOPT_HTTPHEADER => [');
      for (final e in spec.headers.entries) {
        buffer.writeln('        ${phpString(_headerLine(e.key, e.value))},');
      }
      buffer.writeln('    ],');
    }
    if (body != null) buffer.writeln('    CURLOPT_POSTFIELDS => ${phpString(body)},');
    buffer
      ..writeln(']);')
      ..writeln()
      ..writeln(r'$response = curl_exec($curl);')
      ..writeln()
      ..writeln(r'if ($response === false) {')
      ..writeln(r"    echo 'cURL error: ' . curl_error($curl) . PHP_EOL;")
      ..writeln('} else {')
      ..writeln(r'    echo $response;')
      ..write('}');
    return buffer.toString();
  }

  // `Name:` would remove the header; libcurl sends an empty one for `Name;`.
  String _headerLine(String name, String value) => value.isEmpty ? '$name;' : '$name: $value';
}
