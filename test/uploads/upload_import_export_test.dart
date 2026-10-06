import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/import_export/domain/services/har_parser.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_exporter.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/curl_parser.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/upload_path_note.dart';

import '../support/in_memory_import_export_fakes.dart';

KeyValueItem _file(String key, String path, {String fileName = '', String contentType = '', bool enabled = true}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, fileName: fileName, contentType: contentType, enabled: enabled);

ApiRequestEntity _request(RequestBody body, {String name = 'Upload', HttpMethod method = HttpMethod.post, String url = 'https://files.example.com/upload'}) =>
    ApiRequestEntity(
      id: 1,
      collectionId: 1,
      folderId: null,
      name: name,
      method: method,
      url: url,
      headers: const [],
      queryParams: const [],
      body: body,
      auth: const RequestAuth(type: AuthType.none),
    );

const _oneMachinePath =
    '1 file path points to this machine, so it will not work for a teammate. '
    'Replace the start of the path with a variable, for example {{uploadDir}}/avatar.png.';

void main() {
  group('the warning for paths of one machine', () {
    test('counts only file rows whose path belongs to a machine, and is worded for one or many', () {
      final bodies = [
        RequestBody(type: BodyType.formData, formFields: [
          _file('a', '/home/ann/a.png'),
          _file('b', r'C:\Users\ann\b.png'),
          _file('c', '{{uploadDir}}/c.png'),
          _file('d', 'fixtures/d.png'),
          KeyValueItem(key: 'text', value: '/not/a/file'),
        ]),
        const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '~/blob.bin')),
      ];

      expect(UploadPathNote.machineSpecificIn(bodies), 3);
      expect(UploadPathNote.of(0), isNull);
      expect(UploadPathNote.of(1), _oneMachinePath);
      expect(UploadPathNote.of(3), startsWith('3 file paths point to this machine, so they will not work for a teammate.'));
    });
  });

  group('cURL import', () {
    ParsedCurlRequest parse(String command) => CurlParser.parse(command)!;

    test('-F name=@file is a file field with its type, name and quoted path', () {
      final request = parse(r'''curl -F 'photo=@fixtures/cat.png;type=image/png' -F 'doc=@"/data/a;b.pdf";filename=Q3.pdf' -F 'plain=@./x.bin' https://x.test/up''');

      expect(request.formFields.map((f) => (f.key, f.value, f.contentType, f.fileName, f.isFile)), [
        ('photo', 'fixtures/cat.png', 'image/png', '', true),
        ('doc', '/data/a;b.pdf', '', 'Q3.pdf', true),
        ('plain', './x.bin', '', '', true),
      ]);
      expect(request.notes, [_oneMachinePath], reason: 'only the absolute path is a machine path');
    });

    test('a field that takes its text from a file is kept off and says why; --form-string is always text', () {
      final request = parse("curl -F 'a=<note.txt' --form-string 'b=@not-a-file' https://x.test");

      expect(request.formFields.map((f) => (f.key, f.value, f.enabled, f.isFile)), [('a', '<note.txt', false, false), ('b', '@not-a-file', true, false)]);
      expect(request.notes, ['Form field "a" takes its text from a file ("<note.txt"), which cannot be imported; it was kept switched off.']);
    });

    test('several files in one field: the first is imported and the rest is reported', () {
      final request = parse("curl -F 'docs=@a.pdf,b.pdf' https://x.test");

      expect(request.formFields.single.value, 'a.pdf');
      expect(request.notes, ['Form field "docs" sends several files ("@a.pdf,b.pdf"); only the first was imported.']);
    });

    test('--data-binary @file is a binary body, typed like curl types -d data unless a header says otherwise', () {
      final plain = parse('curl --data-binary @backup.tar https://x.test/up');
      expect(plain.method, HttpMethod.post);
      expect(plain.requestBody.type, BodyType.binary);
      expect(plain.requestBody.binaryFile!.value, 'backup.tar');
      expect(plain.body, isNull);
      expect(plain.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/x-www-form-urlencoded')]);

      final typed = parse("curl -X PUT -H 'Content-Type: application/x-tar' --data-binary @/srv/backup.tar https://x.test/up");
      expect(typed.method, HttpMethod.put);
      expect(typed.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/x-tar')]);
      expect(typed.notes, [_oneMachinePath]);
    });

    test('-d @file and --data-binary @- are still not importable, and still say so', () {
      expect(parse('curl -d @body.json https://x.test').notes, ['The body is read from a file or standard input ("@body.json"), which cannot be imported.']);
      expect(parse('curl --data-binary @- https://x.test').notes, ['The body is read from a file or standard input ("@-"), which cannot be imported.']);
      expect(parse('curl --data-raw @literal https://x.test').requestBody.rawText, '@literal');
    });

    test('-T file is a PUT of the file, with no Content-Type of its own; a URL ending in / gets the file name', () {
      final request = parse('curl -T ./dist/app.zip https://x.test/releases/');

      expect(request.method, HttpMethod.put);
      expect(request.url, 'https://x.test/releases/app.zip');
      expect(request.headers, isEmpty);
      expect(request.requestBody.binaryFile!.value, './dist/app.zip');
    });

    test('a command that mixes a file body with form fields or text says which was imported', () {
      expect(parse("curl -F a=1 --data-binary @f.bin https://x.test").notes, ['The command sends a file and form fields; only the form fields were imported.']);
      expect(parse("curl -d a=1 --data-binary @f.bin https://x.test").notes, ['The command sends a file and other data as its body; only the file was imported.']);
    });

    test('a pasted script lists each request\'s notes under its name', () async {
      final db = InMemoryDb();

      final summary = await ImportCurlScriptUseCase(db.writer)(
        const ImportCurlScriptParams(script: "# Upload avatar\ncurl -F 'avatar=@/Users/ann/a.png' https://api.test/up\n"),
      );

      expect(summary.notes, ['Upload avatar: $_oneMachinePath']);
      final saved = db.requestsOf(summary.collectionIds.single).single;
      expect(saved.body.formFields.single.isFile, isTrue);
      expect(saved.body.formFields.single.value, '/Users/ann/a.png');
    });
  });

  group('Postman', () {
    String collection(List<Map<String, Object?>> items) => jsonEncode({'info': {'name': 'C'}, 'item': items});

    Map<String, Object?> item(String name, Map<String, Object?> body, {String method = 'POST'}) => {
          'name': name,
          'request': {'method': method, 'url': 'https://a.test/$name', 'body': body},
        };

    RequestBody bodyOf(ParsedPostmanCollection parsed, int index) => (parsed.items[index] as PostmanRequestItem).body;

    test('a formdata file entry is a file row with its content type; a missing or empty src is a file row with no file yet', () {
      final parsed = PostmanCollectionParser.parse(collection([
        item('one', {
          'mode': 'formdata',
          'formdata': [
            {'key': 'name', 'value': 'x', 'type': 'text'},
            {'key': 'avatar', 'type': 'file', 'src': 'fixtures/a.png', 'contentType': 'image/png'},
            {'key': 'later', 'type': 'file'},
            {'key': 'off', 'type': 'file', 'src': 'b.png', 'disabled': true},
          ],
        }),
      ]));

      expect(bodyOf(parsed, 0).formFields.map((f) => (f.key, f.value, f.isFile, f.contentType, f.enabled)), [
        ('name', 'x', false, '', true),
        ('avatar', 'fixtures/a.png', true, 'image/png', true),
        ('later', '', true, '', true),
        ('off', 'b.png', true, '', false),
      ]);
      expect(parsed.notes, isEmpty, reason: 'no path belongs to a machine');
    });

    test('a src that lists several files imports the first and says so', () {
      final parsed = PostmanCollectionParser.parse(collection([
        item('two', {
          'mode': 'formdata',
          'formdata': [
            {'key': 'docs', 'type': 'file', 'src': ['a.pdf', 'b.pdf']},
          ],
        }),
      ]));

      expect(bodyOf(parsed, 0).formFields.single.value, 'a.pdf');
      expect([for (final n in parsed.notes) n.message], ['Request "two": file field "docs" lists 2 files; only the first was imported.']);
    });

    test('mode file is a binary body; with no src it is a binary body with nothing chosen; inline content is reported', () {
      final parsed = PostmanCollectionParser.parse(collection([
        item('src', {'mode': 'file', 'file': {'src': '/data/blob.bin'}}),
        item('none', {'mode': 'file', 'file': <String, Object?>{}}),
        item('inline', {'mode': 'file', 'file': {'content': 'abc'}}),
      ]));

      expect(bodyOf(parsed, 0).type, BodyType.binary);
      expect(bodyOf(parsed, 0).binaryFile!.value, '/data/blob.bin');
      expect(bodyOf(parsed, 1).type, BodyType.binary);
      expect(bodyOf(parsed, 1).binaryFile, isNull);
      expect(bodyOf(parsed, 2).binaryFile, isNull);
      expect([for (final n in parsed.notes) if (n.skipped) n.message], ['Request "inline": a body typed in as file content was not imported.']);
      expect([for (final n in parsed.notes) if (!n.skipped) n.message], [_oneMachinePath]);
    });

    test('the import summary lists the machine paths of the whole collection, once', () async {
      final db = InMemoryDb();
      final summary = await ImportPostmanCollectionUseCase(
        db.collectionRepository,
        db.requestRepository,
        db.collectionVariableRepository,
        db.collectionAuthRepository,
        db.scriptsRepository,
      ).importWithSummary(collection([
        item('a', {'mode': 'formdata', 'formdata': [{'key': 'f', 'type': 'file', 'src': '/home/ann/a.png'}]}),
        item('b', {'mode': 'file', 'file': {'src': r'C:\temp\b.bin'}}),
      ]));

      expect(summary.notes.where((n) => n.contains('point to this machine')), [startsWith('2 file paths point to this machine')]);
    });

    test('export writes a file row as type file with its src, a binary body as mode file, and no nameless row in a form', () {
      final export = jsonDecode(PostmanCollectionExporter.export(
        collectionName: 'C',
        folders: const [],
        requests: [
          _request(RequestBody(type: BodyType.formData, formFields: [
            KeyValueItem(key: 'title', value: 'Cat'),
            _file('photo', '{{uploadDir}}/cat.png', contentType: 'image/png'),
            _file('off', 'x.png', enabled: false),
          ]).withBinaryFile(_file('', '/hidden.bin')), name: 'Form'),
          _request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '{{dir}}/backup.tar')), name: 'Binary'),
        ],
      )) as Map<String, dynamic>;

      final items = (export['item'] as List).cast<Map<String, dynamic>>();
      final form = (items[0]['request'] as Map)['body'] as Map;
      expect(form['mode'], 'formdata');
      expect(form['formdata'], [
        {'key': 'title', 'value': 'Cat', 'disabled': false},
        {'key': 'photo', 'type': 'file', 'src': '{{uploadDir}}/cat.png', 'contentType': 'image/png', 'disabled': false},
        {'key': 'off', 'type': 'file', 'src': 'x.png', 'disabled': true},
      ]);
      final binary = (items[1]['request'] as Map)['body'] as Map;
      expect(binary, {'mode': 'file', 'file': {'src': '{{dir}}/backup.tar'}});
    });

    test('a file survives export then import, form and binary', () {
      final text = PostmanCollectionExporter.export(
        collectionName: 'C',
        folders: const [],
        requests: [
          _request(RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 't', value: 'v'), _file('photo', 'fixtures/cat.png', contentType: 'image/png')]), name: 'Form'),
          _request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', 'fixtures/blob.bin')), name: 'Binary'),
        ],
      );

      final parsed = PostmanCollectionParser.parse(text);

      expect(bodyOf(parsed, 0).formFields.map((f) => (f.key, f.value, f.isFile, f.contentType)), [('t', 'v', false, ''), ('photo', 'fixtures/cat.png', true, 'image/png')]);
      expect(bodyOf(parsed, 1).type, BodyType.binary);
      expect(bodyOf(parsed, 1).binaryFile!.value, 'fixtures/blob.bin');
    });

    test('redacting an export leaves a file entry alone (a path is not a credential)', () {
      final text = PostmanCollectionExporter.export(
        collectionName: 'C',
        folders: const [],
        requests: [_request(RequestBody(type: BodyType.formData, formFields: [_file('password_file', '/keys/pw.txt')]))],
        redactSecrets: true,
      );

      final form = (((jsonDecode(text) as Map)['item'] as List).single['request'] as Map)['body']['formdata'] as List;
      expect(form.single, {'key': 'password_file', 'type': 'file', 'src': '/keys/pw.txt', 'disabled': false});
    });
  });

  group('OpenAPI', () {
    const document = r'''
    {
      "openapi": "3.0.3",
      "info": { "title": "Files" },
      "servers": [{ "url": "https://files.example.com" }],
      "paths": {
        "/upload": {
          "post": {
            "requestBody": { "content": { "multipart/form-data": {
              "schema": { "type": "object", "properties": {
                "title": { "type": "string", "example": "Cat" },
                "photo": { "type": "string", "format": "binary" },
                "docs": { "type": "array", "items": { "type": "string", "format": "binary" } }
              } },
              "encoding": { "photo": { "contentType": "image/png" }, "docs": { "contentType": "application/pdf, text/plain" } }
            } } }
          }
        },
        "/blob": { "put": { "requestBody": { "content": { "application/octet-stream": { "schema": { "type": "string", "format": "binary" } } } } } },
        "/image": { "put": { "requestBody": { "content": { "image/png": { "schema": { "type": "string", "format": "binary" } } } } } },
        "/form": { "post": { "requestBody": { "content": { "application/x-www-form-urlencoded": { "schema": { "type": "object", "properties": {
          "a": { "type": "string" }, "skipped": { "type": "string", "format": "binary" } } } } } } } }
      }
    }
    ''';

    test('a multipart schema with format: binary properties imports file fields, typed by the encoding when it names one type', () {
      final requests = {for (final r in OpenApiParser.parse(document).rootRequests) r.url.replaceFirst('{{baseUrl}}', ''): r};

      expect(requests['/upload']!.body.formFields.map((f) => (f.key, f.isFile, f.value, f.contentType)), [
        ('title', false, 'Cat', ''),
        ('photo', true, '', 'image/png'),
        ('docs', true, '', ''),
      ]);
    });

    test('application/octet-stream, and any media type with a binary schema, is a binary body with no file chosen yet', () {
      final requests = {for (final r in OpenApiParser.parse(document).rootRequests) r.url.replaceFirst('{{baseUrl}}', ''): r};

      expect(requests['/blob']!.body.type, BodyType.binary);
      expect(requests['/blob']!.body.binaryFile, isNull);
      expect(requests['/blob']!.headers.where((h) => h.key == 'Content-Type'), isEmpty);
      expect(requests['/image']!.body.type, BodyType.binary);
      expect(requests['/image']!.body.binaryFile!.contentType, 'image/png');
      expect(requests['/image']!.body.binaryFile!.value, isEmpty);
    });

    test('a urlencoded form cannot hold a file: its binary property is left out as before', () {
      final form = OpenApiParser.parse(document).rootRequests.firstWhere((r) => r.url.endsWith('/form'));

      expect(form.body.urlEncodedFields.map((f) => f.key), ['a']);
    });

    test('Swagger 2: a file formData parameter and an octet-stream body parameter', () {
      final parsed = OpenApiParser.parse(r'''
      { "swagger": "2.0", "info": { "title": "L" }, "host": "x.test", "schemes": ["https"],
        "paths": {
          "/a": { "post": { "consumes": ["multipart/form-data"], "parameters": [{ "name": "image", "in": "formData", "type": "file" }] } },
          "/b": { "put": { "consumes": ["application/octet-stream"], "parameters": [{ "name": "body", "in": "body", "schema": { "type": "string", "format": "binary" } }] } }
        } }
      ''');

      final byUrl = {for (final r in parsed.rootRequests) r.url.replaceFirst('{{baseUrl}}', ''): r};
      expect(byUrl['/a']!.body.formFields.single.isFile, isTrue);
      expect(byUrl['/b']!.body.type, BodyType.binary);
    });

    test('export writes a file field as format: binary with its encoding, and keeps the path out of the document', () {
      final export = OpenApiExporter.export(collectionName: 'Files', folders: const [], requests: [
        _request(RequestBody(type: BodyType.formData, formFields: [
          KeyValueItem(key: 'title', value: 'Cat'),
          _file('photo', '/home/ann/cat.png', contentType: 'image/png'),
          _file('note', '/home/ann/n.txt', contentType: '{{type}}'),
        ])),
      ]);

      final operation = ((jsonDecode(export.text) as Map)['paths'] as Map)['/upload']['post'] as Map;
      final media = (operation['requestBody']['content'] as Map)['multipart/form-data'] as Map;
      expect(media['schema']['properties'], {
        'title': {'type': 'string'},
        'photo': {'type': 'string', 'format': 'binary'},
        'note': {'type': 'string', 'format': 'binary'},
      });
      expect(media['example'], {'title': 'Cat'});
      expect(media['encoding'], {'photo': {'contentType': 'image/png'}});
      expect(export.text, isNot(contains('/home/ann')));
    });

    test('export writes a binary body as format: binary under its media type', () {
      final plain = OpenApiExporter.export(collectionName: 'Files', folders: const [], requests: [
        _request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/a.tar')), method: HttpMethod.put, url: 'https://files.example.com/blob'),
        _request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/a.png', contentType: 'image/png')), method: HttpMethod.put, url: 'https://files.example.com/image'),
      ]);

      final paths = (jsonDecode(plain.text) as Map)['paths'] as Map;
      expect(paths['/blob']['put']['requestBody']['content'], {'application/octet-stream': {'schema': {'type': 'string', 'format': 'binary'}}});
      expect(paths['/image']['put']['requestBody']['content'], {'image/png': {'schema': {'type': 'string', 'format': 'binary'}}});
      expect(plain.text, isNot(contains('/data/')));
    });

    test('a form and a binary body round trip through export then import', () {
      final export = OpenApiExporter.export(collectionName: 'Files', folders: const [], requests: [
        _request(RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Cat'), _file('photo', '/p/cat.png', contentType: 'image/png')])),
        _request(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/p/blob.bin')), method: HttpMethod.put, url: 'https://files.example.com/blob'),
      ]);

      final parsed = OpenApiParser.parse(export.text);

      final byUrl = {for (final r in parsed.rootRequests) r.url.replaceFirst('{{baseUrl}}', ''): r};
      expect(byUrl['/upload']!.body.formFields.map((f) => (f.key, f.isFile, f.contentType)), [('title', false, ''), ('photo', true, 'image/png')]);
      expect(byUrl['/blob']!.body.type, BodyType.binary);
    });
  });

  group('HAR', () {
    String har(List<Map<String, Object?>> entries) => jsonEncode({'log': {'entries': entries}});

    Map<String, Object?> entry(Map<String, Object?> postData, {List<Map<String, String>> headers = const []}) => {
          'request': {'method': 'POST', 'url': 'https://a.test/upload', 'headers': headers, 'postData': postData},
        };

    test('a multipart part with a fileName is a file row; the recorded multipart header (with the old boundary) is dropped', () {
      final parsed = HarParser.parse(har([
        entry(
          {
            'mimeType': 'multipart/form-data; boundary=----X',
            'params': [
              {'name': 'title', 'value': 'Cat'},
              {'name': 'photo', 'fileName': 'cat.png', 'contentType': 'image/png'},
              {'name': 'bare', 'fileName': 'raw.bin'},
            ],
          },
          headers: [
            {'name': 'Content-Type', 'value': 'multipart/form-data; boundary=----X'},
            {'name': 'X-Trace', 'value': 'abc'},
          ],
        ),
      ]));

      final request = parsed.requests.single;
      expect(request.body.formFields.map((f) => (f.key, f.value, f.isFile, f.contentType)), [
        ('title', 'Cat', false, ''),
        ('photo', 'cat.png', true, 'image/png'),
        ('bare', 'raw.bin', true, ''),
      ]);
      expect(request.headers.map((h) => h.key), ['X-Trace'], reason: 'the app writes the boundary of its own body');
    });

    test('a form made only of file parts is still a form', () {
      final parsed = HarParser.parse(har([
        entry({'mimeType': 'multipart/form-data', 'params': [{'name': 'f', 'fileName': 'a.txt'}]}),
      ]));

      expect(parsed.requests.single.body.type, BodyType.formData);
      expect(parsed.requests.single.body.formFields.single.isFile, isTrue);
    });

    test('a urlencoded body never takes a file part', () {
      final parsed = HarParser.parse(har([
        entry({'mimeType': 'application/x-www-form-urlencoded', 'params': [{'name': 'a', 'value': '1'}, {'name': 'f', 'fileName': 'x'}]}),
      ]));

      expect(parsed.requests.single.body.urlEncodedFields.map((f) => f.key), ['a']);
    });

    test('the import summary says the files have to be chosen again, and lists a machine path', () async {
      final db = InMemoryDb();

      final summary = await ImportHarUseCase(db.writer)(har([
        entry({
          'mimeType': 'multipart/form-data',
          'params': [
            {'name': 'a', 'fileName': 'a.png'},
            {'name': 'b', 'fileName': '/Users/ann/b.png'},
          ],
        }),
      ]));

      expect(summary.notes, [
        '2 file fields were imported with only the names of their files: a HAR recording does not say where a file was. '
            'Choose each file again on the Body tab.',
        _oneMachinePath,
      ]);
    });
  });
}
