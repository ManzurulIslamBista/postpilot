import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/dio_api_client.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/core/network/upload_file_source.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/dart_io_sender.dart';
import 'package:postpilot/features/cli/mcp_server.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';

/// What a request that reached the test server looked like.
final class _Received {
  final String method;
  final String path;
  final int contentLength;
  final bool chunked;
  final String? contentType;
  final Uint8List body;
  const _Received(this.method, this.path, this.contentLength, this.chunked, this.contentType, this.body);
}

/// A loopback server that records every request. `/redirect-307` and `/redirect-303` redirect to `/final`.
final class _Server {
  final HttpServer _server;
  final received = <_Received>[];

  _Server._(this._server) {
    _server.listen(_handle);
  }

  static Future<_Server> start() async => _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String url(String path) => 'http://127.0.0.1:${_server.port}$path';

  Future<void> _handle(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
    }
    received.add(_Received(
      request.method,
      request.uri.path,
      request.headers.contentLength,
      request.headers.chunkedTransferEncoding,
      request.headers.contentType?.toString(),
      bytes.takeBytes(),
    ));
    final redirect = switch (request.uri.path) {
      '/redirect-307' => 307,
      '/redirect-303' => 303,
      _ => null,
    };
    if (redirect != null) {
      request.response
        ..statusCode = redirect
        ..headers.set('location', '/final');
    } else {
      request.response.write('ok');
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

ApiRequestOptions get _local => const ApiRequestOptions(proxy: ProxyConfig.none);

KeyValueItem _file(String key, String path, {String fileName = '', String contentType = ''}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, fileName: fileName, contentType: contentType);

void main() {
  late Directory dir;
  late _Server server;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('pp_send_test_');
    server = await _Server.start();
  });

