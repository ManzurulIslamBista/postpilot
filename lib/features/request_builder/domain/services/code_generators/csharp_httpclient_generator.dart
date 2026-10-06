import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form is a `MultipartFormDataContent` (it writes the boundary and the header); a binary body is a
  /// `StreamContent` over the open file, typed by the request's own `Content-Type`.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final requestHeaders = headers.entries.where((e) => !_contentHeaders.contains(e.key.toLowerCase()));
    final contentHeaders = headers.entries.where((e) => _contentHeaders.contains(e.key.toLowerCase()));

    final buffer = StringBuffer()
      ..writeln('using System;')
      ..writeln('using System.IO;')
      ..writeln('using System.Net.Http;')
      ..writeln('using System.Net.Http.Headers;')
      ..writeln()
      ..writeln('using var client = new HttpClient();')
      ..writeln('using var request = new HttpRequestMessage(${_method(spec.method)}, ${csharpString(spec.url)});');
    for (final e in requestHeaders) {
      buffer.writeln('request.Headers.TryAddWithoutValidation(${csharpString(e.key)}, ${csharpString(e.value)});');
    }
    if (multipart != null) {
      buffer.writeln('using var form = new MultipartFormDataContent();');
      var index = 0;
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('form.Add(new StringContent(${csharpString(value)}), ${csharpString(name)});');
          case UploadFilePart(:final name, :final file):
            index++;
            buffer
              ..writeln('var file$index = new StreamContent(File.OpenRead(${csharpString(file.path)}));')
              ..writeln('file$index.Headers.ContentType = MediaTypeHeaderValue.Parse(${csharpString(file.contentType)});')
              ..writeln('form.Add(file$index, ${csharpString(name)}, ${csharpString(file.fileName)});');
        }
      }
      buffer.writeln('request.Content = form;');
    } else {
      buffer.writeln('request.Content = new StreamContent(File.OpenRead(${csharpString(binaryFileOf(spec)!.path)}));');
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
}
