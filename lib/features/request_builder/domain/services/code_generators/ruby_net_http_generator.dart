import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class RubyNetHttpGenerator implements CodeGenerator {
  const RubyNetHttpGenerator();

  @override
  String get id => 'ruby_net_http';
  @override
  String get label => 'Ruby (Net::HTTP)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln("require 'net/http'")
      ..writeln("require 'uri'")
      ..writeln()
      ..writeln('uri = URI.parse(${rubyString(spec.url)})')
      ..writeln()
      ..writeln('request = ${_requestConstructor(spec.method, hasBody: body != null)}');
    for (final e in spec.headers.entries) {
      buffer.writeln('request[${rubyString(e.key)}] = ${rubyString(e.value)}');
    }
    if (body != null) buffer.writeln('request.body = ${rubyString(body)}');
    buffer
      ..writeln()
      ..writeln("response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|")
      ..writeln('  http.request(request)')
      ..writeln('end')
      ..writeln()
      ..write('puts response.body');
    return buffer.toString();
  }

  String _requestConstructor(String method, {required bool hasBody}) {
    final known = switch (method.toUpperCase()) {
      'GET' => 'Get',
      'POST' => 'Post',
      'PUT' => 'Put',
      'PATCH' => 'Patch',
      'DELETE' => 'Delete',
      'HEAD' => 'Head',
      'OPTIONS' => 'Options',
      'TRACE' => 'Trace',
      _ => null,
    };
    if (known != null) return 'Net::HTTP::$known.new(uri)';
    return 'Net::HTTPGenericRequest.new(${rubyString(method)}, $hasBody, true, uri)';
  }

  /// A form is `set_form` with `multipart/form-data` (Net::HTTP writes the boundary and the header); a binary body
  /// is a body stream over the open file.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln("require 'net/http'")
      ..writeln("require 'uri'")
      ..writeln()
      ..writeln('uri = URI.parse(${rubyString(spec.url)})')
      ..writeln()
      ..writeln('request = ${_requestConstructor(spec.method, hasBody: true)}');
    for (final e in headers.entries) {
      buffer.writeln('request[${rubyString(e.key)}] = ${rubyString(e.value)}');
    }
    if (multipart != null) {
      buffer.writeln('request.set_form([');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('  [${rubyString(name)}, ${rubyString(value)}],');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              '  [${rubyString(name)}, File.open(${rubyString(file.path)}, "rb"), '
              '{ filename: ${rubyString(file.fileName)}, content_type: ${rubyString(file.contentType)} }],',
            );
        }
      }
      buffer.writeln("], 'multipart/form-data')");
    } else {
      final path = rubyString(binaryFileOf(spec)!.path);
      buffer
        ..writeln('request.body_stream = File.open($path, "rb")')
        ..writeln('request.content_length = File.size($path)');
    }
    buffer
      ..writeln()
      ..writeln("response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|")
      ..writeln('  http.request(request)')
      ..writeln('end')
      ..writeln()
      ..write('puts response.body');
    return buffer.toString();
  }
}
