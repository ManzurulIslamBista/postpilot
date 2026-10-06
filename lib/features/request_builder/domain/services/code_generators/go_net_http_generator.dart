import '../resolved_request_spec.dart';
import '../../../../../core/network/upload_body.dart';
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
    if (spec.upload != null) return _generateUpload(spec);
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

  /// A form is written with `mime/multipart` (`CreatePart`, so the part keeps its own type); a binary body is the
  /// open file, with its size as the content length.
  String _generateUpload(ResolvedRequestSpec spec) {
    final multipart = multipartOf(spec);
    final headers = snippetHeadersOf(spec);
    final buffer = StringBuffer()
      ..writeln('package main')
      ..writeln()
      ..writeln('import (');
    if (multipart != null) buffer.writeln('\t"bytes"');
    buffer
      ..writeln('\t"fmt"')
      ..writeln('\t"io"');
    if (multipart != null) buffer.writeln('\t"mime"\n\t"mime/multipart"');
    buffer.writeln('\t"net/http"');
    if (multipart != null) buffer.writeln('\t"net/textproto"');
    buffer
      ..writeln('\t"os"')
      ..writeln(')')
      ..writeln()
      ..writeln('func main() {');

    final String bodyArgument;
    if (multipart != null) {
      buffer
        ..writeln('\tvar payload bytes.Buffer')
        ..writeln('\twriter := multipart.NewWriter(&payload)');
      var index = 0;
      for (final part in multipart.parts) {
        switch (part) {
          case UploadTextPart(:final name, :final value):
            buffer.writeln('\twriter.WriteField(${goString(name)}, ${goString(value)})');
          case UploadFilePart(:final name, :final file):
            index++;
            buffer
              ..writeln()
              ..writeln('\theader$index := make(textproto.MIMEHeader)')
              ..writeln(
                '\theader$index.Set("Content-Disposition", mime.FormatMediaType("form-data", '
                'map[string]string{"name": ${goString(name)}, "filename": ${goString(file.fileName)}}))',
              )
              ..writeln('\theader$index.Set("Content-Type", ${goString(file.contentType)})')
              ..writeln('\tpart$index, err := writer.CreatePart(header$index)')
              ..writeln('\tif err != nil {')
              ..writeln('\t\tfmt.Println(err)')
              ..writeln('\t\treturn')
              ..writeln('\t}')
              ..writeln('\tfile$index, err := os.Open(${goString(file.path)})')
              ..writeln('\tif err != nil {')
              ..writeln('\t\tfmt.Println(err)')
              ..writeln('\t\treturn')
              ..writeln('\t}')
              ..writeln('\tdefer file$index.Close()')
              ..writeln('\tio.Copy(part$index, file$index)')
              ..writeln();
        }
      }
      buffer
        ..writeln('\twriter.Close()')
        ..writeln();
      bodyArgument = '&payload';
    } else {
      buffer
        ..writeln('\tfile, err := os.Open(${goString(binaryFileOf(spec)!.path)})')
        ..writeln('\tif err != nil {')
        ..writeln('\t\tfmt.Println(err)')
        ..writeln('\t\treturn')
        ..writeln('\t}')
        ..writeln('\tdefer file.Close()')
        ..writeln('\tinfo, err := file.Stat()')
        ..writeln('\tif err != nil {')
        ..writeln('\t\tfmt.Println(err)')
        ..writeln('\t\treturn')
        ..writeln('\t}')
        ..writeln();
      bodyArgument = 'file';
    }

    buffer
      ..writeln('\treq, err := http.NewRequest(${goString(spec.method)}, ${goString(spec.url)}, $bodyArgument)')
      ..writeln('\tif err != nil {')
      ..writeln('\t\tfmt.Println(err)')
      ..writeln('\t\treturn')
      ..writeln('\t}');
    if (multipart != null) {
      buffer.writeln('\treq.Header.Set("Content-Type", writer.FormDataContentType())');
    } else {
      buffer.writeln('\treq.ContentLength = info.Size()');
    }
    for (final entry in headers.entries) {
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
