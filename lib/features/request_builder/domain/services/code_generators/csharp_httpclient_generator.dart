import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class CSharpHttpClientGenerator implements CodeGenerator {
  const CSharpHttpClientGenerator();

  // HttpClient rejects these on the request itself; they belong to its content.
  static const _contentHeaders = {
    'allow',
    'content-disposition',
    'content-encoding',
    'content-language',
    'content-length',
    'content-location',
    'content-md5',
    'content-range',
    'content-type',
    'expires',
    'last-modified',
  };

  @override
  String get id => 'csharp_httpclient';
  @override
  String get label => 'C# (HttpClient)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final requestHeaders = spec.headers.entries.where((e) => !_contentHeaders.contains(e.key.toLowerCase()));
    final contentHeaders = spec.headers.entries.where((e) => _contentHeaders.contains(e.key.toLowerCase()));
    final hasContent = body != null || contentHeaders.isNotEmpty;

    final buffer = StringBuffer()
      ..writeln('using System;')
      ..writeln('using System.Net.Http;');
    if (body != null) buffer.writeln('using System.Text;');
    buffer
      ..writeln()
      ..writeln('using var client = new HttpClient();')
      ..writeln('using var request = new HttpRequestMessage(${_method(spec.method)}, ${csharpString(spec.url)});');
    for (final e in requestHeaders) {
      buffer.writeln('request.Headers.TryAddWithoutValidation(${csharpString(e.key)}, ${csharpString(e.value)});');
    }
    if (hasContent) {
      // ByteArrayContent adds no headers of its own, unlike StringContent
      // (default Content-Type, appended charset), so the headers stay as given.
      final content = body == null ? 'Array.Empty<byte>()' : 'Encoding.UTF8.GetBytes(${csharpString(body)})';
      buffer.writeln('request.Content = new ByteArrayContent($content);');
    }
    for (final e in contentHeaders) {
      buffer.writeln(
        'request.Content.Headers.TryAddWithoutValidation(${csharpString(e.key)}, ${csharpString(e.value)});',
      );
    }
    buffer
      ..writeln()
      ..writeln('using var response = await client.SendAsync(request);')
      ..write('Console.WriteLine(await response.Content.ReadAsStringAsync());');
    return buffer.toString();
  }

  String _method(String method) => switch (method.toUpperCase()) {
        'GET' => 'HttpMethod.Get',
        'POST' => 'HttpMethod.Post',
        'PUT' => 'HttpMethod.Put',
        'PATCH' => 'HttpMethod.Patch',
        'DELETE' => 'HttpMethod.Delete',
        'HEAD' => 'HttpMethod.Head',
        'OPTIONS' => 'HttpMethod.Options',
        'TRACE' => 'HttpMethod.Trace',
        _ => 'new HttpMethod(${csharpString(method)})',
      };
}
