import 'generated_files_writer_stub.dart'
    if (dart.library.io) 'generated_files_writer_io.dart' as platform;

/// Whether this platform can write a set of files into a folder the user picks
/// (desktop and mobile; not the browser).
bool get canWriteFilesToFolder => platform.canWriteFilesToFolder;

/// Writes [files] (relative path to text) below [folder], creating directories
/// as needed. A path that would leave [folder] (`..`, absolute) is rejected.
/// Existing files are overwritten. Returns how many files were written.
Future<int> writeFilesToFolder(String folder, Map<String, String> files) => platform.writeFilesToFolder(folder, files);
