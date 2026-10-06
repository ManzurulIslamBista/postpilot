import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/services/api_docs_generator.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/git_sync/data/mappers/request_doc_mapper.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/history/domain/entities/history_entry_entity.dart';
import 'package:postpilot/features/history/domain/entities/history_snapshot.dart';
import 'package:postpilot/features/history/domain/services/har_exporter.dart';
import 'package:postpilot/features/history/domain/services/history_curl.dart';
import 'package:postpilot/features/history/domain/services/history_har.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_exporter.dart';
import 'package:postpilot/features/request_builder/data/models/request_json_codec.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_repository_impl.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator_registry.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';

import '../documentation/support/fakes.dart';

const _marker = 'PP-MARKER-FILE-CONTENT-3d9f7a';

KeyValueItem _file(String key, String path, {String fileName = '', String contentType = '', bool enabled = true}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, fileName: fileName, contentType: contentType, enabled: enabled);

ApiRequestEntity _request(RequestBody body, {int id = 7, HttpMethod method = HttpMethod.post}) => ApiRequestEntity(
      id: id,
      collectionId: 1,
      folderId: null,
      name: 'Upload',
      method: method,
      url: 'https://files.example.com/upload',
      headers: const [],
      queryParams: const [],
      body: body,
      auth: const RequestAuth(type: AuthType.none),
    );

