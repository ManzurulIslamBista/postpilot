import 'dart:io';
import 'upload_body.dart';
import 'upload_file_source.dart';

/// Desktop and mobile: reads the file from its path when it is sent. A relative path is taken from [baseDir] (the
/// folder of the workspace file on the command line). A path that carries a session reference was made by the web
/// build and cannot be read here.
UploadFileSource createUploadFileSource({String? baseDir}) => IoUploadFileSource(baseDir: baseDir);

final class IoUploadFileSource implements UploadFileSource {
  final String? baseDir;

  /// What a leading `~` stands for; the user's home folder unless a test says another.
  final String? homeDir;

  IoUploadFileSource({this.baseDir, String? homeDir})
      : homeDir = homeDir ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  Future<int> sizeOf(UploadFile file) async {
    final path = _pathOf(file);
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) throw UploadFileProblem.notFound(file);
      if (type == FileSystemEntityType.directory) throw UploadFileProblem.notAFile(file);
      return await File(path).length();
    } on FileSystemException catch (e) {
      throw UploadFileProblem.unreadable(file, e.osError?.message.trim().isNotEmpty == true ? e.osError!.message.trim() : e.message);
    }
  }

  @override
  Stream<List<int>> read(UploadFile file) => File(_pathOf(file)).openRead();

  @override
  Future<UploadFileCheck> check(String path) async {
    final text = path.trim();
    if (text.isEmpty) return UploadFileCheck.noFile;
    if (SessionFiles.isReference(text)) return UploadFileCheck.lostWithTheSession;
    if (text.contains('{{')) return const UploadFileCheck(unresolved: true);
    final resolved = _resolve(text);
    try {
      final type = await FileSystemEntity.type(resolved);
      if (type == FileSystemEntityType.notFound) return const UploadFileCheck(problem: 'File not found');
      if (type == FileSystemEntityType.directory) return const UploadFileCheck(problem: 'This is a folder, not a file');
      return UploadFileCheck(size: await File(resolved).length());
    } on FileSystemException {
      return const UploadFileCheck(problem: 'The file cannot be read');
    }
  }

  String _pathOf(UploadFile file) {
    final path = file.path.trim();
    if (path.isEmpty) throw UploadFileProblem.noFileChosen(file);
    if (SessionFiles.isReference(path)) throw UploadFileProblem.lostWithTheSession(file);
    return _resolve(path);
  }

  /// `~` is the user's home folder only where a shell expands it; a path typed into a field never was, so it is here.
  String _resolve(String path) => FilePaths.resolve(_withHome(path), baseDir);

  String _withHome(String path) {
    if (path != '~' && !path.startsWith('~/') && !path.startsWith(r'~\')) return path;
    final home = homeDir;
    return home == null || home.isEmpty ? path : '$home${path.substring(1)}';
  }
}
