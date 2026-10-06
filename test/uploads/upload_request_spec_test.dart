import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

ApiRequestEntity _request({
  HttpMethod method = HttpMethod.post,
  List<KeyValueItem> headers = const [],
  RequestBody body = RequestBody.empty,
  RequestAuth auth = const RequestAuth(type: AuthType.none),
}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: 'upload',
      method: method,
      url: 'https://files.example.com/upload',
      headers: headers,
      queryParams: const [],
      body: body,
      auth: auth,
    );

RequestSpecBuilder get _builder => RequestSpecBuilder(boundary: () => 'B');

ResolvedRequestSpec _build(
  ApiRequestEntity request, {
  Map<String, String> variables = const {},
  bool trim = false,
}) =>
    _builder.build(request, VariableResolver(variables), trimKeysAndValues: trim);

KeyValueItem _text(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

KeyValueItem _file(
  String key,
  String path, {
  String fileName = '',
  String contentType = '',
  bool enabled = true,
}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, fileName: fileName, contentType: contentType, enabled: enabled);

RequestBody _form(List<KeyValueItem> fields) => RequestBody(type: BodyType.formData, formFields: fields);

RequestBody _binary(KeyValueItem? file) => const RequestBody(type: BodyType.binary).withBinaryFile(file);

MultipartUpload _multipart(ResolvedRequestSpec spec) => spec.upload! as MultipartUpload;

void main() {
  group('a form without a file', () {
    test('is plain bytes, as before: no upload, the boundary of the header is the one in the body', () {
      final spec = _build(_request(body: _form([_text('a', '1'), _text('b', 'x y')])));

      expect(spec.upload, isNull);
      expect(spec.headers['Content-Type'], 'multipart/form-data; boundary=B');
      expect(
        utf8.decode(spec.bodyBytes!),
        '--B\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n'
        '--B\r\nContent-Disposition: form-data; name="b"\r\n\r\nx y\r\n'
        '--B--\r\n',
      );
      expect(spec.wireBody, same(spec.bodyBytes));
    });

    test('a switched-off row and a row without a key are not sent', () {
      final spec = _build(_request(body: _form([_text('a', '1'), _text('off', '2', enabled: false), _text('', 'nameless')])));

      expect(utf8.decode(spec.bodyBytes!), isNot(contains('off')));
      expect(utf8.decode(spec.bodyBytes!), isNot(contains('nameless')));
    });

    test('without an injected boundary each form gets its own, with the prefix the app has always used', () {
      final first = const RequestSpecBuilder().build(_request(body: _form([_text('a', '1')])), VariableResolver({}));
      final second = const RequestSpecBuilder().build(_request(body: _form([_text('a', '1')])), VariableResolver({}));

      final boundary = RegExp(r'boundary=(.+)$');
      final one = boundary.firstMatch(first.headers['Content-Type']!)![1]!;
      final two = boundary.firstMatch(second.headers['Content-Type']!)![1]!;
      expect(one, startsWith('----PostPilotBoundary'));
      expect(one, isNot(two));
      expect(utf8.decode(first.bodyBytes!), startsWith('--$one\r\n'));
    });
  });

  group('a form with a file part', () {
    test('keeps only the reference: no bytes, an upload plan, the boundary in the header', () {
      final spec = _build(_request(body: _form([_text('title', 'Cat'), _file('photo', '/data/cat.png')])));

      expect(spec.bodyBytes, isNull);
      expect(spec.headers['Content-Type'], 'multipart/form-data; boundary=B');
      final upload = _multipart(spec);
      expect(upload.boundary, 'B');
      expect(upload.parts, hasLength(2));
      expect((upload.parts[0] as UploadTextPart).name, 'title');
      expect((upload.parts[0] as UploadTextPart).value, 'Cat');
      final file = (upload.parts[1] as UploadFilePart).file;
      expect(file.path, '/data/cat.png');
      expect(file.fileName, 'cat.png', reason: 'the name of the file unless the row says another');
      expect(file.contentType, 'image/png', reason: 'guessed from the extension');
      expect(file.label, 'the form field "photo"');
      expect(spec.wireBody, same(spec.upload));
    });

    test('the row can set the name sent and the content type', () {
      final spec = _build(_request(body: _form([_file('doc', '/d/report.bin', fileName: 'Q3.pdf', contentType: 'application/pdf')])));

      final file = (_multipart(spec).parts.single as UploadFilePart).file;
      expect(file.fileName, 'Q3.pdf');
      expect(file.contentType, 'application/pdf');
    });

    test('a file with an unknown extension is application/octet-stream; a Windows path gives its own file name', () {
      final spec = _build(_request(body: _form([_file('blob', r'C:\Users\ann\dump.zzz')])));

      final file = (_multipart(spec).parts.single as UploadFilePart).file;
      expect(file.fileName, 'dump.zzz');
      expect(file.contentType, 'application/octet-stream');
    });

    test('a {{variable}} path is resolved, and so are the name and type', () {
      final spec = _build(
        _request(body: _form([_file('avatar', '{{uploadDir}}/{{name}}.png', fileName: '{{name}}-v2.png', contentType: '{{type}}')])),
        variables: {'uploadDir': '/srv/up', 'name': 'ann', 'type': 'image/x-custom'},
      );

      final file = (_multipart(spec).parts.single as UploadFilePart).file;
      expect(file.path, '/srv/up/ann.png');
      expect(file.fileName, 'ann-v2.png');
      expect(file.contentType, 'image/x-custom');
    });

    test('a variable in the field name is resolved too, and a disabled or nameless file row is left out', () {
      final spec = _build(
        _request(body: _form([
          _file('{{field}}', '/a.png'),
          _file('off', '/b.png', enabled: false),
          _file('', '/c.png'),
          _text('t', '1'),
        ])),
        variables: {'field': 'upload'},
      );

      final parts = _multipart(spec).parts;
      expect(parts.map((p) => p.name), ['upload', 't']);
    });

    test('the trim setting trims the path and the name like any other value', () {
      final spec = _build(_request(body: _form([_file(' f ', '  /a/b.png  ', fileName: ' n.png ')])), trim: true);

      final part = _multipart(spec).parts.single as UploadFilePart;
      expect(part.name, 'f');
      expect(part.file.path, '/a/b.png');
      expect(part.file.fileName, 'n.png');
    });

    test('a user Content-Type header still wins', () {
      final spec = _build(_request(
        headers: [_text('content-type', 'multipart/mixed; boundary=B')],
        body: _form([_file('f', '/a.png')]),
      ));

      expect(spec.headers.keys.where((k) => k.toLowerCase() == 'content-type'), ['content-type']);
    });

    test('a row with no file chosen still produces a part, so the send can say which field is empty', () {
      final spec = _build(_request(body: _form([_file('avatar', '')])));

      final file = (_multipart(spec).parts.single as UploadFilePart).file;
      expect(file.path, '');
      expect(file.fileName, 'file');
    });

    test('a file picked in a browser session is a reference whose name is the picked name', () {
      final spec = _build(_request(body: _form([_file('doc', 'session-file:k1/notes.txt')])));

      final file = (_multipart(spec).parts.single as UploadFilePart).file;
      expect(file.path, 'session-file:k1/notes.txt');
      expect(file.fileName, 'notes.txt');
      expect(file.contentType, 'text/plain');
    });
  });

  group('a binary body', () {
    test('is the file, typed application/octet-stream unless a header or the row says otherwise', () {
      final spec = _build(_request(method: HttpMethod.put, body: _binary(_file('', '/data/backup.tar'))));

      expect(spec.bodyBytes, isNull);
      expect(spec.upload, isA<BinaryUpload>());
      final file = (spec.upload! as BinaryUpload).file;
      expect(file.path, '/data/backup.tar');
      expect(file.label, 'the request body');
      expect(spec.headers['Content-Type'], 'application/octet-stream', reason: 'the type is not guessed from the extension');
    });

    test("the row's content type becomes the default, and a Content-Type header beats both", () {
      final typed = _build(_request(body: _binary(_file('', '/x/photo.png', contentType: 'image/png'))));
      expect(typed.headers['Content-Type'], 'image/png');

      final header = _build(_request(headers: [_text('Content-Type', 'application/x-custom')], body: _binary(_file('', '/x/photo.png', contentType: 'image/png'))));
      expect(header.headers['Content-Type'], 'application/x-custom');
    });

    test('a variable path is resolved', () {
      final spec = _build(_request(body: _binary(_file('', '{{dir}}/blob.bin'))), variables: {'dir': '/mnt/data'});

      expect((spec.upload! as BinaryUpload).file.path, '/mnt/data/blob.bin');
    });

    test('with no file chosen the plan has an empty path, so the send says "no file chosen"', () {
      final spec = _build(_request(body: const RequestBody(type: BodyType.binary)));

      expect((spec.upload! as BinaryUpload).file.path, '');
    });

    test('the binary file is not a field of a form-data send', () {
      final body = RequestBody(
        type: BodyType.formData,
        formFields: [_text('a', '1')],
      ).withBinaryFile(_file('', '/hidden.bin'));

      final spec = _build(_request(body: body));

      expect(spec.upload, isNull, reason: 'a nameless row is not a field');
      expect(utf8.decode(spec.bodyBytes!), isNot(contains('hidden.bin')));
    });
  });

  group('RequestBody and its binary file', () {
    test('the file is the first file row without a key, wherever it sits', () {
      final file = _file('', '/x.bin');
      final body = RequestBody(type: BodyType.binary, formFields: [_text('a', '1'), _file('named', '/n.bin'), file]);

      expect(body.binaryFile, same(file));
    });

    test('withBinaryFile replaces the file, removes it with null, and forces a nameless enabled file row', () {
      final first = const RequestBody(type: BodyType.binary).withBinaryFile(_file('ignored', '/one.bin', enabled: false));

      expect(first.formFields.single.key, '');
      expect(first.formFields.single.isFile, isTrue);
      expect(first.formFields.single.enabled, isTrue);

      final second = first.withBinaryFile(_file('', '/two.bin'));
      expect(second.formFields, hasLength(1));
      expect(second.binaryFile!.value, '/two.bin');

      final none = second.withBinaryFile(null);
      expect(none.formFields, isEmpty);
      expect(none.binaryFile, isNull);
    });

    test('it leaves the other form rows alone', () {
      final body = RequestBody(type: BodyType.formData, formFields: [_text('a', '1'), _file('f', '/f.bin')]).withBinaryFile(_file('', '/b.bin'));

      expect(body.formFields.map((f) => f.key), ['a', 'f', '']);
      expect(body.withBinaryFile(null).formFields.map((f) => f.key), ['a', 'f']);
    });
  });

  group('{{variables}} the request needs to find its files', () {
    List<String> undefinedNames(ApiRequestEntity request, [Map<String, String> defined = const {}]) => [
          for (final v in _builder.undefinedVariables(request, VariableResolver(defined))) v.name,
        ];

    test('an undefined variable in a file path, name or type is reported with the field it is in', () {
      final request = _request(body: _form([_file('avatar', '{{uploadDir}}/a.png', fileName: '{{n}}.png', contentType: '{{t}}')]));

      final found = {for (final v in _builder.undefinedVariables(request, VariableResolver({}))) v.name: v};

      expect(found.keys, containsAll(['uploadDir', 'n', 't']));
      expect(found['uploadDir']!.places, ['the form field "avatar"']);
      expect(found['uploadDir']!.inBody, isTrue);
    });

    test('a defined variable is not reported, and neither is a disabled or nameless row', () {
      final request = _request(body: _form([
        _file('avatar', '{{uploadDir}}/a.png'),
        _file('off', '{{gone}}/b.png', enabled: false),
        _file('', '{{nameless}}/c.png'),
      ]));

      expect(undefinedNames(request, {'uploadDir': '/srv'}), isEmpty);
    });

    test('the file of a binary body is checked too', () {
      final request = _request(body: _binary(_file('', '{{dir}}/x.bin', contentType: '{{t}}')));

      final found = {for (final v in _builder.undefinedVariables(request, VariableResolver({}))) v.name: v};

      expect(found.keys, containsAll(['dir', 't']));
      expect(found['dir']!.places, ['the file of the request body']);
    });
  });

  group('AWS Signature V4 with a file body', () {
    const aws = RequestAuth(
      type: AuthType.awsSignatureV4,
      awsAccessKey: 'AKIAIOSFODNN7EXAMPLE',
      awsSecretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      awsRegion: 'us-east-1',
      awsService: 's3',
    );

    test('S3 is told the payload is unsigned: the file is read when it is sent, so its hash cannot be signed', () {
      final spec = _build(_request(method: HttpMethod.put, auth: aws, body: _binary(_file('', '/data/a.bin'))));

      expect(spec.headers['X-Amz-Content-Sha256'], 'UNSIGNED-PAYLOAD');
      expect(spec.headers['Authorization'], startsWith('AWS4-HMAC-SHA256 '));
      expect(spec.headers['Authorization'], contains('x-amz-content-sha256'), reason: 'and the header is signed');
    });

    test("the user's own x-amz-content-sha256 row wins", () {
      final spec = _build(_request(
        method: HttpMethod.put,
        auth: aws,
        headers: [_text('x-amz-content-sha256', 'STREAMING-AWS4-HMAC-SHA256-PAYLOAD')],
        body: _binary(_file('', '/data/a.bin')),
      ));

      expect(spec.headers.entries.where((e) => e.key.toLowerCase() == 'x-amz-content-sha256').map((e) => e.value), ['STREAMING-AWS4-HMAC-SHA256-PAYLOAD']);
    });

    test('a request with plain bytes is signed with their hash as before', () {
      final spec = _build(_request(method: HttpMethod.put, auth: aws, body: const RequestBody(type: BodyType.raw, rawText: 'hello')));

      expect(spec.headers['X-Amz-Content-Sha256'], '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
    });
  });
}