void main() {
  group('KeyValueItem JSON', () {
    test('a text row is exactly what it always was', () {
      expect(KeyValueItem(key: 'a', value: '1').toJson(), {'key': 'a', 'value': '1', 'enabled': true});
      expect(KeyValueItem(key: 'a', value: '1', enabled: false).toJson(), {'key': 'a', 'value': '1', 'enabled': false});
    });

    test('a file row adds only kind, and the name and type when they are set', () {
      expect(_file('f', '/a.png').toJson(), {'key': 'f', 'value': '/a.png', 'enabled': true, 'kind': 'file'});
      expect(
        _file('f', '/a.png', fileName: 'b.png', contentType: 'image/png').toJson(),
        {'key': 'f', 'value': '/a.png', 'enabled': true, 'kind': 'file', 'fileName': 'b.png', 'contentType': 'image/png'},
      );
    });

    test('a file name or type left on a text row is not written', () {
      final row = _file('f', '/a.png', fileName: 'b.png', contentType: 'image/png').copyWith(kind: FormFieldKind.text);

      expect(row.toJson(), {'key': 'f', 'value': '/a.png', 'enabled': true});
    });

    test('rows written by an older build read as text rows, and unknown kinds are text', () {
      final old = KeyValueItem.tryFromJson({'key': 'a', 'value': '1', 'enabled': false})!;
      expect((old.key, old.value, old.enabled, old.kind), ('a', '1', false, FormFieldKind.text));

      final future = KeyValueItem.tryFromJson({'key': 'a', 'value': '1', 'kind': 'hologram', 'fileName': 'x'})!;
      expect(future.kind, FormFieldKind.text);
      expect(future.fileName, isEmpty, reason: 'a text row carries no file name');
    });

    test('damaged rows are skipped or read as empty, never thrown', () {
      expect(KeyValueItem.tryFromJson('nope'), isNull);
      expect(KeyValueItem.tryFromJson({'value': 'no key'}), isNull);
      expect(KeyValueItem.tryFromJson({'key': 5}), isNull);
      final lenient = KeyValueItem.tryFromJson({'key': 'k', 'value': 42, 'kind': 'file', 'fileName': 7})!;
      expect((lenient.value, lenient.fileName, lenient.isFile), ('', '', true));
    });

    test('a file row survives toJson then tryFromJson', () {
      final row = _file('f', '{{uploadDir}}/a.png', fileName: 'b.png', contentType: 'image/png', enabled: false);

      final back = KeyValueItem.tryFromJson(jsonDecode(jsonEncode(row.toJson())))!;

      expect((back.key, back.value, back.fileName, back.contentType, back.enabled, back.isFile), ('f', '{{uploadDir}}/a.png', 'b.png', 'image/png', false, true));
    });
  });

  group('the JSON column of the database', () {
    test('text rows are written as before', () {
      expect(RequestJsonCodec.encodeKeyValues([KeyValueItem(key: 'a', value: '1')]), '[{"key":"a","value":"1","enabled":true}]');
    });

    test('a column written before files existed still reads', () {
      final rows = RequestJsonCodec.decodeKeyValues('[{"key":"a","value":"1","enabled":false},{"key":"b","value":"2"}]');

      expect(rows.map((r) => (r.key, r.value, r.enabled, r.isFile)), [('a', '1', false, false), ('b', '2', true, false)]);
    });

    test('file rows round trip through the column, the binary file row included', () {
      final rows = [KeyValueItem(key: 'a', value: '1'), _file('doc', '/d.pdf', contentType: 'application/pdf'), _file('', '/binary.bin')];

      final back = RequestJsonCodec.decodeKeyValues(RequestJsonCodec.encodeKeyValues(rows));

      expect(back.map((r) => (r.key, r.value, r.isFile, r.contentType)), [('a', '1', false, ''), ('doc', '/d.pdf', true, 'application/pdf'), ('', '/binary.bin', true, '')]);
    });
  });

  group('saved in the database', () {
    late AppDatabase db;
    late RequestRepositoryImpl requests;
    late int collectionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      requests = RequestRepositoryImpl(db.requestsDao);
      collectionId = await CollectionRepositoryImpl(db.collectionsDao).createCollection('Files');
    });

    tearDown(() => db.close());

    Future<ApiRequestEntity> saveAndLoad(RequestBody body) async {
      final id = await requests.createRequest(collectionId: collectionId, name: 'Upload');
      await requests.saveRequest(_request(body, id: id).copyWith());
      return (await requests.findById(id))!;
    }

    test('file rows of a form come back as they were saved', () async {
      final loaded = await saveAndLoad(RequestBody(type: BodyType.formData, formFields: [
        KeyValueItem(key: 'title', value: 'Cat'),
        _file('photo', '{{uploadDir}}/cat.png', fileName: 'cat-2.png', contentType: 'image/png'),
      ]));

      expect(loaded.body.type, BodyType.formData);
      final rows = loaded.body.formFields;
      expect((rows[0].key, rows[0].value, rows[0].isFile), ('title', 'Cat', false));
      expect((rows[1].key, rows[1].value, rows[1].isFile, rows[1].fileName, rows[1].contentType), ('photo', '{{uploadDir}}/cat.png', true, 'cat-2.png', 'image/png'));
    });

    test('a binary body comes back as a binary body with its file', () async {
      final loaded = await saveAndLoad(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/backup.tar', contentType: 'application/x-tar')));

      expect(loaded.body.type, BodyType.binary);
      expect(loaded.body.binaryFile!.value, '/data/backup.tar');
      expect(loaded.body.binaryFile!.contentType, 'application/x-tar');
    });

    test('a body type this build does not know reads as no body instead of failing', () async {
      final id = await requests.createRequest(collectionId: collectionId, name: 'From the future');
      await db.requestsDao.updateRequest(id, RequestsCompanion(bodyType: const Value('holographic')));

      final loaded = (await requests.findById(id))!;

      expect(loaded.body.type, BodyType.none);
    });

    test('a request saved with the binary type is stored as the plain string "binary"', () async {
      final id = await requests.createRequest(collectionId: collectionId, name: 'Bin');
      await requests.saveRequest(_request(const RequestBody(type: BodyType.binary), id: id));

      expect((await db.requestsDao.findById(id))!.bodyType, 'binary');
    });

    test('only the reference is stored: the content of the file is in no column, no document, no export and no snippet', () async {
      final dir = Directory.systemTemp.createTempSync('pp_persist_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}${Platform.pathSeparator}secret-photo.bin')..writeAsStringSync('$_marker line two');
      final path = photo.path.replaceAll(r'\', '/');
      final body = RequestBody(type: BodyType.formData, formFields: [
        KeyValueItem(key: 'title', value: 'Cat'),
        _file('photo', path, contentType: 'image/png'),
      ]).withBinaryFile(_file('', path));
      final id = await requests.createRequest(collectionId: collectionId, name: 'Upload');
      await requests.saveRequest(_request(body, id: id));
      final saved = (await requests.findById(id))!;
      final row = (await db.requestsDao.findById(id))!;

      final outputs = <String, String>{
        'database row': jsonEncode(row.toJson()),
        'git document': jsonEncode(RequestDocMapper.toDoc(row, uid: 'u', parentUid: 'p').toJson()),
        'backup file': BackupCodec.encode(BackupSnapshot(
          exportedAt: DateTime.utc(2026),
          collections: [BackupCollection(name: 'Files', requests: [BackupRequest(request: saved)])],
        )),
        'history snapshot': HistoryRequestSnapshot.capture(saved, meta: const HistoryEntryMeta(), maxBodyBytes: 1024, secretValues: const []).encode(),
        'postman export': PostmanCollectionExporter.export(collectionName: 'Files', folders: const [], requests: [saved]),
        'openapi export': OpenApiExporter.export(collectionName: 'Files', folders: const [], requests: [saved]).text,
        for (final generator in CodeGeneratorRegistry.all)
          'snippet ${generator.label}': generator.generate(RequestSpecBuilder().build(saved, VariableResolver(const {}))),
      };
      for (final entry in outputs.entries) {
        expect(entry.value, isNot(contains(_marker)), reason: '${entry.key} must not hold the content of the file');
      }
      // The reference itself is kept where it is meant to be.
      for (final name in ['database row', 'git document', 'backup file', 'history snapshot', 'postman export']) {
        expect(outputs[name], contains('secret-photo.bin'), reason: name);
      }
    });
  });

  group('the workspace file and backups', () {
    test('file rows and a binary body round trip through the backup codec', () {
      final body = RequestBody(type: BodyType.formData, formFields: [
        KeyValueItem(key: 'title', value: 'Cat'),
        _file('photo', '{{uploadDir}}/cat.png', fileName: 'c.png', contentType: 'image/png', enabled: false),
      ]).withBinaryFile(_file('', 'fixtures/blob.bin', contentType: 'application/x-blob'));

      final text = BackupCodec.encode(BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        collections: [BackupCollection(name: 'Files', requests: [BackupRequest(request: _request(body))])],
      ));
      final back = BackupCodec.decode(text).collections.single.requests.single.request.body;

      expect(back.formFields.map((r) => (r.key, r.value, r.isFile, r.enabled, r.fileName, r.contentType)), [
        ('title', 'Cat', false, true, '', ''),
        ('photo', '{{uploadDir}}/cat.png', true, false, 'c.png', 'image/png'),
        ('', 'fixtures/blob.bin', true, true, '', 'application/x-blob'),
      ]);
    });

    test('a workspace file from an older build reads, and its text rows are written the same way again', () {
      const old = '''
      {"format":"postpilot-backup","version":2,"collections":[{"name":"Old","requests":[{"name":"r","method":"post","url":"https://x.test",
      "headers":[],"queryParams":[],"body":{"type":"formData","formFields":[{"key":"a","value":"1","enabled":true}]},"auth":{"type":"none"}}]}]}
      ''';

      final snapshot = BackupCodec.decode(old);
      final field = snapshot.collections.single.requests.single.request.body.formFields.single;

      expect((field.key, field.value, field.isFile), ('a', '1', false));
      final rewritten = jsonDecode(BackupCodec.encode(snapshot)) as Map<String, dynamic>;
      final written = (((rewritten['collections'] as List).single as Map)['requests'] as List).single as Map;
      expect(((written['body'] as Map)['formFields'] as List).single, {'key': 'a', 'value': '1', 'enabled': true});
    });

    test('a body type from a newer build reads as no body', () {
      const future = '''
      {"format":"postpilot-backup","version":2,"collections":[{"name":"F","requests":[{"name":"r","method":"post","url":"https://x.test",
      "body":{"type":"quantum"},"auth":{"type":"none"}}]}]}
      ''';

      expect(BackupCodec.decode(future).collections.single.requests.single.request.body.type, BodyType.none);
    });
  });

  group('History', () {
    final body = RequestBody(type: BodyType.formData, formFields: [
      KeyValueItem(key: 'title', value: 'Cat'),
      _file('photo', '{{uploadDir}}/cat.png', fileName: 'c.png', contentType: 'image/png'),
      _file('api_key_file', '/keys/prod.pem'),
    ]);

    HistoryRequestSnapshot capture(RequestBody body) =>
        HistoryRequestSnapshot.capture(_request(body), meta: const HistoryEntryMeta(), maxBodyBytes: 1024, secretValues: const []);

    test('a snapshot keeps the reference of a file row, and the path of a file is not masked as a secret value', () {
      final stored = HistoryRequestSnapshot.decode(capture(body).encode())!;

      final rows = stored.body.formFields;
      expect((rows[1].value, rows[1].isFile, rows[1].fileName, rows[1].contentType), ('{{uploadDir}}/cat.png', true, 'c.png', 'image/png'));
      expect((rows[2].key, rows[2].value), ('api_key_file', '/keys/prod.pem'), reason: 'a path is not a credential, whatever the field is called');
      expect(stored.hasMaskedValues, isFalse);
    });

    test('a binary body is kept as a reference and comes back as a request that can be sent again', () {
      final snapshot = capture(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/backup.tar')));
      final stored = HistoryRequestSnapshot.decode(snapshot.encode())!;
      final request = stored.toRequest(id: 1, collectionId: 1);

      expect(stored.body.type, BodyType.binary);
      expect(request.body.binaryFile!.value, '/data/backup.tar');
    });

    test('Copy as cURL writes a file as --form name=@path and a binary body as --data-binary', () {
      expect(
        HistoryCurl.template(capture(body)),
        "curl --location --request POST 'https://files.example.com/upload' \\\n"
        "--form 'title=Cat' \\\n"
        "--form 'photo=@{{uploadDir}}/cat.png;type=image/png;filename=c.png' \\\n"
        "--form 'api_key_file=@/keys/prod.pem'",
      );

      final binary = capture(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/backup.tar')));
      expect(
        HistoryCurl.template(binary),
        "curl --location --request POST 'https://files.example.com/upload' \\\n"
        "--header 'Content-Type: application/octet-stream' \\\n"
        "--data-binary '@/data/backup.tar'",
      );
    });

    test('a HAR export writes a file part as name, fileName and type, with no value and no path', () {
      final entry = HistoryEntryEntity(id: 1, method: 'POST', url: 'https://files.example.com/upload', statusCode: 200, durationMs: 5, sentAt: DateTime.utc(2026), meta: const HistoryEntryMeta());
      final input = HistoryHar.inputFor(entry, HistoryDetail(request: capture(body)), expand: (text) => text.replaceAll('{{uploadDir}}', '/srv/up'));

      final har = jsonDecode(HarExporter.export([input])) as Map<String, dynamic>;

      final params = ((((har['log'] as Map)['entries'] as List).single as Map)['request'] as Map)['postData']['params'] as List;
      expect(params[0], {'name': 'title', 'value': 'Cat'});
      expect(params[1], {'name': 'photo', 'fileName': 'c.png', 'contentType': 'image/png'});
      expect(params[2], {'name': 'api_key_file', 'fileName': 'prod.pem'});
      expect(jsonEncode(har), isNot(contains('/srv/up')));
      expect(jsonEncode(har), isNot(contains('/keys/')));
    });

    test('a HAR export of a binary body names the file in a comment and records no content', () {
      final entry = HistoryEntryEntity(id: 1, method: 'PUT', url: 'https://files.example.com/up', statusCode: 200, durationMs: 5, sentAt: DateTime.utc(2026), meta: const HistoryEntryMeta());
      final snapshot = capture(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/backup.tar')));

      final text = HarExporter.export([HistoryHar.inputFor(entry, HistoryDetail(request: snapshot))]);

      expect(text, contains('The body is the file \\"backup.tar\\".'));
      expect(text, isNot(contains('/data/')));
      expect(text, contains('application/octet-stream'));
    });
  });

  group('Git documents', () {
    test('file rows go from a document to the database and back unchanged', () {
      final doc = RequestDocMapper.canonical(
        RequestDocMapper.canonical(
          // The shape a document on disk has.
          _docFor(RequestBody(type: BodyType.formData, formFields: [
            KeyValueItem(key: 'title', value: 'Cat'),
            _file('photo', '{{uploadDir}}/cat.png', fileName: 'c.png', contentType: 'image/png'),
          ])),
        ),
      );

      final fields = ((doc.data['body'] as Map)['formFields'] as List).cast<Map>();
      expect(fields[0], {'key': 'title', 'value': 'Cat', 'enabled': true}, reason: 'a text row has exactly the three keys');
      expect(fields[1], {'key': 'photo', 'value': '{{uploadDir}}/cat.png', 'enabled': true, 'kind': 'file', 'fileName': 'c.png', 'contentType': 'image/png'});

      final companion = RequestDocMapper.toCompanion(doc, folderId: null);
      final back = RequestJsonCodec.decodeKeyValues(companion.formFieldsJson.value);
      expect(back.map((r) => (r.key, r.value, r.isFile, r.fileName, r.contentType)), [
        ('title', 'Cat', false, '', ''),
        ('photo', '{{uploadDir}}/cat.png', true, 'c.png', 'image/png'),
      ]);
    });

    test('a binary body travels as its file row and the type "binary"', () {
      final doc = RequestDocMapper.canonical(_docFor(const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '/data/backup.tar'))));

      expect((doc.data['body'] as Map)['type'], 'binary');
      final companion = RequestDocMapper.toCompanion(doc, folderId: null);
      expect(companion.bodyType.value, 'binary');
      expect(RequestJsonCodec.decodeKeyValues(companion.formFieldsJson.value).single.value, '/data/backup.tar');
    });

    test('a document of a newer build with an unknown body type reads as no body', () {
      final doc = RequestDocMapper.canonical(_docFor(RequestBody.empty, type: 'quantum'));

      expect((doc.data['body'] as Map)['type'], 'none');
    });
  });

  group('documentation', () {
    test('shows the name of a file, never its path or content, and a binary body as its file', () async {
      final requests = FakeRequestRepository({
        1: [
          requestEntity(
            10,
            method: HttpMethod.post,
            name: 'Upload',
            url: '/upload',
            body: RequestBody(type: BodyType.formData, formFields: [
              KeyValueItem(key: 'title', value: 'Cat'),
              _file('photo', r'C:\Users\ann\Pictures\cat.png'),
            ]).withBinaryFile(_file('', '/hidden/nameless.bin')),
          ),
          requestEntity(
            11,
            method: HttpMethod.put,
            name: 'Backup',
            url: '/backup',
            body: const RequestBody(type: BodyType.binary).withBinaryFile(_file('', '{{dir}}/backup.tar')),
          ),
        ],
      });
      final useCase = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Files')]),
        requests,
        FakeResponseExampleRepository(const {}),
        const FakeCollectionVariableRepository({1: <CollectionVariableEntity>[]}),
        FakeCollectionAuthRepository(const {}),
        FakeDocumentationRepository()..seed(EntityKind.collection, 1, ''),
        FakeTagRepository(),
      );

      final model = await useCase(1);

      final upload = model.requests.firstWhere((r) => r.name == 'Upload').body!;
      expect(upload.fields.map((f) => (f.key, f.value)), [('title', 'Cat'), ('photo', 'File: cat.png')]);
      final backup = model.requests.firstWhere((r) => r.name == 'Backup').body!;
      expect(backup.typeLabel, 'Binary');
      expect(backup.fields.map((f) => (f.key, f.value)), [('File', 'backup.tar')]);
      for (final text in [ApiDocsGenerator.toMarkdown(model), ApiDocsGenerator.toHtml(model)]) {
        expect(text, contains('cat.png'));
        expect(text, contains('backup.tar'));
        expect(text, isNot(contains('Pictures')));
        expect(text, isNot(contains('hidden')));
        expect(text, isNot(contains('{{dir}}')));
      }
    });
  });
}

/// A request document in the shape a file in the Git repository has (see `RequestDocMapper.toDoc`).
SyncDoc _docFor(RequestBody body, {String? type}) => SyncDoc(
      uid: 'request-uid',
      kind: SyncKind.request,
      parentUid: 'collection-uid',
      name: 'Upload',
      data: {
        'method': 'post',
        'url': 'https://files.example.com/upload',
        'headers': const <Object?>[],
        'queryParams': const <Object?>[],
        'body': {
          'type': type ?? body.type.name,
          'rawContentType': 'json',
          'rawText': '',
          'formFields': [for (final f in body.formFields) f.toJson()],
          'urlEncodedFields': const <Object?>[],
          'graphqlQuery': '',
          'graphqlVariables': '{}',
        },
        'auth': const RequestAuth(type: AuthType.none).toJson(),
      },
    );
