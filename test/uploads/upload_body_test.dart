import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/core/network/upload_file_source.dart';
import 'package:postpilot/core/network/upload_file_source_io.dart' show IoUploadFileSource;

/// Collects the one digest a chunked sha256 conversion produces.
final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Wraps a source and counts what it was asked to read, to show that nothing is read before the body is opened.
final class _CountingSource implements UploadFileSource {
  final UploadFileSource inner;
  int sizeCalls = 0;
  int bytesRead = 0;
  int opened = 0;

  _CountingSource(this.inner);

  @override
  Future<int> sizeOf(UploadFile file) {
    sizeCalls++;
    return inner.sizeOf(file);
  }

  @override
  Stream<List<int>> read(UploadFile file) {
    opened++;
    return inner.read(file).map((chunk) {
      bytesRead += chunk.length;
      return chunk;
    });
  }

  @override
  Future<UploadFileCheck> check(String path) => inner.check(path);
}

Future<List<int>> _collect(PreparedUpload upload) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in upload.open()) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

UploadFile _file(String path, {String? name, String type = 'application/octet-stream', String label = 'the form field "f"'}) =>
    UploadFile(path: path, fileName: name ?? FilePaths.baseName(path), contentType: type, label: label);

void main() {
  late Directory dir;
  late UploadFileSource disk;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_upload_test_');
    disk = createUploadFileSource();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) => File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(bytes);

  group('multipart encoding, byte for byte', () {
    test('a text part and a file part are written as RFC 7578 describes', () async {
      final photo = write('cat.bin', [0, 1, 2, 3, 250, 251, 252, 253, 254, 255, 13, 10]);
      final body = MultipartUpload(boundary: 'B', parts: [
        const UploadTextPart('title', 'Cat'),
        UploadFilePart('photo', _file(photo.path, name: 'cat.png', type: 'image/png')),
      ]);

      final prepared = await UploadPreparer.prepare(body, disk);

      // Written out by hand from the RFC: CRLF after every header line, a blank line, the content, CRLF, the closing delimiter.
      final expected = BytesBuilder()
        ..add(ascii.encode('--B\r\n'
            'Content-Disposition: form-data; name="title"\r\n'
            '\r\n'
            'Cat\r\n'
            '--B\r\n'
            'Content-Disposition: form-data; name="photo"; filename="cat.png"\r\n'
            'Content-Type: image/png\r\n'
            '\r\n'))
        ..add([0, 1, 2, 3, 250, 251, 252, 253, 254, 255, 13, 10])
        ..add(ascii.encode('\r\n--B--\r\n'));
      expect(await _collect(prepared), expected.toBytes());
      expect(prepared.length, expected.length);
      expect(prepared.contentType, 'multipart/form-data; boundary=B');
    });

    test('a name or file name with a quote or a line break is percent-encoded the way browsers do', () async {
      final f = write('x.txt', [65]);
      final body = MultipartUpload(boundary: 'B', parts: [
        const UploadTextPart('a"b\r\nc', 'v'),
        UploadFilePart('f', _file(f.path, name: 'we"ird\nname.txt', type: 'text/plain')),
      ]);

      final text = latin1.decode(await _collect(await UploadPreparer.prepare(body, disk)));

      expect(text, contains('name="a%22b%0D%0Ac"'));
      expect(text, contains('filename="we%22ird%0Aname.txt"'));
      expect(text, isNot(contains('a"b')));
    });

    test('non-ASCII names and values are sent as UTF-8', () async {
      final f = write('x.txt', [65]);
      final body = MultipartUpload(boundary: 'B', parts: [
        const UploadTextPart('naïve', 'caf\u00e9 \u{1F600}'),
        UploadFilePart('f', _file(f.path, name: 'r\u00e9sum\u00e9.txt', type: 'text/plain')),
      ]);

      final bytes = await _collect(await UploadPreparer.prepare(body, disk));

      expect(utf8.decode(bytes), contains('name="naïve"'));
      expect(utf8.decode(bytes), contains('caf\u00e9 \u{1F600}'));
      expect(utf8.decode(bytes), contains('filename="r\u00e9sum\u00e9.txt"'));
    });

    test('a content type holding a line break cannot start another header', () async {
      final f = write('x.txt', [65]);
      final body = MultipartUpload(boundary: 'B', parts: [UploadFilePart('f', _file(f.path, name: 'x.txt', type: 'text/plain\r\nX-Evil: 1'))]);

      final text = latin1.decode(await _collect(await UploadPreparer.prepare(body, disk)));

      expect(text, contains('Content-Type: text/plain X-Evil: 1\r\n\r\n'));
      expect(text, isNot(contains('\r\nX-Evil')));
    });

    test('two file parts with the same field name are both written, in order', () async {
      final a = write('a.txt', ascii.encode('AAA'));
      final b = write('b.txt', ascii.encode('BBB'));
      final body = MultipartUpload(boundary: 'B', parts: [
        UploadFilePart('doc', _file(a.path, type: 'text/plain')),
        UploadFilePart('doc', _file(b.path, type: 'text/plain')),
      ]);

      final text = ascii.decode(await _collect(await UploadPreparer.prepare(body, disk)));

      expect(
        text,
        '--B\r\nContent-Disposition: form-data; name="doc"; filename="a.txt"\r\nContent-Type: text/plain\r\n\r\nAAA\r\n'
        '--B\r\nContent-Disposition: form-data; name="doc"; filename="b.txt"\r\nContent-Type: text/plain\r\n\r\nBBB\r\n'
        '--B--\r\n',
      );
    });

    test('toBytes writes a form without a file and refuses one with a file', () {
      const plain = MultipartUpload(boundary: 'B', parts: [UploadTextPart('a', '1')]);
      expect(ascii.decode(plain.toBytes()), '--B\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n--B--\r\n');

      final withFile = MultipartUpload(boundary: 'B', parts: [UploadFilePart('f', _file('/x.txt'))]);
      expect(withFile.toBytes, throwsStateError);
    });

    test('a binary body is the file and nothing else', () async {
      final f = write('blob.bin', [9, 8, 7]);
      final prepared = await UploadPreparer.prepare(BinaryUpload(_file(f.path, label: 'the request body')), disk);

      expect(await _collect(prepared), [9, 8, 7]);
      expect(prepared.length, 3);
      expect(prepared.contentType, 'application/octet-stream');
    });
  });

  group('streaming a large file', () {
    test('a 6 MB file goes out in chunks, is never read before the body is opened, and arrives intact', () async {
      final size = 6 * 1024 * 1024 + 123;
      final data = Uint8List(size);
      for (var i = 0; i < size; i++) {
        data[i] = (i * 7 + 3) % 251;
      }
      final big = write('big.bin', data);
      final source = _CountingSource(disk);
      final body = MultipartUpload(boundary: 'BOUNDARY', parts: [
        const UploadTextPart('note', 'hello'),
        UploadFilePart('data', _file(big.path, name: 'big.bin')),
      ]);

      final prepared = await UploadPreparer.prepare(body, source);

      expect(prepared.length, 6291780, reason: 'the size is known up front: it goes out as Content-Length');
      expect(source.sizeCalls, 1);
      expect(source.bytesRead, 0, reason: 'preparing looks at the file, it does not read it');
      expect(source.opened, 0);

      final sink = _DigestSink();
      final input = sha256.startChunkedConversion(sink);
      var chunks = 0;
      var largest = 0;
      var total = 0;
      await for (final chunk in prepared.open()) {
        input.add(chunk);
        chunks++;
        total += chunk.length;
        largest = math.max(largest, chunk.length);
      }
      input.close();

      // Ground truth: python hashlib.sha256 over the multipart body built the same way by hand.
      expect(sink.value.toString(), '496c832f025d78bafdc79fcc85a1d50b3fee26c363500e9e5c91491ca928d8a6');
      expect(total, 6291780);
      expect(chunks, greaterThan(50), reason: 'read piece by piece');
      expect(largest, lessThan(1024 * 1024), reason: 'no chunk is anywhere near the size of the file');
    });

    test('the body can be opened again for every hop of a redirect', () async {
      final f = write('r.bin', [1, 2, 3]);
      final prepared = await UploadPreparer.prepare(BinaryUpload(_file(f.path)), disk);

      expect(await _collect(prepared), [1, 2, 3]);
      expect(await _collect(prepared), [1, 2, 3]);
    });

    test('a file that changed size after it was measured fails with a clear message', () async {
      final f = write('shrinks.bin', List.filled(100, 1));
      final prepared = await UploadPreparer.prepare(BinaryUpload(_file(f.path, name: 'shrinks.bin')), disk);
      f.writeAsBytesSync(List.filled(40, 1));

      await expectLater(
        _collect(prepared),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('changed while it was being sent'))),
      );
    });
  });

  group('what stops a request before anything is sent', () {
    test('a missing file names the field and the path', () async {
      final missing = '${dir.path}${Platform.pathSeparator}nope.png';
      final body = MultipartUpload(boundary: 'B', parts: [UploadFilePart('avatar', _file(missing, label: 'the form field "avatar"'))]);

      await expectLater(
        UploadPreparer.prepare(body, disk),
        throwsA(isA<InvalidRequestException>().having(
          (e) => e.message,
          'message',
          allOf(startsWith('The form field "avatar" sends the file'), contains('nope.png'), contains('was not found')),
        )),
      );
    });

    test('a folder is not a file', () async {
      final body = BinaryUpload(_file(dir.path, label: 'the request body'));

      await expectLater(
        UploadPreparer.prepare(body, disk),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('is a folder, not a file'))),
      );
    });

    test('an empty path says no file was chosen', () async {
      final body = BinaryUpload(_file('', label: 'the request body'));

      await expectLater(
        UploadPreparer.prepare(body, disk),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', 'The request body has no file chosen. Choose a file, or switch the field off.')),
      );
    });

    test('a body over the size limit is refused and says both sizes and where to change it', () async {
      final f = write('two_kb.bin', List.filled(2048, 7));
      final body = BinaryUpload(_file(f.path));

      await expectLater(
        UploadPreparer.prepare(body, disk, maxBytes: 1000),
        throwsA(isA<InvalidRequestException>().having(
          (e) => e.message,
          'message',
          'The upload is 2.0 KB, over the 1000 bytes limit. Raise "Maximum upload size" in Settings to send a larger file.',
        )),
      );
    });

    test('the limit counts every file of a form together, and exactly the limit is allowed', () async {
      final a = write('a.bin', List.filled(600, 1));
      final b = write('b.bin', List.filled(600, 2));
      final body = MultipartUpload(boundary: 'B', parts: [
        UploadFilePart('a', _file(a.path)),
        UploadFilePart('b', _file(b.path)),
      ]);
      final total = (await UploadPreparer.prepare(body, disk)).length;

      expect((await UploadPreparer.prepare(body, disk, maxBytes: total)).length, total);
      await expectLater(UploadPreparer.prepare(body, disk, maxBytes: total - 1), throwsA(isA<InvalidRequestException>()));
    });

    test('a path with a secret in it is masked in the message', () async {
      final body = BinaryUpload(_file('https://user:hunter2@files.example/a.png', label: 'the request body'));

      try {
        await UploadPreparer.prepare(body, disk);
        fail('expected an exception');
      } on InvalidRequestException catch (e) {
        expect(e.message, isNot(contains('hunter2')));
      }
    });

    test('a path made in a browser session cannot be read from disk', () async {
      final body = BinaryUpload(_file('session-file:abc/photo.png', name: 'photo.png', label: 'the request body'));

      await expectLater(
        UploadPreparer.prepare(body, disk),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('chosen in an earlier browser session'))),
      );
    });
  });

  group('relative paths', () {
    test('are taken from the folder given, with its own separator', () async {
      write('here.bin', [5]);
      final source = createUploadFileSource(baseDir: dir.path);

      expect(await source.sizeOf(_file('here.bin')), 1);
      expect(await source.sizeOf(_file('./here.bin')), 1);
    });

    test('a leading ~ is the home folder, which no shell expanded for a path typed into a field', () async {
      write('home_file.bin', [1, 2, 3]);
      final source = IoUploadFileSource(homeDir: dir.path);

      expect(await source.sizeOf(_file('~/home_file.bin')), 3);
      expect((await source.check('~/home_file.bin')).size, 3);
      expect((await source.check('~/missing.bin')).problem, 'File not found');
      expect((await source.check('~')).problem, 'This is a folder, not a file');
      expect((await IoUploadFileSource(homeDir: '').check('~/x')).problem, 'File not found', reason: 'with no home known the path stays as typed');
    });

    test('FilePaths.resolve leaves absolute paths, session references and variables alone', () {
      expect(FilePaths.resolve('a.png', '/base'), '/base/a.png');
      expect(FilePaths.resolve('./sub/a.png', '/base/'), '/base/sub/a.png');
      expect(FilePaths.resolve('a.png', r'C:\base'), r'C:\base\a.png');
      expect(FilePaths.resolve('sub/a.png', r'C:\base'), r'C:\base\sub\a.png');
      expect(FilePaths.resolve('/abs/a.png', '/base'), '/abs/a.png');
      expect(FilePaths.resolve(r'C:\abs\a.png', '/base'), r'C:\abs\a.png');
      expect(FilePaths.resolve('{{dir}}/a.png', '/base'), '{{dir}}/a.png');
      expect(FilePaths.resolve('session-file:x/a.png', '/base'), 'session-file:x/a.png');
      expect(FilePaths.resolve('a.png', null), 'a.png');
    });
  });

  group('FilePaths and ContentTypes', () {
    test('baseName reads both separators and a session reference', () {
      expect(FilePaths.baseName('/a/b/c.txt'), 'c.txt');
      expect(FilePaths.baseName(r'C:\a\b\c.txt'), 'c.txt');
      expect(FilePaths.baseName('c.txt'), 'c.txt');
      expect(FilePaths.baseName('{{uploadDir}}/avatar.png'), 'avatar.png');
      expect(FilePaths.baseName('session-file:k3/my photo.png'), 'my photo.png');
      expect(FilePaths.baseName(''), '');
    });

    test('isMachineSpecific is true for a path of one machine, false for a variable path or a relative one', () {
      expect(FilePaths.isMachineSpecific('/home/ann/a.png'), isTrue);
      expect(FilePaths.isMachineSpecific(r'C:\Users\ann\a.png'), isTrue);
      expect(FilePaths.isMachineSpecific('c:/Users/ann/a.png'), isTrue);
      expect(FilePaths.isMachineSpecific(r'\\server\share\a.png'), isTrue);
      expect(FilePaths.isMachineSpecific('~/a.png'), isTrue);
      expect(FilePaths.isMachineSpecific('{{uploadDir}}/a.png'), isFalse);
      expect(FilePaths.isMachineSpecific('fixtures/a.png'), isFalse);
      expect(FilePaths.isMachineSpecific('a.png'), isFalse);
      expect(FilePaths.isMachineSpecific(''), isFalse);
      expect(FilePaths.isMachineSpecific('session-file:x/a.png'), isFalse);
    });

    test('the type is guessed from the extension, case-insensitively, and falls back to octet-stream', () {
      expect(ContentTypes.forFileName('a.png'), 'image/png');
      expect(ContentTypes.forFileName('A.JPG'), 'image/jpeg');
      expect(ContentTypes.forFileName('report.pdf'), 'application/pdf');
      expect(ContentTypes.forFileName('data.csv'), 'text/csv');
      expect(ContentTypes.forFileName('x.tar.gz'), 'application/gzip');
      expect(ContentTypes.forFileName('sheet.xlsx'), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(ContentTypes.forFileName('noextension'), 'application/octet-stream');
      expect(ContentTypes.forFileName('trailingdot.'), 'application/octet-stream');
      expect(ContentTypes.forFileName('weird.zzz'), 'application/octet-stream');
    });

    test('UploadLimits.describe', () {
      expect(UploadLimits.describe(0), '0 bytes');
      expect(UploadLimits.describe(1), '1 byte');
      expect(UploadLimits.describe(1536), '1.5 KB');
      expect(UploadLimits.describe(5 * 1024 * 1024), '5.0 MB');
      expect(UploadLimits.describe(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('files picked in a browser (kept for the session only)', () {
    test('a picked file is a reference that remembers its name and is live until removed', () {
      final files = SessionFiles();
      final bytes = Uint8List.fromList([1, 2, 3]);

      final reference = files.add(name: 'photo.png', bytes: bytes);

      expect(SessionFiles.isReference(reference), isTrue);
      expect(SessionFiles.nameOf(reference), 'photo.png');
      expect(files.contains(reference), isTrue);
      expect(files.bytesOf(reference), bytes);

      files.remove(reference);
      expect(files.contains(reference), isFalse);
      expect(SessionFiles.nameOf(reference), 'photo.png', reason: 'the name outlives the bytes, for the reload message');
    });

    test('two picks of the same name are two references', () {
      final files = SessionFiles();
      final first = files.add(name: 'a.png', bytes: Uint8List(1));
      final second = files.add(name: 'a.png', bytes: Uint8List(2));

      expect(first, isNot(second));
      expect(files.bytesOf(first)!.length, 1);
      expect(files.bytesOf(second)!.length, 2);
    });

    test('after a reload the reference is saved but its bytes are gone: the registry is empty again', () {
      final before = SessionFiles();
      final reference = before.add(name: 'a.png', bytes: Uint8List(4));

      final afterReload = SessionFiles();

      expect(afterReload.contains(reference), isFalse);
      expect(afterReload.bytesOf(reference), isNull);
      expect(SessionFiles.isReference(reference), isTrue, reason: 'it is still recognised, so the editor can say "choose it again"');
    });

    test('a path, a variable path and an empty path are not session references', () {
      expect(SessionFiles.isReference('/a/b.png'), isFalse);
      expect(SessionFiles.isReference('{{dir}}/b.png'), isFalse);
      expect(SessionFiles.isReference(''), isFalse);
      expect(SessionFiles().bytesOf('/a/b.png'), isNull);
    });

    test('the in-memory source sends the picked bytes and describes every state of a file', () async {
      final files = SessionFiles();
      final reference = files.add(name: 'photo.png', bytes: Uint8List.fromList([4, 5, 6]));
      final source = MemoryUploadFileSource(files);

      final prepared = await UploadPreparer.prepare(
        BinaryUpload(_file(reference, name: 'photo.png', label: 'the request body')),
        source,
      );
      expect(await _collect(prepared), [4, 5, 6]);

      expect((await source.check(reference)).size, 3);
      expect((await source.check('')).problem, 'No file chosen');
      expect((await source.check('session-file:gone/old.png')).problem, contains('Chosen in an earlier browser session'));
      expect((await source.check('{{dir}}/a.png')).unresolved, isTrue);
      expect((await source.check('/some/path.png')).problem, contains('only send a file chosen with the button'));
    });

    test('sending a lost reference says to choose the file again', () async {
      final source = MemoryUploadFileSource(SessionFiles());

      await expectLater(
        UploadPreparer.prepare(BinaryUpload(_file('session-file:gone/old.png', name: 'old.png', label: 'the form field "doc"')), source),
        throwsA(isA<InvalidRequestException>().having(
          (e) => e.message,
          'message',
          'The form field "doc" sends "old.png", which was chosen in an earlier browser session. A browser cannot read it again: choose the file again.',
        )),
      );
    });

    test('the disk source reports a session reference found in a shared workspace', () async {
      final check = await disk.check('session-file:gone/old.png');
      expect(check.problem, contains('Chosen in an earlier browser session'));
    });
  });

  group('looking at a file for the editor', () {
    test('size, not found, folder and variable paths', () async {
      final f = write('known.bin', List.filled(10, 1));

      expect((await disk.check(f.path)).size, 10);
      expect((await disk.check('${dir.path}${Platform.pathSeparator}missing.bin')).problem, 'File not found');
      expect((await disk.check(dir.path)).problem, 'This is a folder, not a file');
      expect((await disk.check('')).problem, 'No file chosen');
      expect((await disk.check('{{uploadDir}}/a.png')).unresolved, isTrue);
    });
  });
}
