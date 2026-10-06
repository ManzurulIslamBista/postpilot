import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form is a .NET `MultipartFormDataContent` (the only way in PowerShell to set a part's type and file name; it
  /// writes the boundary and the header); a binary body goes with `-InFile`.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer();
    if (headers.isNotEmpty) {
      buffer.writeln(r'$headers = @{');
      for (final e in headers.entries) {
        buffer.writeln('    ${powershellString(e.key)} = ${powershellString(e.value)}');
      }
      buffer
        ..writeln('}')
        ..writeln();
    }
    if (multipart != null) {
      buffer
        ..writeln('# Needs PowerShell 7 or newer (Invoke-RestMethod takes the form as the body).')
        ..writeln('Add-Type -AssemblyName System.Net.Http')
        ..writeln(r'$form = [System.Net.Http.MultipartFormDataContent]::new()');
      var index = 0;
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln(
              '\$form.Add([System.Net.Http.StringContent]::new(${powershellString(value)}), ${powershellString(name)})',
            );
          case UploadFilePart(:final name, :final file):
            index++;
            buffer
              ..writeln(
                '\$file$index = [System.Net.Http.StreamContent]::new([System.IO.File]::OpenRead(${powershellString(file.path)}))',
              )
              ..writeln(
                '\$file$index.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse(${powershellString(file.contentType)})',
              )
              ..writeln('\$form.Add(\$file$index, ${powershellString(name)}, ${powershellString(file.fileName)})');
        }
      }
      buffer.writeln();
    }
    final method = _methods.contains(spec.method.toUpperCase()) ? '-Method' : '-CustomMethod';
    buffer
      ..write('\$response = Invoke-RestMethod -Uri ${powershellString(spec.url)} $method ${powershellString(spec.method)}')
      ..write(headers.isEmpty ? '' : r' -Headers $headers')
      ..writeln(
        multipart != null ? r' -Body $form' : ' -InFile ${powershellString(binaryFileOf(spec)!.path)}',
      )
      ..write(r'$response | ConvertTo-Json -Depth 10');
    return buffer.toString();
  }
}
