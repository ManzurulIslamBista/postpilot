import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator_registry.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/csharp_httpclient_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/dart_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/go_net_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/httpie_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/java_okhttp_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/javascript_fetch_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/kotlin_okhttp_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/node_axios_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/php_curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/powershell_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/python_requests_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/r_httr_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/ruby_net_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/rust_reqwest_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/swift_urlsession_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/wget_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/curl_parser.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

UploadFile _upload(String path, String name, String type) =>
    UploadFile(path: path, fileName: name, contentType: type, label: 'the form field "x"');

/// A form with a text part and two files, one of them sent under another name; the header is the one the builder
/// writes (with the boundary of the body it wrote, which a snippet must not repeat).
final _multipart = ResolvedRequestSpec(
  method: 'POST',
  url: 'https://api.example.com/upload',
  headers: const {'Content-Type': 'multipart/form-data; boundary=B', 'X-Trace': 'abc'},
  bodyBytes: null,
  upload: MultipartUpload(boundary: 'B', parts: [
    const UploadTextPart('title', 'My cat'),
    UploadFilePart('photo', _upload('/data/cat.png', 'cat.png', 'image/png')),
    UploadFilePart('doc', _upload('/data/q3 report.pdf', 'Q3.pdf', 'application/pdf')),
  ]),
);

final _binary = ResolvedRequestSpec(
  method: 'PUT',
  url: 'https://bucket.s3.amazonaws.com/backup.tar',
  headers: const {'Content-Type': 'application/octet-stream'},
  bodyBytes: null,
  upload: BinaryUpload(_upload('/data/backup.tar', 'backup.tar', 'application/octet-stream')),
);