  tearDown(() async {
    await server.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    file.parent.createSync(recursive: true);
    return file..writeAsBytesSync(bytes);
  }

  ApiRequestEntity request({
    HttpMethod method = HttpMethod.post,
    String path = '/up',
    List<KeyValueItem> headers = const [],
    required RequestBody body,
  }) =>
      ApiRequestEntity(
        id: 1,
        collectionId: 1,
        folderId: null,
        name: 'upload',
        method: method,
        url: server.url(path),
        headers: headers,
        queryParams: const [],
        body: body,
        auth: const RequestAuth(type: AuthType.none),
      );

  Future<ApiHttpResponse> send(DioApiClient client, ApiRequestEntity entity, {ApiRequestOptions? options}) {
    final spec = RequestSpecBuilder(boundary: () => 'B').build(entity, VariableResolver(const {}));
    return client.send(ApiRequestSpec(
      method: spec.method,
      url: spec.url,
      headers: spec.headers,
      body: spec.wireBody,
      options: options ?? _local,
    ));
  }

  group('the app sends a file', () {
    test('a form with text and a file reaches the server byte for byte, with its length declared (not chunked)', () async {
      write('cat.bin', [0, 1, 2, 3, 250, 251, 252, 253, 254, 255]);
      final entity = request(
        body: RequestBody(type: BodyType.formData, formFields: [
          KeyValueItem(key: 'title', value: 'Cat'),
          _file('photo', '{{dir}}/cat.bin', fileName: 'cat.png', contentType: 'image/png'),
        ]),
      );
      final spec = RequestSpecBuilder(boundary: () => 'B').build(entity, VariableResolver({'dir': dir.path.replaceAll(r'\', '/')}));

      final response = await DioApiClient().send(ApiRequestSpec(
        method: spec.method,
        url: spec.url,
        headers: spec.headers,
        body: spec.wireBody,
        options: _local,
      ));

      expect(response.statusCode, 200);
      final expected = BytesBuilder()
        ..add(ascii.encode('--B\r\nContent-Disposition: form-data; name="title"\r\n\r\nCat\r\n'
            '--B\r\nContent-Disposition: form-data; name="photo"; filename="cat.png"\r\nContent-Type: image/png\r\n\r\n'))
        ..add([0, 1, 2, 3, 250, 251, 252, 253, 254, 255])
        ..add(ascii.encode('\r\n--B--\r\n'));
      final got = server.received.single;
      expect(got.method, 'POST');
      expect(got.body, expected.toBytes());
      expect(got.contentLength, expected.length);
      expect(got.chunked, isFalse);
      expect(got.contentType, 'multipart/form-data; boundary=B');
    });

    test('a 6 MB binary body is streamed whole and intact with Content-Length, typed octet-stream', () async {
      final size = 6 * 1024 * 1024 + 123;
      final data = Uint8List(size);
      for (var i = 0; i < size; i++) {
        data[i] = (i * 7 + 3) % 251;
      }
      final big = write('big.bin', data);
      final entity = request(
        method: HttpMethod.put,
        body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', big.path)),
      );

      final response = await send(DioApiClient(), entity);

      expect(response.statusCode, 200);
      final got = server.received.single;
      expect(got.method, 'PUT');
      expect(got.contentLength, 6291579);
      expect(got.chunked, isFalse);
      expect(got.contentType, 'application/octet-stream');
      // Ground truth: python hashlib.sha256 of the same 6291579 bytes.
      expect(sha256.convert(got.body).toString(), '81a60e3a8d8a57ddd3ad78f0c30ff22ccb52f0c59a397de4afcbc338a6ef3b16');
    });

    test('a Content-Type header on a binary request is the one the server sees', () async {
      final f = write('x.json', ascii.encode('{"a":1}'));
      final entity = request(
        method: HttpMethod.put,
        headers: [KeyValueItem(key: 'Content-Type', value: 'application/json')],
        body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', f.path)),
      );

      await send(DioApiClient(), entity);

      expect(server.received.single.contentType, 'application/json');
      expect(utf8.decode(server.received.single.body), '{"a":1}');
    });

    test('a client given a bare upload body names its type and length itself', () async {
      final f = write('raw.bin', [1, 2, 3]);
      final upload = BinaryUpload(UploadFile(path: f.path, fileName: 'raw.bin', contentType: 'image/gif', label: 'the request body'));

      await DioApiClient().send(ApiRequestSpec(method: 'POST', url: server.url('/up'), body: upload, options: _local));

      final got = server.received.single;
      expect(got.contentType, 'image/gif');
      expect(got.contentLength, 3);
    });

    test('a 307 redirect sends the file again to the new place; a 303 turns into a GET without the body', () async {
      final f = write('r.bin', [9, 9, 9, 9]);
      final entity307 = request(
        path: '/redirect-307',
        body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', f.path)),
      );

      await send(DioApiClient(), entity307);

      expect(server.received.map((r) => '${r.method} ${r.path}'), ['POST /redirect-307', 'POST /final']);
      expect(server.received[1].body, [9, 9, 9, 9]);
      expect(server.received[1].contentLength, 4);

      server.received.clear();
      await send(DioApiClient(), request(path: '/redirect-303', body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', f.path))));

      expect(server.received.map((r) => '${r.method} ${r.path}'), ['POST /redirect-303', 'GET /final']);
      expect(server.received[1].body, isEmpty);
      expect(server.received[1].contentType, isNull, reason: 'the body headers go with the body');
    });

    test('a missing file is a clear error and nothing is sent', () async {
      final entity = request(
        body: RequestBody(type: BodyType.formData, formFields: [_file('avatar', '${dir.path}/nope.png')]),
      );

      await expectLater(
        send(DioApiClient(), entity),
        throwsA(isA<InvalidRequestException>().having(
          (e) => e.message,
          'message',
          allOf(startsWith('The form field "avatar" sends the file'), contains('nope.png'), contains('was not found')),
        )),
      );
      expect(server.received, isEmpty);
    });

    test('a body over the upload limit is refused before anything is sent', () async {
      final f = write('ten.bin', List.filled(10, 1));
      final entity = request(body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', f.path)));

      await expectLater(
        send(DioApiClient(), entity, options: const ApiRequestOptions(proxy: ProxyConfig.none, maxUploadBytes: 5)),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('over the 5 bytes limit'))),
      );
      expect(server.received, isEmpty);

      await send(DioApiClient(), entity, options: const ApiRequestOptions(proxy: ProxyConfig.none, maxUploadBytes: 10));
      expect(server.received, hasLength(1), reason: 'exactly the limit is allowed');
    });

    test('in a browser the picked bytes are sent from memory, and a reference lost in a reload is refused', () async {
      final files = SessionFiles();
      final reference = files.add(name: 'note.txt', bytes: Uint8List.fromList(ascii.encode('picked in this session')));
      final client = DioApiClient(uploads: MemoryUploadFileSource(files));
      final entity = request(
        body: RequestBody(type: BodyType.formData, formFields: [_file('doc', reference)]),
      );

      await send(client, entity);

      final text = ascii.decode(server.received.single.body);
      expect(text, contains('name="doc"; filename="note.txt"'));
      expect(text, contains('Content-Type: text/plain'));
      expect(text, contains('picked in this session'));

      final afterReload = DioApiClient(uploads: MemoryUploadFileSource(SessionFiles()));
      await expectLater(
        send(afterReload, entity),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('choose the file again'))),
      );
      expect(server.received, hasLength(1));
    });
  });

  group('the snippet is what is sent', () {
    test('the parts a curl snippet names are the parts the server receives', () async {
      write('report.csv', ascii.encode('a,b\n1,2\n'));
      final entity = request(
        body: RequestBody(type: BodyType.formData, formFields: [
          KeyValueItem(key: 'note', value: '@looks-like-a-file'),
          _file('report', '${dir.path}/report.csv'),
        ]),
      );
      final spec = RequestSpecBuilder(boundary: () => 'B').build(entity, VariableResolver(const {}));
      await send(DioApiClient(), entity);

      final sent = ascii.decode(server.received.single.body);
      final parts = (spec.upload! as MultipartUpload).parts;
      expect((parts[0] as UploadTextPart).value, '@looks-like-a-file');
      expect(sent, contains('name="note"\r\n\r\n@looks-like-a-file\r\n'));
      final file = (parts[1] as UploadFilePart).file;
      expect(sent, contains('name="report"; filename="${file.fileName}"\r\nContent-Type: ${file.contentType}\r\n\r\na,b\n1,2\n\r\n'));
    });
  });

  group('the command line sends a file', () {
    test('a relative path is found from the folder of the workspace and the file is streamed', () async {
      write('fixtures/a.bin', [1, 2, 3, 4, 5]);
      final response = await sendWithDartIo(CliRequest(
        method: 'POST',
        url: server.url('/up'),
        headers: {'Content-Type': 'multipart/form-data; boundary=B'},
        body: null,
        timeout: const Duration(seconds: 20),
        verifySsl: true,
        upload: MultipartUpload(boundary: 'B', parts: [
          UploadFilePart('f', UploadFile(path: 'fixtures/a.bin', fileName: 'a.bin', contentType: 'application/octet-stream', label: 'the form field "f"')),
        ]),
        baseDir: dir.path,
      ));

      expect(response.statusCode, 200);
      final got = server.received.single;
      expect(got.chunked, isFalse);
      expect(got.contentLength, got.body.length);
      final expected = BytesBuilder()
        ..add(ascii.encode('--B\r\nContent-Disposition: form-data; name="f"; filename="a.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'))
        ..add([1, 2, 3, 4, 5])
        ..add(ascii.encode('\r\n--B--\r\n'));
      expect(got.body, expected.toBytes());
    });

    test('a missing file is an error of the request with no connection made', () async {
      await expectLater(
        sendWithDartIo(CliRequest(
          method: 'PUT',
          url: server.url('/up'),
          headers: const {},
          body: null,
          timeout: const Duration(seconds: 20),
          verifySsl: true,
          upload: BinaryUpload(UploadFile(path: 'missing.bin', fileName: 'missing.bin', contentType: 'application/octet-stream', label: 'the request body')),
          baseDir: dir.path,
        )),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('was not found'))),
      );
      expect(server.received, isEmpty);
    });

    test('a workspace request with a relative file runs through the real CLI, exit code 0, the file received', () async {
      write('fixtures/avatar.png', [137, 80, 78, 71]);
      final workspace = File('${dir.path}${Platform.pathSeparator}workspace.json');
      workspace.writeAsStringSync(BackupCodec.encode(BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [
          BackupCollection(name: 'Files', requests: [
            BackupRequest(
              request: ApiRequestEntity(
                id: 0,
                collectionId: 0,
                folderId: null,
                name: 'Upload avatar',
                method: HttpMethod.post,
                url: server.url('/upload'),
                headers: const [],
                queryParams: const [],
                body: RequestBody(type: BodyType.formData, formFields: [
                  KeyValueItem(key: 'user', value: 'ann'),
                  _file('avatar', 'fixtures/avatar.png'),
                ]),
                auth: const RequestAuth(type: AuthType.none),
              ),
            ),
          ]),
        ],
      )));
      final out = StringBuffer();
      final err = StringBuffer();
      final outController = StreamController<List<int>>();
      final errController = StreamController<List<int>>();
      outController.stream.transform(utf8.decoder).listen(out.write);
      errController.stream.transform(utf8.decoder).listen(err.write);

      final code = await runCli(
        ['run', workspace.path, '--no-color'],
        out: IOSink(outController.sink),
        err: IOSink(errController.sink),
        environment: const {},
      );

      expect(code, 0, reason: 'out: $out err: $err');
      final got = server.received.single;
      final text = latin1.decode(got.body);
      expect(text, contains('name="user"\r\n\r\nann\r\n'));
      expect(text, contains('name="avatar"; filename="avatar.png"\r\nContent-Type: image/png\r\n\r\n'));
      // The runner writes its own boundary: the first line is `--<boundary>`, and the file ends where `CRLF--<boundary>--CRLF` starts.
      final opening = latin1.decode(got.body.sublist(0, got.body.indexOf(13)));
      final closing = '\r\n$opening--\r\n'.length;
      expect(got.body.sublist(got.body.length - closing - 4, got.body.length - closing), [137, 80, 78, 71]);
    });

    test('a missing file fails that request with a specific message, and the report does not carry file bytes', () async {
      final workspace = File('${dir.path}${Platform.pathSeparator}workspace.json');
      workspace.writeAsStringSync(BackupCodec.encode(BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [
          BackupCollection(name: 'Files', requests: [
            BackupRequest(
              request: ApiRequestEntity(
                id: 0,
                collectionId: 0,
                folderId: null,
                name: 'Upload',
                method: HttpMethod.put,
                url: server.url('/upload'),
                headers: const [],
                queryParams: const [],
                body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', 'gone.bin')),
                auth: const RequestAuth(type: AuthType.none),
              ),
            ),
          ]),
        ],
      )));
      final fake = <CliRequest>[];
      final runner = WorkspaceRunner.parse(workspace.readAsStringSync(), (r) async {
        fake.add(r);
        return CliResponse(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: const [], duration: Duration.zero);
      }, baseDir: dir.path);

      final summary = await runner.run(const RunOptions());

      expect(fake.single.upload, isA<BinaryUpload>(), reason: 'the runner hands the plan and the base folder to the sender');
      expect(fake.single.baseDir, dir.path);
      expect(fake.single.body, isNull);
      expect(summary.ok, isTrue);

      // With the real sender the same request fails before a connection is made.
      final real = WorkspaceRunner.parse(workspace.readAsStringSync(), sendWithDartIo, baseDir: dir.path);
      final outcome = (await real.run(const RunOptions())).outcomes.single;
      expect(outcome.passed, isFalse);
      expect(outcome.error, allOf(startsWith('The request body sends the file'), contains('gone.bin'), contains('was not found')));
      expect(server.received, isEmpty);
    });
  });

