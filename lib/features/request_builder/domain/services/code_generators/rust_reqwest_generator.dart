import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class RustReqwestGenerator implements CodeGenerator {
  const RustReqwestGenerator();

  @override
  String get id => 'rust_reqwest';
  @override
  String get label => 'Rust (reqwest)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('#[tokio::main]')
      ..writeln('async fn main() -> Result<(), Box<dyn std::error::Error>> {')
      ..writeln('    let client = reqwest::Client::new();')
      ..writeln()
      ..writeln('    let response = client')
      ..writeln('        .request(${_method(spec.method)}, ${rustString(spec.url)})');
    for (final e in spec.headers.entries) {
      buffer.writeln('        .header(${rustString(e.key)}, ${rustString(e.value)})');
    }
    if (body != null) buffer.writeln('        .body(${rustString(body)})');
    buffer
      ..writeln('        .send()')
      ..writeln('        .await?;')
      ..writeln()
      ..writeln('    println!("{}", response.text().await?);')
      ..writeln('    Ok(())')
      ..write('}');
    return buffer.toString();
  }

  String _method(String method) {
    final upper = method.toUpperCase();
    const known = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'TRACE', 'CONNECT'};
    return known.contains(upper)
        ? 'reqwest::Method::$upper'
        : 'reqwest::Method::from_bytes(b${rustString(method)})?';
  }

  /// A form is `reqwest::multipart` (the `multipart` feature of reqwest; it writes the boundary and the header); a
  /// binary body is the bytes of the file.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln('// Needs reqwest with the "multipart" feature for the form.')
      ..writeln('#[tokio::main]')
      ..writeln('async fn main() -> Result<(), Box<dyn std::error::Error>> {')
      ..writeln('    let client = reqwest::Client::new();')
      ..writeln();
    if (multipart != null) {
      buffer.writeln('    let form = reqwest::multipart::Form::new()');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('        .text(${rustString(name)}, ${rustString(value)})');
          case UploadFilePart(:final name, :final file):
            buffer
              ..writeln('        .part(')
              ..writeln('            ${rustString(name)},')
              ..writeln('            reqwest::multipart::Part::bytes(std::fs::read(${rustString(file.path)})?)')
              ..writeln('                .file_name(${rustString(file.fileName)})')
              ..writeln('                .mime_str(${rustString(file.contentType)})?,')
              ..writeln('        )');
        }
      }
      buffer.writeln('    ;');
    }
    buffer
      ..writeln()
      ..writeln('    let response = client')
      ..writeln('        .request(${_method(spec.method)}, ${rustString(spec.url)})');
    for (final e in headers.entries) {
      buffer.writeln('        .header(${rustString(e.key)}, ${rustString(e.value)})');
    }
    buffer.writeln(
      multipart != null
          ? '        .multipart(form)'
          : '        .body(std::fs::read(${rustString(binaryFileOf(spec)!.path)})?)',
    );
    buffer
      ..writeln('        .send()')
      ..writeln('        .await?;')
      ..writeln()
      ..writeln('    println!("{}", response.text().await?);')
      ..writeln('    Ok(())')
      ..write('}');
    return buffer.toString();
  }
}
