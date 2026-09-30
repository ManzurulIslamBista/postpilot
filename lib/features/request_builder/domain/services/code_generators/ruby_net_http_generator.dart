import '../resolved_request_spec.dart';
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
}