  group('an agent over MCP sends a file', () {
    test('run_request hands the plan and the workspace folder to the sender, and a missing file is a failed request, not a crash', () async {
      write('fixtures/doc.pdf', [37, 80, 68, 70]);
      final snapshot = BackupCodec.encode(BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [
          BackupCollection(name: 'Files', requests: [
            BackupRequest(
              request: ApiRequestEntity(
                id: 0,
                collectionId: 0,
                folderId: null,
                name: 'Upload doc',
                method: HttpMethod.post,
                url: server.url('/upload'),
                headers: const [],
                queryParams: const [],
                body: RequestBody(type: BodyType.formData, formFields: [_file('doc', 'fixtures/doc.pdf'), _file('gone', 'fixtures/gone.pdf')]),
                auth: const RequestAuth(type: AuthType.none),
              ),
            ),
          ]),
        ],
      ));
      final seen = <CliRequest>[];
      final real = McpServer(
        WorkspaceRunner.parse(snapshot, (r) {
          seen.add(r);
          return sendWithDartIo(r);
        }, baseDir: dir.path),
        const RunOptions(),
        const {},
      );

      final reply = jsonDecode((await real.handleLine(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'run_request', 'arguments': {'request': 'Upload doc'}},
      })))!) as Map<String, dynamic>;

      expect(seen.single.upload, isA<MultipartUpload>());
      expect(seen.single.baseDir, dir.path);
      final text = (((reply['result'] as Map)['content'] as List).first as Map)['text'] as String;
      final outcome = jsonDecode(text) as Map<String, dynamic>;
      expect(jsonEncode(outcome), contains('fixtures/gone.pdf'), reason: 'the missing file is named');
      expect(jsonEncode(outcome), contains('was not found'));
      expect(server.received, isEmpty, reason: 'the request was not sent');
    });
  });

  group('the production lock still judges an upload by its method', () {
    test('a POST or PUT that carries a file changes data, a GET does not', () {
      for (final method in [HttpMethod.post, HttpMethod.put, HttpMethod.patch]) {
        expect(ProductionDetector.classify(method, url: 'https://api.acme.com/upload', body: null).changesData, isTrue, reason: method.label);
      }
      expect(ProductionDetector.classify(HttpMethod.get, url: 'https://api.acme.com/upload', body: null).changesData, isFalse);
    });
  });
}
