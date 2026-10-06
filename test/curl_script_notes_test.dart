import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/import_export/domain/services/curl_script_parser.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_usecase.dart';
import 'support/in_memory_import_export_fakes.dart';

void main() {
  group('CurlScriptParser with the wider flag set', () {
    test('flags with values do not turn into URLs, and the body is typed like curl sends it', () {
      final parsed = CurlScriptParser.parse('''
# Health
curl -s -o /dev/null -m 5 -w '%{http_code}' https://api.test/health

# Login
curl -X POST https://api.test/login -d username=ann -d password=pw

# Upload
curl -F 'name=Ann' -F 'file=@/tmp/a.png' https://api.test/up
''');

      expect(parsed.requests.map((r) => (r.name, r.method, r.url)), [
        ('Health', HttpMethod.get, 'https://api.test/health'),
        ('Login', HttpMethod.post, 'https://api.test/login'),
        ('Upload', HttpMethod.post, 'https://api.test/up'),
      ]);
      final login = parsed.requests[1];
      expect(login.body.rawText, 'username=ann&password=pw');
      expect(login.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/x-www-form-urlencoded')]);
      final upload = parsed.requests[2];
      expect(upload.body.type, BodyType.formData);
      expect(upload.body.formFields.map((f) => (f.key, f.enabled)), [('name', true), ('file', false)]);
      expect(parsed.skipped, 0);
    });

    test('what a command asks for and PostPilot cannot do is listed with the request name', () {
      final parsed = CurlScriptParser.parse('# Send\ncurl -d @body.json https://api.test/send\ncurl -T a.csv https://api.test/put');

      expect(parsed.notes, [
        'Send: The body is read from a file or standard input ("@body.json"), which cannot be imported.',
        'PUT /put: The command uploads a file ("a.csv"), which cannot be imported; the body is empty.',
      ]);
    });

    test('a dollar-quoted body with escapes survives a multi-line command', () {
      final parsed = CurlScriptParser.parse(r'''
# Escaped
curl https://api.test/e \
  -H 'Content-Type: application/json' \
  --data-raw $'{"a":"it\'s","b":"x\ny"}'
curl https://api.test/next
''');

      expect(parsed.requests, hasLength(2));
      expect(parsed.requests.first.body.rawText, '{"a":"it\'s","b":"x\ny"}');
      expect(parsed.requests.last.url, 'https://api.test/next');
    });

    test('a command cut off in the middle of an option is skipped, not thrown', () {
      final parsed = CurlScriptParser.parse('curl https://api.test/a -H\ncurl https://api.test/b');

      expect(parsed.requests.single.url, 'https://api.test/b');
      expect(parsed.skipped, 1);
    });
  });

  group('ImportCurlScriptUseCase summary', () {
    late InMemoryDb db;
    late ImportCurlScriptUseCase useCase;

    setUp(() {
      db = InMemoryDb();
      useCase = ImportCurlScriptUseCase(db.writer);
    });

    test('carries the skipped-command line and the per-request notes', () async {
      final summary = await useCase(
        const ImportCurlScriptParams(script: '# Send\ncurl -d @body.json https://api.test/send\ncurl -X GET\ncurl https://api.test/b -H'),
      );

      expect((summary.requests, summary.skipped), (1, 2));
      expect(summary.notes, [
        '2 commands had no URL or were cut off, so they were skipped.',
        'Send: The body is read from a file or standard input ("@body.json"), which cannot be imported.',
      ]);
    });

    test('one skipped command is described in the singular, and a clean import has no notes', () async {
      final one = await useCase(const ImportCurlScriptParams(script: 'curl https://a.test/ok\ncurl -X GET'));
      expect(one.notes, ['1 command had no URL or was cut off, so it was skipped.']);

      final clean = await useCase(const ImportCurlScriptParams(script: 'curl https://a.test/ok'));
      expect(clean.notes, isEmpty);
    });
  });

  group('ImportCurlUseCase (one command)', () {
    test('saves the typed body: a form is text with its Content-Type, -F is form data', () async {
      final db = InMemoryDb();
      final useCase = ImportCurlUseCase(db.requestRepository);
      final collectionId = await db.collectionRepository.createCollection('c');

      await useCase(ImportCurlParams(collectionId: collectionId, folderId: null, curlCommand: "curl -d 'a=1&b=2' https://api.test/form"));
      await useCase(ImportCurlParams(collectionId: collectionId, folderId: null, curlCommand: "curl -F 'a=1' https://api.test/multi"));

      final form = db.requests.first;
      expect((form.method, form.body.type, form.body.rawContentType, form.body.rawText), (HttpMethod.post, BodyType.raw, RawContentType.text, 'a=1&b=2'));
      expect(form.headers.map((h) => (h.key, h.value)), [('Content-Type', 'application/x-www-form-urlencoded')]);
      final multi = db.requests.last;
      expect((multi.body.type, multi.body.formFields.single.key), (BodyType.formData, 'a'));
    });
  });
}
