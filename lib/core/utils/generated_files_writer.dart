import 'generated_files_writer_result.dart';
import 'generated_files_writer_stub.dart'
    if (dart.library.io) 'generated_files_writer_io.dart' as platform;

export 'generated_files_writer_result.dart';

/// Whether this platform can write a set of files into a folder the user picks
/// (desktop and mobile; not the browser).
bool get canWriteFilesToFolder => platform.canWriteFilesToFolder;

/// Which of [paths] (relative to [folder]) already exist there. Ask this before
/// [writeFilesToFolder] so the user can decide about each file that would be replaced.
Future<List<String>> existingFilesInFolder(String folder, Iterable<String> paths) =>
    platform.existingFilesInFolder(folder, paths);

/// Writes [files] (relative path to text) below [folder], creating directories
/// as needed. A path that would leave [folder] (`..`, absolute) is rejected, and
/// nothing is written when any path is.
///
/// Nothing that already exists is replaced unless [overwrite] says so, and a path
/// in [neverOverwrite] is kept even then (a file the user's project shares with
/// the generated code, like its own `api_client.dart`). What was written and what
/// was left alone is in the result.
Future<WriteFilesResult> writeFilesToFolder(
  String folder,
  Map<String, String> files, {
  bool overwrite = false,
  Set<String> neverOverwrite = const {},
}) =>
    platform.writeFilesToFolder(folder, files, overwrite: overwrite, neverOverwrite: neverOverwrite);

/// The text of those of [paths] (relative to [folder]) that exist there, by path; a path that does not exist, is a
/// folder or is unreasonably large is left out. This is what a "what would change" preview compares the generated
/// files with. A path that would leave [folder] is rejected, as in [writeFilesToFolder].
Future<Map<String, String>> readFilesInFolder(String folder, Iterable<String> paths) =>
    platform.readFilesInFolder(folder, paths);
