import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// URLSession has no multipart encoder, so the body is written out part by part; the files are read with
  /// `Data(contentsOf:)`. A binary body is the content of the file.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln('import Foundation')
      ..writeln('#if canImport(FoundationNetworking)')
      ..writeln('import FoundationNetworking')
      ..writeln('#endif')
      ..writeln()
      ..writeln('var request = URLRequest(url: URL(string: ${swiftString(spec.url)})!)')
      ..writeln('request.httpMethod = ${swiftString(spec.method)}');
    for (final e in headers.entries) {
      buffer.writeln('request.setValue(${swiftString(e.value)}, forHTTPHeaderField: ${swiftString(e.key)})');
    }
    if (multipart != null) {
      buffer
        ..writeln()
        ..writeln('let boundary = ${swiftString(multipart.boundary)}')
        ..writeln('var body = Data()')
        ..writeln('func append(_ text: String) { body.append(text.data(using: .utf8)!) }')
        ..writeln();
      for (final part in multipart.parts) {
        buffer.writeln('append("--" + boundary + "\\r\\n")');
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer
              ..writeln('append(${swiftString('Content-Disposition: form-data; name="${_quoted(name)}"\r\n\r\n')})')
              ..writeln('append(${swiftString('$value\r\n')})');
          case UploadFilePart(:final name, :final file):
            buffer
              ..writeln(
                'append(${swiftString('Content-Disposition: form-data; name="${_quoted(name)}"; '
                    'filename="${_quoted(file.fileName)}"\r\n')})',
              )
              ..writeln('append(${swiftString('Content-Type: ${file.contentType}\r\n\r\n')})')
              ..writeln('body.append(try! Data(contentsOf: URL(fileURLWithPath: ${swiftString(file.path)})))')
              ..writeln('append("\\r\\n")');
        }
      }
      buffer
        ..writeln('append("--" + boundary + "--\\r\\n")')
        ..writeln('request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")')
        ..writeln('request.httpBody = body');
    } else {
      buffer.writeln(
        'request.httpBody = try! Data(contentsOf: URL(fileURLWithPath: ${swiftString(binaryFileOf(spec)!.path)}))',
      );
    }
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

  /// The way browsers write a name inside the quotes of a part header.
  static String _quoted(String text) => text.replaceAll('"', '%22').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
}
