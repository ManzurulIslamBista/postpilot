import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
import 'code_generator.dart';
import 'okhttp_rules.dart';
import 'string_literals.dart';

final class KotlinOkHttpGenerator implements CodeGenerator {
  const KotlinOkHttpGenerator();

  @override
  String get id => 'kotlin_okhttp';
  @override
  String get label => 'Kotlin (OkHttp)';

  @override
  String generate(ResolvedRequestSpec spec) {
    if (spec.upload != null) return _generateUpload(spec);
    final body = bodyTextOf(spec);
    // No media type: see JavaOkHttpGenerator.
    final bodyExpression = body != null
        ? '${kotlinString(body)}.toRequestBody()'
        : okHttpRequiresBody(spec.method)
            ? '"".toRequestBody()'
            : null;
    final buffer = StringBuffer()
      ..writeln('import okhttp3.OkHttpClient')
      ..writeln('import okhttp3.Request');
    if (bodyExpression != null) buffer.writeln('import okhttp3.RequestBody.Companion.toRequestBody');
    buffer
      ..writeln()
      ..writeln('fun main() {')
      ..writeln('    val client = OkHttpClient()')
      ..writeln();
    if (bodyExpression != null) buffer.writeln('    val body = $bodyExpression');
    buffer
      ..writeln('    val request = Request.Builder()')
      ..writeln('        .url(${kotlinString(spec.url)})')
      ..writeln('        .method(${kotlinString(spec.method)}, ${bodyExpression == null ? 'null' : 'body'})');
    for (final entry in spec.headers.entries) {
      buffer.writeln('        .addHeader(${kotlinString(entry.key)}, ${kotlinString(entry.value)})');
    }
    buffer
      ..writeln('        .build()')
      ..writeln()
      ..writeln('    client.newCall(request).execute().use { response ->')
      ..writeln('        println(response.body?.string())')
      ..writeln('    }')
      ..write('}');
    return buffer.toString();
  }

  /// See [JavaOkHttpGenerator]: a form is a `MultipartBody`, a binary body is the `File` with no media type.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer();
    if (multipart != null) buffer.writeln('import okhttp3.MediaType.Companion.toMediaType');
    buffer.writeln('import okhttp3.MultipartBody');
    buffer
      ..writeln('import okhttp3.OkHttpClient')
      ..writeln('import okhttp3.Request')
      ..writeln('import okhttp3.RequestBody.Companion.asRequestBody')
      ..writeln('import java.io.File')
      ..writeln()
      ..writeln('fun main() {')
      ..writeln('    val client = OkHttpClient()')
      ..writeln();
    if (multipart != null) {
      buffer
        ..writeln('    val body = MultipartBody.Builder()')
        ..writeln('        .setType(MultipartBody.FORM)');
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('        .addFormDataPart(${kotlinString(name)}, ${kotlinString(value)})');
          case UploadFilePart(:final name, :final file):
            buffer.writeln(
              '        .addFormDataPart(${kotlinString(name)}, ${kotlinString(file.fileName)}, '
              'File(${kotlinString(file.path)}).asRequestBody(${kotlinString(file.contentType)}.toMediaType()))',
            );
        }
      }
      buffer.writeln('        .build()');
    } else {
      buffer.writeln('    val body = File(${kotlinString(binaryFileOf(spec)!.path)}).asRequestBody()');
    }
    buffer
      ..writeln('    val request = Request.Builder()')
      ..writeln('        .url(${kotlinString(spec.url)})')
      ..writeln('        .method(${kotlinString(spec.method)}, body)');
    for (final entry in headers.entries) {
      buffer.writeln('        .addHeader(${kotlinString(entry.key)}, ${kotlinString(entry.value)})');
    }
    buffer
      ..writeln('        .build()')
      ..writeln()
      ..writeln('    client.newCall(request).execute().use { response ->')
      ..writeln('        println(response.body?.string())')
      ..writeln('    }')
      ..write('}');
    return buffer.toString();
  }
}
