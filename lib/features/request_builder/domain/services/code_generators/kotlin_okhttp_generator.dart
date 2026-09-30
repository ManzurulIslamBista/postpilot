import '../resolved_request_spec.dart';
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
}
