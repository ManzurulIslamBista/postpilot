import '../resolved_request_spec.dart';
import 'code_generator.dart';
import 'string_literals.dart';

final class GoNetHttpGenerator implements CodeGenerator {
  const GoNetHttpGenerator();

  @override
  String get id => 'go_net_http';
  @override
  String get label => 'Go (net/http)';

  @override
  String generate(ResolvedRequestSpec spec) {
    final body = bodyTextOf(spec);
    final buffer = StringBuffer()
      ..writeln('package main')
      ..writeln()
      ..writeln('import (')
      ..writeln('\t"fmt"')
      ..writeln('\t"io"')
      ..writeln('\t"net/http"');
    if (body != null) buffer.writeln('\t"strings"');
    buffer
      ..writeln(')')
      ..writeln()
      ..writeln('func main() {');
    if (body != null) {
      buffer
        ..writeln('\tpayload := strings.NewReader(${goString(body, preferRaw: true)})')
        ..writeln();
    }
    buffer
      ..writeln(
        '\treq, err := http.NewRequest(${goString(spec.method)}, ${goString(spec.url)}, ${body == null ? 'nil' : 'payload'})',
      )
      ..writeln('\tif err != nil {')
      ..writeln('\t\tfmt.Println(err)')
      ..writeln('\t\treturn')
      ..writeln('\t}');
    for (final entry in spec.headers.entries) {
      // net/http sends req.Host, never a Host entry in the header map.
      if (entry.key.toLowerCase() == 'host') {
        buffer.writeln('\treq.Host = ${goString(entry.value)}');
      } else {
        buffer.writeln('\treq.Header.Set(${goString(entry.key)}, ${goString(entry.value)})');
      }
    }
    buffer
      ..writeln()
      ..writeln('\tres, err := http.DefaultClient.Do(req)')
      ..writeln('\tif err != nil {')
      ..writeln('\t\tfmt.Println(err)')
      ..writeln('\t\treturn')
      ..writeln('\t}')
      ..writeln('\tdefer res.Body.Close()')
      ..writeln()
      ..writeln('\tbody, err := io.ReadAll(res.Body)')
      ..writeln('\tif err != nil {')
      ..writeln('\t\tfmt.Println(err)')
      ..writeln('\t\treturn')
      ..writeln('\t}')
      ..writeln('\tfmt.Println(string(body))')
      ..write('}');
    return buffer.toString();
  }
}
