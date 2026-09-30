import '../resolved_request_spec.dart';
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
}