void main() {
  group('cURL', () {
    test('a form is --form with @path;type=, --form-string for text, the renamed file with ;filename=', () {
      expect(
        const CurlGenerator().generate(_multipart),
        "curl --location --request POST 'https://api.example.com/upload' \\\n"
        "--header 'X-Trace: abc' \\\n"
        "--form-string 'title=My cat' \\\n"
        "--form 'photo=@/data/cat.png;type=image/png' \\\n"
        "--form 'doc=@/data/q3 report.pdf;type=application/pdf;filename=Q3.pdf'",
      );
    });

    test('a binary body is --data-binary @path, and keeps its Content-Type header', () {
      expect(
        const CurlGenerator().generate(_binary),
        "curl --location --request PUT 'https://bucket.s3.amazonaws.com/backup.tar' \\\n"
        "--header 'Content-Type: application/octet-stream' \\\n"
        "--data-binary '@/data/backup.tar'",
      );
    });

    test('a path with ; , or a quote is written in double quotes, as curl reads them', () {
      final spec = ResolvedRequestSpec(
        method: 'POST',
        url: 'https://x.test/up',
        headers: const {},
        bodyBytes: null,
        upload: MultipartUpload(boundary: 'B', parts: [UploadFilePart('f', _upload(r'/data/a;b,c "d".txt', 'a;b,c "d".txt', 'text/plain'))]),
      );

      expect(const CurlGenerator().generate(spec), contains(r'''--form 'f=@"/data/a;b,c \"d\".txt";type=text/plain' '''.trim()));
    });

    test('what the snippet says is read back by the importer: files, types, names, and text that looks like a file', () {
      final spec = ResolvedRequestSpec(
        method: 'POST',
        url: 'https://x.test/up',
        headers: const {},
        bodyBytes: null,
        upload: MultipartUpload(boundary: 'B', parts: [
          const UploadTextPart('note', '@not-a-file'),
          UploadFilePart('photo', _upload('/data/cat.png', 'cat.png', 'image/png')),
          UploadFilePart('doc', _upload(r'/data/a;b "c".pdf', 'Q3.pdf', 'application/pdf')),
        ]),
      );

      final parsed = CurlParser.parse(const CurlGenerator().generate(spec))!;

      expect(parsed.requestBody.type, BodyType.formData);
      final rows = parsed.formFields;
      expect((rows[0].key, rows[0].value, rows[0].isFile), ('note', '@not-a-file', false));
      expect((rows[1].key, rows[1].value, rows[1].contentType, rows[1].fileName), ('photo', '/data/cat.png', 'image/png', ''));
      expect((rows[2].key, rows[2].value, rows[2].contentType, rows[2].fileName), ('doc', r'/data/a;b "c".pdf', 'application/pdf', 'Q3.pdf'));
    });

    test('a binary snippet is read back as a binary body', () {
      final parsed = CurlParser.parse(const CurlGenerator().generate(_binary))!;

      expect(parsed.requestBody.type, BodyType.binary);
      expect(parsed.requestBody.binaryFile!.value, '/data/backup.tar');
      expect(parsed.method.label, 'PUT');
      expect(parsed.headers.single.value, 'application/octet-stream');
    });
  });

  group('HTTPie', () {
    test('a form is --multipart with name=value and name@path;type=, and says a file name cannot be set', () {
      expect(
        const HttpieGenerator().generate(_multipart),
        '# HTTPie sends a file under its own name: the name of "doc" cannot be set.\n'
        "http --multipart POST 'https://api.example.com/upload' \\\n"
        "  'X-Trace:abc' \\\n"
        "  'title=My cat' \\\n"
        "  'photo@/data/cat.png;type=image/png' \\\n"
        "  'doc@/data/q3 report.pdf;type=application/pdf'",
      );
    });

    test('a binary body is the file on standard input', () {
      expect(
        const HttpieGenerator().generate(_binary),
        "http PUT 'https://bucket.s3.amazonaws.com/backup.tar' \\\n"
        "  'Content-Type:application/octet-stream' \\\n"
        "  < '/data/backup.tar'",
      );
    });
  });

  group('wget', () {
    test('has no multipart encoder: it says so and sends no other body in its place', () {
      expect(
        const WgetGenerator().generate(_multipart),
        '# wget cannot send multipart/form-data with files: use the cURL snippet for this request.\n'
        'wget --quiet \\\n'
        '  --method POST \\\n'
        "  --header 'X-Trace: abc' \\\n"
        '  --output-document - \\\n'
        "  'https://api.example.com/upload'",
      );
    });

    test('a binary body is --body-file', () {
      expect(
        const WgetGenerator().generate(_binary),
        'wget --quiet \\\n'
        '  --method PUT \\\n'
        "  --header 'Content-Type: application/octet-stream' \\\n"
        "  --body-file '/data/backup.tar' \\\n"
        '  --output-document - \\\n'
        "  'https://bucket.s3.amazonaws.com/backup.tar'",
      );
    });
  });

  group('JavaScript (fetch)', () {
    test('a form is a FormData of Blob parts read with node:fs, without a Content-Type of its own', () {
      expect(
        const JavaScriptFetchGenerator().generate(_multipart),
        'import { readFile } from "node:fs/promises";\n'
        '\n'
        'const form = new FormData();\n'
        'form.append("title", "My cat");\n'
        'form.append("photo", new Blob([await readFile("/data/cat.png")], { type: "image/png" }), "cat.png");\n'
        'form.append("doc", new Blob([await readFile("/data/q3 report.pdf")], { type: "application/pdf" }), "Q3.pdf");\n'
        '\n'
        'const response = await fetch("https://api.example.com/upload", {\n'
        '  method: "POST",\n'
        '  headers: {\n'
        '    "X-Trace": "abc"\n'
        '  },\n'
        '  body: form,\n'
        '});\n'
        'const data = await response.text();\n'
        'console.log(data);',
      );
    });

    test('a binary body is the content of the file', () {
      expect(
        const JavaScriptFetchGenerator().generate(_binary),
        'import { readFile } from "node:fs/promises";\n'
        '\n'
        'const response = await fetch("https://bucket.s3.amazonaws.com/backup.tar", {\n'
        '  method: "PUT",\n'
        '  headers: {\n'
        '    "Content-Type": "application/octet-stream"\n'
        '  },\n'
        '  body: await readFile("/data/backup.tar"),\n'
        '});\n'
        'const data = await response.text();\n'
        'console.log(data);',
      );
    });
  });

  group('Node.js (axios)', () {
    test('a form goes through form-data, whose headers carry the boundary', () {
      expect(
        const NodeAxiosGenerator().generate(_multipart),
        'const axios = require("axios");\n'
        'const FormData = require("form-data");\n'
        'const fs = require("fs");\n'
        '\n'
        'const data = new FormData();\n'
        'data.append("title", "My cat");\n'
        'data.append("photo", fs.createReadStream("/data/cat.png"), { filename: "cat.png", contentType: "image/png" });\n'
        'data.append("doc", fs.createReadStream("/data/q3 report.pdf"), { filename: "Q3.pdf", contentType: "application/pdf" });\n'
        '\n'
        'const config = {\n'
        '  method: "post",\n'
        '  url: "https://api.example.com/upload",\n'
        '  headers: {\n'
        '    ...data.getHeaders(),\n'
        '    "X-Trace": "abc"\n'
        '  },\n'
        '  data: data,\n'
        '  maxBodyLength: Infinity,\n'
        '};\n'
        '\n'
        'axios.request(config)\n'
        '  .then((response) => console.log(response.data))\n'
        '  .catch((error) => console.error(error));',
      );
    });

    test('a binary body is a read stream', () {
      expect(
        const NodeAxiosGenerator().generate(_binary),
        'const axios = require("axios");\n'
        'const fs = require("fs");\n'
        '\n'
        'const config = {\n'
        '  method: "put",\n'
        '  url: "https://bucket.s3.amazonaws.com/backup.tar",\n'
        '  headers: {\n'
        '    "Content-Type": "application/octet-stream"\n'
        '  },\n'
        '  data: fs.createReadStream("/data/backup.tar"),\n'
        '  maxBodyLength: Infinity,\n'
        '};\n'
        '\n'
        'axios.request(config)\n'
        '  .then((response) => console.log(response.data))\n'
        '  .catch((error) => console.error(error));',
      );
    });
  });

  group('Python (requests)', () {
    test('a form is a files list: (None, value) for text, (name, open file, type) for a file', () {
      expect(
        const PythonRequestsGenerator().generate(_multipart),
        'import requests\n'
        '\n'
        'headers = {\n'
        "    'X-Trace': 'abc',\n"
        '}\n'
        'files = [\n'
        "    ('title', (None, 'My cat')),\n"
        "    ('photo', ('cat.png', open('/data/cat.png', \"rb\"), 'image/png')),\n"
        "    ('doc', ('Q3.pdf', open('/data/q3 report.pdf', \"rb\"), 'application/pdf')),\n"
        ']\n'
        "response = requests.request('POST', 'https://api.example.com/upload', headers=headers, files=files)\n"
        'print(response.text)',
      );
    });

    test('a binary body is the open file', () {
      expect(
        const PythonRequestsGenerator().generate(_binary),
        'import requests\n'
        '\n'
        'headers = {\n'
        "    'Content-Type': 'application/octet-stream',\n"
        '}\n'
        "payload = open('/data/backup.tar', \"rb\")\n"
        "response = requests.request('PUT', 'https://bucket.s3.amazonaws.com/backup.tar', headers=headers, data=payload)\n"
        'print(response.text)',
      );
    });
  });

  group('Go (net/http)', () {
    test('a form is written with mime/multipart, each file part with its own type and name', () {
      final out = const GoNetHttpGenerator().generate(_multipart);

      expect(out, contains('\t"mime/multipart"'));
      expect(out, contains('\t"net/textproto"'));
      expect(out, contains('writer.WriteField("title", "My cat")'));
      expect(out, contains('header1.Set("Content-Disposition", mime.FormatMediaType("form-data", map[string]string{"name": "photo", "filename": "cat.png"}))'));
      expect(out, contains('header1.Set("Content-Type", "image/png")'));
      expect(out, contains('header2.Set("Content-Disposition", mime.FormatMediaType("form-data", map[string]string{"name": "doc", "filename": "Q3.pdf"}))'));
      expect(out, contains('file1, err := os.Open("/data/cat.png")'));
      expect(out, contains('file2, err := os.Open("/data/q3 report.pdf")'));
      expect(out, contains('req, err := http.NewRequest("POST", "https://api.example.com/upload", &payload)'));
      expect(out, contains('req.Header.Set("Content-Type", writer.FormDataContentType())'));
      expect(out, contains('req.Header.Set("X-Trace", "abc")'));
      expect(out, isNot(contains('boundary=B')));
    });

    test('a binary body is the open file with its size as the content length', () {
      final out = const GoNetHttpGenerator().generate(_binary);

      expect(out, contains('file, err := os.Open("/data/backup.tar")'));
      expect(out, contains('info, err := file.Stat()'));
      expect(out, contains('req, err := http.NewRequest("PUT", "https://bucket.s3.amazonaws.com/backup.tar", file)'));
      expect(out, contains('req.ContentLength = info.Size()'));
      expect(out, contains('req.Header.Set("Content-Type", "application/octet-stream")'));
      expect(out, isNot(contains('mime/multipart')));
    });
  });

  group('Java and Kotlin (OkHttp)', () {
    test('Java: a MultipartBody, and no Content-Type header', () {
      final out = const JavaOkHttpGenerator().generate(_multipart);

      expect(out, contains('.setType(MultipartBody.FORM)'));
      expect(out, contains('.addFormDataPart("title", "My cat")'));
      expect(out, contains('.addFormDataPart("photo", "cat.png", RequestBody.create(new File("/data/cat.png"), MediaType.parse("image/png")))'));
      expect(out, contains('.addFormDataPart("doc", "Q3.pdf", RequestBody.create(new File("/data/q3 report.pdf"), MediaType.parse("application/pdf")))'));
      expect(out, contains('.method("POST", body)'));
      expect(out, contains('.addHeader("X-Trace", "abc")'));
      expect(out, isNot(contains('addHeader("Content-Type"')));
      expect(out, contains('import okhttp3.MultipartBody;'));
      expect(out, contains('import java.io.File;'));
    });

    test('Java: a binary body is the File with no media type', () {
      final out = const JavaOkHttpGenerator().generate(_binary);

      expect(out, contains('RequestBody body = RequestBody.create(new File("/data/backup.tar"), null);'));
      expect(out, contains('.addHeader("Content-Type", "application/octet-stream")'));
    });

    test('Kotlin: a MultipartBody with asRequestBody', () {
      final out = const KotlinOkHttpGenerator().generate(_multipart);

      expect(out, contains('.addFormDataPart("title", "My cat")'));
      expect(out, contains('.addFormDataPart("photo", "cat.png", File("/data/cat.png").asRequestBody("image/png".toMediaType()))'));
      expect(out, contains('import okhttp3.MediaType.Companion.toMediaType'));
      expect(out, contains('import okhttp3.RequestBody.Companion.asRequestBody'));
      expect(out, isNot(contains('addHeader("Content-Type"')));
    });

    test('Kotlin: a binary body is File(...).asRequestBody()', () {
      final out = const KotlinOkHttpGenerator().generate(_binary);

      expect(out, contains('val body = File("/data/backup.tar").asRequestBody()'));
      expect(out, isNot(contains('toMediaType')));
    });
  });

  group('C# (HttpClient)', () {
    test('a form is a MultipartFormDataContent with a StreamContent per file', () {
      final out = const CSharpHttpClientGenerator().generate(_multipart);

      expect(out, contains('using var form = new MultipartFormDataContent();'));
      expect(out, contains('form.Add(new StringContent("My cat"), "title");'));
      expect(out, contains('var file1 = new StreamContent(File.OpenRead("/data/cat.png"));'));
      expect(out, contains('file1.Headers.ContentType = MediaTypeHeaderValue.Parse("image/png");'));
      expect(out, contains('form.Add(file1, "photo", "cat.png");'));
      expect(out, contains('form.Add(file2, "doc", "Q3.pdf");'));
      expect(out, contains('request.Content = form;'));
      expect(out, contains('request.Headers.TryAddWithoutValidation("X-Trace", "abc");'));
      expect(out, isNot(contains('"Content-Type"')));
    });

    test('a binary body is a StreamContent typed by its own header', () {
      final out = const CSharpHttpClientGenerator().generate(_binary);

      expect(out, contains('request.Content = new StreamContent(File.OpenRead("/data/backup.tar"));'));
      expect(out, contains('request.Content.Headers.TryAddWithoutValidation("Content-Type", "application/octet-stream");'));
    });
  });

  group('PHP, Ruby, Swift, Rust', () {
    test('PHP: an array of fields with CURLFile, and no Content-Type', () {
      final out = const PhpCurlGenerator().generate(_multipart);

      expect(out, contains("'title' => 'My cat',"));
      expect(out, contains("'photo' => new CURLFile('/data/cat.png', 'image/png', 'cat.png'),"));
      expect(out, contains("'doc' => new CURLFile('/data/q3 report.pdf', 'application/pdf', 'Q3.pdf'),"));
      expect(out, contains('CURLOPT_POSTFIELDS => ['));
      expect(out, isNot(contains('Content-Type')));
      expect(const PhpCurlGenerator().generate(_binary), contains("CURLOPT_POSTFIELDS => file_get_contents('/data/backup.tar'),"));
    });

    test('Ruby: set_form with multipart/form-data, and a body stream for a binary body', () {
      final out = const RubyNetHttpGenerator().generate(_multipart);

      expect(out, contains('request.set_form(['));
      expect(out, contains("['title', 'My cat'],"));
      expect(out, contains("['photo', File.open('/data/cat.png', \"rb\"), { filename: 'cat.png', content_type: 'image/png' }],"));
      expect(out, contains("], 'multipart/form-data')"));
      expect(out, isNot(contains("request['Content-Type']")));
      final binary = const RubyNetHttpGenerator().generate(_binary);
      expect(binary, contains('request.body_stream = File.open(\'/data/backup.tar\', "rb")'));
      expect(binary, contains("request.content_length = File.size('/data/backup.tar')"));
    });

    test('Swift: the body is written part by part from the files, with the boundary set in the header', () {
      final out = const SwiftUrlSessionGenerator().generate(_multipart);

      expect(out, contains('let boundary = "B"'));
      expect(out, contains(r'filename=\"cat.png\"'));
      expect(out, contains('Data(contentsOf: URL(fileURLWithPath: "/data/cat.png"))'));
      expect(out, contains('request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")'));
      expect(out, contains('request.httpBody = body'));
      expect(const SwiftUrlSessionGenerator().generate(_binary), contains('request.httpBody = try! Data(contentsOf: URL(fileURLWithPath: "/data/backup.tar"))'));
    });

    test('Rust: reqwest::multipart with Part::bytes, and the bytes of the file for a binary body', () {
      final out = const RustReqwestGenerator().generate(_multipart);

      expect(out, contains('.text("title", "My cat")'));
      expect(out, contains('reqwest::multipart::Part::bytes(std::fs::read("/data/cat.png")?)'));
      expect(out, contains('.file_name("cat.png")'));
      expect(out, contains('.mime_str("image/png")?'));
      expect(out, contains('.multipart(form)'));
      expect(const RustReqwestGenerator().generate(_binary), contains('.body(std::fs::read("/data/backup.tar")?)'));
    });
  });

  group('Dart, PowerShell and R', () {
    test('Dart: a MultipartRequest with MultipartFile.fromPath; a Request with the bytes of the file for a binary body', () {
      final out = const DartHttpGenerator().generate(_multipart);

      expect(out, contains("import 'package:http_parser/http_parser.dart' show MediaType;"));
      expect(out, contains("final request = http.MultipartRequest('POST', uri);"));
      expect(out, contains("request.fields['title'] = 'My cat';"));
      expect(out, contains("'/data/cat.png',"));
      expect(out, contains("filename: 'cat.png',"));
      expect(out, contains("contentType: MediaType('image', 'png'),"));
      expect(out, contains("request.headers.addAll({\n    'X-Trace': 'abc',\n  });"));
      final binary = const DartHttpGenerator().generate(_binary);
      expect(binary, contains("import 'dart:io';"));
      expect(binary, contains("final request = http.Request('PUT', uri);"));
      expect(binary, contains("request.bodyBytes = await File('/data/backup.tar').readAsBytes();"));
    });

    test('PowerShell: a .NET MultipartFormDataContent as the body; -InFile for a binary body', () {
      final out = const PowerShellGenerator().generate(_multipart);

      expect(out, contains('[System.Net.Http.MultipartFormDataContent]::new()'));
      expect(out, contains(r"$form.Add([System.Net.Http.StringContent]::new('My cat'), 'title')"));
      expect(out, contains(r"$file1 = [System.Net.Http.StreamContent]::new([System.IO.File]::OpenRead('/data/cat.png'))"));
      expect(out, contains(r"$form.Add($file1, 'photo', 'cat.png')"));
      expect(out, contains(r'-Body $form'));
      expect(out, isNot(contains("'Content-Type'")));
      final binary = const PowerShellGenerator().generate(_binary);
      expect(binary, contains("-InFile '/data/backup.tar'"));
      expect(binary, contains("'Content-Type' = 'application/octet-stream'"));
    });

    test('R: upload_file parts with encode = "multipart", and a note for a renamed file', () {
      final out = const RHttrGenerator().generate(_multipart);

      expect(out, contains('"photo" = upload_file("/data/cat.png", type = "image/png")'));
      expect(out, contains('"doc" = upload_file("/data/q3 report.pdf", type = "application/pdf")'));
      expect(out, contains('encode = "multipart"'));
      expect(out, contains('# httr sends a file under its own name: the name of "doc" cannot be set.'));
      expect(const RHttrGenerator().generate(_binary), contains('body = upload_file("/data/backup.tar", type = "application/octet-stream")'));
    });
  });

  group('every generator', () {
    test('writes a form and a binary body that name their files, never repeat the boundary, and never fail', () {
      expect(CodeGeneratorRegistry.all, hasLength(17));
      for (final generator in CodeGeneratorRegistry.all) {
        final form = generator.generate(_multipart);
        // wget has no multipart encoder and says so instead of naming the files.
        expect(form, generator.id == 'wget' ? contains('cannot send multipart') : contains('cat.png'), reason: generator.label);
        expect(form, isNot(contains('boundary=B')), reason: '${generator.label} must leave the boundary to the library');

        final binary = generator.generate(_binary);
        expect(binary, contains('backup.tar'), reason: '${generator.label} names the file of a binary body');
      }
    });

    test('a form without a file is still printed as the body it sends, as before', () {
      final plain = ResolvedRequestSpec(
        method: 'POST',
        url: 'https://api.example.com/upload',
        headers: const {'Content-Type': 'multipart/form-data; boundary=B'},
        bodyBytes: const [45, 45, 66, 13, 10],
      );

      expect(const CurlGenerator().generate(plain), contains('--data-raw'));
      expect(const CurlGenerator().generate(plain), contains('boundary=B'));
    });
  });
}
