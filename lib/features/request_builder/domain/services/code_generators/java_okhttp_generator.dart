import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'okhttp_rules.dart';
import 'string_literals.dart';

final class JavaOkHttpGenerator implements CodeGenerator {
  const JavaOkHttpGenerator();

  @override
  String get id => 'java_okhttp';
  @override
  String get label => 'Java (OkHttp)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final body = bodyTextOf(spec);
    // A null media type leaves Content-Type to the explicit header below;
    // otherwise OkHttp overwrites it and appends `; charset=utf-8`.
    final bodyExpression = body != null
        ? 'RequestBody.create(${javaString(body)}, null)'
        : okHttpRequiresBody(spec.method)
            ? 'RequestBody.create(new byte[0], null)'
            : null;
    final buffer = StringBuffer()
      ..writeln('import okhttp3.OkHttpClient;')
      ..writeln('import okhttp3.Request;');
    if (bodyExpression != null) buffer.writeln('import okhttp3.RequestBody;');
    buffer
      ..writeln('import okhttp3.Response;')
      ..writeln()
      ..writeln('import java.io.IOException;')
      ..writeln()
      ..writeln('public class Main {')
      ..writeln('    public static void main(String[] args) throws IOException {')
      ..writeln('        OkHttpClient client = new OkHttpClient();')
      ..writeln();
    if (bodyExpression != null) buffer.writeln('        RequestBody body = $bodyExpression;');
    buffer
      ..writeln('        Request request = new Request.Builder()')
      ..writeln('                .url(${javaString(spec.url)})')
      ..writeln('                .method(${javaString(spec.method)}, ${bodyExpression == null ? 'null' : 'body'})');
    for (final entry in spec.headers.entries) {
      buffer.writeln('                .addHeader(${javaString(entry.key)}, ${javaString(entry.value)})');
    }
    buffer
      ..writeln('                .build();')
      ..writeln()
      ..writeln('        try (Response response = client.newCall(request).execute()) {')
      ..writeln('            System.out.println(response.body().string());')
      ..writeln('        }')
      ..writeln('    }')
      ..write('}');
    return buffer.toString();
  }

  /// A form is a `MultipartBody` (it writes the boundary and the header); a binary body is the `File` itself. A
  /// null media type leaves a binary body's type to the explicit header, as in [generate].
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln('import okhttp3.MediaType;')
      ..writeln('import okhttp3.MultipartBody;')
      ..writeln('import okhttp3.OkHttpClient;')
      ..writeln('import okhttp3.Request;')
      ..writeln('import okhttp3.RequestBody;')
      ..writeln('import okhttp3.Response;')
      ..writeln()
      ..writeln('import java.io.File;')
      ..writeln('import java.io.IOException;')
      ..writeln()
      ..writeln('public class Main {')
      ..writeln('    public static void main(String[] args) throws IOException {')
      ..writeln('        OkHttpClient client = new OkHttpClient();')
      ..writeln();
    if (multipart != null) {
      buffer
        ..writeln('        RequestBody body = new MultipartBody.Builder()')
        ..writeln('                .setType(MultipartBody.FORM)');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('                .addFormDataPart(${javaString(name)}, ${javaString(value)})');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              '                .addFormDataPart(${javaString(name)}, ${javaString(file.fileName)}, '
              'RequestBody.create(new File(${javaString(file.path)}), MediaType.parse(${javaString(file.contentType)})))',
            );
        }
      }
      buffer.writeln('                .build();');
    } else {
      buffer.writeln('        RequestBody body = RequestBody.create(new File(${javaString(binaryFileOf(spec)!.path)}), null);');
    }
    buffer
      ..writeln('        Request request = new Request.Builder()')
      ..writeln('                .url(${javaString(spec.url)})')
      ..writeln('                .method(${javaString(spec.method)}, body)');
    for (final entry in headers.entries) {
      buffer.writeln('                .addHeader(${javaString(entry.key)}, ${javaString(entry.value)})');
    }
    buffer
      ..writeln('                .build();')
      ..writeln()
      ..writeln('        try (Response response = client.newCall(request).execute()) {')
      ..writeln('            System.out.println(response.body().string());')
      ..writeln('        }')
      ..writeln('    }')
      ..write('}');
    return buffer.toString();
  }
}
