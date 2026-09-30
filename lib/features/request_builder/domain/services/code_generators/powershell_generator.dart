import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class PowerShellGenerator implements CodeGenerator {
  const PowerShellGenerator();

  // The verbs Invoke-RestMethod accepts for -Method; anything else needs
  // -CustomMethod (PowerShell 6+).
  static const _methods = {'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'TRACE', 'OPTIONS', 'MERGE', 'PATCH'};

  @override
  String get id => 'powershell_invoke_restmethod';
  @override
  String get label => 'PowerShell (Invoke-RestMethod)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final buffer = StringBuffer();
    if (spec.headers.isNotEmpty) {
      buffer.writeln(r'$headers = @{');
      for (final e in spec.headers.entries) {
        buffer.writeln('    ${powershellString(e.key)} = ${powershellString(e.value)}');
      }
      buffer
        ..writeln('}')
        ..writeln();
    }
    if (body != null) {
      buffer
        ..writeln('\$body = ${powershellString(body)}')
        ..writeln();
    }
    final method = _methods.contains(spec.method.toUpperCase()) ? '-Method' : '-CustomMethod';
    // Windows PowerShell 5.1 sends a string body as Latin-1, so non-ASCII text goes as UTF-8 bytes.
    final bodyArgument = body != null && body.runes.any((r) => r > 0x7F)
        ? r' -Body ([System.Text.Encoding]::UTF8.GetBytes($body))'
        : r' -Body $body';
    buffer
      ..write('\$response = Invoke-RestMethod -Uri ${powershellString(spec.url)} $method ${powershellString(spec.method)}')
      ..write(spec.headers.isEmpty ? '' : r' -Headers $headers')
      ..writeln(body == null ? '' : bodyArgument)
      ..write(r'$response | ConvertTo-Json -Depth 10');
    return buffer.toString();
  }
}
