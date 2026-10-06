import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/features/request_builder/presentation/file_picker_service.dart';

/// What the file dialog hands back, with the size and the bytes the test says, and a count of the reads.
final class _ChosenFile implements XFile {
  @override
  final String name;
  @override
  final String path;
  final int size;
  final Uint8List data;
  int reads = 0;

  _ChosenFile({required this.name, this.path = '', required this.size, Uint8List? data}) : data = data ?? Uint8List(0);

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} is not used by the picker');
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  group('FileSelectorPicker', () {
    test('on desktop and mobile it keeps the path of the file and reads nothing', () async {
      final files = SessionFiles();
      final chosen = _ChosenFile(name: 'cat.png', path: '/data/cat.png', size: 3, data: bytes);
      final picker = FileSelectorPicker(sessionFiles: files, isWeb: false, open: () async => chosen);

      final picked = (await picker.pick())!;

      expect((picked.path, picked.name, picked.size, picked.sessionOnly), ('/data/cat.png', 'cat.png', 3, false));
      expect(chosen.reads, 0);
      expect(files.contains(picked.path), isFalse);
    });

    test('in a browser the bytes are kept for the session and the reference is what is saved', () async {
      final files = SessionFiles();
      final picker = FileSelectorPicker(
        sessionFiles: files,
        isWeb: true,
        open: () async => _ChosenFile(name: 'cat.png', path: 'blob:http://localhost/1234', size: 3, data: bytes),
      );

      final picked = (await picker.pick())!;

      expect(SessionFiles.isReference(picked.path), isTrue, reason: 'the blob address of a browser is not kept');
      expect(SessionFiles.nameOf(picked.path), 'cat.png');
      expect((picked.name, picked.size, picked.sessionOnly), ('cat.png', 3, true));
      expect(files.bytesOf(picked.path), bytes);
    });

    test('in a browser a file over the memory limit is refused before it is read, with a message that says what to do', () async {
      final files = SessionFiles();
      final tooBig = _ChosenFile(name: 'disk.iso', size: UploadLimits.webSessionBytes * 2);
      final picker = FileSelectorPicker(sessionFiles: files, isWeb: true, open: () async => tooBig);

      await expectLater(
        picker.pick(),
        throwsA(isA<FilePickRefused>().having(
          (e) => e.message,
          'message',
          '"disk.iso" is 200.0 MB. A browser keeps the file in memory while it is sent, so the web version takes files up to '
              '100.0 MB: use the desktop app for a larger one.',
        )),
      );
      expect(tooBig.reads, 0);
    });

    test('a file of exactly the limit is taken', () async {
      final files = SessionFiles();
      final atLimit = _ChosenFile(name: 'edge.bin', size: UploadLimits.webSessionBytes, data: bytes);
      final picker = FileSelectorPicker(sessionFiles: files, isWeb: true, open: () async => atLimit);

      final picked = (await picker.pick())!;

      expect(picked.size, UploadLimits.webSessionBytes);
      expect(atLimit.reads, 1);
    });

    test('closing the dialog without a choice is null', () async {
      final picker = FileSelectorPicker(sessionFiles: SessionFiles(), isWeb: false, open: () async => null);

      expect(await picker.pick(), isNull);
    });
  });
}
