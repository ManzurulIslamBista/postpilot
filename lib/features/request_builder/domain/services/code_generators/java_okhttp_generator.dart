import '../resolved_request_spec.dart';
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
}
