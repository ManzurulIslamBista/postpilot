import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class SwiftUrlSessionGenerator implements CodeGenerator {
  const SwiftUrlSessionGenerator();

  @override
  String get id => 'swift_urlsession';
  @override
  String get label => 'Swift (URLSession)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('import Foundation')
      ..writeln('#if canImport(FoundationNetworking)')
      ..writeln('import FoundationNetworking')
      ..writeln('#endif')
      ..writeln()
      ..writeln('var request = URLRequest(url: URL(string: ${swiftString(spec.url)})!)')
      ..writeln('request.httpMethod = ${swiftString(spec.method)}');
    for (final e in spec.headers.entries) {
      buffer.writeln('request.setValue(${swiftString(e.value)}, forHTTPHeaderField: ${swiftString(e.key)})');
    }
    if (body != null) buffer.writeln('request.httpBody = ${swiftString(body)}.data(using: .utf8)');
    buffer
      ..writeln()
      ..writeln('let semaphore = DispatchSemaphore(value: 0)')
      ..writeln('let task = URLSession.shared.dataTask(with: request) { data, response, error in')
      ..writeln('    if let error = error {')
      ..writeln('        print(error)')
      ..writeln('    } else if let data = data {')
      ..writeln('        print(String(decoding: data, as: UTF8.self))')
      ..writeln('    }')
      ..writeln('    semaphore.signal()')
      ..writeln('}')
      ..writeln('task.resume()')
      ..write('semaphore.wait()');
    return buffer.toString();
  }
}
