import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/generated_files_writer.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('postpilot_writer_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File at(String relative) => File('${dir.path}/$relative');

  test('writes new files, creating the folders they sit in', () async {
    final result = await writeFilesToFolder(dir.path, {'lib/a.dart': 'A', 'lib/deep/er/b.dart': 'B'});
    expect(result.written, ['lib/a.dart', 'lib/deep/er/b.dart']);
    expect(result.overwritten, isEmpty);
    expect(result.skipped, isEmpty);
    expect(result.createdCount, 2);
    expect(at('lib/a.dart').readAsStringSync(), 'A');
    expect(at('lib/deep/er/b.dart').readAsStringSync(), 'B');
  });

  test('an existing file is left alone by default, and the result says which', () async {
    Directory('${dir.path}/lib').createSync();
    at('lib/api_client.dart').writeAsStringSync('my own client');
    final result = await writeFilesToFolder(dir.path, {'lib/api_client.dart': 'generated', 'lib/new.dart': 'N'});
    expect(at('lib/api_client.dart').readAsStringSync(), 'my own client');
    expect(result.skipped, ['lib/api_client.dart']);
    expect(result.written, ['lib/new.dart']);
    expect(result.createdCount, 1);
  });

  test('overwrite replaces what exists, but a protected path is still kept', () async {
    Directory('${dir.path}/lib').createSync();
    at('lib/old.dart').writeAsStringSync('old');
    at('lib/api_client.dart').writeAsStringSync('mine');
    final result = await writeFilesToFolder(
      dir.path,
      {'lib/old.dart': 'new', 'lib/api_client.dart': 'generated', 'lib/fresh.dart': 'F'},
      overwrite: true,
      neverOverwrite: {'lib/api_client.dart'},
    );
    expect(at('lib/old.dart').readAsStringSync(), 'new');
    expect(at('lib/api_client.dart').readAsStringSync(), 'mine');
    expect(result.written, ['lib/old.dart', 'lib/fresh.dart']);
    expect(result.overwritten, ['lib/old.dart']);
    expect(result.skipped, ['lib/api_client.dart']);
    expect(result.createdCount, 1);
  });

  test('a protected path that does not exist yet is written', () async {
    final result = await writeFilesToFolder(dir.path, {'lib/api_client.dart': 'generated'}, neverOverwrite: {'lib/api_client.dart'});
    expect(result.written, ['lib/api_client.dart']);
    expect(at('lib/api_client.dart').readAsStringSync(), 'generated');
  });

  test('existingFilesInFolder lists exactly what is already there', () async {
    Directory('${dir.path}/lib').createSync();
    at('lib/there.dart').writeAsStringSync('x');
    expect(await existingFilesInFolder(dir.path, ['lib/there.dart', 'lib/absent.dart', 'other/absent.dart']), ['lib/there.dart']);
  });

  test('a path that leaves the folder rejects the whole batch before anything is written', () async {
    await expectLater(writeFilesToFolder(dir.path, {'ok.dart': 'x', '../escape.dart': 'y'}), throwsArgumentError);
    await expectLater(writeFilesToFolder(dir.path, {'a/../../escape.dart': 'y'}), throwsArgumentError);
    await expectLater(existingFilesInFolder(dir.path, ['../escape.dart']), throwsArgumentError);
    expect(at('ok.dart').existsSync(), isFalse);
    expect(at('../escape.dart').existsSync(), isFalse);
  });

  test('a folder where a file should go is an error, not a silent skip', () async {
    Directory('${dir.path}/lib/x.dart').createSync(recursive: true);
    await expectLater(writeFilesToFolder(dir.path, {'lib/x.dart': 'y'}), throwsArgumentError);
  });

  test('a folder that does not exist is an error', () async {
    await expectLater(writeFilesToFolder('${dir.path}/missing', {'a.dart': 'x'}), throwsArgumentError);
  });
}
