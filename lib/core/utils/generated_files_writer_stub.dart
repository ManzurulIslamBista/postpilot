import 'generated_files_writer_result.dart';

bool get canWriteFilesToFolder => false;

Future<List<String>> existingFilesInFolder(String folder, Iterable<String> paths) =>
    throw UnsupportedError('Writing to a folder is not supported on this platform');

Future<WriteFilesResult> writeFilesToFolder(
  String folder,
  Map<String, String> files, {
  bool overwrite = false,
  Set<String> neverOverwrite = const {},
}) =>
    throw UnsupportedError('Writing to a folder is not supported on this platform');

Future<Map<String, String>> readFilesInFolder(String folder, Iterable<String> paths) =>
    throw UnsupportedError('Reading from a folder is not supported on this platform');
